// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentAccount} from "../src/AgentAccount.sol";
import {GuardianRecovery, IRecoverable} from "../src/GuardianRecovery.sol";

/// E2E recovery scenarios the parallel sweep could not run (worktree infra),
/// authored + run here against the REAL GuardianRecovery + AgentAccount:
/// weighted/class-diversity threshold, post-recovery agent posture (does a stale
/// grant survive a rotation?), and two adversarial cases (agent forging a quorum,
/// single-guardian grief + cross-contract signature replay).
contract GuardianRecoveryE2ETest is Test {
    AgentAccount account;
    GuardianRecovery recovery;

    uint256 ownerPk = 0xA11CE;
    address owner;
    address agentCourier = vm.addr(0xC0DE); // a non-guardian courier (drives, never authorizes)
    address newOwner = makeAddr("newOwner");
    address bob = makeAddr("bob");

    // 4 guardians, assigned weight/class AFTER sorting by address (the module
    // requires ascending order). g[2] is a high-weight guardian sharing class 0
    // with g[0] so we can separate the WEIGHT test from the CLASS test.
    uint256[] gpks;     // sorted by signer address ascending
    address[] gaddr;
    uint96[4] gWeight = [uint96(1), 1, 5, 1];
    uint8[4] gClass = [uint8(0), 1, 0, 2];

    uint256 constant DELAY = 1 days;
    uint256 constant THRESHOLD = 2;
    uint8 constant MIN_CLASSES = 2;

    function setUp() public {
        owner = vm.addr(ownerPk);
        uint256[] memory pks = new uint256[](4);
        pks[0] = 0xA1; pks[1] = 0xB2; pks[2] = 0xC3; pks[3] = 0xD4;
        _sortByAddr(pks);
        gpks = pks;
        gaddr = new address[](4);
        for (uint256 i; i < 4; i++) gaddr[i] = vm.addr(gpks[i]);

        account = new AgentAccount(owner, address(0xE17240E1));
        vm.deal(address(account), 10 ether);
        recovery = new GuardianRecovery(IRecoverable(address(account)), _specs(), THRESHOLD, MIN_CLASSES, DELAY);
        vm.prank(owner);
        account.setRecoveryModule(address(recovery));
    }

    // ── helpers ──────────────────────────────────────────────────

    function _specs() internal view returns (GuardianRecovery.GuardianSpec[] memory s) {
        s = new GuardianRecovery.GuardianSpec[](4);
        for (uint256 i; i < 4; i++) {
            s[i] = GuardianRecovery.GuardianSpec({addr: gaddr[i], weight: gWeight[i], classId: gClass[i]});
        }
    }

    function _sortByAddr(uint256[] memory pks) internal pure {
        for (uint256 i = 1; i < pks.length; i++) {
            uint256 key = pks[i];
            address ka = vm.addr(key);
            uint256 j = i;
            while (j > 0 && vm.addr(pks[j - 1]) > ka) { pks[j] = pks[j - 1]; j--; }
            pks[j] = key;
        }
    }

    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    /// Signatures over `mod`'s current digest for the given guardian indices
    /// (indices into the address-sorted set, so already ascending).
    function _sigs(GuardianRecovery mod, address no, uint256[] memory idx) internal view returns (bytes[] memory out) {
        bytes32 d = mod.recoveryDigest(no);
        out = new bytes[](idx.length);
        for (uint256 i; i < idx.length; i++) out[i] = _sign(gpks[idx[i]], d);
    }

    function _idx(uint256 a) internal pure returns (uint256[] memory x) { x = new uint256[](1); x[0] = a; }
    function _idx(uint256 a, uint256 b) internal pure returns (uint256[] memory x) { x = new uint256[](2); x[0] = a; x[1] = b; }

    function _one(address t, uint256 v, bytes memory d) internal pure returns (AgentAccount.Call[] memory a) {
        a = new AgentAccount.Call[](1);
        a[0] = AgentAccount.Call(t, v, d);
    }

    // ── weighted + class-diversity threshold ─────────────────────

    function test_WeightedThreshold_ClassDiversityEnforced() public {
        // (sigs built BEFORE expectRevert: _sigs makes an external recoveryDigest read)
        // A single high-weight guardian (g[2]: weight 5 >= threshold 2) STILL fails
        // because it spans only ONE class (< minClasses 2). Weight alone is not enough.
        bytes[] memory only2 = _sigs(recovery, newOwner, _idx(2));
        vm.expectRevert(abi.encodeWithSelector(GuardianRecovery.ClassDiversityNotMet.selector, 1, MIN_CLASSES));
        recovery.scheduleRecovery(newOwner, only2);

        // Two guardians of the SAME class (g0 + g2, both class 0): weight 6, classes 1 → still fails.
        bytes[] memory sameClass = _sigs(recovery, newOwner, _idx(0, 2));
        vm.expectRevert(abi.encodeWithSelector(GuardianRecovery.ClassDiversityNotMet.selector, 1, MIN_CLASSES));
        recovery.scheduleRecovery(newOwner, sameClass);

        // g0 (class 0) + g1 (class 1): weight 2, classes 2 → succeeds.
        recovery.scheduleRecovery(newOwner, _sigs(recovery, newOwner, _idx(0, 1)));
        (address pno,, bool exists) = recovery.pending();
        assertTrue(exists);
        assertEq(pno, newOwner);
    }

    // ── adversarial: the agent (courier) cannot forge a quorum ───

    function test_Adversarial_AgentCannotForgeQuorum() public {
        // The courier's own signature is recovered but is NOT a guardian → 0 weight.
        bytes32 d = recovery.recoveryDigest(newOwner);
        bytes[] memory selfSig = new bytes[](1);
        selfSig[0] = _sign(0xC0DE, d); // courier key — recovered but NOT a guardian
        vm.expectRevert(abi.encodeWithSelector(GuardianRecovery.ThresholdNotMet.selector, 0, THRESHOLD));
        recovery.scheduleRecovery(newOwner, selfSig);

        // One real guardian alone is sub-threshold by weight.
        bytes[] memory lone = _sigs(recovery, newOwner, _idx(0));
        vm.expectRevert(abi.encodeWithSelector(GuardianRecovery.ThresholdNotMet.selector, 1, THRESHOLD));
        recovery.scheduleRecovery(newOwner, lone);

        // Double-counting the same guardian is impossible: ascending-order rule.
        bytes[] memory dup = new bytes[](2);
        dup[0] = _sign(gpks[0], d);
        dup[1] = _sign(gpks[0], d);
        vm.expectRevert(GuardianRecovery.SignersNotOrdered.selector);
        recovery.scheduleRecovery(newOwner, dup);
    }

    // ── adversarial: single-guardian grief + cross-contract replay ─

    function test_Adversarial_SingleGuardianCannotGriefOrCancel() public {
        // A lone guardian cannot schedule (sub-threshold), so cannot grief-occupy
        // the single pending slot to block a real recovery.
        bytes[] memory lone = _sigs(recovery, newOwner, _idx(0));
        vm.expectRevert(abi.encodeWithSelector(GuardianRecovery.ThresholdNotMet.selector, 1, THRESHOLD));
        recovery.scheduleRecovery(newOwner, lone);

        // And a guardian cannot veto/cancel a legitimately scheduled recovery
        // (cancel is owner-only, prevents single-guardian censorship, H1).
        recovery.scheduleRecovery(newOwner, _sigs(recovery, newOwner, _idx(0, 1)));
        vm.prank(gaddr[0]);
        vm.expectRevert(GuardianRecovery.NotRoot.selector);
        recovery.cancelRecovery();
        // Owner CAN veto.
        vm.prank(owner);
        recovery.cancelRecovery();
        (,, bool exists) = recovery.pending();
        assertFalse(exists);
    }

    function test_Adversarial_CrossContractSigReplayFails() public {
        // A second account+module with the SAME guardians but a different address
        // → different DOMAIN_SEPARATOR. Signatures made for `recovery` recover the
        // WRONG addresses on `recovery2` → zero guardian weight → rejected.
        AgentAccount account2 = new AgentAccount(owner, address(0xE17240E1));
        GuardianRecovery recovery2 =
            new GuardianRecovery(IRecoverable(address(account2)), _specs(), THRESHOLD, MIN_CLASSES, DELAY);
        vm.prank(owner);
        account2.setRecoveryModule(address(recovery2));

        bytes[] memory sigsFor1 = _sigs(recovery, newOwner, _idx(0, 1)); // signed against module 1
        vm.expectRevert(); // recovers non-guardian addresses on module 2 → Threshold/Ordering revert
        recovery2.scheduleRecovery(newOwner, sigsFor1);
    }

    // ── post-recovery agent posture (the "stale grant" question) ──

    function test_PostRecovery_CannotInstallActiveAgentAsOwner() public {
        // Register an active agent, then try to RECOVER the account TO that agent.
        address agentX = makeAddr("agentX");
        vm.prank(owner);
        account.setAgent(agentX, 0, uint48(block.timestamp + 30 days), true);

        recovery.scheduleRecovery(agentX, _sigs(recovery, agentX, _idx(0, 1)));
        vm.warp(block.timestamp + DELAY);
        // executeRecovery → account.recoverOwner(agentX) reverts on the I1 invariant.
        vm.expectRevert(bytes("owner is active agent"));
        recovery.executeRecovery();
        assertEq(account.owner(), owner, "owner unchanged: cannot fold an agent into the root");
    }

    function test_PostRecovery_StaleAgentGrantSurvives_NewOwnerCanRevoke() public {
        // An agent the owner delegated BEFORE recovery.
        address agentX = makeAddr("agentX");
        vm.prank(owner);
        account.setAgent(agentX, 0, uint48(block.timestamp + 30 days), true);
        (bool activeBefore,,) = account.agents(agentX);
        assertTrue(activeBefore);

        // Full recovery to a fresh newOwner.
        recovery.scheduleRecovery(newOwner, _sigs(recovery, newOwner, _idx(0, 1)));
        vm.warp(block.timestamp + DELAY);
        recovery.executeRecovery();
        assertEq(account.owner(), newOwner, "owner rotated");

        // FINDING (by design, not a bug): owner rotation does NOT auto-revoke
        // agents. The grant SURVIVES — correct for key-LOSS (the same human keeps
        // their agents), a caveat for key-COMPROMISE (the new owner must revoke a
        // malicious agent). Pin the behavior + the new owner's ability to revoke.
        (bool activeAfter,,) = account.agents(agentX);
        assertTrue(activeAfter, "stale agent grant survives owner rotation");

        // The NEW owner has full authority to revoke it.
        vm.prank(newOwner);
        account.revokeAgent(agentX);
        (bool activeRevoked,,) = account.agents(agentX);
        assertFalse(activeRevoked, "new owner can revoke the inherited agent");

        // And the OLD owner is fully locked out.
        vm.prank(owner);
        vm.expectRevert(AgentAccount.NotOwnerOrSelf.selector);
        account.revokeAgent(agentX);
    }

    // ── happy path (for a self-contained green signal) ────────────

    function test_HappyPath_CourierDrivesGuardiansAuthorize() public {
        assertFalse(recovery.isGuardian(agentCourier));
        recovery.scheduleRecovery(newOwner, _sigs(recovery, newOwner, _idx(0, 1)));
        // too early
        vm.expectRevert();
        recovery.executeRecovery();
        vm.warp(block.timestamp + DELAY);
        recovery.executeRecovery();
        assertEq(account.owner(), newOwner);
        // new owner controls funds; old owner cannot
        vm.prank(newOwner);
        account.executeAsOwner(_one(bob, 1 ether, ""));
        assertEq(bob.balance, 1 ether);
        vm.prank(owner);
        vm.expectRevert(AgentAccount.NotOwner.selector);
        account.executeAsOwner(_one(bob, 1 ether, ""));
    }
}

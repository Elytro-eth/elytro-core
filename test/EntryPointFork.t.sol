// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AgentAccount} from "../src/AgentAccount.sol";
import {AgentAccountFactory} from "../src/AgentAccountFactory.sol";
import {PackedUserOperation} from "../src/interfaces/IERC4337.sol";
import {MockERC20} from "./mocks/Mocks.sol";

interface IEntryPoint {
    function getNonce(address sender, uint192 key) external view returns (uint256);
    function getUserOpHash(PackedUserOperation calldata userOp) external view returns (bytes32);
    function handleOps(PackedUserOperation[] calldata ops, address payable beneficiary) external;
}

/**
 * @notice Integration test against the CANONICAL ERC-4337 EntryPoint v0.8 on a
 *         Base mainnet fork — proves the account works with the real EntryPoint
 *         (not just our MockEntryPoint), and that the realized-value cap holds
 *         when an agent's UserOp is processed by the genuine handleOps path.
 *
 * Run: forge test --match-path test/EntryPointFork.t.sol
 *      (uses a public Base RPC; override with FORK_RPC=<url>)
 */
contract EntryPointForkTest is Test {
    address constant ENTRYPOINT_V08 = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;
    IEntryPoint ep = IEntryPoint(ENTRYPOINT_V08);

    AgentAccountFactory factory;
    AgentAccount account;
    MockERC20 usdc;

    uint256 ownerPk = 0xA11CE;
    uint256 agentPk = 0xB0B;
    address owner;
    address agent;
    address bob = makeAddr("bob");
    address payable bene = payable(makeAddr("beneficiary"));

    function setUp() public {
        // Opt-in: keeps the default `forge test` hermetic/offline. Run with:
        //   RUN_FORK_TESTS=true forge test --match-path test/EntryPointFork.t.sol
        if (!vm.envOr("RUN_FORK_TESTS", false)) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(vm.envOr("FORK_RPC", string("https://mainnet.base.org")));
        owner = vm.addr(ownerPk);
        agent = vm.addr(agentPk);

        factory = new AgentAccountFactory(ENTRYPOINT_V08);
        account = AgentAccount(payable(factory.createAccount(owner, bytes32(uint256(1)))));

        usdc = new MockERC20("USD Coin", "USDC");
        usdc.mint(address(account), 1000e18);
        vm.deal(address(account), 1 ether); // gas prefund source

        vm.startPrank(owner);
        account.setProtectedToken(address(usdc), true);
        account.setAgent(agent, 0, uint48(block.timestamp + 30 days), true);
        account.setAllowedCall(agent, address(usdc), MockERC20.transfer.selector, true);
        account.setCap(agent, address(usdc), 100e18, 0, 0, 300e18);
        // Native cap for the agent's gas prefund (bounded since the HIGH-1 fix).
        account.setCap(agent, address(0), 1 ether, 0, 0, 10 ether);
        vm.stopPrank();
    }

    function test_realEntryPoint_agentCappedTransfer() public {
        PackedUserOperation memory op = _agentTransferOp(50e18);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        ep.handleOps(ops, bene);

        // The capped transfer executed through the genuine EntryPoint.
        assertEq(usdc.balanceOf(bob), 50e18);
        assertEq(account.getCap(agent, address(usdc)).spentTotal, 50e18);
    }

    function test_realEntryPoint_overCapDoesNotMove() public {
        // Validation passes (sig ok), execution reverts on the cap. The real
        // EntryPoint catches the execution revert: the op is charged gas but no
        // value moves. The cap held end-to-end against the real EntryPoint.
        PackedUserOperation memory op = _agentTransferOp(150e18);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        ep.handleOps(ops, bene);

        assertEq(usdc.balanceOf(bob), 0, "over-cap value must not move");
        assertEq(account.getCap(agent, address(usdc)).spentTotal, 0);
    }

    // ── helper: build a properly-packed, agent-signed UserOp ──────

    function _agentTransferOp(uint256 amt) internal view returns (PackedUserOperation memory op) {
        AgentAccount.Call[] memory calls = new AgentAccount.Call[](1);
        calls[0] = AgentAccount.Call(address(usdc), 0, abi.encodeWithSelector(MockERC20.transfer.selector, bob, amt));

        op.sender = address(account);
        op.nonce = ep.getNonce(address(account), 0);
        op.callData = abi.encodeWithSelector(AgentAccount.executeUserOp.selector, calls);
        // accountGasLimits = verificationGasLimit << 128 | callGasLimit
        op.accountGasLimits = bytes32((uint256(400_000) << 128) | uint256(400_000));
        op.preVerificationGas = 100_000;
        // gasFees = maxPriorityFeePerGas << 128 | maxFeePerGas
        op.gasFees = bytes32((uint256(1 gwei) << 128) | uint256(20 gwei));

        bytes32 h = ep.getUserOpHash(op);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(agentPk, h);
        op.signature = abi.encodePacked(r, s, v);
    }
}

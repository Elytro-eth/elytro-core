// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {AgentAccount} from "../src/AgentAccount.sol";
import {AgentAccountFactory} from "../src/AgentAccountFactory.sol";
import {PackedUserOperation} from "../src/interfaces/IERC4337.sol";
import {MockERC20} from "../test/mocks/Mocks.sol";

interface IEntryPoint {
    function getNonce(address sender, uint192 key) external view returns (uint256);
    function getUserOpHash(PackedUserOperation calldata userOp) external view returns (bytes32);
    function handleOps(PackedUserOperation[] calldata ops, address payable beneficiary) external;
}

/**
 * Live E2E on the Cleave testnet (anvil mainnet fork) against the canonical
 * EntryPoint v0.8: deploy a fresh agent-native account, provision an agent with
 * a realized-value cap, and push a real agent-signed UserOp through handleOps.
 *
 * Env: PK (owner/bundler = anvil #9), AGENT_PK (agent key), FACTORY (deployed).
 */
contract CleaveE2E is Script {
    address constant EP = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;
    address constant BOB = 0x0000000000000000000000000000000000000B0b;

    function run() external {
        uint256 ownerPk = vm.envUint("PK");
        uint256 agentPk = vm.envUint("AGENT_PK");
        address owner = vm.addr(ownerPk);
        address agent = vm.addr(agentPk);
        AgentAccountFactory factory = AgentAccountFactory(vm.envAddress("FACTORY"));
        bytes32 salt = keccak256(abi.encodePacked("cleave-e2e", agent));

        // ── Deploy + provision (owner authority) ──
        vm.startBroadcast(ownerPk);
        AgentAccount account = AgentAccount(payable(factory.createAccount(owner, salt)));
        MockERC20 token = new MockERC20("Test USD", "TUSD");
        token.mint(address(account), 1000e18);
        (bool funded,) = address(account).call{value: 0.05 ether}(""); // EntryPoint gas prefund
        require(funded, "fund failed");
        account.setProtectedToken(address(token), true);
        account.setAgent(agent, 0, uint48(block.timestamp + 30 days), true);
        account.setAllowedCall(agent, address(token), MockERC20.transfer.selector, true);
        account.setCap(agent, address(token), 100e18, 0, 0, 300e18); // perTx 100, total 300
        vm.stopBroadcast();

        // ── Build + sign the agent UserOp (transfer 50, within the 100 cap) ──
        PackedUserOperation memory op;
        {
            AgentAccount.Call[] memory calls = new AgentAccount.Call[](1);
            calls[0] = AgentAccount.Call(address(token), 0, abi.encodeWithSelector(MockERC20.transfer.selector, BOB, 50e18));
            op.sender = address(account);
            op.nonce = IEntryPoint(EP).getNonce(address(account), 0);
            op.callData = abi.encodeWithSelector(AgentAccount.executeUserOp.selector, calls);
            op.accountGasLimits = bytes32((uint256(400_000) << 128) | uint256(400_000));
            op.preVerificationGas = 100_000;
            op.gasFees = bytes32((uint256(1 gwei) << 128) | uint256(2 gwei));
            bytes32 h = IEntryPoint(EP).getUserOpHash(op);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(agentPk, h);
            op.signature = abi.encodePacked(r, s, v);
        }

        // ── Submit via the real EntryPoint (broadcaster acts as the bundler) ──
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.startBroadcast(ownerPk);
        IEntryPoint(EP).handleOps(ops, payable(owner));
        vm.stopBroadcast();

        console.log("account :", address(account));
        console.log("token   :", address(token));
        console.log("bob bal :", token.balanceOf(BOB));
        console.log("spent   :", account.getCap(agent, address(token)).spentTotal);
    }
}

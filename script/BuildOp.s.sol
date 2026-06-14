// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {AgentAccount} from "../src/AgentAccount.sol";
import {PackedUserOperation} from "../src/interfaces/IERC4337.sol";

interface IEntryPoint {
    function getNonce(address sender, uint192 key) external view returns (uint256);
    function getUserOpHash(PackedUserOperation calldata userOp) external view returns (bytes32);
    function handleOps(PackedUserOperation[] calldata ops, address payable beneficiary) external;
}

/// Read-only: builds + signs an agent UserOp and prints the handleOps calldata
/// to submit via `cast send` (avoids forge-script's handleOps gas estimation).
/// Env: ACCOUNT, TOKEN, AGENT_PK, AMOUNT, BENE.
contract BuildOp is Script {
    address constant EP = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;
    address constant BOB = 0x0000000000000000000000000000000000000B0b;

    function run() external view {
        address account = vm.envAddress("ACCOUNT");
        address token = vm.envAddress("TOKEN");
        uint256 agentPk = vm.envUint("AGENT_PK");
        uint256 amount = vm.envUint("AMOUNT");
        address bene = vm.envAddress("BENE");

        AgentAccount.Call[] memory calls = new AgentAccount.Call[](1);
        calls[0] = AgentAccount.Call(token, 0, abi.encodeWithSelector(bytes4(0xa9059cbb), BOB, amount));

        PackedUserOperation memory op;
        op.sender = account;
        op.nonce = IEntryPoint(EP).getNonce(account, 0);
        op.callData = abi.encodeWithSelector(AgentAccount.executeUserOp.selector, calls);
        op.accountGasLimits = bytes32((uint256(400_000) << 128) | uint256(400_000));
        op.preVerificationGas = 100_000;
        op.gasFees = bytes32((uint256(1 gwei) << 128) | uint256(2 gwei));
        bytes32 h = IEntryPoint(EP).getUserOpHash(op);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(agentPk, h);
        op.signature = abi.encodePacked(r, s, v);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        bytes memory cd = abi.encodeWithSelector(IEntryPoint.handleOps.selector, ops, bene);
        console.log("nonce:", op.nonce);
        console.logBytes(cd);
    }
}

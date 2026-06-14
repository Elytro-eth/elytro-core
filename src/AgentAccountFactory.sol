// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AgentAccount} from "./AgentAccount.sol";

/**
 * @title AgentAccountFactory
 * @notice CREATE2 factory for AgentAccount, so a wallet has a deterministic
 *         counterfactual address before it is deployed. The EntryPoint deploys
 *         it on the first UserOp via `initCode = factory ++ createAccount(...)`.
 *
 * The EntryPoint is baked into the factory and into every account it mints, so
 * an account can never be pointed at a rogue EntryPoint after the fact.
 */
contract AgentAccountFactory {
    address public immutable entryPoint;

    event AccountCreated(address indexed account, address indexed owner, bytes32 salt);

    constructor(address _entryPoint) {
        entryPoint = _entryPoint;
    }

    /// Deploy (or return, if already deployed) the account for (owner, salt).
    /// Idempotent — required by ERC-4337, which may call this more than once.
    function createAccount(address owner, bytes32 salt) external returns (address account) {
        account = getAddress(owner, salt);
        if (account.code.length > 0) return account;
        AgentAccount deployed = new AgentAccount{salt: salt}(owner, entryPoint);
        require(address(deployed) == account, "CREATE2 address mismatch");
        emit AccountCreated(account, owner, salt);
    }

    /// The counterfactual address for (owner, salt). Different owners yield
    /// different addresses under the same salt (owner is in the init code).
    function getAddress(address owner, bytes32 salt) public view returns (address) {
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(AgentAccount).creationCode, abi.encode(owner, entryPoint)));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash));
        return address(uint160(uint256(hash)));
    }
}

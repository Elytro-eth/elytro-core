// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AgentAccount} from "../src/AgentAccount.sol";
import {AgentAccountFactory} from "../src/AgentAccountFactory.sol";

contract AgentAccountFactoryTest is Test {
    AgentAccountFactory factory;
    address entryPoint = address(0xE17240E1);
    address owner = makeAddr("owner");

    function setUp() public {
        factory = new AgentAccountFactory(entryPoint);
    }

    function test_PredictedAddressMatchesDeployed() public {
        bytes32 salt = bytes32(uint256(1));
        address predicted = factory.getAddress(owner, salt);
        address deployed = factory.createAccount(owner, salt);
        assertEq(deployed, predicted, "predicted != deployed");
        assertGt(deployed.code.length, 0, "no code");
        assertEq(AgentAccount(payable(deployed)).owner(), owner);
        assertEq(AgentAccount(payable(deployed)).entryPoint(), entryPoint);
    }

    function test_CreateIsIdempotent() public {
        bytes32 salt = bytes32(uint256(7));
        address a = factory.createAccount(owner, salt);
        address b = factory.createAccount(owner, salt); // second call must not revert
        assertEq(a, b);
    }

    function test_DifferentSaltDifferentAddress() public {
        address a = factory.createAccount(owner, bytes32(uint256(1)));
        address b = factory.createAccount(owner, bytes32(uint256(2)));
        assertTrue(a != b);
    }

    function test_DifferentOwnerDifferentAddress() public {
        address a = factory.getAddress(owner, bytes32(uint256(1)));
        address b = factory.getAddress(makeAddr("other"), bytes32(uint256(1)));
        assertTrue(a != b, "owner must affect the address");
    }
}

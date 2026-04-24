// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AlreadyFinalized, DuplicateMember, InvalidMember, InvalidThreshold, KeyperSet} from "../src/KeyperSet.sol";

contract KeyperSetTest is Test {
    KeyperSet private keyperSet;

    address private owner = address(0xA11CE);
    address private keyper1 = address(0x1001);
    address private keyper2 = address(0x1002);
    address private keyper3 = address(0x1003);

    function setUp() external {
        keyperSet = new KeyperSet(owner);
    }

    function test_ownerCanConfigureMembersAndThreshold() external {
        address[] memory members = _members();

        vm.startPrank(owner);
        keyperSet.addMembers(members);
        keyperSet.setThreshold(2);
        vm.stopPrank();

        assertEq(keyperSet.getNumMembers(), 3);
        assertEq(keyperSet.getMember(0), keyper1);
        assertEq(keyperSet.getMember(1), keyper2);
        assertEq(keyperSet.getMember(2), keyper3);
        assertEq(keyperSet.getMembers(), members);
        assertEq(keyperSet.getThreshold(), 2);
        assertTrue(keyperSet.isMember(keyper1));
    }

    function test_onlyOwnerCanConfigure() external {
        address nonOwner = address(0xBAD);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        keyperSet.addMembers(_members());
    }

    function test_rejectsInvalidMembersAndThresholds() external {
        address[] memory members = new address[](2);
        members[0] = keyper1;
        members[1] = keyper1;

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(DuplicateMember.selector, keyper1));
        keyperSet.addMembers(members);

        members[1] = address(0);
        vm.expectRevert(abi.encodeWithSelector(InvalidMember.selector, address(0)));
        keyperSet.addMembers(members);

        keyperSet.addMembers(_members());

        vm.expectRevert(abi.encodeWithSelector(InvalidThreshold.selector, 0, 3));
        keyperSet.setThreshold(0);

        vm.expectRevert(abi.encodeWithSelector(InvalidThreshold.selector, 4, 3));
        keyperSet.setThreshold(4);
        vm.stopPrank();
    }

    function test_finalizedLocksConfiguration() external {
        vm.startPrank(owner);
        keyperSet.addMembers(_members());
        keyperSet.setThreshold(2);
        keyperSet.setFinalized();

        assertTrue(keyperSet.isFinalized());

        vm.expectRevert(AlreadyFinalized.selector);
        keyperSet.addMembers(_members());

        vm.expectRevert(AlreadyFinalized.selector);
        keyperSet.setThreshold(3);
        vm.stopPrank();
    }

    function _members() private view returns (address[] memory members) {
        members = new address[](3);
        members[0] = keyper1;
        members[1] = keyper2;
        members[2] = keyper3;
    }
}

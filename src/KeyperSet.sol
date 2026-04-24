// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IKeyperSet} from "./interfaces/IKeyperSet.sol";

error AlreadyFinalized();
error DuplicateMember(address member);
error InvalidMember(address member);
error InvalidThreshold(uint64 threshold, uint256 membersLen);

/// @notice Keyper membership and threshold configuration, based on Shutter's common KeyperSet.
contract KeyperSet is Ownable, IKeyperSet {
    bool private finalized;
    uint64 private threshold;

    address[] private members;
    mapping(address => bool) private memberRegistered;

    constructor(address initialOwner) Ownable(initialOwner) {}

    function isFinalized() external view returns (bool) {
        return finalized;
    }

    function getNumMembers() external view returns (uint64) {
        return uint64(members.length);
    }

    function getMember(uint64 index) external view returns (address) {
        return members[index];
    }

    function getMembers() external view returns (address[] memory) {
        return members;
    }

    function getThreshold() external view returns (uint64) {
        return threshold;
    }

    function isMember(address account) external view returns (bool) {
        return memberRegistered[account];
    }

    function addMembers(address[] calldata newMembers) external onlyOwner {
        if (finalized) revert AlreadyFinalized();
        for (uint256 i = 0; i < newMembers.length; i++) {
            address member = newMembers[i];
            if (member == address(0)) revert InvalidMember(member);
            if (memberRegistered[member]) revert DuplicateMember(member);
            memberRegistered[member] = true;
            members.push(member);
        }
    }

    function setThreshold(uint64 newThreshold) external onlyOwner {
        if (finalized) revert AlreadyFinalized();
        if (newThreshold == 0 || newThreshold > members.length) {
            revert InvalidThreshold(newThreshold, members.length);
        }
        threshold = newThreshold;
    }

    function setFinalized() external onlyOwner {
        finalized = true;
    }
}

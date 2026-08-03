// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {IKeyperSet} from "./interfaces/IKeyperSet.sol";

error DuplicateMember(address member);
error InvalidMember(address member);
error InvalidThreshold(uint64 threshold, uint256 membersLen);

/// @notice Immutable keyper membership and threshold configuration.
contract KeyperSet is IKeyperSet {
    uint64 private threshold;

    address[] private members;
    mapping(address => uint64) private memberIndexPlusOne;

    constructor(address[] memory initialMembers, uint64 initialThreshold) {
        for (uint256 i = 0; i < initialMembers.length; i++) {
            address member = initialMembers[i];
            if (member == address(0)) revert InvalidMember(member);
            if (memberIndexPlusOne[member] != 0) revert DuplicateMember(member);
            // forge-lint: disable-next-line(unsafe-typecast)
            memberIndexPlusOne[member] = uint64(i + 1);
            members.push(member);
        }

        if (initialThreshold == 0 || initialThreshold > members.length) {
            revert InvalidThreshold(initialThreshold, members.length);
        }
        threshold = initialThreshold;
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

    function getMemberIndex(address account) external view returns (uint64) {
        uint64 indexPlusOne = memberIndexPlusOne[account];
        if (indexPlusOne == 0) revert InvalidMember(account);
        return indexPlusOne - 1;
    }

    function getThreshold() external view returns (uint64) {
        return threshold;
    }

    function isMember(address account) external view returns (bool) {
        return memberIndexPlusOne[account] != 0;
    }
}

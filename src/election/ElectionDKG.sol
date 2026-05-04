// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElectionBase} from "./ElectionBase.sol";

abstract contract ElectionDKG is ElectionBase {
    // forge-lint: disable-next-line(mixed-case-function)
    function voteDKGResult(bytes calldata pkElection, bytes[] calldata committeePKs) external {
        if (dkgFinalized) revert AlreadyFinalized();
        if (!keyperSet.isMember(msg.sender)) revert UnauthorizedKeyper(msg.sender);
        if (hasVotedForDKG[msg.sender]) revert AlreadyVoted(msg.sender);

        _requireG2Point(pkElection);

        uint64 numMembers = keyperSet.getNumMembers();
        if (committeePKs.length != numMembers) revert InvalidCommitteeLength(committeePKs.length, numMembers);
        for (uint256 index = 0; index < committeePKs.length; index++) {
            _requireG2Point(committeePKs[index]);
        }

        bytes32 resultDigest = keccak256(abi.encode(pkElection, committeePKs));
        hasVotedForDKG[msg.sender] = true;
        dkgVoteCountByResult[resultDigest] += 1;

        emit DKGVoteRegistered(msg.sender, pkElection);

        if (dkgVoteCountByResult[resultDigest] >= keyperSet.getThreshold()) {
            electionPublicKey = pkElection;
            _storeCommitteePublicKeys(committeePKs);
            dkgFinalized = true;
            emit DKGResultPublished(electionPublicKey, committeePublicKeys);
        }
    }

    function _storeCommitteePublicKeys(bytes[] calldata committeePKs) private {
        delete committeePublicKeys;
        for (uint256 index = 0; index < committeePKs.length; index++) {
            committeePublicKeys.push(committeePKs[index]);
        }
    }
}

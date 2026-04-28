// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElectionBase} from "./ElectionBase.sol";
import {VotingTypes} from "../VotingTypes.sol";

abstract contract ElectionDecryption is ElectionBase {
    function submitDecryptionShare(bytes[] calldata shares, VotingTypes.DLEQProof[] calldata proofs) external {
        if (!dkgFinalized) revert DKGNotFinalized();
        if (block.timestamp < votingEnd) revert VotingStillOpen(block.timestamp);
        if (!keyperSet.isMember(msg.sender)) revert UnauthorizedKeyper(msg.sender);
        if (hasSubmittedDecryptionShare[msg.sender]) revert AlreadyVoted(msg.sender);
        if (shares.length != numCandidates || proofs.length != shares.length) {
            revert InvalidDecryptionSharePayload();
        }

        hasSubmittedDecryptionShare[msg.sender] = true;

        decryptionShares.push();
        VotingTypes.DecryptionShare storage share = decryptionShares[decryptionShares.length - 1];
        // forge-lint: disable-next-line(unsafe-typecast)
        share.keyperIndex = uint8(keyperSet.getMemberIndex(msg.sender));
        share.submittedAt = uint64(block.timestamp);

        for (uint256 index = 0; index < shares.length; index++) {
            _requireG2Point(shares[index]);
            share.shares.push(shares[index]);
            share.proofs.push(proofs[index]);
        }

        emit DecryptionSharePosted(share.keyperIndex);
    }

    function getDecryptionShares() external view returns (VotingTypes.DecryptionShare[] memory shares) {
        shares = new VotingTypes.DecryptionShare[](decryptionShares.length);
        for (uint256 index = 0; index < decryptionShares.length; index++) {
            shares[index] = decryptionShares[index];
        }
    }
}

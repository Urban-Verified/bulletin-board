// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Shared types for the Shutter ElGamal voting bulletin board.
library VotingTypes {
    struct ElectionParams {
        uint64 votingStart;
        uint64 votingEnd;
        uint256 selfSubmitFee;
        uint32 numCandidates;
        uint32 budget;
        // forge-lint: disable-next-line(mixed-case-variable)
        bytes pkWR;
        address tallyAggregator;
        address voteProxy;
    }

    // forge-lint: disable-next-line(pascal-case-struct)
    struct DLEQProof {
        uint256 e;
        uint256 z;
    }

    /// @notice ElGamal ciphertext in G2: (c1, c2), each 96-byte compressed point.
    struct Ciphertext {
        bytes c1;
        bytes c2;
    }

    /// @notice External ballot payload aligned with the contract spec.
    struct Ballot {
        bytes32 pseudonym;
        bytes vk;
        Ciphertext[] ciphertexts;
        bytes zkProof;
        bytes voterSignature;
        bytes wrAttestation;
    }

    /// @notice Stored ballot metadata alongside the user payload.
    struct BallotRecord {
        Ballot ballot;
        uint64 submittedAt;
        uint256 feePaid;
    }

    // forge-lint: disable-next-line(pascal-case-struct)
    struct DKGResult {
        bytes pkElection;
        bytes[] committeePKs;
    }

    struct ElectionConfigView {
        uint256 electionId;
        uint64 votingStart;
        uint64 votingEnd;
        uint256 selfSubmitFee;
        uint32 numCandidates;
        uint32 budget;
        uint64 thresholdN;
        uint64 thresholdT;
        address[] keyperAddresses;
        // forge-lint: disable-next-line(mixed-case-variable)
        bytes pkWR;
    }

    struct EncryptedTally {
        Ciphertext[] aggregates;
        bytes proof;
    }

    struct DecryptionShare {
        uint8 keyperIndex;
        uint64 submittedAt;
        bytes[] shares;
        DLEQProof[] proofs;
    }

    struct ElectionResult {
        uint256[] tally;
        uint8[] keyperIndices;
    }
}

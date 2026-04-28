// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {VotingTypes} from "./VotingTypes.sol";
import {IElection} from "./interfaces/IElection.sol";
import {IKeyperSet} from "./interfaces/IKeyperSet.sol";

contract Election is AccessControl, IElection {
    error AggregateNotPublished();
    error AlreadyFinalized();
    error AlreadyVoted(address keyper);
    error BallotNotFound(bytes32 pseudonym);
    error DKGSubmissionMismatch();
    error InvalidCommitteeLength(uint256 actualLength, uint256 expectedLength);
    error InvalidConfig();
    error InvalidG1PointLength(uint256 actualLength);
    error InvalidG2PointLength(uint256 actualLength);
    error InvalidPseudonym();
    error InvalidResultPayload();
    error InvalidVoteFee(uint256 expectedFee, uint256 actualFee);
    error InvalidVotePayload();
    error InvalidAggregatePayload();
    error InvalidDecryptionSharePayload();
    error DKGNotFinalized();
    error EtherTransferFailed();
    error DirectETHUnsupported();
    error VotingClosed(uint256 timestamp);
    error VotingNotStarted(uint256 timestamp);
    error VotingStillOpen(uint256 timestamp);
    error UnauthorizedKeyper(address account);

    bytes32 public constant VOTE_PROXY_ROLE = keccak256("VOTE_PROXY_ROLE");
    bytes32 public constant TALLY_AGGREGATOR_ROLE = keccak256("TALLY_AGGREGATOR_ROLE");

    uint256 private constant G2_COMPRESSED_LENGTH = 96;

    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    uint256 public immutable electionId;
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    IKeyperSet public immutable keyperSet;
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    uint64 public immutable votingStart;
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    uint64 public immutable votingEnd;
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    uint256 public immutable selfSubmitFee;
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    uint32 public immutable numCandidates;
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    uint32 public immutable budget;

    bytes private wrPublicKey;
    bool private dkgFinalized;
    uint64 private dkgVoteCount;
    bytes private electionPublicKey;
    bytes[] private committeePublicKeys;
    VotingTypes.BallotRecord[] private ballotRecords;
    mapping(bytes32 => uint256) private ballotIndexPlusOneByPseudonym;
    VotingTypes.EncryptedTally private encryptedTally;
    bool private aggregatePublished;
    VotingTypes.DecryptionShare[] private decryptionShares;
    bool private resultFinalized;
    VotingTypes.ElectionResult private electionResult;

    // forge-lint: disable-next-line(mixed-case-variable)
    mapping(address => bool) private hasVotedForDKG;
    mapping(address => bool) private hasSubmittedDecryptionShare;

    constructor(address admin, uint256 electionId_, IKeyperSet keyperSet_, VotingTypes.ElectionParams memory params) {
        if (
            admin == address(0) || address(keyperSet_) == address(0) || params.tallyAggregator == address(0)
                || params.voteProxy == address(0) || params.votingEnd <= params.votingStart || params.numCandidates == 0
                || params.budget == 0
        ) {
            revert InvalidConfig();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(TALLY_AGGREGATOR_ROLE, params.tallyAggregator);
        _grantRole(VOTE_PROXY_ROLE, params.voteProxy);

        electionId = electionId_;
        keyperSet = keyperSet_;
        votingStart = params.votingStart;
        votingEnd = params.votingEnd;
        selfSubmitFee = params.selfSubmitFee;
        numCandidates = params.numCandidates;
        budget = params.budget;
        wrPublicKey = params.pkWR;
    }

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

        if (electionPublicKey.length == 0) {
            electionPublicKey = pkElection;
            _storeCommitteePublicKeys(committeePKs);
        } else if (!_sameDkgResult(pkElection, committeePKs)) {
            revert DKGSubmissionMismatch();
        }

        hasVotedForDKG[msg.sender] = true;
        dkgVoteCount += 1;

        emit DKGVoteRegistered(msg.sender, pkElection);

        if (dkgVoteCount >= keyperSet.getThreshold()) {
            dkgFinalized = true;
            emit DKGResultPublished(electionPublicKey, committeePublicKeys);
        }
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function isDKGFinalized() external view returns (bool) {
        return dkgFinalized;
    }

    function submitVote(VotingTypes.Ballot calldata ballot) external payable {
        if (!dkgFinalized) revert DKGNotFinalized();
        if (block.timestamp < votingStart) revert VotingNotStarted(block.timestamp);
        if (block.timestamp >= votingEnd) revert VotingClosed(block.timestamp);
        if (ballot.pseudonym == bytes32(0)) revert InvalidPseudonym();
        if (
            ballot.vk.length != 48 || ballot.zkProof.length == 0 || ballot.voterSignature.length == 0
                || ballot.wrAttestation.length == 0 || ballot.ciphertexts.length != numCandidates
        ) {
            revert InvalidVotePayload();
        }

        uint256 expectedFee = hasRole(VOTE_PROXY_ROLE, msg.sender) ? 0 : selfSubmitFee;
        if (msg.value != expectedFee) revert InvalidVoteFee(expectedFee, msg.value);

        for (uint256 index = 0; index < ballot.ciphertexts.length; index++) {
            _requireG2Point(ballot.ciphertexts[index].c1);
            _requireG2Point(ballot.ciphertexts[index].c2);
        }

        ballotRecords.push();
        uint256 ballotIndex = ballotRecords.length - 1;
        VotingTypes.BallotRecord storage record = ballotRecords[ballotIndex];
        record.ballot.pseudonym = ballot.pseudonym;
        record.ballot.vk = ballot.vk;
        record.ballot.zkProof = ballot.zkProof;
        record.ballot.voterSignature = ballot.voterSignature;
        record.ballot.wrAttestation = ballot.wrAttestation;
        record.submittedAt = uint64(block.timestamp);
        record.submittedBy = msg.sender;

        for (uint256 index = 0; index < ballot.ciphertexts.length; index++) {
            record.ballot.ciphertexts.push(ballot.ciphertexts[index]);
        }

        ballotIndexPlusOneByPseudonym[ballot.pseudonym] = ballotIndex + 1;

        emit VoteSubmitted(ballot.pseudonym, ballotIndex);
    }

    function getNumBallots() external view returns (uint256) {
        return ballotRecords.length;
    }

    function getBallot(bytes32 pseudonym) external view returns (VotingTypes.Ballot memory ballot) {
        uint256 ballotIndexPlusOne = ballotIndexPlusOneByPseudonym[pseudonym];
        if (ballotIndexPlusOne == 0) revert BallotNotFound(pseudonym);
        return ballotRecords[ballotIndexPlusOne - 1].ballot;
    }

    function getBallots(uint256 startIndex, uint256 count) external view returns (VotingTypes.Ballot[] memory ballots) {
        ballots = new VotingTypes.Ballot[](count);
        for (uint256 index = 0; index < count; index++) {
            ballots[index] = ballotRecords[startIndex + index].ballot;
        }
    }

    function publishAggregate(VotingTypes.EncryptedTally calldata aggregate) external onlyRole(TALLY_AGGREGATOR_ROLE) {
        if (!dkgFinalized) revert DKGNotFinalized();
        if (block.timestamp < votingEnd) revert VotingStillOpen(block.timestamp);
        if (aggregate.aggregates.length != numCandidates) revert InvalidAggregatePayload();

        delete encryptedTally.aggregates;
        encryptedTally.proof = aggregate.proof;
        for (uint256 index = 0; index < aggregate.aggregates.length; index++) {
            _requireG2Point(aggregate.aggregates[index].c1);
            _requireG2Point(aggregate.aggregates[index].c2);
            encryptedTally.aggregates.push(aggregate.aggregates[index]);
        }
        aggregatePublished = true;
        emit AggregatePublished(electionId);
    }

    function getAggregate() external view returns (VotingTypes.EncryptedTally memory aggregate) {
        if (!aggregatePublished) revert AggregateNotPublished();
        return encryptedTally;
    }

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

    function publishResult(uint256[] calldata totals, uint8[] calldata keyperIndices)
        external
        onlyRole(TALLY_AGGREGATOR_ROLE)
    {
        if (!dkgFinalized) revert DKGNotFinalized();
        if (block.timestamp < votingEnd) revert VotingStillOpen(block.timestamp);
        if (totals.length != numCandidates || keyperIndices.length == 0) revert InvalidResultPayload();

        resultFinalized = true;
        electionResult.tally = totals;
        electionResult.keyperIndices = keyperIndices;

        emit ResultPublished(totals, keyperIndices);
    }

    function isResultFinalized() external view returns (bool) {
        return resultFinalized;
    }

    function getResult() external view returns (VotingTypes.ElectionResult memory result) {
        return electionResult;
    }

    function getPhase() external view returns (uint8 phase) {
        if (block.timestamp >= votingEnd) return 4;
        if (block.timestamp >= votingStart) return 3;
        if (dkgFinalized) return 2;
        return 0;
    }

    function getElection()
        external
        view
        returns (VotingTypes.ElectionConfigView memory config, VotingTypes.DKGResult memory dkgResult)
    {
        config.electionId = electionId;
        config.votingStart = votingStart;
        config.votingEnd = votingEnd;
        config.selfSubmitFee = selfSubmitFee;
        config.numCandidates = numCandidates;
        config.budget = budget;
        config.thresholdN = keyperSet.getNumMembers();
        config.thresholdT = keyperSet.getThreshold();
        config.keyperAddresses = keyperSet.getMembers();
        config.pkWR = wrPublicKey;

        dkgResult.pkElection = electionPublicKey;
        dkgResult.committeePKs = committeePublicKeys;
    }

    function withdrawFees(address payable recipient) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256 amount) {
        if (recipient == address(0)) revert InvalidConfig();
        amount = address(this).balance;
        (bool ok,) = recipient.call{value: amount}("");
        if (!ok) revert EtherTransferFailed();
        emit FeesWithdrawn(recipient, amount);
    }

    receive() external payable {
        revert DirectETHUnsupported();
    }

    fallback() external payable {
        revert DirectETHUnsupported();
    }

    function _requireG2Point(bytes memory point) private pure {
        if (point.length != G2_COMPRESSED_LENGTH) revert InvalidG2PointLength(point.length);
    }

    function _storeCommitteePublicKeys(bytes[] calldata committeePKs) private {
        delete committeePublicKeys;
        for (uint256 index = 0; index < committeePKs.length; index++) {
            committeePublicKeys.push(committeePKs[index]);
        }
    }

    function _sameDkgResult(bytes calldata pkElection, bytes[] calldata committeePKs) private view returns (bool) {
        if (keccak256(electionPublicKey) != keccak256(pkElection)) {
            return false;
        }
        if (committeePublicKeys.length != committeePKs.length) {
            return false;
        }
        for (uint256 index = 0; index < committeePKs.length; index++) {
            if (keccak256(committeePublicKeys[index]) != keccak256(committeePKs[index])) {
                return false;
            }
        }
        return true;
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {Test, console2, Vm} from "forge-std/Test.sol";
import {ElectionRegistry} from "../src/ElectionRegistry.sol";
import {KeyperSet} from "../src/KeyperSet.sol";
import {Election} from "../src/Election.sol";
import {IKeyperSet} from "../src/interfaces/IKeyperSet.sol";
import {VotingTypes} from "../src/VotingTypes.sol";

/// @notice Guards the ballot-storage design: the zkProof is committed to in
/// storage as a hash and published in full via `VoteSubmitted`.
///
/// zkProof = numCandidates * (budget + 1) * 256 + headers.
contract BallotProofStorageTest is Test {
    uint32 constant NUM_CANDIDATES = 10;
    uint32 constant BUDGET = 10;
    uint256 constant ZK_PROOF_LEN =
        1 + 1 + 2 + 2 * NUM_CANDIDATES + uint256(NUM_CANDIDATES) * (BUDGET + 1) * 256 + 1 + 32 + 32;

    uint256 constant MAX_EXECUTION_GAS = 4_000_000;

    address constant ADMIN = address(0xA11CE);
    address constant TALLY = address(0x7A11);
    address constant PROXY = address(0x9209);

    Election election;

    function setUp() public {
        address[] memory members = new address[](3);
        members[0] = address(0x1111);
        members[1] = address(0x2222);
        members[2] = address(0x3333);
        KeyperSet keyperSet = new KeyperSet(members, 2);

        vm.prank(ADMIN);
        ElectionRegistry registry = new ElectionRegistry(ADMIN);

        VotingTypes.ElectionParams memory params = VotingTypes.ElectionParams({
            votingStart: uint64(block.timestamp + 10),
            votingEnd: uint64(block.timestamp + 100000),
            selfSubmitFee: 0,
            numCandidates: NUM_CANDIDATES,
            budget: BUDGET,
            pkWR: _filled(48, 0xAA),
            tallyAggregator: TALLY,
            voteProxy: PROXY
        });
        vm.prank(ADMIN);
        election = Election(payable(registry.publishElection(IKeyperSet(address(keyperSet)), params)));

        bytes memory pkElection = _filled(96, 0xBB);
        bytes[] memory committeePKs = new bytes[](3);
        committeePKs[0] = _filled(96, 0xC1);
        committeePKs[1] = _filled(96, 0xC2);
        committeePKs[2] = _filled(96, 0xC3);
        vm.prank(members[0]);
        election.voteDKGResult(pkElection, committeePKs);
        vm.prank(members[1]);
        election.voteDKGResult(pkElection, committeePKs);
        require(election.isDKGFinalized(), "DKG not finalized");

        vm.warp(block.timestamp + 20);
    }

    /// Non-zero, varied bytes -- the realistic shape for proof material and
    /// the worst case for calldata pricing.
    function _filled(uint256 length, uint8 seed) internal pure returns (bytes memory out) {
        out = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            out[i] = bytes1(uint8(((i * 31 + seed) % 255) + 1));
        }
    }

    function _ballot() internal pure returns (VotingTypes.Ballot memory ballot) {
        VotingTypes.Ciphertext[] memory ciphertexts = new VotingTypes.Ciphertext[](NUM_CANDIDATES);
        for (uint256 i = 0; i < NUM_CANDIDATES; i++) {
            ciphertexts[i] =
                VotingTypes.Ciphertext({c1: _filled(96, uint8(i + 1)), c2: _filled(96, uint8(i + 50))});
        }
        ballot = VotingTypes.Ballot({
            pseudonym: keccak256("voter-1"),
            vk: _filled(48, 0x11),
            ciphertexts: ciphertexts,
            zkProof: _filled(ZK_PROOF_LEN, 0x77),
            voterSignature: _filled(80, 0x22),
            wrAttestation: _filled(80, 0x33)
        });
    }

    function test_submitVoteFitsBlockGasLimit() external {
        VotingTypes.Ballot memory ballot = _ballot();

        vm.prank(PROXY);
        uint256 before = gasleft();
        election.submitVote(ballot);
        uint256 used = before - gasleft();

        console2.log("zkProof bytes  ", ballot.zkProof.length);
        console2.log("execution gas  ", used);

        assertLt(used, MAX_EXECUTION_GAS, "submitVote gas regressed -- is bulk data back in storage?");
    }

    /// The proof must be recoverable from logs and bound to the on-chain
    /// commitment. This is what lets the tally aggregator and the dashboard
    /// trust a proof they fetched from a log rather than from state.
    function test_proofRecoverableFromLogAndBoundToCommitment() external {
        VotingTypes.Ballot memory ballot = _ballot();

        vm.recordLogs();
        vm.prank(PROXY);
        election.submitVote(ballot);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 signature = keccak256("VoteSubmitted(bytes32,uint256,bytes)");
        bytes memory recovered;
        bytes32 recoveredPseudonym;
        uint256 recoveredIndex = type(uint256).max;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == signature) {
                recoveredPseudonym = logs[i].topics[1];
                recoveredIndex = uint256(logs[i].topics[2]);
                recovered = abi.decode(logs[i].data, (bytes));
            }
        }
        require(recovered.length > 0, "no VoteSubmitted event carrying a proof");

        assertEq(recovered.length, ballot.zkProof.length, "proof length round-trip");
        assertEq(keccak256(recovered), keccak256(ballot.zkProof), "proof bytes round-trip");
        assertEq(recoveredPseudonym, ballot.pseudonym, "pseudonym topic");
        // ballotIndex is the join key between the log and the stored record --
        // pseudonym is NOT unique, because re-votes append a new record.
        assertEq(recoveredIndex, 0, "ballotIndex join key");

        VotingTypes.BallotView memory stored = election.getBallot(ballot.pseudonym);
        assertEq(keccak256(recovered), stored.zkProofHash, "commitment binds the logged proof");

        bytes memory tampered = recovered;
        tampered[0] = bytes1(uint8(tampered[0]) ^ 0xFF);
        assertTrue(keccak256(tampered) != stored.zkProofHash, "tampered proof must fail the commitment check");
    }
}

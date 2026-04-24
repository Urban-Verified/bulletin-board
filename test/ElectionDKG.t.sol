// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Election} from "../src/Election.sol";
import {IElection} from "../src/interfaces/IElection.sol";
import {KeyperSet} from "../src/KeyperSet.sol";
import {VotingTypes} from "../src/VotingTypes.sol";

contract ElectionDKGTest is Test {
    Election private election;
    KeyperSet private keyperSet;

    address private owner = address(0xA11CE);
    address private keyper1 = address(0x1001);
    address private keyper2 = address(0x1002);
    address private keyper3 = address(0x1003);
    address private outsider = address(0xBAD);
    address private tallyAggregator = address(0xA66);
    address private voteProxy = address(0x970);

    function setUp() external {
        keyperSet = new KeyperSet(owner);
        election = new Election(owner, 1, keyperSet, _params());

        address[] memory members = new address[](3);
        members[0] = keyper1;
        members[1] = keyper2;
        members[2] = keyper3;

        vm.startPrank(owner);
        keyperSet.addMembers(members);
        keyperSet.setThreshold(2);
        keyperSet.setFinalized();
        vm.stopPrank();
    }

    function test_voteDKGResultFinalizesAtThreshold() external {
        bytes memory pkElection = _g2Point(1);
        bytes[] memory committeePKs = _committeePKs(10);
        bytes32 digest = keccak256(pkElection);

        vm.prank(keyper1);
        election.voteDKGResult(pkElection, committeePKs);

        assertFalse(election.isDKGFinalized());

        vm.expectEmit(true, true, false, true, address(election));
        emit IElection.DKGCompleted(digest, pkElection, committeePKs);

        vm.prank(keyper2);
        election.voteDKGResult(pkElection, committeePKs);

        assertTrue(election.isDKGFinalized());
        (, VotingTypes.DKGResult memory dkgResult) = election.getElection();
        assertEq(dkgResult.pkElection, pkElection);
        assertEq(dkgResult.committeePKs.length, 3);
        assertEq(dkgResult.committeePKs[0], committeePKs[0]);
        assertEq(dkgResult.committeePKs[1], committeePKs[1]);
        assertEq(dkgResult.committeePKs[2], committeePKs[2]);
    }

    function test_voteDKGResultRejectsNonMember() external {
        bytes memory pkElection = _g2Point(1);
        bytes[] memory committeePKs = _committeePKs(10);

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Election.UnauthorizedKeyper.selector, outsider));
        election.voteDKGResult(pkElection, committeePKs);
    }

    function test_voteDKGResultRejectsDuplicateVote() external {
        bytes memory pkElection = _g2Point(1);
        bytes[] memory committeePKs = _committeePKs(10);

        vm.startPrank(keyper1);
        election.voteDKGResult(pkElection, committeePKs);

        vm.expectRevert(abi.encodeWithSelector(Election.AlreadyVoted.selector, keyper1));
        election.voteDKGResult(_g2Point(2), _committeePKs(20));
        vm.stopPrank();
    }

    function test_voteDKGResultRejectsInvalidLengths() external {
        bytes memory shortPoint = new bytes(95);
        bytes memory pkElection = _g2Point(1);
        bytes[] memory committeePKs = _committeePKs(10);

        vm.prank(keyper1);
        vm.expectRevert(abi.encodeWithSelector(Election.InvalidG2PointLength.selector, 95));
        election.voteDKGResult(shortPoint, committeePKs);

        committeePKs[1] = shortPoint;

        vm.prank(keyper1);
        vm.expectRevert(abi.encodeWithSelector(Election.InvalidG2PointLength.selector, 95));
        election.voteDKGResult(pkElection, committeePKs);
    }

    function test_voteDKGResultRejectsWrongCommitteeLength() external {
        bytes[] memory committeePKs = new bytes[](2);
        committeePKs[0] = _g2Point(10);
        committeePKs[1] = _g2Point(11);

        vm.prank(keyper1);
        vm.expectRevert(abi.encodeWithSelector(Election.InvalidCommitteeLength.selector, 2, 3));
        election.voteDKGResult(_g2Point(1), committeePKs);
    }

    function test_voteDKGResultRequiresSamePublishedResult() external {
        bytes memory firstPkElection = _g2Point(1);
        bytes[] memory firstCommitteePKs = _committeePKs(10);

        bytes memory secondPkElection = _g2Point(2);
        bytes[] memory secondCommitteePKs = _committeePKs(20);

        vm.prank(keyper1);
        election.voteDKGResult(firstPkElection, firstCommitteePKs);

        vm.prank(keyper2);
        vm.expectRevert(Election.DKGSubmissionMismatch.selector);
        election.voteDKGResult(secondPkElection, secondCommitteePKs);

        vm.prank(keyper3);
        election.voteDKGResult(firstPkElection, firstCommitteePKs);

        assertTrue(election.isDKGFinalized());
        (, VotingTypes.DKGResult memory dkgResult) = election.getElection();
        assertEq(dkgResult.pkElection, firstPkElection);
    }

    function test_voteDKGResultRejectsAfterFinalization() external {
        bytes memory pkElection = _g2Point(1);
        bytes[] memory committeePKs = _committeePKs(10);

        vm.prank(keyper1);
        election.voteDKGResult(pkElection, committeePKs);

        vm.prank(keyper2);
        election.voteDKGResult(pkElection, committeePKs);

        vm.prank(keyper3);
        vm.expectRevert(Election.AlreadyFinalized.selector);
        election.voteDKGResult(pkElection, committeePKs);
    }

    function _committeePKs(uint8 seed) private pure returns (bytes[] memory committeePKs) {
        committeePKs = new bytes[](3);
        committeePKs[0] = _g2Point(seed);
        committeePKs[1] = _g2Point(seed + 1);
        committeePKs[2] = _g2Point(seed + 2);
    }

    function _g2Point(uint8 seed) private pure returns (bytes memory point) {
        point = new bytes(96);
        for (uint256 index = 0; index < point.length; index++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            point[index] = bytes1(seed + uint8(index));
        }
    }

    function _params() private view returns (VotingTypes.ElectionParams memory) {
        return VotingTypes.ElectionParams({
            votingStart: 100,
            votingEnd: 200,
            selfSubmitFee: 0.01 ether,
            numCandidates: 3,
            budget: 1,
            pkWR: bytes(""),
            tallyAggregator: tallyAggregator,
            voteProxy: voteProxy
        });
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {Election} from "../src/Election.sol";
import {ElectionRegistry} from "../src/ElectionRegistry.sol";
import {IKeyperSet} from "../src/interfaces/IKeyperSet.sol";
import {VotingTypes} from "../src/VotingTypes.sol";

/// @notice Foundry script to publish (deploy) a new Election via an existing ElectionRegistry.

contract PublishElection is Script {
    error InvalidVotingWindow(uint256 votingStart, uint256 votingEnd);
    error ValueTooLarge(string name, uint256 value, uint256 maxValue);

    function run() external returns (address electionAddr) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address registryAddr = vm.envAddress("REGISTRY");
        address keyperSetAddr = vm.envAddress("KEYPER_SET");

        uint64 votingStart = _toUint64("VOTING_START", vm.envUint("VOTING_START"));
        uint64 votingEnd = _toUint64("VOTING_END", vm.envUint("VOTING_END"));
        if (votingEnd <= votingStart) revert InvalidVotingWindow(votingStart, votingEnd);

        VotingTypes.ElectionParams memory params = VotingTypes.ElectionParams({
            votingStart: votingStart,
            votingEnd: votingEnd,
            selfSubmitFee: vm.envUint("SELF_SUBMIT_FEE"),
            numCandidates: _toUint32("NUM_CANDIDATES", vm.envUint("NUM_CANDIDATES")),
            budget: _toUint32("BUDGET", vm.envUint("BUDGET")),
            pkWR: vm.envBytes("PK_WR"),
            tallyAggregator: vm.envAddress("TALLY_AGGREGATOR"),
            voteProxy: vm.envAddress("VOTE_PROXY")
        });

        vm.startBroadcast(pk);
        electionAddr = ElectionRegistry(registryAddr).publishElection(IKeyperSet(keyperSetAddr), params);
        vm.stopBroadcast();

        console2.log("Election deployed:", electionAddr);
        console2.log("Election ID:", Election(payable(electionAddr)).electionId());
        console2.log("Tally aggregator:", params.tallyAggregator);
        console2.log("Vote proxy:", params.voteProxy);
    }

    function _toUint64(string memory name, uint256 value) private pure returns (uint64 result) {
        if (value > type(uint64).max) revert ValueTooLarge(name, value, type(uint64).max);
        // forge-lint: disable-next-line(unsafe-typecast)
        result = uint64(value);
    }

    function _toUint32(string memory name, uint256 value) private pure returns (uint32 result) {
        if (value > type(uint32).max) revert ValueTooLarge(name, value, type(uint32).max);
        // forge-lint: disable-next-line(unsafe-typecast)
        result = uint32(value);
    }
}


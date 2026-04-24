// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Election} from "../src/Election.sol";
import {KeyperSet} from "../src/KeyperSet.sol";
import {ElectionRegistry} from "../src/ElectionRegistry.sol";
import {VotingTypes} from "../src/VotingTypes.sol";

contract DeployLocalScript is Script {
    function run() external returns (KeyperSet keyperSet, ElectionRegistry registry, Election election) {
        address admin = vm.envOr("VOTE_MANAGER", msg.sender);

        vm.startBroadcast();
        keyperSet = new KeyperSet(admin);
        registry = new ElectionRegistry(admin);

        _configureKeyperSet(keyperSet, admin);

        address electionAddress = registry.publishElection(keyperSet, _params(admin));
        election = Election(payable(electionAddress));
        vm.stopBroadcast();
    }

    function _configureKeyperSet(KeyperSet keyperSet, address admin) private {
        address[] memory keypers = new address[](2);
        keypers[0] = vm.envOr("KEYPER_1", admin);
        keypers[1] = vm.envOr("KEYPER_2", admin);
        keyperSet.addMembers(keypers);
        keyperSet.setThreshold(2);
        keyperSet.setFinalized();
    }

    function _params(address admin) private view returns (VotingTypes.ElectionParams memory) {
        return VotingTypes.ElectionParams({
            votingStart: uint64(vm.envOr("VOTING_START", uint256(block.timestamp + 1 hours))),
            votingEnd: uint64(vm.envOr("VOTING_END", uint256(block.timestamp + 25 hours))),
            selfSubmitFee: vm.envOr("SELF_SUBMIT_FEE", uint256(0.01 ether)),
            numCandidates: uint32(vm.envOr("NUM_CANDIDATES", uint256(3))),
            budget: uint32(vm.envOr("BUDGET", uint256(1))),
            pkWR: vm.envOr("PK_WR", bytes("")),
            tallyAggregator: vm.envOr("TALLY_AGGREGATOR", admin),
            voteProxy: vm.envOr("VOTE_PROXY", admin)
        });
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Election} from "../src/Election.sol";
import {ElectionRegistry} from "../src/ElectionRegistry.sol";
import {KeyperSet} from "../src/KeyperSet.sol";
import {VotingTypes} from "../src/VotingTypes.sol";

contract DeployScript is Script {
    error InvalidKeyperCount();
    error InvalidThreshold(uint256 threshold, uint256 keyperCount);
    error InvalidVotingWindow(uint256 votingStart, uint256 votingEnd);
    error MissingEnv(string name);
    error MissingKeyperConfiguration();
    error ValueTooLarge(string name, uint256 value, uint256 maxValue);

    struct DeploymentConfig {
        address admin;
        address tallyAggregator;
        address voteProxy;
        uint64 threshold;
        uint64 votingStart;
        uint64 votingEnd;
        uint256 selfSubmitFee;
        uint32 numCandidates;
        uint32 budget;
        address[] keypers;
    }

    function run() external returns (KeyperSet keyperSet, ElectionRegistry registry, Election election) {
        DeploymentConfig memory config = _loadConfig();

        vm.startBroadcast();
        keyperSet = new KeyperSet(config.admin);
        registry = new ElectionRegistry(config.admin);

        _configureKeyperSet(keyperSet, config);

        address electionAddress = registry.publishElection(keyperSet, _electionParams(config));
        election = Election(payable(electionAddress));
        vm.stopBroadcast();

        _logDeployment(keyperSet, registry, election, config);
    }

    function _loadConfig() private view returns (DeploymentConfig memory config) {
        config.admin = _loadAdmin();
        config.keypers = _loadKeypers();
        config.threshold = _loadThreshold(config.keypers.length);
        config.votingStart = _toUint64("VOTING_START", vm.envOr("VOTING_START", uint256(block.timestamp + 1 hours)));
        config.votingEnd = _toUint64("VOTING_END", vm.envOr("VOTING_END", uint256(block.timestamp + 25 hours)));
        config.selfSubmitFee = vm.envOr("SELF_SUBMIT_FEE", uint256(0.01 ether));
        config.numCandidates = _toUint32("NUM_CANDIDATES", vm.envOr("NUM_CANDIDATES", uint256(3)));
        config.budget = _toUint32("BUDGET", vm.envOr("BUDGET", uint256(1)));
        config.tallyAggregator = vm.envOr("TALLY_AGGREGATOR", config.admin);
        config.voteProxy = vm.envOr("VOTE_PROXY", config.admin);

        if (config.votingEnd <= config.votingStart) {
            revert InvalidVotingWindow(config.votingStart, config.votingEnd);
        }
    }

    function _loadAdmin() private view returns (address admin) {
        if (vm.envExists("VOTE_MANAGER")) {
            return vm.envAddress("VOTE_MANAGER");
        }
        if (vm.envExists("PRIVATE_KEY")) {
            return vm.addr(vm.envUint("PRIVATE_KEY"));
        }
        revert MissingEnv("VOTE_MANAGER");
    }

    function _loadKeypers() private view returns (address[] memory keypers) {
        if (vm.envExists("KEYPERS")) {
            keypers = vm.envAddress("KEYPERS", ",");
            if (keypers.length == 0) revert InvalidKeyperCount();
            return keypers;
        }

        if (!vm.envExists("KEYPER_COUNT")) revert MissingKeyperConfiguration();

        uint256 keyperCount = vm.envUint("KEYPER_COUNT");
        if (keyperCount == 0) revert InvalidKeyperCount();

        keypers = new address[](keyperCount);
        for (uint256 index = 0; index < keyperCount; index++) {
            string memory envName = string.concat("KEYPER_", vm.toString(index + 1));
            if (!vm.envExists(envName)) revert MissingEnv(envName);
            keypers[index] = vm.envAddress(envName);
        }
    }

    function _loadThreshold(uint256 keyperCount) private view returns (uint64 threshold) {
        uint256 thresholdRaw = vm.envOr("KEYPER_THRESHOLD", keyperCount);
        if (thresholdRaw == 0 || thresholdRaw > keyperCount) {
            revert InvalidThreshold(thresholdRaw, keyperCount);
        }
        threshold = _toUint64("KEYPER_THRESHOLD", thresholdRaw);
    }

    function _configureKeyperSet(KeyperSet keyperSet, DeploymentConfig memory config) private {
        keyperSet.addMembers(config.keypers);
        keyperSet.setThreshold(config.threshold);
        keyperSet.setFinalized();
    }

    function _electionParams(DeploymentConfig memory config) private view returns (VotingTypes.ElectionParams memory) {
        return VotingTypes.ElectionParams({
            votingStart: config.votingStart,
            votingEnd: config.votingEnd,
            selfSubmitFee: config.selfSubmitFee,
            numCandidates: config.numCandidates,
            budget: config.budget,
            pkWR: vm.envOr("PK_WR", bytes("")),
            tallyAggregator: config.tallyAggregator,
            voteProxy: config.voteProxy
        });
    }

    function _logDeployment(
        KeyperSet keyperSet,
        ElectionRegistry registry,
        Election election,
        DeploymentConfig memory config
    ) private view {
        console2.log("Deployment complete");
        console2.log("Admin:", config.admin);
        console2.log("KeyperSet:", address(keyperSet));
        console2.log("ElectionRegistry:", address(registry));
        console2.log("Election:", address(election));
        console2.log("Election ID:", election.electionId());
        console2.log("Keyper threshold:", uint256(config.threshold));
        console2.log("Keyper count:", config.keypers.length);
        console2.log("Tally aggregator:", config.tallyAggregator);
        console2.log("Vote proxy:", config.voteProxy);
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IKeyperSet {
    function isFinalized() external view returns (bool);
    function getNumMembers() external view returns (uint64);
    function getMember(uint64 index) external view returns (address);
    function getMembers() external view returns (address[] memory);
    function getThreshold() external view returns (uint64);
    function isMember(address account) external view returns (bool);
    function addMembers(address[] calldata newMembers) external;
    function setThreshold(uint64 newThreshold) external;
    function setFinalized() external;
}

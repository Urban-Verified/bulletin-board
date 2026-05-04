// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElectionBase} from "./ElectionBase.sol";

abstract contract ElectionAdmin is ElectionBase {
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
}

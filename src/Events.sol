// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

/// @notice Emitted on a successful LSP7 token transfer made by the $POTATO token contract
///
/// @param from The UP address that sent a tip
/// @param to The UP address that received a tip
/// @param amount The amount of the tip in wei
event TipSent(address indexed from, address indexed to, uint256 amount);

/// @notice Emitted on a failed LSP7 token transfer made by the $POTATO token contract
///
/// @dev This event is emitted when a tip fails to be sent, which can happen if the `universalReceiver(...)`
/// function on `from` or `to` reverted during the LSP1 `universalReceiver(...)` hook call
/// (or any subsequent call made by `universalReceiver(...)` function of `from` or `to`).
///
/// @param from The UP address that sent a tip
/// @param to The UP address that received a tip
/// @param amount The amount of the tip in wei
/// @param errorData The error data returned from the failed transfer
event TipFailed(address indexed from, address indexed to, uint256 amount, bytes errorData);

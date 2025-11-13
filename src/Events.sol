// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

/// @notice Emitted on a successful LSP7 token transfer made by the $POTATO token contract
///
/// @param from The UP address that sent a tip
/// @param to The UP address that received a tip
/// @param amount The amount of 🥔 tokens sent as a tip (in wei with 18 decimals)
event TipSent(address indexed from, address indexed to, uint256 indexed amount);

/// @notice Emitted on a failed LSP7 token transfer made by the $POTATO token contract
///
/// @dev This event is emitted when a tip fails to be sent, which can happen if the `universalReceiver(...)`
/// function on `from` or `to` reverted during the LSP1 `universalReceiver(...)` hook call
/// (or any sub-calls made by `universalReceiver(...)` function of `from` or `to`).
///
/// @param from The UP address that sent the tip
/// @param to The UP address that was a recipient of the tip
/// @param amount The amount of 🥔 tokens that were attempted to be sent as a tip (in wei with 18 decimals)
/// @param errorData The error data returned from the failed LSP7 tokentransfer
event TipFailed(address indexed from, address indexed to, uint256 indexed amount, bytes errorData);

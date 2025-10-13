// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

event TipSent(address indexed from, address indexed to, uint256 amount);

event TipFailed(address indexed from, address indexed to, uint256 amount, bytes errorData);

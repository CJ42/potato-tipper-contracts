// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

// interfaces
import {ILSP7DigitalAsset as ILSP7} from "@lukso/lsp7-contracts/contracts/ILSP7DigitalAsset.sol";
import {ILSP26FollowerSystem as ILSP26} from "@lukso/lsp26-contracts/contracts/ILSP26FollowerSystem.sol";

// Address of the $POTATO Token contract deployed on LUKSO Testnet.
ILSP7 constant _POTATO_TOKEN = ILSP7(0xE8280e7f0d54daE39725dC5f500F567Af2854A13);

// Address of the Follower Registry deployed on LUKSO Testnet based on the LSP26 standard.
ILSP26 constant _FOLLOWER_REGISTRY = ILSP26(0xf01103E5a9909Fc0DBe8166dA7085e0285daDDcA);

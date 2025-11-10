// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

// interfaces
import {ILSP7DigitalAsset as ILSP7} from "@lukso/lsp7-contracts/contracts/ILSP7DigitalAsset.sol";
import {ILSP26FollowerSystem as ILSP26} from "@lukso/lsp26-contracts/contracts/ILSP26FollowerSystem.sol";

// ----------------------------------------------------------------------------------------------
// keccak256("PotatoTipper") = 0xd1d57abed02d4c2d7ce037580f0abe6e7bf141f9a07e2d0d09d90ed7d5f9128a
// keccak256("Settings") = 0xe8211998bb257be214c7b0997830cd295066cc6adf46c8dea63a2079d60c88d3
//
// key = bytes10(keccak256("PotatoTipper")) + 0000 + bytes20(keccak256("Settings"))
// value = (tip amount, min nb of followers, min $POTATO balance)
// ----------------------------------------------------------------------------------------------
// LSP2 ERC725Y JSON Schema
// {
//     name: "PotatoTipper:Settings",
//     key: 0xd1d57abed02d4c2d7ce00000e8211998bb257be214c7b0997830cd295066cc6a,
//     keyType: "Mapping",
//     valueType: "(uint256,uint256,uint256)",
//     valueContent: "(Number,Number,Number)"
// }
bytes32 constant POTATO_TIPPER_SETTINGS_DATA_KEY = 0xd1d57abed02d4c2d7ce00000e8211998bb257be214c7b0997830cd295066cc6a;

// Address of the $POTATO Token contract deployed on LUKSO Mainnet.
ILSP7 constant _POTATO_TOKEN = ILSP7(0x80D898C5A3A0B118a0c8C8aDcdBB260FC687F1ce);

// Address of the Follower Registry deployed on LUKSO Mainnet based on the LSP26 standard.
ILSP26 constant _FOLLOWER_REGISTRY = ILSP26(0xf01103E5a9909Fc0DBe8166dA7085e0285daDDcA);

// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

// interfaces
import {ILSP7DigitalAsset as ILSP7} from "@lukso/lsp7-contracts/contracts/ILSP7DigitalAsset.sol";

// ----------------------------------------------------------------------------------------------
// keccak256("PotatoTipper") = 0xd1d57abed02d4c2d7ce037580f0abe6e7bf141f9a07e2d0d09d90ed7d5f9128a
// keccak256("TipAmount") = 0x7ac37193edd83998b040b27baa12f8c01dc5eec0cf51ab0a70ea498f664d08f5
//
// key = bytes10(keccak256("PotatoTipper")) + 0000 + bytes20(keccak256("TipAmount"))
// ----------------------------------------------------------------------------------------------
// LSP2 ERC725Y JSON Schema
// {
//     name: "PotatoTipper:TipAmount",
//     key: 0xd1d57abed02d4c2d7ce000007ac37193edd83998b040b27baa12f8c01dc5eec0,
//     keyType: "Mapping",
//     valueType: "uint256",
//     valueContent: "Number"
// }
bytes32 constant POTATO_TIPPER_TIP_AMOUNT_DATA_KEY =
    0xd1d57abed02d4c2d7ce000007ac37193edd83998b040b27baa12f8c01dc5eec0;

// Address of the $POTATO Token contract deployed on LUKSO Mainnet.
ILSP7 constant _POTATO_TOKEN = ILSP7(0x80D898C5A3A0B118a0c8C8aDcdBB260FC687F1ce);

// Address of the Follower Registry deployed on LUKSO Mainnet based on the LSP26 standard.
address constant _FOLLOWER_REGISTRY = 0xf01103E5a9909Fc0DBe8166dA7085e0285daDDcA;

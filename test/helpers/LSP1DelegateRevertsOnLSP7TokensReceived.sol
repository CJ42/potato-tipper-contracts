// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

// interfaces
import {
    ILSP1UniversalReceiverDelegate as ILSP1Delegate
} from "@lukso/lsp1-contracts/contracts/ILSP1UniversalReceiverDelegate.sol";

import {_TYPEID_LSP7_TOKENSRECIPIENT} from "@lukso/lsp7-contracts/contracts/LSP7Constants.sol";

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

// constants
import {_INTERFACEID_LSP1_DELEGATE} from "@lukso/lsp1-contracts/contracts/LSP1Constants.sol";

contract LSP1DelegateRevertsOnLSP7TokensReceived is IERC165, ILSP1Delegate {
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == _INTERFACEID_LSP1_DELEGATE || interfaceId == type(IERC165).interfaceId;
    }

    function universalReceiverDelegate(address, uint256, bytes32 typeId, bytes memory)
        external
        pure
        override
        returns (bytes memory)
    {
        if (typeId == _TYPEID_LSP7_TOKENSRECIPIENT) revert("Force revert on LSP7TokensReceived");
        return "";
    }
}

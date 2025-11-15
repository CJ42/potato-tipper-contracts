// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

// interfaces
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {ILSP1UniversalReceiver} from "@lukso/lsp1-contracts/contracts/ILSP1UniversalReceiver.sol";

contract MinimalLSP1Implementer is IERC165, ILSP1UniversalReceiver {
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(ILSP1UniversalReceiver).interfaceId;
    }

    function universalReceiver(
        bytes32, // typeId
        bytes calldata // data
    )
        external
        payable
        returns (bytes memory)
    {
        return "Hey called the universal receiver function!";
    }
}

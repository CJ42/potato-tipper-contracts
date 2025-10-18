// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

/// @title PotatoLib
/// @notice Library for parsing PotatoTipper settings stored in the LSP2 ERC725Y data key `PotatoTipper:Settings`.
library PotatoLib {
    /// @dev Parses the raw bytes value stored under `POTATO_TIPPER_SETTINGS_DATA_KEY`
    /// into its respective tuple components:
    /// - tipAmount (uint256)
    /// - minimumFollowers (uint16)
    /// - minimumPotatoBalance (uint256)
    ///
    /// e.g:
    /// 0x000000000000000000000000000000000000000000000000000000000000000100020000000000000000000000000000000000000000000000000000000000000003
    /// => (1, 2, 3)
    ///
    /// @param rawValue The raw bytes value stored under `POTATO_TIPPER_SETTINGS_DATA_KEY`
    ///
    /// @return tipAmount The amount of $POTATO tokens to tip (in wei)
    /// @return minimumFollowers The minimum number of followers required to tip
    /// @return minimumPotatoBalance The minimum $POTATO token balance required to tip (in wei)
    function getSettings(bytes memory rawValue) internal pure returns (uint256, uint16, uint256) {
        uint256 tipAmount;
        uint16 minimumFollowers;
        uint256 minimumPotatoBalance;

        assembly {
            tipAmount := mload(add(rawValue, 32))
            minimumFollowers := mload(add(rawValue, 34))
            minimumPotatoBalance := mload(add(rawValue, 66))
        }

        return (tipAmount, minimumFollowers, minimumPotatoBalance);
    }
}


// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

/// @title PotatoLib
/// @notice Library for parsing PotatoTipper settings stored in the LSP2 ERC725Y data key `PotatoTipper:Settings`.
library PotatoLib {
    /// @dev Parses the raw bytes value stored under the `PotatoTipper:Settings` data key and decodes its tuple
    /// components: - tipAmount (uint256) = 32 bytes long
    /// - minimumFollowers (uint256) = 32 bytes long
    /// - minimumPotatoBalance (uint256) = 32 bytes long
    ///
    /// e.g:
    /// 0x0000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000056bc75e2d63100000
    /// => (1 $POTATO token as tip amount, 5 minimum followers, 100 $POTATO tokens minimum in follower balance)
    ///
    /// Note that the potato balance values in the tuple are encoded in wei, since the $POTATO token has 18 decimals
    ///
    /// @param rawValue The raw bytes value that was fetched from the `PotatoTipper:Settings` data key
    ///
    /// @return decodingSuccess False if couldn't decode because the raw value is not the correct length, true if the
    /// decoding was successful @return tipAmount The amount of $POTATO tokens to tip (in wei)
    /// @return minimumFollowers The minimum number of followers required to tip
    /// @return minimumPotatoBalance The minimum $POTATO token balance required to tip (in wei)
    function decodeSettings(bytes memory rawValue)
        internal
        pure
        returns (bool decodingSuccess, uint256, uint256, uint256)
    {
        // return early if the raw value is not the correct length
        if (rawValue.length != 96) return (false, 0, 0, 0);

        (uint256 tipAmount, uint256 minimumFollowers, uint256 minimumPotatoBalance) =
            abi.decode(rawValue, (uint256, uint256, uint256));

        return (true, tipAmount, minimumFollowers, minimumPotatoBalance);
    }
}


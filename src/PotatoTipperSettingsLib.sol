// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

// interfaces
import {IERC725Y} from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";

// constants
import {POTATO_TIPPER_SETTINGS_DATA_KEY} from "./Constants.sol";

/// @notice Object storing the tipping settings (tip amount and tip eligibility criterias).
/// @dev The tip amount and minimum potato balance are encoded "in wei", since the $POTATO token has 18 decimals.
struct TipSettings {
    uint256 tipAmount;
    uint256 minimumFollowers;
    uint256 minimumPotatoBalance;
}

/// @notice Fetch the encoded Potato Tipper tip settings from the `PotatoTipper:Settings` data key.
///
/// @param erc725YStorage The ERC725Y contract to read from (expected to be a Universal Profile)
/// @return The raw bytes value stored under the `PotatoTipper:Settings` data key
function loadTipSettingsRaw(IERC725Y erc725YStorage) view returns (bytes memory) {
    return erc725YStorage.getData(POTATO_TIPPER_SETTINGS_DATA_KEY);
}

/// @notice Decode the tipping settings from raw bytes to a struct object.
///
/// @dev Parses the raw abi-encoded tip settings and decodes its components:
/// - tipAmount (uint256) = 32 bytes long
/// - minimumFollowers (uint256) = 32 bytes long
/// - minimumPotatoBalance (uint256) = 32 bytes long
/// The `tipAmount` and `minimumPotatoBalance` values are encoded in wei, since the $POTATO token has 18 decimals.
///
/// e.g:
/// 0x0000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000056bc75e2d63100000
/// => (1 $POTATO token as tip amount, 5 minimum followers, 100 $POTATO tokens minimum in follower balance)
///
/// @param rawValue The raw encoded bytes for the tip settings (fetched from the `PotatoTipper:Settings` data key)
///
/// @return decodingSuccess Return if the data is correctly encoded and the tip amount is not 0.
/// @return settings The decoded tip settings as a struct object.
/// @return decodingErrorMessage A human-readable error message if the decoding failed, empty string if successful.
function decodeTipSettings(bytes memory rawValue)
    pure
    returns (bool decodingSuccess, TipSettings memory settings, bytes memory decodingErrorMessage)
{
    if (rawValue.length != 96) {
        decodingErrorMessage =
            unicode"❌ Invalid settings: settings value must be encoded as a 96 bytes long tuple of (uint256,uint256,uint256)";
        return (false, settings, decodingErrorMessage);
    }

    (uint256 tipAmount, uint256 minimumFollowers, uint256 minimumPotatoBalance) =
        abi.decode(rawValue, (uint256, uint256, uint256));

    settings = TipSettings({
        tipAmount: tipAmount, minimumFollowers: minimumFollowers, minimumPotatoBalance: minimumPotatoBalance
    });

    if (tipAmount == 0) {
        decodingErrorMessage = unicode"❌ Invalid settings: cannot set tip amount to 0";
        return (false, settings, decodingErrorMessage);
    }

    return (true, settings, "");
}

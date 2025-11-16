// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

// interfaces
import {ILSP7DigitalAsset as ILSP7} from "@lukso/lsp7-contracts/contracts/ILSP7DigitalAsset.sol";

// utils
import {LSP2Utils} from "@lukso/lsp2-contracts/contracts/LSP2Utils.sol";

// constants
import {_POTATO_TOKEN} from "./Constants.sol";
import {TipSettings} from "./PotatoTipperSettingsLib.sol";

struct ConfigDataKeys {
    bytes32 tipSettingsDataKey;
    bytes32 lsp1DelegateReactOnFollowDataKey;
    bytes32 lsp1DelegateReactOnUnfollowDataKey;
}

/// @dev ERC725Y data key where the tip settings are stored.
///
/// ```
/// keccak256("PotatoTipper") = 0xd1d57abed02d4c2d7ce037580f0abe6e7bf141f9a07e2d0d09d90ed7d5f9128a
/// keccak256("Settings") = 0xe8211998bb257be214c7b0997830cd295066cc6adf46c8dea63a2079d60c88d3
/// ```
///
/// key = bytes10(keccak256("PotatoTipper")) + 0000 + bytes20(keccak256("Settings"))
/// value = (tip amount, min nb of followers, min $POTATO balance)
/// -------------------------------------------------------------------------------------------------------
/// LSP2 ERC725Y JSON Schema
/// {
///     name: "PotatoTipper:Settings",
///     key: 0xd1d57abed02d4c2d7ce00000e8211998bb257be214c7b0997830cd295066cc6a,
///     keyType: "Mapping",
///     valueType: "(uint256,uint256,uint256)",
///     valueContent: "(Number,Number,Number)"
/// }
bytes32 constant POTATO_TIPPER_SETTINGS_DATA_KEY = 0xd1d57abed02d4c2d7ce00000e8211998bb257be214c7b0997830cd295066cc6a;

/// @dev ERC725Y data key where an LSP1 Delegate contract address is stored to react on follow / unfollow.
bytes32 constant LSP1DELEGATE_ON_FOLLOW_DATA_KEY = 0x0cfc51aec37c55a4d0b1000071e02f9f05bcd5816ec4f3134aa2e5a916669537;
bytes32 constant LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY = 0x0cfc51aec37c55a4d0b100009d3c0b4012b69658977b099bdaa51eff0f0460f4;

/// @notice Configurations to set to use the Potato Tipper contract
abstract contract PotatoTipperConfig {
    using LSP2Utils for bytes10;

    /// @notice Return a configuration object describing the data keys to set to:
    /// - connect the Potato Tipper contract
    /// - configure the tip settings
    function configDataKeys() public pure returns (ConfigDataKeys memory) {
        return ConfigDataKeys({
            tipSettingsDataKey: POTATO_TIPPER_SETTINGS_DATA_KEY,
            lsp1DelegateReactOnFollowDataKey: LSP1DELEGATE_ON_FOLLOW_DATA_KEY,
            lsp1DelegateReactOnUnfollowDataKey: LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY
        });
    }

    /// @notice Return an array of data keys to configure the PotatoTipper.
    /// Useful to be used with `setDataBatch(bytes32[],bytes[])`.
    function configDataKeysList() public pure returns (bytes32[] memory) {
        bytes32[] memory dataKeys = new bytes32[](3);
        dataKeys[0] = POTATO_TIPPER_SETTINGS_DATA_KEY;
        dataKeys[1] = LSP1DELEGATE_ON_FOLLOW_DATA_KEY;
        dataKeys[2] = LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY;
        return dataKeys;
    }

    /// @notice Return two lists of config data keys and values ready to be set via `setDataBatch(bytes32[],bytes[])`
    /// to configure the PotatoTipper contract.
    ///
    /// @dev Example usage:
    ///
    /// ```
    /// bytes memory tipSettings = TipSettings(
    ///     tipAmount: 1 ether,
    ///     minimumFollowers: 5,
    ///     minimumPotatoBalance: 100 ether
    /// );
    /// (bytes32[] memory dataKeys, bytes[] memory dataValues) =
    /// tipper.encodeConfigDataKeysValues(abi.encode(tipSettings));
    /// universalProfile.setDataBatch(dataKeys, dataValues);
    /// ```
    function encodeConfigDataKeysValues(TipSettings memory tipSettings)
        public
        view
        returns (bytes32[] memory configDataKeysToSet, bytes[] memory configDataValuesToSet)
    {
        configDataKeysToSet = configDataKeysList();

        bytes memory encodedPotatoTipperAddress = abi.encodePacked(address(this));
        bytes memory encodedTipSettings = abi.encode(tipSettings);

        configDataValuesToSet = new bytes[](3);
        configDataValuesToSet[0] = encodedTipSettings;
        configDataValuesToSet[1] = encodedPotatoTipperAddress;
        configDataValuesToSet[2] = encodedPotatoTipperAddress;

        return (configDataKeysToSet, configDataValuesToSet);
    }

    /// @notice LSP7 token used to send tips to new followers
    function token() public pure returns (ILSP7) {
        return _POTATO_TOKEN;
    }
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

// interfaces
import {ILSP7DigitalAsset as ILSP7} from "@lukso/lsp7-contracts/contracts/ILSP7DigitalAsset.sol";

// utils
import {LSP2Utils} from "@lukso/lsp2-contracts/contracts/LSP2Utils.sol";

// constants
import {
    _LSP1_UNIVERSAL_RECEIVER_DELEGATE_PREFIX as _LSP1_DELEGATE_PREFIX
} from "@lukso/lsp1-contracts/contracts/LSP1Constants.sol";
import {_TYPEID_LSP26_FOLLOW, _TYPEID_LSP26_UNFOLLOW} from "@lukso/lsp26-contracts/contracts/LSP26Constants.sol";
import {POTATO_TIPPER_SETTINGS_DATA_KEY, _POTATO_TOKEN} from "./Constants.sol";
import {TipSettings} from "./PotatoTipperSettingsLib.sol";

struct ConfigDataKeys {
    bytes32 tipSettingsDataKey;
    bytes32 lsp1DelegateReactOnFollowDataKey;
    bytes32 lsp1DelegateReactOnUnfollowDataKey;
}

/// @notice Configurations to set to use the Potato Tipper contract
abstract contract PotatoTipperConfig {
    using LSP2Utils for bytes10;

    bytes32 immutable _LSP1_DELEGATE_ON_FOLLOW_DATA_KEY =
        _LSP1_DELEGATE_PREFIX.generateMappingKey(bytes20(_TYPEID_LSP26_FOLLOW));
    bytes32 immutable _LSP1_DELEGATE_ON_UNFOLLOW_DATA_KEY =
        _LSP1_DELEGATE_PREFIX.generateMappingKey(bytes20(_TYPEID_LSP26_UNFOLLOW));

    /// @notice Return a configuration object describing the data keys to set to connect the Potato Tipper contract, and
    /// setup tips
    function configDataKeys() public view returns (ConfigDataKeys memory) {
        return ConfigDataKeys({
            tipSettingsDataKey: POTATO_TIPPER_SETTINGS_DATA_KEY,
            lsp1DelegateReactOnFollowDataKey: _LSP1_DELEGATE_ON_FOLLOW_DATA_KEY,
            lsp1DelegateReactOnUnfollowDataKey: _LSP1_DELEGATE_ON_UNFOLLOW_DATA_KEY
        });
    }

    /// @notice Return an array of data keys to configure the PotatoTipper. Useful to be used with
    /// `setDataBatch(bytes32[],bytes[])`
    function configDataKeysList() public view returns (bytes32[] memory) {
        bytes32[] memory dataKeys = new bytes32[](3);
        dataKeys[0] = POTATO_TIPPER_SETTINGS_DATA_KEY;
        dataKeys[1] = _LSP1_DELEGATE_ON_FOLLOW_DATA_KEY;
        dataKeys[2] = _LSP1_DELEGATE_ON_UNFOLLOW_DATA_KEY;
        return dataKeys;
    }

    /// @notice Return a list of config data keys and values ready set via `setDataBatch(bytes32[],bytes[])` to
    /// configure the PotatoTipper @dev Example usage:
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

    /// @notice LSP7 token used to send tip new followers
    function token() public pure returns (ILSP7) {
        return _POTATO_TOKEN;
    }
}

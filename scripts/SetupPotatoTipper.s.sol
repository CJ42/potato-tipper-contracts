// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC725X} from "@erc725/smart-contracts/contracts/interfaces/IERC725X.sol";
import {IERC725Y} from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";
import {ILSP0ERC725Account} from "@lukso/lsp0-contracts/contracts/ILSP0ERC725Account.sol";
import {ILSP7DigitalAsset as ILSP7} from "@lukso/lsp7-contracts/contracts/ILSP7DigitalAsset.sol";
import {_INTERFACEID_LSP0} from "@lukso/lsp0-contracts/contracts/LSP0Constants.sol";

import {
    POTATO_TIPPER_SETTINGS_DATA_KEY,
    LSP1DELEGATE_ON_FOLLOW_DATA_KEY,
    LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY
} from "../src/PotatoTipperConfig.sol";
import {_POTATO_TOKEN} from "../src/Constants.sol";

/// @title Setup PotatoTipper via LSP0 batchCalls
/// @notice One-click setup: connect PotatoTipper + set settings + authorize budget
/// @dev Run with: forge script scripts/SetupPotatoTipper.s.sol:SetupPotatoTipper --rpc-url lukso --broadcast
///
/// Required env vars:
/// - PRIVATE_KEY: EOA controller key (must have ADDUNIVERSALRECEIVERDELEGATE + CALL permissions on UP)
/// - UP_ADDRESS: Universal Profile address to configure
/// - TIP_AMOUNT: Amount to tip per follower (in wei, e.g., "1000000000000000000" = 1 POTATO)
/// - MIN_FOLLOWERS: Minimum follower count for eligibility (e.g., "5")
/// - MIN_POTATO_BALANCE: Minimum POTATO balance for eligibility (in wei, e.g., "100000000000000000000" = 100 POTATO)
/// - TIPPING_BUDGET: Total POTATO authorized for tipping (in wei, e.g., "1000000000000000000000" = 1000 POTATO)
contract SetupPotatoTipper is Script {
    address constant POTATO_TIPPER_ADDRESS = 0x5eed04004c2D46C12Fe30C639A90AD5d6F5D573d;

    struct SetupConfig {
        uint256 privateKey;
        address upAddress;
        uint256 tipAmount;
        uint256 minFollowers;
        uint256 minPotatoBalance;
        uint256 tippingBudget;
    }

    error InvalidAddress(string field);
    error InvalidAmount(string field);
    error TipAmountExceedsBudget(uint256 tipAmount, uint256 budget);
    error AddressIsNotUniversalProfile(address candidate);

    function run() external {
        SetupConfig memory config = _loadConfig();
        _validateConfig(config);
        _logConfig(config);

        bytes[] memory payloads = _buildBatchCallsPayloads(config);

        vm.startBroadcast(config.privateKey);

        console2.log("Broadcasting batchCalls to UP...");
        ILSP0ERC725Account(config.upAddress).batchCalls(payloads);

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Setup Complete ===");
        console2.log("PotatoTipper is now connected to the UP!");
        console2.log("Settings configured:");
        console2.log("  - Tip amount:", config.tipAmount, "wei");
        console2.log("  - Min followers:", config.minFollowers);
        console2.log("  - Min POTATO balance:", config.minPotatoBalance, "wei");
        console2.log("Tipping budget authorized:", config.tippingBudget, "wei");
    }

    function _loadConfig() internal view returns (SetupConfig memory config) {
        config.privateKey = vm.envUint("PRIVATE_KEY");
        config.upAddress = vm.envAddress("UP_ADDRESS");
        config.tipAmount = vm.envUint("TIP_AMOUNT");
        config.minFollowers = vm.envUint("MIN_FOLLOWERS");
        config.minPotatoBalance = vm.envUint("MIN_POTATO_BALANCE");
        config.tippingBudget = vm.envUint("TIPPING_BUDGET");
    }

    function _validateConfig(SetupConfig memory config) internal view {
        if (config.upAddress == address(0)) revert InvalidAddress("UP_ADDRESS");
        if (!IERC165(config.upAddress).supportsInterface(_INTERFACEID_LSP0)) {
            revert AddressIsNotUniversalProfile(config.upAddress);
        }
        if (config.tipAmount == 0) revert InvalidAmount("TIP_AMOUNT");
        if (config.tippingBudget == 0) revert InvalidAmount("TIPPING_BUDGET");
        if (config.tipAmount > config.tippingBudget) {
            revert TipAmountExceedsBudget(config.tipAmount, config.tippingBudget);
        }
    }

    function _buildBatchCallsPayloads(SetupConfig memory config) internal pure returns (bytes[] memory payloads) {
        bytes32[] memory dataKeys = new bytes32[](3);
        dataKeys[0] = POTATO_TIPPER_SETTINGS_DATA_KEY;
        dataKeys[1] = LSP1DELEGATE_ON_FOLLOW_DATA_KEY;
        dataKeys[2] = LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY;

        bytes[] memory dataValues = new bytes[](3);
        dataValues[0] = abi.encode(config.tipAmount, config.minFollowers, config.minPotatoBalance);

        bytes memory encodedTipperAddress = abi.encodePacked(POTATO_TIPPER_ADDRESS);
        dataValues[1] = encodedTipperAddress;
        dataValues[2] = encodedTipperAddress;

        payloads = new bytes[](2);
        payloads[0] = abi.encodeCall(IERC725Y.setDataBatch, (dataKeys, dataValues));

        bytes memory authorizeCalldata = abi.encodeCall(ILSP7.authorizeOperator, (POTATO_TIPPER_ADDRESS, config.tippingBudget, ""));

        payloads[1] = abi.encodeCall(
            IERC725X.execute,
            (0, address(_POTATO_TOKEN), 0, authorizeCalldata)
        );
    }

    function _logConfig(SetupConfig memory config) internal view {
        console2.log("=== PotatoTipper Setup ===");
        console2.log("Controller:", vm.addr(config.privateKey));
        console2.log("UP Address:", config.upAddress);
        console2.log("PotatoTipper:", POTATO_TIPPER_ADDRESS);
        console2.log("POTATO Token:", address(_POTATO_TOKEN));
        console2.log("Tip Amount (wei):", config.tipAmount);
        console2.log("Min Followers:", config.minFollowers);
        console2.log("Min POTATO Balance (wei):", config.minPotatoBalance);
        console2.log("Tipping Budget (wei):", config.tippingBudget);
        console2.log("");
    }
}

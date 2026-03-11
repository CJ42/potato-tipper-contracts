// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

interface ILSP0 {
    function batchCalls(uint256[] calldata values, bytes[] calldata payloads) external returns (bytes[] memory);
}

interface IERC725Y {
    function setDataBatch(bytes32[] calldata keys, bytes[] calldata values) external;
}

interface ILSP7 {
    function authorizeOperator(address operator, uint256 amount, bytes calldata data) external;
}

/// @title Setup PotatoTipper via LSP0 batchCalls
/// @notice One-click setup: connect PotatoTipper + set settings + authorize budget
/// @dev Run with: forge script scripts/SetupPotatoTipper.s.sol:SetupPotatoTipper --rpc-url lukso --broadcast
///
/// Required env vars:
/// - PRIVATE_KEY: EOA controller key (must have ADDUNIVERSALRECEIVERDELEGATE + CALL permissions on UP)
/// - UP_ADDRESS: Universal Profile address to configure
/// - POTATO_TIPPER_ADDRESS: PotatoTipper contract address
/// - POTATO_TOKEN_ADDRESS: $POTATO LSP7 token address
/// - TIP_AMOUNT: Amount to tip per follower (in wei, e.g., "1000000000000000000" = 1 POTATO)
/// - MIN_FOLLOWERS: Minimum follower count for eligibility (e.g., "5")
/// - MIN_POTATO_BALANCE: Minimum POTATO balance for eligibility (in wei, e.g., "100000000000000000000" = 100 POTATO)
/// - TIPPING_BUDGET: Total POTATO authorized for tipping (in wei, e.g., "1000000000000000000000" = 1000 POTATO)
contract SetupPotatoTipper is Script {
    bytes32 constant LSP1DELEGATE_ON_FOLLOW_DATA_KEY = 0x0cfc51aec37c55a4d0b1000071e02f9f05bcd5816ec4f3134aa2e5a916669537;
    bytes32 constant LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY = 0x0cfc51aec37c55a4d0b100009d3c0b4012b69658977b099bdaa51eff0f0460f4;
    bytes32 constant POTATO_TIPPER_SETTINGS_KEY = 0xd1d57abed02d4c2d7ce00000e8211998bb257be214c7b0997830cd295066cc6a;

    function run() external {
        address upAddress = vm.envAddress("UP_ADDRESS");
        address potatoTipperAddress = vm.envAddress("POTATO_TIPPER_ADDRESS");
        address potatoTokenAddress = vm.envAddress("POTATO_TOKEN_ADDRESS");
        uint256 tipAmount = vm.envUint("TIP_AMOUNT");
        uint256 minFollowers = vm.envUint("MIN_FOLLOWERS");
        uint256 minPotatoBalance = vm.envUint("MIN_POTATO_BALANCE");
        uint256 tippingBudget = vm.envUint("TIPPING_BUDGET");

        console2.log("=== PotatoTipper Setup ===");
        console2.log("UP Address:", upAddress);
        console2.log("PotatoTipper:", potatoTipperAddress);
        console2.log("POTATO Token:", potatoTokenAddress);
        console2.log("Tip Amount (wei):", tipAmount);
        console2.log("Min Followers:", minFollowers);
        console2.log("Min POTATO Balance (wei):", minPotatoBalance);
        console2.log("Tipping Budget (wei):", tippingBudget);
        console2.log("");

        bytes32[] memory dataKeys = new bytes32[](3);
        dataKeys[0] = POTATO_TIPPER_SETTINGS_KEY;
        dataKeys[1] = LSP1DELEGATE_ON_FOLLOW_DATA_KEY;
        dataKeys[2] = LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY;

        bytes[] memory dataValues = new bytes[](3);
        dataValues[0] = abi.encode(tipAmount, minFollowers, minPotatoBalance);
        dataValues[1] = abi.encodePacked(potatoTipperAddress);
        dataValues[2] = abi.encodePacked(potatoTipperAddress);

        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeCall(IERC725Y.setDataBatch, (dataKeys, dataValues));

        bytes memory authorizeCalldata = abi.encodeCall(
            ILSP7.authorizeOperator, (potatoTipperAddress, tippingBudget, "")
        );
        payloads[1] = abi.encodeWithSignature(
            "execute(uint256,address,uint256,bytes)", 0, potatoTokenAddress, 0, authorizeCalldata
        );

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        console2.log("Broadcasting batchCalls to UP...");
        ILSP0(upAddress).batchCalls(values, payloads);

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Setup Complete ===");
        console2.log("PotatoTipper is now connected to the UP!");
        console2.log("Settings configured:");
        console2.log("  - Tip amount:", tipAmount, "wei");
        console2.log("  - Min followers:", minFollowers);
        console2.log("  - Min POTATO balance:", minPotatoBalance, "wei");
        console2.log("Tipping budget authorized:", tippingBudget, "wei");
    }
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

interface IERC725Y {
    function getData(bytes32 key) external view returns (bytes memory);
    function getDataBatch(bytes32[] calldata keys) external view returns (bytes[] memory);
}

interface ILSP7 {
    function authorizedAmountFor(address operator, address tokenOwner) external view returns (uint256);
}

/// @title Post-Check: Verify PotatoTipper setup was applied correctly
/// @notice Reads back the 3 data keys from the UP and verifies they match expected values.
///         Also checks the $POTATO token allowance for the PotatoTipper contract.
/// @dev Run with: forge script scripts/PostCheck_SetupPotatoTipper.s.sol:PostCheckSetupPotatoTipper --rpc-url lukso
///
/// Required env vars:
/// - UP_ADDRESS: Universal Profile address to inspect
/// - POTATO_TIPPER_ADDRESS: Expected PotatoTipper contract address
/// - POTATO_TOKEN_ADDRESS: $POTATO LSP7 token address
/// - TIP_AMOUNT: Expected tip amount (in wei)
/// - MIN_FOLLOWERS: Expected minimum follower count
/// - MIN_POTATO_BALANCE: Expected minimum POTATO balance (in wei)
/// - TIPPING_BUDGET: Expected tipping budget (in wei)
contract PostCheckSetupPotatoTipper is Script {
    bytes32 constant LSP1DELEGATE_ON_FOLLOW_DATA_KEY = 0x0cfc51aec37c55a4d0b1000071e02f9f05bcd5816ec4f3134aa2e5a916669537;
    bytes32 constant LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY = 0x0cfc51aec37c55a4d0b100009d3c0b4012b69658977b099bdaa51eff0f0460f4;
    bytes32 constant POTATO_TIPPER_SETTINGS_KEY = 0xd1d57abed02d4c2d7ce00000e8211998bb257be214c7b0997830cd295066cc6a;

    function run() external view {
        address upAddress = vm.envAddress("UP_ADDRESS");
        address potatoTipperAddress = vm.envAddress("POTATO_TIPPER_ADDRESS");
        address potatoTokenAddress = vm.envAddress("POTATO_TOKEN_ADDRESS");
        uint256 expectedTipAmount = vm.envUint("TIP_AMOUNT");
        uint256 expectedMinFollowers = vm.envUint("MIN_FOLLOWERS");
        uint256 expectedMinPotatoBalance = vm.envUint("MIN_POTATO_BALANCE");
        uint256 expectedTippingBudget = vm.envUint("TIPPING_BUDGET");

        console2.log("=== Post-Check: PotatoTipper Setup Verification ===");
        console2.log("UP Address:           ", upAddress);
        console2.log("PotatoTipper Address: ", potatoTipperAddress);
        console2.log("POTATO Token Address: ", potatoTokenAddress);
        console2.log("");

        // Read all 3 data keys at once
        bytes32[] memory dataKeys = new bytes32[](3);
        dataKeys[0] = POTATO_TIPPER_SETTINGS_KEY;
        dataKeys[1] = LSP1DELEGATE_ON_FOLLOW_DATA_KEY;
        dataKeys[2] = LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY;

        bytes[] memory rawValues = IERC725Y(upAddress).getDataBatch(dataKeys);

        // --- Check 1: Settings key ---
        console2.log("--- Check 1: Tip Settings ---");
        if (rawValues[0].length == 0) {
            console2.log(unicode"❌ POTATO_TIPPER_SETTINGS_KEY is empty — settings were not written.");
        } else {
            (uint256 tipAmount, uint256 minFollowers, uint256 minPotatoBalance) =
                abi.decode(rawValues[0], (uint256, uint256, uint256));

            console2.log("  Tip Amount (wei):        ", tipAmount);
            console2.log("  Min Followers:           ", minFollowers);
            console2.log("  Min POTATO Balance (wei):", minPotatoBalance);

            bool settingsMatch = (tipAmount == expectedTipAmount) && (minFollowers == expectedMinFollowers)
                && (minPotatoBalance == expectedMinPotatoBalance);

            if (settingsMatch) {
                console2.log(unicode"  ✅ Settings match expected values.");
            } else {
                console2.log(unicode"  ❌ Settings do NOT match expected values.");
                console2.log("     Expected Tip Amount:        ", expectedTipAmount);
                console2.log("     Expected Min Followers:     ", expectedMinFollowers);
                console2.log("     Expected Min POTATO Balance:", expectedMinPotatoBalance);
            }
        }

        console2.log("");

        // --- Check 2: LSP1 delegate for follow ---
        console2.log("--- Check 2: LSP1 Delegate (on follow) ---");
        if (rawValues[1].length == 0) {
            console2.log(unicode"❌ LSP1DELEGATE_ON_FOLLOW_DATA_KEY is empty — delegate not set.");
        } else {
            address followDelegate = address(bytes20(rawValues[1]));
            if (followDelegate == potatoTipperAddress) {
                console2.log(unicode"  ✅ Follow delegate correctly set to PotatoTipper:", followDelegate);
            } else {
                console2.log(unicode"  ❌ Follow delegate mismatch.");
                console2.log("     Expected:", potatoTipperAddress);
                console2.log("     Got:     ", followDelegate);
            }
        }

        console2.log("");

        // --- Check 3: LSP1 delegate for unfollow ---
        console2.log("--- Check 3: LSP1 Delegate (on unfollow) ---");
        if (rawValues[2].length == 0) {
            console2.log(unicode"❌ LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY is empty — delegate not set.");
        } else {
            address unfollowDelegate = address(bytes20(rawValues[2]));
            if (unfollowDelegate == potatoTipperAddress) {
                console2.log(unicode"  ✅ Unfollow delegate correctly set to PotatoTipper:", unfollowDelegate);
            } else {
                console2.log(unicode"  ❌ Unfollow delegate mismatch.");
                console2.log("     Expected:", potatoTipperAddress);
                console2.log("     Got:     ", unfollowDelegate);
            }
        }

        console2.log("");

        // --- Check 4: Token allowance ---
        console2.log("--- Check 4: $POTATO Token Allowance ---");
        uint256 allowance = ILSP7(potatoTokenAddress).authorizedAmountFor(potatoTipperAddress, upAddress);
        console2.log("  Authorized amount (wei):", allowance);

        if (allowance >= expectedTippingBudget) {
            console2.log(unicode"  ✅ Tipping budget authorized — PotatoTipper can spend POTATO tokens.");
        } else if (allowance > 0) {
            console2.log(unicode"  ⚠️  Partial budget authorized. Expected:", expectedTippingBudget);
        } else {
            console2.log(unicode"  ❌ No tipping budget authorized — authorizeOperator was not called.");
        }

        console2.log("");
        console2.log("=== Verification Complete ===");
    }
}

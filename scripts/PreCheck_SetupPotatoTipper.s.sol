// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

interface IERC725Y {
    function getData(bytes32 key) external view returns (bytes memory);
}

/// @title Pre-Check: Verify ADDUNIVERSALRECEIVERDELEGATE permission before setup
/// @notice Reads the controller's LSP6 permissions on the UP and checks the ADDUNIVERSALRECEIVERDELEGATE bit
/// @dev Run with: forge script scripts/PreCheck_SetupPotatoTipper.s.sol:PreCheckSetupPotatoTipper --rpc-url lukso
///
/// Required env vars:
/// - PRIVATE_KEY: EOA controller key to check permissions for
/// - UP_ADDRESS: Universal Profile address to inspect
contract PreCheckSetupPotatoTipper is Script {
    // LSP6 permission bit for ADDUNIVERSALRECEIVERDELEGATE
    bytes32 constant PERMISSION_ADDUNIVERSALRECEIVERDELEGATE =
        0x0000000000000000000000000000000000000000000000000000000000000020;

    // LSP6 data key prefix: AddressPermissions:Permissions:<address>
    // keccak256("AddressPermissions:Permissions") = 0x4b80742de2bf82acb3630000
    bytes12 constant ADDRESS_PERMISSIONS_PERMISSIONS_PREFIX = 0x4b80742de2bf82acb3630000;

    function run() external view {
        address upAddress = vm.envAddress("UP_ADDRESS");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address controller = vm.addr(privateKey);

        console2.log("=== Pre-Check: PotatoTipper Setup ===");
        console2.log("UP Address:  ", upAddress);
        console2.log("Controller:  ", controller);
        console2.log("");

        // Build the AddressPermissions:Permissions:<controller> data key
        bytes32 permissionsKey = bytes32(abi.encodePacked(ADDRESS_PERMISSIONS_PERMISSIONS_PREFIX, controller));

        // Read permissions from the UP's ERC725Y storage
        bytes memory rawPermissions = IERC725Y(upAddress).getData(permissionsKey);

        if (rawPermissions.length == 0) {
            console2.log(
                unicode"❌ No permissions found for controller on this UP. The controller has no permissions at all."
            );
            console2.log("");
            console2.log("To fix: grant ADDUNIVERSALRECEIVERDELEGATE permission via the UP Browser Extension.");
            return;
        }

        bytes32 permissions = abi.decode(rawPermissions, (bytes32));
        bool hasPermission = (permissions & PERMISSION_ADDUNIVERSALRECEIVERDELEGATE) != 0;

        if (hasPermission) {
            console2.log(unicode"✅ Controller has ADDUNIVERSALRECEIVERDELEGATE permission — ready to run setup!");
        } else {
            console2.log(
                unicode"❌ Controller is MISSING the ADDUNIVERSALRECEIVERDELEGATE permission on this UP."
            );
            console2.log("");
            console2.log("To fix:");
            console2.log("  1. Open the UP Browser Extension");
            console2.log("  2. Navigate to Controllers");
            console2.log("  3. Find your controller address:", controller);
            console2.log("  4. Enable 'Add Universal Receiver Delegate' permission");
            console2.log("  5. Save and re-run this check");
        }
    }
}

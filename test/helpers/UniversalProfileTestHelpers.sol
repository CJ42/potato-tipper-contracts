// SPDX-License-Identifer: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

// modules
import {UniversalProfile} from "@lukso/universalprofile-contracts/contracts/UniversalProfile.sol";
import {LSP6KeyManager} from "@lukso/lsp6-contracts/contracts/LSP6KeyManager.sol";
import {
    LSP1UniversalReceiverDelegateUP as LSP1DelegateUP
} from "@lukso/lsp1delegate-contracts/contracts/LSP1UniversalReceiverDelegateUP.sol";

// libraries
import {LSP2Utils} from "@lukso/lsp2-contracts/contracts/LSP2Utils.sol";
import {LSP6Utils} from "@lukso/lsp6-contracts/contracts/LSP6Utils.sol";

// interfaces
import {
    ILSP1UniversalReceiverDelegate as ILSP1Delegate
} from "@lukso/lsp1-contracts/contracts/ILSP1UniversalReceiverDelegate.sol";
import {IERC725Y} from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";

// constants
import {
    _LSP1_UNIVERSAL_RECEIVER_DELEGATE_KEY,
    _LSP1_UNIVERSAL_RECEIVER_DELEGATE_PREFIX
} from "@lukso/lsp1-contracts/contracts/LSP1Constants.sol";
import {
    _LSP6KEY_ADDRESSPERMISSIONS_ARRAY,
    _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX,
    _PERMISSION_REENTRANCY,
    _PERMISSION_SUPER_SETDATA,
    ALL_REGULAR_PERMISSIONS,
    _PERMISSION_ADDUNIVERSALRECEIVERDELEGATE
} from "@lukso/lsp6-contracts/contracts/LSP6Constants.sol";
import {
    _TYPEID_LSP7_TOKENSSENDER,
    _TYPEID_LSP7_TOKENSRECIPIENT
} from "@lukso/lsp7-contracts/contracts/LSP7Constants.sol";

/// @dev Helper functions to deploy Universal Profiles and set them up
/// like if they were configured in the 🆙 Browser Extension 🧩
contract UniversalProfileTestHelpers is Test {
    using LSP2Utils for *;
    using LSP6Utils for *;

    LSP1DelegateUP mainLsp1DelegateImplementationForUps;

    function setUp() public virtual {
        mainLsp1DelegateImplementationForUps = new LSP1DelegateUP();
    }

    function _setUpUniversalProfileLikeBrowserExtension(address mainController) internal returns (UniversalProfile) {
        UniversalProfile universalProfile = new UniversalProfile(mainController);

        LSP6KeyManager keyManager = new LSP6KeyManager(address(universalProfile));

        _setupMainControllerPermissions(universalProfile, mainController);
        _setUPMainLSP1DelegateWithPermissions(universalProfile, mainController, mainLsp1DelegateImplementationForUps);

        _transferOwnershipToKeyManager(universalProfile, mainController, keyManager);

        return universalProfile;
    }

    function _setupMainLsp1DelegateWithPermissions(
        UniversalProfile universalProfile,
        address mainController,
        ILSP1Delegate mainLsp1DelegateImplementation
    ) internal {
        vm.startPrank(mainController);
        universalProfile.setData(
            _LSP1_UNIVERSAL_RECEIVER_DELEGATE_KEY, abi.encodePacked(mainLsp1DelegateImplementation)
        );

        // give SUPER_SETDATA + REENTRANCY permissions to the main LSP1 Universal Receiver Delegate
        // contract
        bytes32 permissionDataKeyForMainLSP1Delegate =
            _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX.generateMappingWithGroupingKey(
                bytes20(abi.encodePacked(mainLSP1DelegateImplementation))
            );

        // use Bitwise OR to set each permission bit individually
        // (just for simplicity here and avoid creating a `bytes32[] memory` array).
        // However, it is recommended to use the LSP6Utils.combinePermissions(...) function.
        universalProfile.setData(
            permissionDataKeyForMainLSP1Delegate, abi.encodePacked(_PERMISSION_REENTRANCY | _PERMISSION_SUPER_SETDATA)
        );

        vm.stopPrank();
    }

    function _setupMainControllerPermissions(UniversalProfile universalProfile, address mainController) internal {
        bytes32 dataKey =
            _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX.generateMappingWithGroupingKey(bytes20(mainController));

        bytes memory dataValue = abi.encodePacked(ALL_REGULAR_PERMISSIONS);

        vm.prank(mainController);
        universalProfile.setData(dataKey, dataValue);
    }

    function _transferOwnershipToKeyManager(
        UniversalProfile universalProfile,
        address oldOwner,
        LSP6KeyManager keyManager
    ) internal {
        vm.prank(oldOwner);
        universalProfile.transferOwnership(address(keyManager));

        vm.prank(address(keyManager));
        universalProfile.acceptOwnership();

        // Sanity CHECK to ensure KeyManager is now the UniversalProfile's owner
        assertEq(universalProfile.owner(), address(keyManager));
    }

    // Unused helper function for now (can be used for testing future reactions on tokens sent / received)
    // ---------------------------------------------------------------------------------------------------

    function _setUpSpecificLsp1DelegateForTokensSent(
        UniversalProfile universalProfile,
        address mainController,
        ILSP1Delegate specificLsp1Delegate,
        bytes32[] memory lsp1DelegatePermissionsList
    ) internal {
        vm.startPrank(mainController);

        bytes32 dataKeyLsp1DelegateForTokensSent =
            _LSP1_UNIVERSAL_RECEIVER_DELEGATE_PREFIX.generateMappingKey(bytes20(_TYPEID_LSP7_TOKENSSENDER));

        bytes32 dataKeyPermissionsOfLsp1Delegate =
            _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX.generateMappingWithGroupingKey(
                bytes20(abi.encodePacked(specificLsp1Delegate))
            );

        bytes32 lsp1DelegatePermissionsValue = lsp1DelegatePermissionsList.combinePermissions();

        // register the specific LSP1 delegate to react on tokens sent
        universalProfile.setData(dataKeyLsp1DelegateForTokensSent, abi.encodePacked(specificLsp1Delegate));

        // set the permissions for the specific LSP1 delegate
        universalProfile.setData(dataKeyPermissionsOfLsp1Delegate, abi.encodePacked(lsp1DelegatePermissionsValue));

        vm.stopPrank();
    }

    function _setUpSpecificLSP1DelegateForTokensReceived(
        UniversalProfile universalProfile,
        address mainController,
        ILSP1Delegate specificLsp1Delegate
    ) internal {
        bytes32 dataKeyLSP1DelegateForTokensReceived =
            _LSP1_UNIVERSAL_RECEIVER_DELEGATE_PREFIX.generateMappingKey(bytes20(_TYPEID_LSP7_TOKENSRECIPIENT));

        vm.prank(mainController);
        // register the specific LSP1 delegate to react on tokens received
        universalProfile.setData(dataKeyLSP1DelegateForTokensReceived, abi.encodePacked(specificLsp1Delegate));

        vm.stopPrank();
    }

    function _getControllerAtIndex(UniversalProfile profile, uint128 index) internal view returns (address) {
        bytes32 addressPermissionDataKeyAtIndex =
            _LSP6KEY_ADDRESSPERMISSIONS_ARRAY.generateArrayElementKeyAtIndex(index);

        bytes memory value = profile.getData(addressPermissionDataKeyAtIndex);
        assertTrue(value.length == 20, "not an address under AddressPermissions[index]");

        return address(bytes20(value));
    }

    /// @dev Give permission to add LSP1 Delegate
    function _grantAddLSP1DelegatePermissionToController(UniversalProfile profile, address controller) internal {
        bytes32 currentPermissions = IERC725Y(address(profile)).getPermissionsFor(controller);

        bytes32[] memory newPermissionsList = new bytes32[](2);
        newPermissionsList[0] = currentPermissions;
        newPermissionsList[1] = _PERMISSION_ADDUNIVERSALRECEIVERDELEGATE;

        bytes32 newPermissions = newPermissionsList.combinePermissions();

        vm.prank(controller);
        profile.setData(
            _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX.generateMappingKey(bytes20(controller)),
            abi.encodePacked(newPermissions)
        );
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// test libraries
import {Test} from "forge-std/Test.sol";
import {UniversalProfileTestHelpers} from "./helpers/UniversalProfileTestHelpers.sol";
import {NetworkForkTestHelpers} from "./helpers/NetworkForkTestHelpers.sol";

// interfaces
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC725Y} from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";
import {ILSP1UniversalReceiver} from "@lukso/lsp1-contracts/contracts/ILSP1UniversalReceiver.sol";
import {ILSP1UniversalReceiverDelegate as ILSP1Delegate} from
    "@lukso/lsp1-contracts/contracts/ILSP1UniversalReceiverDelegate.sol";
import {ILSP7DigitalAsset as ILSP7} from "@lukso/lsp7-contracts/contracts/ILSP7DigitalAsset.sol";

// utils
import {LSP2Utils} from "@lukso/lsp2-contracts/contracts/LSP2Utils.sol";
import {LSP6Utils} from "@lukso/lsp6-contracts/contracts/LSP6Utils.sol";

// constants
import {
    _INTERFACEID_LSP1_DELEGATE,
    _LSP1_UNIVERSAL_RECEIVER_DELEGATE_PREFIX
} from "@lukso/lsp1-contracts/contracts/LSP1Constants.sol";
import {
    _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX,
    _PERMISSION_ADDUNIVERSALRECEIVERDELEGATE
} from "@lukso/lsp6-contracts/contracts/LSP6Constants.sol";
import {_TYPEID_LSP26_UNFOLLOW} from "@lukso/lsp26-contracts/contracts/LSP26Constants.sol";
import {_FOLLOWER_REGISTRY, _TYPEID_LSP26_FOLLOW} from "../src/PotatoTipper.sol";
import {_POTATO_TOKEN} from "../src/PotatoTipper.sol";

// contracts to test
import {LSP26FollowerSystem} from "@lukso/lsp26-contracts/contracts/LSP26FollowerSystem.sol";
import {UniversalProfile} from "@lukso/universalprofile-contracts/contracts/UniversalProfile.sol";
import {PotatoTipper} from "../src/PotatoTipper.sol";

contract PotatoTipperTest is NetworkForkTestHelpers, UniversalProfileTestHelpers {
    using LSP6Utils for *;
    // uint256 luksoMainnetFork;

    bytes32 immutable _LSP1_DELEGATE_ON_FOLLOW_DATA_KEY = LSP2Utils.generateMappingKey(
        _LSP1_UNIVERSAL_RECEIVER_DELEGATE_PREFIX, bytes20(_TYPEID_LSP26_FOLLOW)
    );

    // mainnet contracts
    LSP26FollowerSystem followerRegistry = LSP26FollowerSystem(_FOLLOWER_REGISTRY);
    ILSP7 potatoToken = _POTATO_TOKEN;

    // 🆙 user contracts
    // The `follower` address below does not follow any of the two users listed
    address userBrowserExtensionController;
    UniversalProfile user = UniversalProfile(payable(0x927aAD446E3bF6eeB776387B3d7A89D8016fA54d)); // Jean

    address anotherUserBrowserExtensionController;
    UniversalProfile anotherUser =
        UniversalProfile(payable(0x041B2744fB8433Fc8165036d30072c514390271e)); // Lamboftodd

    address followerBrowserExtensionController;
    UniversalProfile follower =
        UniversalProfile(payable(0xbbE88a2F48eAA2EF04411e356d193BA3C1b37200)); // mbeezlyx

    // contract to test
    PotatoTipper potatoTipper;

    function setUp() public override {
        // _useMainnetForkEnvironment(); // This is not needed anymore
        super.setUp();

        // Fetch the main controller of these users
        userBrowserExtensionController = address(
            bytes20(
                user.getData(
                    // AddressPermissions[3]
                    bytes32(0xdf30dba06db6a30e65354d9a64c6098600000000000000000000000000000003)
                )
            )
        );

        anotherUserBrowserExtensionController = address(
            bytes20(
                anotherUser.getData(
                    // AddressPermissions[1]
                    bytes32(0xdf30dba06db6a30e65354d9a64c6098600000000000000000000000000000001)
                )
            )
        );

        followerBrowserExtensionController = address(
            bytes20(
                follower.getData(
                    // AddressPermissions[3]
                    bytes32(0xdf30dba06db6a30e65354d9a64c6098600000000000000000000000000000003)
                )
            )
        );

        potatoTipper = new PotatoTipper();

        vm.prank(userBrowserExtensionController);
        user.setData(_LSP1_DELEGATE_ON_FOLLOW_DATA_KEY, abi.encodePacked(address(potatoTipper)));

        // Give permission to add LSP1 Delegate
        bytes32 currentPermissions =
            IERC725Y(address(anotherUser)).getPermissionsFor(anotherUserBrowserExtensionController);

        bytes32[] memory newPermissionsList = new bytes32[](2);
        newPermissionsList[0] = currentPermissions;
        newPermissionsList[1] = _PERMISSION_ADDUNIVERSALRECEIVERDELEGATE;

        bytes32 newPermissions = LSP6Utils.combinePermissions(newPermissionsList);

        vm.prank(anotherUserBrowserExtensionController);
        anotherUser.setData(
            // AddressPermissions:Permissions:<controller>
            LSP2Utils.generateMappingKey(
                _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX,
                bytes20(anotherUserBrowserExtensionController)
            ),
            abi.encodePacked(newPermissions)
        );

        vm.prank(anotherUserBrowserExtensionController);
        anotherUser.setData(
            _LSP1_DELEGATE_ON_FOLLOW_DATA_KEY, abi.encodePacked(address(potatoTipper))
        );
    }

    function test_FollowerDoesNotAlreadyFollowUser() public view {
        assertFalse(followerRegistry.isFollowing(address(follower), address(user)));
    }

    function test_FollowerFollowUser() public {
        vm.prank(address(follower));
        followerRegistry.follow(address(user));

        assertTrue(followerRegistry.isFollowing(address(follower), address(user)));
    }

    function test_PotatoTipperIsRegisteredForNotificationTypeNewFollower() public view {
        bytes memory data = user.getData(_LSP1_DELEGATE_ON_FOLLOW_DATA_KEY);
        assertEq(data, abi.encodePacked(address(potatoTipper)));
    }

    function test_IsLSP1Delegate() public view {
        assertTrue(IERC165(address(potatoTipper)).supportsInterface(_INTERFACEID_LSP1_DELEGATE));
    }

    function test_shouldNotTipIfPotatoTipperHasNotBeenAuthorizedAsOperator() public {
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), 0);

        uint256 followerPotatoBalanceBefore = potatoToken.balanceOf(address(follower));

        assertFalse(potatoTipper.hasReceivedTip(address(user), address(follower)));

        vm.prank(address(follower));
        followerRegistry.follow(address(user));

        // CHECK that the follower did not receive any potato token
        uint256 followerPotatoBalanceAfter = potatoToken.balanceOf(address(follower));
        assertEq(followerPotatoBalanceAfter, followerPotatoBalanceBefore);

        // CHECK that the follower is still now following the user
        assertTrue(followerRegistry.isFollowing(address(follower), address(user)));

        assertFalse(potatoTipper.hasReceivedTip(address(user), address(follower)));
    }

    function test_tippingOnFollowAfterAuthorizingPotatoTipperAsOperator() public {
        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = potatoToken.balanceOf(address(follower));

        uint256 tipAmount = 1e18; // 1 $POTATO token
        uint256 tippingBudget = 10 * tipAmount;

        // Authorize the Potato Tipper contract to be able to transfer up to 10 POTATO tokens
        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");

        uint256 potatoTipperAllowanceBefore =
            potatoToken.authorizedAmountFor(address(potatoTipper), address(user));
        assertEq(potatoTipperAllowanceBefore, tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(user), address(follower)));

        vm.prank(address(follower));
        followerRegistry.follow(address(user));

        // CHECK that follower has received a tip (POTATO balance has increased by the tip amount)
        assertTrue(potatoTipper.hasReceivedTip(address(user), address(follower)));
        assertEq(potatoToken.balanceOf(address(follower)), followerPotatoBalanceBefore + tipAmount);

        // CHECK that the user's gave a tip
        // - $POTATO balance has decreased by tip amount)
        // - `POTATOTipper` allowance decreased by tip amount
        assertEq(potatoToken.balanceOf(address(user)), userPotatoBalanceBefore - tipAmount);
        assertEq(
            potatoToken.authorizedAmountFor(address(potatoTipper), address(user)),
            potatoTipperAllowanceBefore - tipAmount
        );
    }

    function test_FollowerCanReceiveTipsFromTwoDifferentFollowers() public {
        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));
        uint256 anotherUserPotatoBalanceBefore = potatoToken.balanceOf(address(anotherUser));
        uint256 followerPotatoBalanceBefore = potatoToken.balanceOf(address(follower));

        uint256 tipAmount = 1e18; // 1 $POTATO token
        uint256 tippingBudget = 10 * tipAmount;

        // Authorize the Potato Tipper contract to be able to transfer up to 10 POTATO tokens
        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");
        vm.prank(address(anotherUser));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");
        assertEq(
            potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget
        );
        assertEq(
            potatoToken.authorizedAmountFor(address(potatoTipper), address(anotherUser)),
            tippingBudget
        );

        // Following user 1
        assertFalse(potatoTipper.hasReceivedTip(address(user), address(follower)));

        vm.prank(address(follower));
        followerRegistry.follow(address(user));

        // CHECK that user has given a tip
        assertEq(potatoToken.balanceOf(address(user)), userPotatoBalanceBefore - tipAmount);
        assertEq(
            potatoToken.authorizedAmountFor(address(potatoTipper), address(user)),
            tippingBudget - tipAmount
        );

        // Following user 2
        assertFalse(potatoTipper.hasReceivedTip(address(anotherUser), address(follower)));

        vm.prank(address(follower));
        followerRegistry.follow(address(anotherUser));

        // CHECK that another user has given a tip
        assertEq(
            potatoToken.balanceOf(address(anotherUser)), anotherUserPotatoBalanceBefore - tipAmount
        );
        assertEq(
            potatoToken.authorizedAmountFor(address(potatoTipper), address(anotherUser)),
            tippingBudget - tipAmount
        );

        // CHECK that follower has received a tip
        assertTrue(potatoTipper.hasReceivedTip(address(user), address(follower)));
        assertTrue(potatoTipper.hasReceivedTip(address(anotherUser), address(follower)));
        assertEq(
            potatoToken.balanceOf(address(follower)), followerPotatoBalanceBefore + (tipAmount * 2)
        );
    }

    // TODO: these tests below are wrong as it's the UP that will call the POTATO Tipper
    // function test_ReturnSpecificMessagesDependingOnCall(address caller) public {
    //     vm.assume(caller != _FOLLOWER_REGISTRY);

    //     // This should not revert
    //     vm.prank(caller);
    //     bytes memory returnedData =
    // ILSP1Delegate(address(potatoTipper)).universalReceiverDelegate(
    //         msg.sender, // caller
    //         0, // value received
    //         bytes32(0), // typeId (= notification type)
    //         "" // any data we want to pass
    //     );

    //     assertEq(returnedData, unicode"❌ Not triggered by the Follower Registry");
    // }

    // function test_DoesNotRunOnUnfollowAndReturnSpecificMessageData() public {
    //     // Simulate call from Follower Registry with a typeId different than _TYPEID_LSP26_FOLLOW
    //     bytes memory returnedData =
    // ILSP1Delegate(address(potatoTipper)).universalReceiverDelegate(
    //         _FOLLOWER_REGISTRY, // caller
    //         0, // value received
    //         _TYPEID_LSP26_UNFOLLOW, // typeId (= notification type)
    //         "" // any data we want to pass
    //     );

    //     assertEq(returnedData, unicode"❌ Not a follow notification");
    // }

    // function test_RunsOnlyOnFollowReturnSpecificMessageData(bytes32 typeId) public {
    //     vm.assume(typeId != _TYPEID_LSP26_FOLLOW);

    //     // Simulate a call from the Follower Registry but with a typeId different than
    //     bytes memory returnedData =
    // ILSP1Delegate(address(potatoTipper)).universalReceiverDelegate(
    //         _FOLLOWER_REGISTRY, // caller
    //         0, // value received
    //         typeId, // typeId (= notification type)
    //         "" // any data we want to pass
    //     );

    //     assertEq(returnedData, unicode"❌ Not a follow notification");
    // }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// test libraries
import {Test, Vm, console} from "forge-std/Test.sol";
import {UniversalProfileTestHelpers} from "./helpers/UniversalProfileTestHelpers.sol";

// interfaces
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC725Y} from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";
import {ILSP1UniversalReceiver} from "@lukso/lsp1-contracts/contracts/ILSP1UniversalReceiver.sol";
import {ILSP1UniversalReceiverDelegate as ILSP1Delegate} from
    "@lukso/lsp1-contracts/contracts/ILSP1UniversalReceiverDelegate.sol";
import {ILSP7DigitalAsset as ILSP7} from "@lukso/lsp7-contracts/contracts/ILSP7DigitalAsset.sol";

// utils
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
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
import {
    _TYPEID_LSP26_FOLLOW, _TYPEID_LSP26_UNFOLLOW
} from "@lukso/lsp26-contracts/contracts/LSP26Constants.sol";
import {POTATO_TIPPER_TIP_AMOUNT_DATA_KEY, _FOLLOWER_REGISTRY, _POTATO_TOKEN} from "../src/Constants.sol";

// contracts to test
import {LSP26FollowerSystem} from "@lukso/lsp26-contracts/contracts/LSP26FollowerSystem.sol";
import {UniversalProfile} from "@lukso/universalprofile-contracts/contracts/UniversalProfile.sol";
import {PotatoTipper} from "../src/PotatoTipper.sol";

contract PotatoTipperTest is UniversalProfileTestHelpers {
    using Strings for address;
    using LSP6Utils for *;

    // TODO: Move to a parent `Config` contract added to the inheritance of the PotatoTipper contract
    // So that dApps can fetch the data key to configure easily without needing to encode with erc725.js
    bytes32 immutable _LSP1_DELEGATE_ON_FOLLOW_DATA_KEY =
        LSP2Utils.generateMappingKey(_LSP1_UNIVERSAL_RECEIVER_DELEGATE_PREFIX, bytes20(_TYPEID_LSP26_FOLLOW));

    bytes32 immutable _LSP1_DELEGATE_ON_UNFOLLOW_DATA_KEY = LSP2Utils.generateMappingKey(
        _LSP1_UNIVERSAL_RECEIVER_DELEGATE_PREFIX, bytes20(_TYPEID_LSP26_UNFOLLOW)
    );

    // Contract addresses from LUKSO Mainnet for mainnet fork testing
    // (🆙 users, 🥔 token, and LSP26 Follower Registry)
    //
    // Note: main controller addresses need to be retrieved to be able to do `setData(...)` to setup in tests:
    // - LSP1 Delegate to react on follow
    // - PotatoTipper:TipAmount
    // ------------------------------------------------------------------------------------------------------------------

    LSP26FollowerSystem followerRegistry = LSP26FollowerSystem(_FOLLOWER_REGISTRY);
    ILSP7 potatoToken = _POTATO_TOKEN;

    // Main 🆙 user setting Potato Tipper
    UniversalProfile user = UniversalProfile(payable(0x927aAD446E3bF6eeB776387B3d7A89D8016fA54d)); // Jean
    address userBrowserExtensionController;

    // Another user used for testing followers can get tips from multiple users you don't follow
    UniversalProfile anotherUser = UniversalProfile(payable(0x041B2744fB8433Fc8165036d30072c514390271e)); // Lamboftodd
    address anotherUserBrowserExtensionController;

    // This 🆙 does not follow any of the two users listed above
    UniversalProfile newFollower = UniversalProfile(payable(0xbbE88a2F48eAA2EF04411e356d193BA3C1b37200)); // mbeezlyx

    // This 🆙 already follows the first user
    // TODO: does it follow the other user? Test it too
    UniversalProfile existingFollower = UniversalProfile(payable(0x26e7Da1968cfC61FB8aB2Aad039b5A083b9De21e)); // ethalorian

    // contract to test
    PotatoTipper potatoTipper;
    uint256 constant TIP_AMOUNT = 1e18; // 1 $POTATO token

    function setUp() public override {
        super.setUp();

        potatoTipper = new PotatoTipper();

        // Fetch the main controller of these users`
        userBrowserExtensionController = _getControllerAtIndex(user, 3);
        anotherUserBrowserExtensionController = _getControllerAtIndex(anotherUser, 1);

        _grantAddLSP1DelegatePermissionToController(user, userBrowserExtensionController);
        _grantAddLSP1DelegatePermissionToController(anotherUser, anotherUserBrowserExtensionController);

        vm.startPrank(userBrowserExtensionController);
        user.setData(_LSP1_DELEGATE_ON_FOLLOW_DATA_KEY, abi.encodePacked(address(potatoTipper)));
        user.setData(_LSP1_DELEGATE_ON_UNFOLLOW_DATA_KEY, abi.encodePacked(address(potatoTipper)));
        user.setData(POTATO_TIPPER_TIP_AMOUNT_DATA_KEY, abi.encode(TIP_AMOUNT));
        vm.stopPrank();

        vm.startPrank(anotherUserBrowserExtensionController);
        anotherUser.setData(_LSP1_DELEGATE_ON_FOLLOW_DATA_KEY, abi.encodePacked(address(potatoTipper)));
        anotherUser.setData(_LSP1_DELEGATE_ON_UNFOLLOW_DATA_KEY, abi.encodePacked(address(potatoTipper)));
        anotherUser.setData(POTATO_TIPPER_TIP_AMOUNT_DATA_KEY, abi.encode(TIP_AMOUNT));
        vm.stopPrank();
    }

    // Pre tipping checks:
    // - follower does not already follow user
    // - follower has not received a tip yet
    // - PotatoTipper is authorized as operator by user for at least the tip amount
    function _preTippingChecks(address userTipping, address follower, uint256 tippingBudget) internal view {
        // CHECK PotatoTipper allowance is set
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), userTipping), tippingBudget);

        // CHECK that follower does not already follow user
        assertFalse(followerRegistry.isFollowing(address(follower), userTipping));

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(follower), userTipping));
    }

    // Post tipping checks:
    // - follower is now following user
    // - follower has received a tip (POTATO balance has increased by the tip amount)
    // - user has gave a tip (POTATO balance has decreased by tip amount)
    // - PotatoTipper allowance decreased by tip amount
    function _postTippingChecks(
        address userTipping,
        address followerReceivingTip,
        uint256 tipAmount,
        uint256 followerPotatoBalanceBefore,
        uint256 userPotatoBalanceBefore,
        uint256 potatoTipperAllowanceBefore
    ) internal view {
        // CHECK that follower is now following user
        assertTrue(followerRegistry.isFollowing(address(followerReceivingTip), userTipping));

        // CHECK that follower has received a tip (POTATO balance has increased by the tip amount)
        assertTrue(potatoTipper.hasReceivedTip(address(followerReceivingTip), userTipping));
        assertEq(
            potatoToken.balanceOf(address(followerReceivingTip)), followerPotatoBalanceBefore + tipAmount
        );

        // CHECK that the user's gave a tip
        assertEq(potatoToken.balanceOf(userTipping), userPotatoBalanceBefore - tipAmount);

        // CHECK that the PotatoTipper allowance decreased by tip amount
        assertEq(
            potatoToken.authorizedAmountFor(address(potatoTipper), userTipping),
            potatoTipperAllowanceBefore - tipAmount
        );
    }

    function _checkReturnedDataEmittedInUniversalReceiverEvent(
        Vm.Log[] memory logs,
        address expectedFollower,
        string memory expectedMessage
    ) internal pure {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] != ILSP1UniversalReceiver.UniversalReceiver.selector) continue;
            if (bytes32(logs[i].topics[3]) != _TYPEID_LSP26_FOLLOW) continue;

            // event UniversalReceiver(
            //     address indexed from,
            //     uint256 indexed value,
            //     bytes32 indexed typeId,
            //     bytes receivedData,
            //     bytes returnedValue
            // );
            // console.log("Found UniversalReceiver event related to a typeId new follow at index:", i);

            // receivedData + returnedValue
            // ------------------------------------------------------------------
            // 0x0000000000000000000000000000000000000000000000000000000000000040 <------------
            //.  0000000000000000000000000000000000000000000000000000000000000080 receivedData
            //.  0000000000000000000000000000000000000000000000000000000000000014 .............
            //.  bbe88a2f48eaa2ef04411e356d193ba3c1b37200000000000000000000000000 <------------
            //.  0000000000000000000000000000000000000000000000000000000000000100 returnedValue
            //.  0000000000000000000000000000000000000000000000000000000000000040 .............
            //.  0000000000000000000000000000000000000000000000000000000000000080 .............
            //.  0000000000000000000000000000000000000000000000000000000000000019 .............
            //.  4c5350313a20747970654964206f7574206f662073636f706500000000000000 .............
            //.  0000000000000000000000000000000000000000000000000000000000000050 .............
            //.  e29c85f09f8da0205375636365737366756c6c792074697070656420312024504f5441544f20746f6b656e20746f206e657720666f6c6c6f7765722ebbe88a2f48eaa2ef04411e356d193ba3c1b3720000000000000000000000000000000000

            (bytes memory receivedNotificationData, bytes memory allReturnedLSP1DelegateValues) =
                abi.decode((logs[i].data), (bytes, bytes));

            // CHECK LSP26 Follower registry sent follower address as notification data
            assertEq(receivedNotificationData, abi.encodePacked(expectedFollower));

            // CHECK Potato Tipper returned the right message
            assertEq(allReturnedLSP1DelegateValues, abi.encode("LSP1: typeId out of scope", expectedMessage));

            // 0x0000000000000000000000000000000000000000000000000000000000000040
            //.  0000000000000000000000000000000000000000000000000000000000000080
            //.  0000000000000000000000000000000000000000000000000000000000000019 -> 25 bytes
            //.  4c5350313a20747970654964206f7574206f662073636f706500000000000000
            //.  0000000000000000000000000000000000000000000000000000000000000050 -> 80 bytes
            //.  e29c85f09f8da0205375636365737366756c6c792074697070656420312024504f5441544f20746f6b656e20746f206e657720666f6c6c6f7765722ebbe88a2f48eaa2ef04411e356d193ba3c1b3720000000000000000000000000000000000

            // -> utf8("LSP1: typeId out of scope") = 25 bytes

            // Example:
            // -> ✅🍠 Successfully tipped 1 $POTATO token to new follower. (60 bytes characters)
            // -> e29c85 = utf8("✅") = 3 bytes
            // -> f09f8da0 = utf8("🍠") = 4 bytes
            // -> rest of the message = 53 bytes
            // -> follower address (abi packed encoded) = 20 bytes
            (bytes memory returnedDataDefaultLSP1Delegate, bytes memory returnedDataPotatoTipper) =
                abi.decode(allReturnedLSP1DelegateValues, (bytes, bytes));

            assertEq(string(returnedDataDefaultLSP1Delegate), "LSP1: typeId out of scope");
            assertEq(string(returnedDataPotatoTipper), expectedMessage);
        }
    }

    // Sanity checks

    function test_FollowerDoesNotAlreadyFollowUser() public view {
        assertFalse(followerRegistry.isFollowing(address(newFollower), address(user)));
    }

    function test_FollowerFollowUser() public {
        vm.prank(address(newFollower));
        followerRegistry.follow(address(user));

        assertTrue(followerRegistry.isFollowing(address(newFollower), address(user)));
    }

    // Setup tests

    function test_PotatoTipperIsRegisteredForNotificationTypeNewFollower() public view {
        bytes memory data = user.getData(_LSP1_DELEGATE_ON_FOLLOW_DATA_KEY);
        assertEq(data, abi.encodePacked(address(potatoTipper)));
    }

    function test_PotatoTipperIsRegisteredForNotificationTypeUnfollow() public view {
        bytes memory data = user.getData(_LSP1_DELEGATE_ON_UNFOLLOW_DATA_KEY);
        assertEq(data, abi.encodePacked(address(potatoTipper)));
    }

    function test_IsLSP1Delegate() public view {
        assertTrue(IERC165(address(potatoTipper)).supportsInterface(_INTERFACEID_LSP1_DELEGATE));
    }

    // Tipping behaviours tests

    function test_shouldNotTipButStillFollowIfPotatoTipperConnectedButNotAuthorizedAsOperator() public {
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), 0);

        uint256 followerPotatoBalanceBefore = potatoToken.balanceOf(address(newFollower));

        assertFalse(followerRegistry.isFollowing(address(newFollower), address(user)));
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));

        vm.prank(address(newFollower));
        followerRegistry.follow(address(user));

        // CHECK that the follower did not receive any potato token
        uint256 followerPotatoBalanceAfter = potatoToken.balanceOf(address(newFollower));
        assertEq(followerPotatoBalanceAfter, followerPotatoBalanceBefore);

        // CHECK that the follower is still now following the user
        assertTrue(followerRegistry.isFollowing(address(newFollower), address(user)));
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
    }

    function test_tippingOnFollowAfterAuthorizingPotatoTipperAsOperator() public {
        uint256 followerPotatoBalanceBefore = potatoToken.balanceOf(address(newFollower));
        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));
        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Authorize the Potato Tipper contract to be able to transfer up to 10 POTATO tokens
        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");

        _preTippingChecks(address(user), address(newFollower), tippingBudget);

        vm.prank(address(newFollower));
        followerRegistry.follow(address(user));

        _postTippingChecks(
            address(user),
            address(newFollower),
            TIP_AMOUNT,
            followerPotatoBalanceBefore,
            userPotatoBalanceBefore,
            tippingBudget
        );
    }

    // TODO: use helper functions pre + post tipping here for first occurence of following
    function test_cannotTipTwiceTheSameNewFollowerIfFollowedUnfollowAndRefollow() public {
        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = potatoToken.balanceOf(address(newFollower));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Authorize the Potato Tipper contract to be able to transfer up to 10 POTATO tokens
        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");

        uint256 potatoTipperAllowanceBefore =
            potatoToken.authorizedAmountFor(address(potatoTipper), address(user));
        assertEq(potatoTipperAllowanceBefore, tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));

        vm.recordLogs();

        vm.prank(address(newFollower));
        followerRegistry.follow(address(user));

        // CHECK that follower has received a tip (POTATO balance has increased by the tip amount)
        assertTrue(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertEq(potatoToken.balanceOf(address(newFollower)), followerPotatoBalanceBefore + TIP_AMOUNT);

        // CHECK that the user's gave a tip
        // - $POTATO balance has decreased by tip amount)
        // - POTATOTipper allowance decreased by tip amount
        assertEq(potatoToken.balanceOf(address(user)), userPotatoBalanceBefore - TIP_AMOUNT);
        assertEq(
            potatoToken.authorizedAmountFor(address(potatoTipper), address(user)),
            potatoTipperAllowanceBefore - TIP_AMOUNT
        );

        // CHECK for right data returned by Potato Tipper and emitted in the `UniversalReceiver` event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs,
            address(newFollower),
            unicode"✅ Successfully tipped 🍠 to new follower: 0xbbe88a2f48eaa2ef04411e356d193ba3c1b37200"
        );

        // Test unfollow and re-follow does not trigger a new tip
        vm.prank(address(newFollower));
        followerRegistry.unfollow(address(user));

        vm.prank(address(newFollower));
        followerRegistry.follow(address(user));

        // CHECK that follower has not received a second tip
        assertTrue(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertEq(potatoToken.balanceOf(address(newFollower)), followerPotatoBalanceBefore + TIP_AMOUNT);

        // CHECK that the user's did not give a second tip
        // - $POTATO balance has NOT decreased by tip amount)
        // - `POTATOTipper` allowance NOT decreased by tip amount
        assertEq(potatoToken.balanceOf(address(user)), userPotatoBalanceBefore - TIP_AMOUNT);
        assertEq(
            potatoToken.authorizedAmountFor(address(potatoTipper), address(user)),
            potatoTipperAllowanceBefore - TIP_AMOUNT
        );
    }

    function test_followerCanReceiveTipsFromTwoDifferentUsersWhoConnectedPotatoTipper() public {
        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));
        uint256 anotherUserPotatoBalanceBefore = potatoToken.balanceOf(address(anotherUser));
        uint256 followerPotatoBalanceBefore = potatoToken.balanceOf(address(newFollower));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Following user 1
        // ----------------

        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");

        _preTippingChecks(address(user), address(newFollower), tippingBudget);

        vm.prank(address(newFollower));
        followerRegistry.follow(address(user));

        _postTippingChecks(
            address(user),
            address(newFollower),
            TIP_AMOUNT,
            followerPotatoBalanceBefore,
            userPotatoBalanceBefore,
            tippingBudget
        );

        // Following user 2
        // ----------------

        vm.prank(address(anotherUser));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");

        _preTippingChecks(address(anotherUser), address(newFollower), tippingBudget);

        vm.prank(address(newFollower));
        followerRegistry.follow(address(anotherUser));

        // CHECK that the follower is now following both users
        assertTrue(followerRegistry.isFollowing(address(newFollower), address(user)));
        assertTrue(followerRegistry.isFollowing(address(newFollower), address(anotherUser)));

        // CHECK that another user has given a tip
        assertEq(potatoToken.balanceOf(address(anotherUser)), anotherUserPotatoBalanceBefore - TIP_AMOUNT);
        assertEq(
            potatoToken.authorizedAmountFor(address(potatoTipper), address(anotherUser)),
            tippingBudget - TIP_AMOUNT
        );

        // CHECK that follower has received a tip from both users
        assertTrue(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertTrue(potatoTipper.hasReceivedTip(address(newFollower), address(anotherUser)));

        // CHECK that follower's balance has increased by the tip amount x 2 from both users
        assertEq(potatoToken.balanceOf(address(newFollower)), followerPotatoBalanceBefore + (TIP_AMOUNT * 2));
    }

    function test_customTipAmount() public {
        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = potatoToken.balanceOf(address(newFollower));

        uint256 customTipAmount = 5e18; // 5 $POTATO token
        uint256 tippingBudget = 10 * customTipAmount;

        // Set custom tip amount to 5 POTATO tokens
        vm.prank(userBrowserExtensionController);
        user.setData(POTATO_TIPPER_TIP_AMOUNT_DATA_KEY, abi.encode(customTipAmount));

        assertEq(
            abi.decode(IERC725Y(address(user)).getData(POTATO_TIPPER_TIP_AMOUNT_DATA_KEY), (uint256)),
            customTipAmount
        );

        // Authorize the Potato Tipper contract to be able to transfer up to 50 POTATO tokens
        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");

        _preTippingChecks(address(user), address(newFollower), tippingBudget);

        vm.prank(address(newFollower));
        followerRegistry.follow(address(user));

        _postTippingChecks(
            address(user),
            address(newFollower),
            customTipAmount,
            followerPotatoBalanceBefore,
            userPotatoBalanceBefore,
            tippingBudget
        );
    }

    function test_customTipAmountIncorrectlySetDontTriggerTip(bytes memory badEncodedDataValue) public {
        vm.assume(badEncodedDataValue.length != 32);
        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = potatoToken.balanceOf(address(newFollower));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Set an incorrect value for the tip amount
        vm.prank(userBrowserExtensionController);
        user.setData(POTATO_TIPPER_TIP_AMOUNT_DATA_KEY, badEncodedDataValue);

        // Authorize the Potato Tipper contract to be able to transfer up to 50 POTATO tokens
        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");

        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));

        vm.prank(address(newFollower));
        followerRegistry.follow(address(user));

        // CHECK that follower has NOT received a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertEq(potatoToken.balanceOf(address(newFollower)), followerPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(potatoToken.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);
    }

    // TODO: fix this test
    function test_customTipAmountGreaterThanUserBalanceButLessThanTippingBudgetDontTriggerTip(
        uint256 customTipAmount,
        uint256 tippingBudget
    ) public {
        vm.skip(true);
        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));
        tippingBudget = bound(tippingBudget, customTipAmount + 1, userPotatoBalanceBefore);
        customTipAmount = bound(customTipAmount, userPotatoBalanceBefore + 1, tippingBudget);

        uint256 followerPotatoBalanceBefore = potatoToken.balanceOf(address(newFollower));

        // 0x0000000000000000000000000000000000000000000000000000000000000040
        //.  0000000000000000000000000000000000000000000000000000000000000080
        //.  0000000000000000000000000000000000000000000000000000000000000019
        //.  4c5350313a20747970654964206f7574206f662073636f706500000000000000
        //   0000000000000000000000000000000000000000000000000000000000000031
        //.  f09fa4b7f09f8fbbe2808de29982efb88f204e6f7420656e6f75676820f09fa59420746f2074697020666f6c6c6f776572000000000000000000000000000000;

        // 0x0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000194c5350313a20747970654964206f7574206f662073636f7065000000000000000000000000000000000000000000000000000000000000000000000000000025e29d8c204e6f7420656e6f756768206c65667420696e2074697070696e6720627564676574000000000000000000000000000000000000000000000000000000

        vm.prank(userBrowserExtensionController);
        user.setData(POTATO_TIPPER_TIP_AMOUNT_DATA_KEY, abi.encode(customTipAmount));

        // Authorize the Potato Tipper contract to be able to transfer $POTATO tokens
        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));

        vm.recordLogs();
        // CHECK for right data returned by Potato Tipper and emitted in the `UniversalReceiver` event

        vm.prank(address(newFollower));
        followerRegistry.follow(address(user));

        // CHECK that follower has NOT received a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertEq(potatoToken.balanceOf(address(newFollower)), followerPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(potatoToken.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(newFollower), unicode"🤷🏻‍♂️ Not enough 🥔 to tip follower"
        );
    }

    function test_customTipAmountLessThanUserBalanceButGreaterThanTippingBudgetDontTriggerTip(
        uint256 customTipAmount,
        uint256 potatoTipperAllowance
    ) public {
        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));

        vm.assume(potatoTipperAllowance < customTipAmount);
        uint256 tippingBudget = bound(potatoTipperAllowance, 1, userPotatoBalanceBefore);
        customTipAmount = bound(customTipAmount, tippingBudget + 1, userPotatoBalanceBefore);

        uint256 followerPotatoBalanceBefore = potatoToken.balanceOf(address(newFollower));

        // Set an incorrect value for the tip amount
        vm.prank(userBrowserExtensionController);
        user.setData(POTATO_TIPPER_TIP_AMOUNT_DATA_KEY, abi.encode(customTipAmount));

        // Authorize the Potato Tipper contract to be able to transfer up to 50 POTATO tokens
        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");

        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));

        vm.recordLogs();

        vm.prank(address(newFollower));
        followerRegistry.follow(address(user));

        // CHECK that follower has NOT received a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertEq(potatoToken.balanceOf(address(newFollower)), followerPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(potatoToken.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK for right data returned by Potato Tipper and emitted in the `UniversalReceiver` event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(newFollower), unicode"❌ Not enough left in tipping budget"
        );
    }

    function test_TippingFailsAfterTippingBudgetGoesToZero() public {
        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = potatoToken.balanceOf(address(newFollower));

        uint256 tippingBudget = TIP_AMOUNT;

        // Set custom tip amount to 5 POTATO tokens
        vm.prank(userBrowserExtensionController);
        user.setData(POTATO_TIPPER_TIP_AMOUNT_DATA_KEY, abi.encode(TIP_AMOUNT));

        assertEq(
            abi.decode(IERC725Y(address(user)).getData(POTATO_TIPPER_TIP_AMOUNT_DATA_KEY), (uint256)),
            TIP_AMOUNT
        );

        // Authorize the Potato Tipper contract to be able to transfer up to 50 POTATO tokens
        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");

        _preTippingChecks(address(user), address(newFollower), tippingBudget);

        vm.prank(address(newFollower));
        followerRegistry.follow(address(user));

        _postTippingChecks(
            address(user),
            address(newFollower),
            TIP_AMOUNT,
            followerPotatoBalanceBefore,
            userPotatoBalanceBefore,
            tippingBudget
        );

        // Check that subsequent tipping attempt will fail, but new follower will still be registered

        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), 0);

        UniversalProfile anotherFollower =
            UniversalProfile(payable(0x04063d2b65634a91221596Dc5864e3f12288fA16));

        uint256 anotherFollowerPotatoBalanceBefore = potatoToken.balanceOf(address(anotherFollower));

        assertFalse(followerRegistry.isFollowing(address(anotherFollower), address(user)));
        assertFalse(potatoTipper.hasReceivedTip(address(anotherFollower), address(user)));

        vm.recordLogs();

        vm.prank(address(anotherFollower));
        followerRegistry.follow(address(user));

        // CHECK that the follower did not receive any potato token
        uint256 anotherFollowerPotatoBalanceAfter = potatoToken.balanceOf(address(anotherFollower));
        assertEq(anotherFollowerPotatoBalanceAfter, anotherFollowerPotatoBalanceBefore);

        // CHECK that the follower is still now following the user
        assertTrue(followerRegistry.isFollowing(address(anotherFollower), address(user)));
        assertFalse(potatoTipper.hasReceivedTip(address(anotherFollower), address(user)));

        Vm.Log[] memory logs = vm.getRecordedLogs();

        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(anotherFollower), unicode"❌ Not enough left in tipping budget"
        );
    }

    function test_TippingFailsAfterTippingBudgetGoesBelowCustomAmount(uint256 tippingBudget) public {
        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = potatoToken.balanceOf(address(newFollower));

        tippingBudget = bound(tippingBudget, TIP_AMOUNT + 1, (TIP_AMOUNT * 2) - 1);

        // Set custom tip amount to 5 POTATO tokens
        vm.prank(userBrowserExtensionController);
        user.setData(POTATO_TIPPER_TIP_AMOUNT_DATA_KEY, abi.encode(TIP_AMOUNT));

        assertEq(
            abi.decode(IERC725Y(address(user)).getData(POTATO_TIPPER_TIP_AMOUNT_DATA_KEY), (uint256)),
            TIP_AMOUNT
        );

        // Authorize the Potato Tipper contract to be able to transfer up to 50 POTATO tokens
        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");

        _preTippingChecks(address(user), address(newFollower), tippingBudget);

        vm.prank(address(newFollower));
        followerRegistry.follow(address(user));

        _postTippingChecks(
            address(user),
            address(newFollower),
            TIP_AMOUNT,
            followerPotatoBalanceBefore,
            userPotatoBalanceBefore,
            tippingBudget
        );

        assertEq(
            potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget - TIP_AMOUNT
        );

        UniversalProfile anotherFollower =
            UniversalProfile(payable(0x04063d2b65634a91221596Dc5864e3f12288fA16));

        uint256 anotherFollowerPotatoBalanceBefore = potatoToken.balanceOf(address(anotherFollower));

        assertFalse(followerRegistry.isFollowing(address(anotherFollower), address(user)));
        assertFalse(potatoTipper.hasReceivedTip(address(anotherFollower), address(user)));

        vm.recordLogs();

        vm.prank(address(anotherFollower));
        followerRegistry.follow(address(user));

        // CHECK that the follower did not receive any potato token
        uint256 anotherFollowerPotatoBalanceAfter = potatoToken.balanceOf(address(anotherFollower));
        assertEq(anotherFollowerPotatoBalanceAfter, anotherFollowerPotatoBalanceBefore);

        // CHECK that the follower is still now following the user
        assertTrue(followerRegistry.isFollowing(address(anotherFollower), address(user)));
        assertFalse(potatoTipper.hasReceivedTip(address(anotherFollower), address(user)));

        Vm.Log[] memory logs = vm.getRecordedLogs();

        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(anotherFollower), unicode"❌ Not enough left in tipping budget"
        );
    }

    // Caller context tests

    // TODO: change this test (logic changed)
    function test_doesNotRunOnUnfollow() public {
        vm.skip(true);
        bytes32 lsp1DelegateOnUnfollowDataKey = LSP2Utils.generateMappingKey(
            _LSP1_UNIVERSAL_RECEIVER_DELEGATE_PREFIX, bytes20(_TYPEID_LSP26_UNFOLLOW)
        );

        // Assume the user connected the POTATO Tipper with the data key
        // LSP1UniversalReceiverDelegate:_TYPEID_LSP26_UNFOLLOW
        vm.prank(userBrowserExtensionController);
        user.setData(lsp1DelegateOnUnfollowDataKey, abi.encodePacked(address(potatoTipper)));

        vm.prank(address(12_345));
        followerRegistry.follow(address(user));

        vm.recordLogs();

        vm.prank(address(12_345));
        followerRegistry.unfollow(address(user));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(12_345), unicode"❌ Not a follow / unfollow notification"
        );
    }

    function test_OnlyRunWithFollowOrUnfollowTypeId(bytes32 typeId) public {
        vm.assume(typeId != _TYPEID_LSP26_FOLLOW);
        vm.assume(typeId != _TYPEID_LSP26_UNFOLLOW);

        vm.recordLogs();

        // This cannot happen in production as the follower registry can only trigger `universalReceiver(...)`
        // with the follow and unfollow type IDs, but testing for sanity purpose
        vm.prank(_FOLLOWER_REGISTRY);
        user.universalReceiver(typeId, abi.encodePacked(address(12_345)));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(12_345), unicode"❌ Not a follow or unfollow notification"
        );
    }

    function test_existingFollowerCannotTriggerDirectlyToGetTipped() public {
        assertTrue(
            LSP26FollowerSystem(_FOLLOWER_REGISTRY).isFollowing(address(existingFollower), address(user))
        );

        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));
        uint256 existingFollowerPotatoBalanceBefore = potatoToken.balanceOf(address(existingFollower));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Authorize the Potato Tipper contract to be able to transfer up to 50 POTATO tokens
        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));

        vm.recordLogs();

        vm.prank(address(existingFollower));
        user.universalReceiver(_TYPEID_LSP26_FOLLOW, abi.encodePacked(address(existingFollower)));

        // CHECK that follower did NOT receive a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertEq(potatoToken.balanceOf(address(existingFollower)), existingFollowerPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(potatoToken.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK for right data returned by Potato Tipper and emitted in the `UniversalReceiver` event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(existingFollower), unicode"❌ Not triggered by the Follower Registry"
        );
    }

    function test_OnlyCallsFromFollowerRegistry(address caller) public {
        vm.assume(caller != _FOLLOWER_REGISTRY);
        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));
        uint256 callerPotatoBalanceBefore = potatoToken.balanceOf(address(caller));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Authorize the Potato Tipper contract to be able to transfer up to 50 POTATO tokens
        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(caller), address(user)));

        vm.recordLogs();

        vm.prank(caller);
        user.universalReceiver(_TYPEID_LSP26_FOLLOW, abi.encodePacked(caller));

        // CHECK that follower did NOT receive a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(caller, address(user)));
        assertEq(potatoToken.balanceOf(caller), callerPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(potatoToken.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK for right data returned by Potato Tipper and emitted in the `UniversalReceiver` event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, caller, unicode"❌ Not triggered by the Follower Registry"
        );
    }

    /// @dev Not using a `uint256` to avoid using a number that is over the Secp256k1 curve order
    function test_EOAsCannotFollowAndReceiveTips(uint160 randomPrivateKey) public {
        vm.assume(randomPrivateKey != 0);

        address eoa = vm.addr(randomPrivateKey);

        vm.assume(eoa != address(0));
        vm.assume(eoa.code.length == 0);

        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));
        uint256 eoaPotatoBalanceBefore = potatoToken.balanceOf(address(eoa));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(eoa, address(user)));

        vm.recordLogs();

        vm.prank(eoa);
        followerRegistry.follow(address(user));

        // CHECK that follower did NOT receive a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(eoa, address(user)));
        assertEq(potatoToken.balanceOf(eoa), eoaPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(potatoToken.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK for right data returned by Potato Tipper and emitted in the `UniversalReceiver` event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(logs, eoa, unicode"❌ Only 🆙 allowed to be tipped");
    }

    function test_onlyUniversalProfilesCanReceiveTips(uint160 randomPrivateKey) public {
        vm.assume(randomPrivateKey != 0);
        // Mock a 🆙 minimal proxy pointing to UP implementation v0.12.1
        address universalProfile = vm.addr(randomPrivateKey);
        vm.etch(
            universalProfile,
            hex"363d3d373d3d3d363d7352c90985af970d4e0dc26cb5d052505278af32a95af43d82803e903d91602b57fd5bf3"
        );

        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));
        uint256 eoaPotatoBalanceBefore = potatoToken.balanceOf(address(universalProfile));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");

        _preTippingChecks(address(user), universalProfile, tippingBudget);

        vm.recordLogs();

        vm.prank(universalProfile);
        followerRegistry.follow(address(user));

        _postTippingChecks(
            address(user),
            address(universalProfile),
            TIP_AMOUNT,
            eoaPotatoBalanceBefore,
            userPotatoBalanceBefore,
            tippingBudget
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();

        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs,
            universalProfile,
            string.concat(unicode"✅ Successfully tipped 🍠 to new follower: ", universalProfile.toHexString())
        );
    }

    // Tests to add

    // - Existing follower unfollows, after that it is registered as `wasFollowingBeforePotatoTipper`
    // - Existing follower unfollowed -> then refollowed = did not get a tip
    // - New follower follows, but does not get a tip because POTATO allowance too low, then increase
    // allowance. Able to unfollow and then re-follow
    // - Test that the user cannot trigger the Potato Tipper directly even if it connected to the Potato
    // Tipper (via UP.execute(...) calling the `universalReceiverDelegate(...)` function on the Potato Tipper
    // contract)

    // Tests for gas cost of setting list of existing followers
    // -----------------------------------------------

    // function test_encodeListOfMappingWithGroupingKeys() public {
    //     vm.skip(true);
    //     uint256 initialFollowerCount =
    // LSP26FollowerSystem(_FOLLOWER_REGISTRY).followerCount(address(user));
    //     assertEq(initialFollowerCount, 217);

    //     address[] memory userInitialFollowers =
    // LSP26FollowerSystem(_FOLLOWER_REGISTRY).getFollowersByIndex(
    //         address(user), 0, initialFollowerCount
    //     );

    //     bytes32[] memory followersDataKeys = new bytes32[](initialFollowerCount);
    //     bytes[] memory followersDataValues = new bytes[](initialFollowerCount);

    //     // PotatoTipper:ExistingFollower:<address>
    //     bytes6 keyPrefix = 0xd1d57abed02d;
    //     bytes4 mapPrefix = 0xb67dad42;

    //     for (uint128 ii; ii < initialFollowerCount; ii++) {
    //         followersDataKeys[ii] = LSP2Utils.generateMappingWithGroupingKey(
    //             keyPrefix, mapPrefix, bytes20(userInitialFollowers[ii])
    //         );
    //         followersDataValues[ii] = hex"01";
    //     }

    //     console.log("setDataBatch calldata:");
    //     console.logBytes(abi.encodeCall(IERC725Y.setDataBatch, (followersDataKeys, followersDataValues)));
    // }

    // function test_abiEncodeArrayofFollowerAddressesAndStoreInSingleKey() public {
    //     vm.skip(true);
    //     uint256 initialFollowerCount =
    // LSP26FollowerSystem(_FOLLOWER_REGISTRY).followerCount(address(user));
    //     assertEq(initialFollowerCount, 218);

    //     address[] memory userInitialFollowers =
    // LSP26FollowerSystem(_FOLLOWER_REGISTRY).getFollowersByIndex(
    //         address(user), 0, initialFollowerCount
    //     );

    //     console.logBytes(
    //         abi.encodeCall(
    //             IERC725Y.setData, (keccak256("ExistingFollowers"), abi.encode(userInitialFollowers))
    //         )
    //     );

    //     console.logBytes(abi.encode(userInitialFollowers));
    // }

    // function test_settingFollowerListInLSP2ArrayKey() public {
    //     vm.skip(true);
    //     uint256 initialFollowerCount =
    // LSP26FollowerSystem(_FOLLOWER_REGISTRY).followerCount(address(user));
    //     assertEq(initialFollowerCount, 217);

    //     address[] memory userInitialFollowers =
    // LSP26FollowerSystem(_FOLLOWER_REGISTRY).getFollowersByIndex(
    //         address(user), 0, initialFollowerCount
    //     );

    //     bytes32[] memory followersDataKeys = new bytes32[](initialFollowerCount + 1);
    //     bytes[] memory followersDataValues = new bytes[](initialFollowerCount + 1);

    //     bytes32 EXISTING_FOLLOWER_ARRAY_DATA_KEY = keccak256("ExistingFollowers");
    //     console.logBytes32(EXISTING_FOLLOWER_ARRAY_DATA_KEY);

    //     followersDataKeys[0] = EXISTING_FOLLOWER_ARRAY_DATA_KEY;
    //     followersDataValues[0] = abi.encodePacked(uint128(initialFollowerCount));

    //     vm.prank(userBrowserExtensionController);
    //     user.setDataBatch(followersDataKeys, followersDataValues);

    //     for (uint128 ii; ii < initialFollowerCount; ii++) {
    //         bytes32 followerDataKey =
    //             LSP2Utils.generateArrayElementKeyAtIndex(EXISTING_FOLLOWER_ARRAY_DATA_KEY, ii);

    //         console.log("Follower data key:", ii);
    //         console.logBytes32(followerDataKey);

    //         followersDataKeys[ii + 1] = followerDataKey;
    //         followersDataValues[ii + 1] = abi.encodePacked(userInitialFollowers[ii]);
    //     }

    //     // console.logBytes(abi.encode(followersDataKeys));
    //     // console.logBytes(abi.encode(followersDataValues));
    //     console.log("setDataBatch calldata:");
    //     console.logBytes(abi.encodeCall(IERC725Y.setDataBatch, (followersDataKeys, followersDataValues)));

    //     assertEq(
    //         IERC725Y(address(user)).getData(EXISTING_FOLLOWER_ARRAY_DATA_KEY),
    //         abi.encodePacked(uint128(initialFollowerCount))
    //     );
    // }

    // function test_SettingInitialFollowerList() public {
    //     vm.skip(true);
    //     uint256 initialFollowerCount =
    // LSP26FollowerSystem(_FOLLOWER_REGISTRY).followerCount(address(user));
    //     assertEq(initialFollowerCount, 218);

    //     // address[] memory userInitialFollowers =
    //     // LSP26FollowerSystem(_FOLLOWER_REGISTRY).getFollowersByIndex(
    //     //     address(user), 0, initialFollowerCount
    //     // );

    //     // Set the initial follower list
    //     // vm.prank(address(user));
    //     // potatoTipper.setInitialFollowerList(userInitialFollowers);

    //     // for (uint256 ii; ii < initialFollowerCount; ii++) {
    //     //     assertTrue(potatoTipper.isInitialFollower(userInitialFollowers[ii], address(user)));
    //     // }
    // }
}

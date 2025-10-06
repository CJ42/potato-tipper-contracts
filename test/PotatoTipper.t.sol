// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// test libraries
import {Test, Vm, console} from "forge-std/Test.sol";
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
import {
    _TYPEID_LSP26_FOLLOW, _TYPEID_LSP26_UNFOLLOW
} from "@lukso/lsp26-contracts/contracts/LSP26Constants.sol";
import {POTATO_TIPPER_TIP_AMOUNT_DATA_KEY, _FOLLOWER_REGISTRY, _POTATO_TOKEN} from "../src/Constants.sol";

// contracts to test
import {LSP26FollowerSystem} from "@lukso/lsp26-contracts/contracts/LSP26FollowerSystem.sol";
import {UniversalProfile} from "@lukso/universalprofile-contracts/contracts/UniversalProfile.sol";
import {PotatoTipper} from "../src/PotatoTipper.sol";

// TODO: can probably remove `NetworkForkTestHelpers` from the inheritance
contract PotatoTipperTest is NetworkForkTestHelpers, UniversalProfileTestHelpers {
    using LSP6Utils for *;

    bytes32 immutable _LSP1_DELEGATE_ON_FOLLOW_DATA_KEY =
        LSP2Utils.generateMappingKey(_LSP1_UNIVERSAL_RECEIVER_DELEGATE_PREFIX, bytes20(_TYPEID_LSP26_FOLLOW));

    bytes32 immutable _LSP1_DELEGATE_ON_UNFOLLOW_DATA_KEY = LSP2Utils.generateMappingKey(
        _LSP1_UNIVERSAL_RECEIVER_DELEGATE_PREFIX, bytes20(_TYPEID_LSP26_UNFOLLOW)
    );

    // mainnet contracts
    LSP26FollowerSystem followerRegistry = LSP26FollowerSystem(_FOLLOWER_REGISTRY);
    ILSP7 potatoToken = _POTATO_TOKEN;

    // 🆙 user contracts
    // The `follower` address below does not follow any of the two users listed
    UniversalProfile user = UniversalProfile(payable(0x927aAD446E3bF6eeB776387B3d7A89D8016fA54d)); // Jean
    address userBrowserExtensionController;

    // TODO: rename to `newFollower`
    UniversalProfile follower = UniversalProfile(payable(0xbbE88a2F48eAA2EF04411e356d193BA3C1b37200)); // mbeezlyx
    address followerBrowserExtensionController;

    UniversalProfile existingFollower = UniversalProfile(payable(0x26e7Da1968cfC61FB8aB2Aad039b5A083b9De21e)); // ethalorian
    address existingFollowerBrowserExtensionController;

    // Used for testing getting tips from multiple users you don't follow
    UniversalProfile anotherUser = UniversalProfile(payable(0x041B2744fB8433Fc8165036d30072c514390271e)); // Lamboftodd
    address anotherUserBrowserExtensionController;

    // contract to test
    PotatoTipper potatoTipper;
    uint256 constant TIP_AMOUNT = 1e18; // 1 $POTATO token

    function setUp() public override {
        // _useMainnetForkEnvironment(); // This is not needed anymore
        super.setUp();

        // TODO: do I really need to get the main controller addresses? Can't I just vm.prank from these UP
        // addresses

        // Fetch the main controller of these users
        userBrowserExtensionController = address(
            bytes20(
                user.getData(
                    // AddressPermissions[3]
                    bytes32(0xdf30dba06db6a30e65354d9a64c6098600000000000000000000000000000003)
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

        existingFollowerBrowserExtensionController = address(
            bytes20(
                existingFollower.getData(
                    // AddressPermissions[1]
                    bytes32(0xdf30dba06db6a30e65354d9a64c6098600000000000000000000000000000001)
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
                _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX, bytes20(anotherUserBrowserExtensionController)
            ),
            abi.encodePacked(newPermissions)
        );

        vm.prank(anotherUserBrowserExtensionController);
        anotherUser.setData(_LSP1_DELEGATE_ON_FOLLOW_DATA_KEY, abi.encodePacked(address(potatoTipper)));

        vm.prank(userBrowserExtensionController);
        user.setData(POTATO_TIPPER_TIP_AMOUNT_DATA_KEY, abi.encode(TIP_AMOUNT));

        vm.prank(anotherUserBrowserExtensionController);
        anotherUser.setData(POTATO_TIPPER_TIP_AMOUNT_DATA_KEY, abi.encode(TIP_AMOUNT));
    }

    function _testCorrectDataReturnedAndEmittedInUniversalReceiverEvent(
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
        assertFalse(followerRegistry.isFollowing(address(follower), address(user)));
    }

    function test_FollowerFollowUser() public {
        vm.prank(address(follower));
        followerRegistry.follow(address(user));

        assertTrue(followerRegistry.isFollowing(address(follower), address(user)));
    }

    // POTATO Tipper setup tests

    function test_PotatoTipperIsRegisteredForNotificationTypeNewFollower() public view {
        bytes memory data = user.getData(_LSP1_DELEGATE_ON_FOLLOW_DATA_KEY);
        assertEq(data, abi.encodePacked(address(potatoTipper)));
    }

    function test_IsLSP1Delegate() public view {
        assertTrue(IERC165(address(potatoTipper)).supportsInterface(_INTERFACEID_LSP1_DELEGATE));
    }

    // POTATO Tipper behaviours tests

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

        uint256 tippingBudget = 10 * TIP_AMOUNT;

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
        assertEq(potatoToken.balanceOf(address(follower)), followerPotatoBalanceBefore + TIP_AMOUNT);

        // CHECK that the user's gave a tip
        // - $POTATO balance has decreased by tip amount)
        // - `POTATOTipper` allowance decreased by tip amount
        assertEq(potatoToken.balanceOf(address(user)), userPotatoBalanceBefore - TIP_AMOUNT);
        assertEq(
            potatoToken.authorizedAmountFor(address(potatoTipper), address(user)),
            potatoTipperAllowanceBefore - TIP_AMOUNT
        );
    }

    function test_cannotTipTwiceTheSameNewFollowerIfFollowedUnfollowAndRefollow() public {
        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = potatoToken.balanceOf(address(follower));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Authorize the Potato Tipper contract to be able to transfer up to 10 POTATO tokens
        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");

        uint256 potatoTipperAllowanceBefore =
            potatoToken.authorizedAmountFor(address(potatoTipper), address(user));
        assertEq(potatoTipperAllowanceBefore, tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(user), address(follower)));

        vm.recordLogs();

        vm.prank(address(follower));
        followerRegistry.follow(address(user));

        // CHECK that follower has received a tip (POTATO balance has increased by the tip amount)
        assertTrue(potatoTipper.hasReceivedTip(address(user), address(follower)));
        assertEq(potatoToken.balanceOf(address(follower)), followerPotatoBalanceBefore + TIP_AMOUNT);

        // CHECK that the user's gave a tip
        // - $POTATO balance has decreased by tip amount)
        // - `POTATOTipper` allowance decreased by tip amount
        assertEq(potatoToken.balanceOf(address(user)), userPotatoBalanceBefore - TIP_AMOUNT);
        assertEq(
            potatoToken.authorizedAmountFor(address(potatoTipper), address(user)),
            potatoTipperAllowanceBefore - TIP_AMOUNT
        );

        // CHECK for right data returned by Potato Tipper and emitted in the `UniversalReceiver` event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _testCorrectDataReturnedAndEmittedInUniversalReceiverEvent(
            logs,
            address(follower),
            unicode"✅🍠 Successfully tipped 1 $POTATO token to new follower: 0xbbe88a2f48eaa2ef04411e356d193ba3c1b37200"
        );

        // Test unfollow and re-follow does not trigger a new tip
        vm.prank(address(follower));
        followerRegistry.unfollow(address(user));

        vm.prank(address(follower));
        followerRegistry.follow(address(user));

        // CHECK that follower has not received a second tip
        assertTrue(potatoTipper.hasReceivedTip(address(user), address(follower)));
        assertEq(potatoToken.balanceOf(address(follower)), followerPotatoBalanceBefore + TIP_AMOUNT);

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
        uint256 followerPotatoBalanceBefore = potatoToken.balanceOf(address(follower));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Authorize the Potato Tipper contract to be able to transfer up to 10 POTATO tokens
        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");
        vm.prank(address(anotherUser));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(anotherUser)), tippingBudget);

        // Following user 1
        assertFalse(potatoTipper.hasReceivedTip(address(user), address(follower)));

        vm.prank(address(follower));
        followerRegistry.follow(address(user));

        // CHECK that user has given a tip
        assertEq(potatoToken.balanceOf(address(user)), userPotatoBalanceBefore - TIP_AMOUNT);
        assertEq(
            potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget - TIP_AMOUNT
        );

        // Following user 2
        assertFalse(potatoTipper.hasReceivedTip(address(anotherUser), address(follower)));

        vm.prank(address(follower));
        followerRegistry.follow(address(anotherUser));

        // CHECK that another user has given a tip
        assertEq(potatoToken.balanceOf(address(anotherUser)), anotherUserPotatoBalanceBefore - TIP_AMOUNT);
        assertEq(
            potatoToken.authorizedAmountFor(address(potatoTipper), address(anotherUser)),
            tippingBudget - TIP_AMOUNT
        );

        // CHECK that follower has received a tip
        assertTrue(potatoTipper.hasReceivedTip(address(user), address(follower)));
        assertTrue(potatoTipper.hasReceivedTip(address(anotherUser), address(follower)));
        assertEq(potatoToken.balanceOf(address(follower)), followerPotatoBalanceBefore + (TIP_AMOUNT * 2));
    }

    function test_customTipAmount() public {
        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = potatoToken.balanceOf(address(follower));

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

        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(user), address(follower)));

        vm.prank(address(follower));
        followerRegistry.follow(address(user));

        // CHECK that follower has received a tip (POTATO balance has increased by the tip amount)
        assertTrue(potatoTipper.hasReceivedTip(address(user), address(follower)));
        assertEq(potatoToken.balanceOf(address(follower)), followerPotatoBalanceBefore + customTipAmount);

        // CHECK that the user's gave a tip
        // - $POTATO balance has decreased by tip amount)
        // - `POTATOTipper` allowance decreased by tip amount
        assertEq(potatoToken.balanceOf(address(user)), userPotatoBalanceBefore - customTipAmount);
        assertEq(
            potatoToken.authorizedAmountFor(address(potatoTipper), address(user)),
            tippingBudget - customTipAmount
        );
    }

    function test_customTipAmountIncorrectlySetDontTriggerTip(bytes memory badEncodedDataValue) public {
        vm.assume(badEncodedDataValue.length != 32);
        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = potatoToken.balanceOf(address(follower));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Set an incorrect value for the tip amount
        vm.prank(userBrowserExtensionController);
        user.setData(POTATO_TIPPER_TIP_AMOUNT_DATA_KEY, badEncodedDataValue);

        // Authorize the Potato Tipper contract to be able to transfer up to 50 POTATO tokens
        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");

        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(user), address(follower)));

        vm.prank(address(follower));
        followerRegistry.follow(address(user));

        // CHECK that follower has NOT received a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(address(user), address(follower)));
        assertEq(potatoToken.balanceOf(address(follower)), followerPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(potatoToken.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);
    }

    function test_customTipAmountGreaterThanUserBalanceDontTriggerTip(uint256 customTipAmount) public {
        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));
        customTipAmount = bound(customTipAmount, userPotatoBalanceBefore + 1, type(uint256).max);

        uint256 followerPotatoBalanceBefore = potatoToken.balanceOf(address(follower));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Set an incorrect value for the tip amount
        vm.prank(userBrowserExtensionController);
        user.setData(POTATO_TIPPER_TIP_AMOUNT_DATA_KEY, abi.encode(customTipAmount));

        // Authorize the Potato Tipper contract to be able to transfer up to 50 POTATO tokens
        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");

        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(user), address(follower)));

        vm.recordLogs();
        // CHECK for right data returned by Potato Tipper and emitted in the `UniversalReceiver` event

        vm.prank(address(follower));
        followerRegistry.follow(address(user));

        // CHECK that follower has NOT received a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(address(user), address(follower)));
        assertEq(potatoToken.balanceOf(address(follower)), followerPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(potatoToken.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _testCorrectDataReturnedAndEmittedInUniversalReceiverEvent(
            logs, address(follower), unicode"🤷🏻‍♂️ Not enough 🥔 to tip the follower"
        );
    }

    function test_customTipAmountGreaterThanPotatoTipperAllowanceButLessThanUserBalanceDontTriggerTip(
        uint256 customTipAmount,
        uint256 potatoTipperAllowance
    ) public {
        uint256 userPotatoBalanceBefore = potatoToken.balanceOf(address(user));

        vm.assume(potatoTipperAllowance < customTipAmount);
        uint256 tippingBudget = bound(potatoTipperAllowance, 1, userPotatoBalanceBefore);
        customTipAmount = bound(customTipAmount, tippingBudget + 1, userPotatoBalanceBefore);

        uint256 followerPotatoBalanceBefore = potatoToken.balanceOf(address(follower));

        // Set an incorrect value for the tip amount
        vm.prank(userBrowserExtensionController);
        user.setData(POTATO_TIPPER_TIP_AMOUNT_DATA_KEY, abi.encode(customTipAmount));

        // Authorize the Potato Tipper contract to be able to transfer up to 50 POTATO tokens
        vm.prank(address(user));
        potatoToken.authorizeOperator(address(potatoTipper), tippingBudget, "");

        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(user), address(follower)));

        vm.recordLogs();

        vm.prank(address(follower));
        followerRegistry.follow(address(user));

        // CHECK that follower has NOT received a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(address(user), address(follower)));
        assertEq(potatoToken.balanceOf(address(follower)), followerPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(potatoToken.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK for right data returned by Potato Tipper and emitted in the `UniversalReceiver` event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _testCorrectDataReturnedAndEmittedInUniversalReceiverEvent(
            logs, address(follower), unicode"❌ Not enough allowance to tip $POTATO tokens"
        );
    }

    function test_doesNotRunOnUnfollow() public {
        // Assume the user connected the POTATO Tipper with the data key
        // LSP1UniversalReceiverDelegate:_TYPEID_LSP26_UNFOLLOW
        vm.prank(userBrowserExtensionController);
        user.setData(_LSP1_DELEGATE_ON_UNFOLLOW_DATA_KEY, abi.encodePacked(address(potatoTipper)));

        vm.prank(address(12_345));
        followerRegistry.follow(address(user));

        vm.recordLogs();

        vm.prank(address(12_345));
        followerRegistry.unfollow(address(user));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _testCorrectDataReturnedAndEmittedInUniversalReceiverEvent(
            logs, address(12_345), unicode"❌ Not a follow notification"
        );
    }

    function test_OnlyRunWithFollowTypeId(bytes32 typeId) public {
        vm.assume(typeId != _TYPEID_LSP26_FOLLOW);

        vm.recordLogs();

        // This cannot happen in production as the follower registry can only trigger `universalReceiver(...)`
        // with the follow and unfollow type IDs, but testing for sanity purpose
        vm.prank(_FOLLOWER_REGISTRY);
        user.universalReceiver(typeId, abi.encodePacked(address(12_345)));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _testCorrectDataReturnedAndEmittedInUniversalReceiverEvent(
            logs, address(12_345), unicode"❌ Not a follow notification"
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
        assertFalse(potatoTipper.hasReceivedTip(address(user), address(follower)));

        vm.recordLogs();

        vm.prank(address(existingFollower));
        user.universalReceiver(_TYPEID_LSP26_FOLLOW, abi.encodePacked(address(existingFollower)));

        // CHECK that follower did NOT receive a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(address(user), address(follower)));
        assertEq(potatoToken.balanceOf(address(existingFollower)), existingFollowerPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(potatoToken.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK for right data returned by Potato Tipper and emitted in the `UniversalReceiver` event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _testCorrectDataReturnedAndEmittedInUniversalReceiverEvent(
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
        assertFalse(potatoTipper.hasReceivedTip(address(user), address(follower)));

        vm.recordLogs();

        vm.prank(caller);
        user.universalReceiver(_TYPEID_LSP26_FOLLOW, abi.encodePacked(address(caller)));

        // CHECK that follower did NOT receive a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(address(user), address(follower)));
        assertEq(potatoToken.balanceOf(address(caller)), callerPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(potatoToken.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(potatoToken.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK for right data returned by Potato Tipper and emitted in the `UniversalReceiver` event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _testCorrectDataReturnedAndEmittedInUniversalReceiverEvent(
            logs, address(caller), unicode"❌ Not triggered by the Follower Registry"
        );
    }

    // function test_SettingInitialFollowerList() public {
    //     uint256 initialFollowerCount =
    // LSP26FollowerSystem(_FOLLOWER_REGISTRY).followerCount(address(user));
    //     assertEq(initialFollowerCount, 216);

    //     address[] memory userInitialFollowers =
    // LSP26FollowerSystem(_FOLLOWER_REGISTRY).getFollowersByIndex(
    //         address(user), 0, initialFollowerCount
    //     );

    //     // Set the initial follower list
    //     vm.prank(userBrowserExtensionController);
    //     potatoTipper.setInitialFollowerList(userInitialFollowers);
    // }
}

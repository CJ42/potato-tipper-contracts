// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

// test libraries
import {Vm} from "forge-std/Test.sol";
import {UniversalProfileTestHelpers} from "./helpers/UniversalProfileTestHelpers.sol";
import {LSP1DelegateRevertsOnLSP7TokensReceived} from "./mocks/LSP1DelegateRevertsOnLSP7TokensReceived.sol";
import {MinimalLSP1Implementer} from "./mocks/MinimalLSP1Implementer.sol";

// interfaces
import {IERC725Y} from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";
import {ILSP1UniversalReceiver} from "@lukso/lsp1-contracts/contracts/ILSP1UniversalReceiver.sol";
import {
    ILSP1UniversalReceiverDelegate as ILSP1Delegate
} from "@lukso/lsp1-contracts/contracts/ILSP1UniversalReceiverDelegate.sol";
import {ILSP7DigitalAsset as ILSP7} from "@lukso/lsp7-contracts/contracts/ILSP7DigitalAsset.sol";

// utils
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {LSP2Utils} from "@lukso/lsp2-contracts/contracts/LSP2Utils.sol";
import {LSP6Utils} from "@lukso/lsp6-contracts/contracts/LSP6Utils.sol";
import "../src/PotatoTipperSettingsLib.sol" as SettingsLib;

// constants
import {
    _LSP1_UNIVERSAL_RECEIVER_DELEGATE_PREFIX as _LSP1_DELEGATE_PREFIX
} from "@lukso/lsp1-contracts/contracts/LSP1Constants.sol";
import {_TYPEID_LSP26_FOLLOW, _TYPEID_LSP26_UNFOLLOW} from "@lukso/lsp26-contracts/contracts/LSP26Constants.sol";
import {_FOLLOWER_REGISTRY, _POTATO_TOKEN} from "../src/Constants.sol";
import {
    ConfigDataKeys,
    POTATO_TIPPER_SETTINGS_DATA_KEY,
    LSP1DELEGATE_ON_FOLLOW_DATA_KEY,
    LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY
} from "../src/PotatoTipperConfig.sol";

// events
import {TipSent, TipFailed} from "../src/Events.sol";

// contracts to test
import {UniversalProfile} from "@lukso/universalprofile-contracts/contracts/UniversalProfile.sol";
import {PotatoTipper} from "../src/PotatoTipper.sol";

/// @dev Fork tests against LUKSO Mainnet
contract PotatoTipperTest is UniversalProfileTestHelpers {
    using Strings for address;
    using LSP2Utils for *;
    using LSP6Utils for *;
    using {SettingsLib.loadTipSettingsRaw} for IERC725Y;
    using {SettingsLib.decodeTipSettings} for bytes;

    // Contract addresses from LUKSO Mainnet for mainnet fork testing
    // (🆙 users, 🥔 token, and LSP26 Follower Registry)
    //
    // Note: main controller addresses need to be retrieved to be able to do `setData(...)` to setup in tests:
    // - LSP1 Delegate to react on follow + unfollow
    // - PotatoTipper:Settings
    // ------------------------------------------------------------------------------------------------------------------

    // Main 🆙 user setting Potato Tipper
    UniversalProfile user = UniversalProfile(payable(0x927aAD446E3bF6eeB776387B3d7A89D8016fA54d)); // Jean
    address userBrowserExtensionController;

    // Another user for testing followers can get tips from multiple users you don't follow
    UniversalProfile anotherUser = UniversalProfile(payable(0x041B2744fB8433Fc8165036d30072c514390271e)); // Lamboftodd
    address anotherUserBrowserExtensionController;

    // This 🆙 does not follow any of the two users listed above
    UniversalProfile newFollower = UniversalProfile(payable(0xbbE88a2F48eAA2EF04411e356d193BA3C1b37200)); // mbeezlyx
    address newFollowerBrowserExtensionController;

    // This 🆙 already follows the other two users
    UniversalProfile existingFollower = UniversalProfile(payable(0x26e7Da1968cfC61FB8aB2Aad039b5A083b9De21e)); // ethalorian

    // contract to test
    PotatoTipper potatoTipper;
    uint256 constant TIP_AMOUNT = 1e18; // 1 $POTATO token
    uint256 constant MIN_FOLLOWER_REQUIRED = 0;
    uint256 constant MIN_POTATO_BALANCE_REQUIRED = 0;

    function setUp() public override {
        super.setUp();

        // Fetch the main controller of these users`
        userBrowserExtensionController = _getControllerAtIndex(user, 3);
        anotherUserBrowserExtensionController = _getControllerAtIndex(anotherUser, 1);
        newFollowerBrowserExtensionController = _getControllerAtIndex(newFollower, 1);

        _grantAddAndEditLsp1DelegatePermissionToController(user, userBrowserExtensionController);
        _grantAddAndEditLsp1DelegatePermissionToController(anotherUser, anotherUserBrowserExtensionController);
        _grantAddAndEditLsp1DelegatePermissionToController(newFollower, newFollowerBrowserExtensionController);

        // Deploy and configure the Potato Tipper
        potatoTipper = new PotatoTipper();

        SettingsLib.TipSettings memory tipSettings = SettingsLib.TipSettings({
            tipAmount: TIP_AMOUNT,
            minimumFollowers: MIN_FOLLOWER_REQUIRED,
            minimumPotatoBalance: MIN_POTATO_BALANCE_REQUIRED
        });
        (bytes32[] memory dataKeys, bytes[] memory dataValues) = potatoTipper.encodeConfigDataKeysValues(tipSettings);

        vm.prank(userBrowserExtensionController);
        user.setDataBatch(dataKeys, dataValues);

        vm.prank(anotherUserBrowserExtensionController);
        anotherUser.setDataBatch(dataKeys, dataValues);
    }

    // Pre tipping checks:
    // - follower does not already follow user
    // - follower has not received a tip yet
    // - PotatoTipper is authorized as operator by user for at least the tip amount
    function _preTippingChecks(address userTipping, address follower, uint256 tippingBudget) internal view {
        // CHECK PotatoTipper allowance is set
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), userTipping), tippingBudget);

        // CHECK that follower does not already follow user
        assertFalse(_FOLLOWER_REGISTRY.isFollowing(address(follower), userTipping));

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
        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(followerReceivingTip), userTipping));

        // CHECK that follower has received a tip (POTATO balance has increased by the tip amount)
        assertTrue(potatoTipper.hasReceivedTip(address(followerReceivingTip), userTipping));
        assertTrue(potatoTipper.hasFollowedPostInstall(address(followerReceivingTip), userTipping));
        assertEq(_POTATO_TOKEN.balanceOf(address(followerReceivingTip)), followerPotatoBalanceBefore + tipAmount);

        // CHECK that the user's gave a tip
        assertEq(_POTATO_TOKEN.balanceOf(userTipping), userPotatoBalanceBefore - tipAmount);

        // CHECK that the PotatoTipper allowance decreased by tip amount
        assertEq(
            _POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), userTipping),
            potatoTipperAllowanceBefore - tipAmount
        );
    }

    function _checkReturnedDataEmittedInUniversalReceiverEvent(
        Vm.Log[] memory logs,
        address expectedFollower,
        string memory expectedMessage
    ) internal pure {
        for (uint256 i = 0; i < logs.length; i++) {
            // Check for transfer data sent to 🥔 token `Transfer` event

            // event Transfer(
            //     address indexed operator,
            //     address indexed from,
            //     address indexed to,
            //     uint256 amount,
            //     bool force,
            //     bytes data
            // );
            if (logs[i].topics[0] == ILSP7.Transfer.selector) {
                (,, bytes memory data) = abi.decode(logs[i].data, (uint256, bool, bytes));
                assertEq(string(data), unicode"Thanks for following! Tipping you some 🥔");
            }

            if (logs[i].topics[0] != ILSP1UniversalReceiver.UniversalReceiver.selector) continue;
            if (bytes32(logs[i].topics[3]) != _TYPEID_LSP26_FOLLOW) continue;

            // event UniversalReceiver(
            //     address indexed from,
            //     uint256 indexed value,
            //     bytes32 indexed typeId,
            //     bytes receivedData,
            //     bytes returnedValues
            // );

            // receivedData + returnedValue
            // ------------------------------------------------------------------
            // 0x0000000000000000000000000000000000000000000000000000000000000040 <------------
            //   0000000000000000000000000000000000000000000000000000000000000080 receivedData
            //   0000000000000000000000000000000000000000000000000000000000000014 .............
            //   bbe88a2f48eaa2ef04411e356d193ba3c1b37200000000000000000000000000 <------------
            //   0000000000000000000000000000000000000000000000000000000000000100 returnedValue
            //   0000000000000000000000000000000000000000000000000000000000000040 .............
            //   0000000000000000000000000000000000000000000000000000000000000080 .............
            //   0000000000000000000000000000000000000000000000000000000000000019 .............
            //   4c5350313a20747970654964206f7574206f662073636f706500000000000000 .............
            //   0000000000000000000000000000000000000000000000000000000000000050 .............
            //
            // e29c85f09f8da0205375636365737366756c6c792074697070656420312024504f5441544f20746f6b656e20746f206e657720666f6c6c6f7765722ebbe88a2f48eaa2ef04411e356d193ba3c1b3720000000000000000000000000000000000

            (bytes memory receivedNotificationData, bytes memory allReturnedLsp1DelegateValues) =
                abi.decode((logs[i].data), (bytes, bytes));

            // CHECK LSP26 Follower registry sent follower address as notification data
            assertEq(receivedNotificationData, abi.encodePacked(expectedFollower));

            // `returnedValues` from both the default LSP1 Delegate + LSP1 Delegate for New Follower typeId
            // ------------------------------------------------------------------
            // 0x0000000000000000000000000000000000000000000000000000000000000040
            //   0000000000000000000000000000000000000000000000000000000000000080
            //   0000000000000000000000000000000000000000000000000000000000000019 -> 25 bytes (characters)
            //   4c5350313a20747970654964206f7574206f662073636f706500000000000000
            //   0000000000000000000000000000000000000000000000000000000000000050 -> 80 bytes (characters)
            //
            // e29c85f09f8da0205375636365737366756c6c792074697070656420312024504f5441544f20746f6b656e20746f206e657720666f6c6c6f7765722ebbe88a2f48eaa2ef04411e356d193ba3c1b3720000000000000000000000000000000000
            assertEq(allReturnedLsp1DelegateValues, abi.encode("LSP1: typeId out of scope", expectedMessage));

            // CHECK LSP1 Default Delegate returned the right message
            // CHECK Potato Tipper returned the right message
            // Example:
            // -> ✅🍠 Successfully tipped 1 $POTATO token to new follower. (60 bytes characters)
            // -> e29c85 = utf8("✅") = 3 bytes
            // -> f09f8da0 = utf8("🍠") = 4 bytes
            // -> rest of the message = 53 bytes
            // -> follower address (abi packed encoded) = 20 bytes
            (bytes memory returnedDataDefaultLsp1Delegate, bytes memory returnedDataPotatoTipper) =
                abi.decode(allReturnedLsp1DelegateValues, (bytes, bytes));

            assertEq(string(returnedDataDefaultLsp1Delegate), "LSP1: typeId out of scope");
            assertEq(string(returnedDataPotatoTipper), expectedMessage);
        }
    }

    // Sanity checks

    function test_FollowerDoesNotAlreadyFollowUser() public view {
        assertFalse(_FOLLOWER_REGISTRY.isFollowing(address(newFollower), address(user)));
    }

    function test_FollowerFollowUser() public {
        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(newFollower), address(user)));
    }

    function test_lsp1DelegateOnFollowDataKeyConstantIsCorrectlyEncoded() public pure {
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 expectedDataKey = _LSP1_DELEGATE_PREFIX.generateMappingKey(bytes20(_TYPEID_LSP26_FOLLOW));
        assertEq(LSP1DELEGATE_ON_FOLLOW_DATA_KEY, expectedDataKey);
    }

    function test_lsp1DelegateOnUnfollowDataKeyConstantIsCorrectlyEncoded() public pure {
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 expectedDataKey = _LSP1_DELEGATE_PREFIX.generateMappingKey(bytes20(_TYPEID_LSP26_UNFOLLOW));
        assertEq(LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY, expectedDataKey);
    }

    // Setup tests

    function test_PotatoTipperIsRegisteredForNotificationTypeNewFollower() public view {
        bytes memory data = user.getData(LSP1DELEGATE_ON_FOLLOW_DATA_KEY);
        assertEq(data, abi.encodePacked(address(potatoTipper)));
    }

    function test_PotatoTipperIsRegisteredForNotificationTypeUnfollow() public view {
        bytes memory data = user.getData(LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY);
        assertEq(data, abi.encodePacked(address(potatoTipper)));
    }

    function test_IsLSP1Delegate() public view {
        assertTrue(potatoTipper.supportsInterface(type(ILSP1Delegate).interfaceId));
    }

    function test_configDataKeysReturnsCorrectBytes32DataKeys() public view {
        ConfigDataKeys memory configDataKeys = potatoTipper.configDataKeys();
        assertEq(configDataKeys.tipSettingsDataKey, POTATO_TIPPER_SETTINGS_DATA_KEY);
        assertEq(configDataKeys.lsp1DelegateReactOnFollowDataKey, LSP1DELEGATE_ON_FOLLOW_DATA_KEY);
        assertEq(configDataKeys.lsp1DelegateReactOnUnfollowDataKey, LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY);
    }

    function test_configDataKeysListReturnsCorrectBytes32DataKeysList() public view {
        bytes32[] memory configDataKeysList = potatoTipper.configDataKeysList();
        assertEq(configDataKeysList[0], POTATO_TIPPER_SETTINGS_DATA_KEY);
        assertEq(configDataKeysList[1], LSP1DELEGATE_ON_FOLLOW_DATA_KEY);
        assertEq(configDataKeysList[2], LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY);
    }

    function test_encodeConfigDataKeysValuesReturnsCorrectBytes32AndBytesData(
        uint256 tipAmount,
        uint256 minimumFollowers,
        uint256 minimumPotatoBalance
    ) public view {
        SettingsLib.TipSettings memory tipSettings = SettingsLib.TipSettings({
            tipAmount: tipAmount, minimumFollowers: minimumFollowers, minimumPotatoBalance: minimumPotatoBalance
        });
        (bytes32[] memory dataKeys, bytes[] memory dataValues) = potatoTipper.encodeConfigDataKeysValues(tipSettings);
        assertEq(dataKeys[0], POTATO_TIPPER_SETTINGS_DATA_KEY);
        assertEq(dataKeys[1], LSP1DELEGATE_ON_FOLLOW_DATA_KEY);
        assertEq(dataKeys[2], LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY);
        assertEq(dataValues[0], abi.encode(tipSettings));
        assertEq(dataValues[1], abi.encodePacked(address(potatoTipper)));
        assertEq(dataValues[2], abi.encodePacked(address(potatoTipper)));
    }

    // Tipping behaviours tests

    function test_shouldNotTipButStillFollowIfPotatoTipperConnectedButNotAuthorizedAsOperator() public {
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), 0);

        uint256 followerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));

        assertFalse(_FOLLOWER_REGISTRY.isFollowing(address(newFollower), address(user)));
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));

        vm.recordLogs();

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(newFollower), unicode"❌ Not enough 🥔 left in tipping budget"
        );

        // CHECK that the follower did not receive any potato token
        uint256 followerPotatoBalanceAfter = _POTATO_TOKEN.balanceOf(address(newFollower));
        assertEq(followerPotatoBalanceAfter, followerPotatoBalanceBefore);

        // CHECK that the follower is still now following the user
        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(newFollower), address(user)));
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
    }

    function test_tippingOnFollowAfterAuthorizingPotatoTipperAsOperator() public {
        uint256 followerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Authorize the Potato Tipper contract to be able to transfer up to 10 POTATO tokens
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");

        _preTippingChecks(address(user), address(newFollower), tippingBudget);

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        _postTippingChecks(
            address(user),
            address(newFollower),
            TIP_AMOUNT,
            followerPotatoBalanceBefore,
            userPotatoBalanceBefore,
            tippingBudget
        );
    }

    function test_cannotTipTwiceTheSameNewFollowerIfFollowedUnfollowAndRefollow() public {
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Authorize the Potato Tipper contract to be able to transfer up to 10 POTATO tokens
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");
        uint256 potatoTipperAllowanceBefore = _POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user));

        _preTippingChecks(address(user), address(newFollower), tippingBudget);

        vm.recordLogs();

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        _postTippingChecks(
            address(user),
            address(newFollower),
            TIP_AMOUNT,
            followerPotatoBalanceBefore,
            userPotatoBalanceBefore,
            tippingBudget
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
        _FOLLOWER_REGISTRY.unfollow(address(user));

        vm.recordLogs();

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        logs = vm.getRecordedLogs();

        // CHECK that follower has not received a second tip
        assertTrue(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertEq(_POTATO_TOKEN.balanceOf(address(newFollower)), followerPotatoBalanceBefore + TIP_AMOUNT);

        // CHECK that the user's did not give a second tip
        // - $POTATO balance has NOT decreased by tip amount)
        // - `POTATOTipper` allowance NOT decreased by tip amount
        assertEq(_POTATO_TOKEN.balanceOf(address(user)), userPotatoBalanceBefore - TIP_AMOUNT);
        assertEq(
            _POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)),
            potatoTipperAllowanceBefore - TIP_AMOUNT
        );

        // See details of logs structure above in function
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] != ILSP1UniversalReceiver.UniversalReceiver.selector) continue;
            if (bytes32(logs[i].topics[3]) != _TYPEID_LSP26_FOLLOW) continue;

            (bytes memory receivedNotificationData, bytes memory allReturnedLsp1DelegateValues) =
                abi.decode((logs[i].data), (bytes, bytes));

            // CHECK LSP26 Follower registry sent follower address as notification data
            assertEq(receivedNotificationData, abi.encodePacked(newFollower));
            assertEq(
                allReturnedLsp1DelegateValues,
                abi.encode("LSP1: typeId out of scope", unicode"🙅🏻 Already tipped a potato")
            );

            (bytes memory returnedDataDefaultLsp1Delegate, bytes memory returnedDataPotatoTipper) =
                abi.decode(allReturnedLsp1DelegateValues, (bytes, bytes));

            assertEq(string(returnedDataDefaultLsp1Delegate), "LSP1: typeId out of scope");
            assertEq(string(returnedDataPotatoTipper), unicode"🙅🏻 Already tipped a potato");
        }
    }

    function test_followerCanReceiveTipsFromTwoDifferentUsersWhoConnectedPotatoTipper() public {
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 anotherUserPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(anotherUser));
        uint256 followerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Following user 1
        // ----------------

        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");

        _preTippingChecks(address(user), address(newFollower), tippingBudget);

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

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
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");

        _preTippingChecks(address(anotherUser), address(newFollower), tippingBudget);

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(anotherUser));

        // CHECK that the follower is now following both users
        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(newFollower), address(user)));
        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(newFollower), address(anotherUser)));

        // CHECK that another user has given a tip
        assertEq(_POTATO_TOKEN.balanceOf(address(anotherUser)), anotherUserPotatoBalanceBefore - TIP_AMOUNT);
        assertEq(
            _POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(anotherUser)), tippingBudget - TIP_AMOUNT
        );

        // CHECK that follower has received a tip from both users
        assertTrue(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertTrue(potatoTipper.hasReceivedTip(address(newFollower), address(anotherUser)));

        // CHECK that follower's balance has increased by the tip amount x 2 from both users
        assertEq(_POTATO_TOKEN.balanceOf(address(newFollower)), followerPotatoBalanceBefore + (TIP_AMOUNT * 2));
    }

    function test_customTipAmount() public {
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));

        uint256 customTipAmount = 5e18; // 5 $POTATO token
        uint256 tippingBudget = 10 * customTipAmount;

        // Set custom tip amount to 5 POTATO tokens
        SettingsLib.TipSettings memory tipSettings = SettingsLib.TipSettings({
            tipAmount: customTipAmount,
            minimumFollowers: MIN_FOLLOWER_REQUIRED,
            minimumPotatoBalance: MIN_POTATO_BALANCE_REQUIRED
        });

        bytes memory encodedTipSettings = abi.encode(tipSettings);

        vm.prank(userBrowserExtensionController);
        user.setData(POTATO_TIPPER_SETTINGS_DATA_KEY, encodedTipSettings);

        bytes memory tipSettingsDataValue = IERC725Y(address(user)).getData(POTATO_TIPPER_SETTINGS_DATA_KEY);

        assertEq(tipSettingsDataValue, encodedTipSettings);
        (uint256 tipAmount, uint256 minimumFollowers, uint256 minimumPotatoBalance) =
            abi.decode(tipSettingsDataValue, (uint256, uint256, uint256));
        assertEq(tipAmount, customTipAmount);
        assertEq(minimumFollowers, MIN_FOLLOWER_REQUIRED);
        assertEq(minimumPotatoBalance, MIN_POTATO_BALANCE_REQUIRED);

        // Authorize the Potato Tipper contract to be able to transfer up to 50 POTATO tokens
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");

        _preTippingChecks(address(user), address(newFollower), tippingBudget);

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        _postTippingChecks(
            address(user),
            address(newFollower),
            customTipAmount,
            followerPotatoBalanceBefore,
            userPotatoBalanceBefore,
            tippingBudget
        );
    }

    function test_doesNotTipIfTipSettingsDataKeyNotSet() public {
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Set an incorrect value for the tip amount
        vm.prank(userBrowserExtensionController);
        user.setData(POTATO_TIPPER_SETTINGS_DATA_KEY, bytes(""));

        // Authorize the Potato Tipper contract to be able to transfer up to 50 POTATO tokens
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");

        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));

        vm.recordLogs();

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        // CHECK that follower has NOT received a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertEq(_POTATO_TOKEN.balanceOf(address(newFollower)), followerPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(_POTATO_TOKEN.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs,
            address(newFollower),
            unicode"❌ Invalid settings: must be encoded as 96 bytes (uint256,uint256,uint256)"
        );
    }

    function test_customTipSettingsIncorrectlySetDontTriggerTip(bytes memory badEncodedDataValue) public {
        vm.assume(badEncodedDataValue.length != 96);
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Set an incorrect value for the tip amount
        vm.prank(userBrowserExtensionController);
        user.setData(POTATO_TIPPER_SETTINGS_DATA_KEY, badEncodedDataValue);

        // Authorize the Potato Tipper contract to be able to transfer up to 50 POTATO tokens
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");

        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));

        vm.recordLogs();

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        // CHECK that follower has NOT received a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertEq(_POTATO_TOKEN.balanceOf(address(newFollower)), followerPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(_POTATO_TOKEN.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs,
            address(newFollower),
            unicode"❌ Invalid settings: must be encoded as 96 bytes (uint256,uint256,uint256)"
        );
    }

    function test_minimumFollowerRequiredNotMetDontTriggerTip(uint256 minimumFollowerCountRequired) public {
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));

        uint256 currentFollowerCount = _FOLLOWER_REGISTRY.followerCount(address(newFollower));
        minimumFollowerCountRequired = bound(minimumFollowerCountRequired, currentFollowerCount + 1, type(uint256).max);

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Set an incorrect value for the tip amount
        vm.prank(userBrowserExtensionController);
        user.setData(POTATO_TIPPER_SETTINGS_DATA_KEY, abi.encode(TIP_AMOUNT, minimumFollowerCountRequired, 0));

        // Authorize the Potato Tipper contract to be able to transfer $POTATO tokens
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");

        _preTippingChecks(address(user), address(newFollower), tippingBudget);

        vm.recordLogs();

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(newFollower), address(user)));

        assertTrue(potatoTipper.hasFollowedPostInstall(address(newFollower), address(user)));
        assertFalse(potatoTipper.existingFollowerUnfollowedPostInstall(address(newFollower), address(user)));

        // CHECK that follower has NOT received a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertEq(_POTATO_TOKEN.balanceOf(address(newFollower)), followerPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(newFollower), unicode"❌ Not eligible for tip: minimum follower required not met"
        );
    }

    function test_minimumFollowerRequiredExactMatchTriggerTip() public {
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));

        uint256 currentFollowerCount = _FOLLOWER_REGISTRY.followerCount(address(newFollower));
        uint256 minimumFollowerCountRequired = currentFollowerCount;

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Set an incorrect value for the tip amount
        vm.prank(userBrowserExtensionController);
        user.setData(POTATO_TIPPER_SETTINGS_DATA_KEY, abi.encode(TIP_AMOUNT, minimumFollowerCountRequired, 0));

        // Authorize the Potato Tipper contract to be able to transfer $POTATO tokens
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");

        _preTippingChecks(address(user), address(newFollower), tippingBudget);

        vm.recordLogs();

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        _postTippingChecks(
            address(user),
            address(newFollower),
            TIP_AMOUNT,
            followerPotatoBalanceBefore,
            userPotatoBalanceBefore,
            tippingBudget
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs,
            address(newFollower),
            unicode"✅ Successfully tipped 🍠 to new follower: 0xbbe88a2f48eaa2ef04411e356d193ba3c1b37200"
        );
    }

    function test_minimumPotatoBalanceRequiredNotMetDontTriggerTip(uint256 minimumPotatoBalanceRequired) public {
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));

        uint256 currentFollowerPotatoBalance = _POTATO_TOKEN.balanceOf(address(newFollower));
        minimumPotatoBalanceRequired =
            bound(minimumPotatoBalanceRequired, currentFollowerPotatoBalance + 1, type(uint256).max);

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Set an incorrect value for the tip amount
        vm.prank(userBrowserExtensionController);
        user.setData(POTATO_TIPPER_SETTINGS_DATA_KEY, abi.encode(TIP_AMOUNT, 0, minimumPotatoBalanceRequired));

        // Authorize the Potato Tipper contract to be able to transfer $POTATO tokens
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");

        _preTippingChecks(address(user), address(newFollower), tippingBudget);

        vm.recordLogs();

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(newFollower), address(user)));

        assertTrue(potatoTipper.hasFollowedPostInstall(address(newFollower), address(user)));
        assertFalse(potatoTipper.existingFollowerUnfollowedPostInstall(address(newFollower), address(user)));

        // CHECK that follower has NOT received a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertEq(_POTATO_TOKEN.balanceOf(address(newFollower)), followerPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(newFollower), unicode"❌ Not eligible for tip: minimum 🥔 balance required not met"
        );
    }

    function test_minimumPotatoBalanceRequiredExactMatchTriggerTip() public {
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));

        uint256 currentFollowerPotatoBalance = _POTATO_TOKEN.balanceOf(address(newFollower));
        uint256 minimumPotatoBalanceRequired = currentFollowerPotatoBalance;

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Set an incorrect value for the tip amount
        vm.prank(userBrowserExtensionController);
        user.setData(POTATO_TIPPER_SETTINGS_DATA_KEY, abi.encode(TIP_AMOUNT, 0, minimumPotatoBalanceRequired));

        // Authorize the Potato Tipper contract to be able to transfer $POTATO tokens
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");

        _preTippingChecks(address(user), address(newFollower), tippingBudget);

        vm.recordLogs();

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        _postTippingChecks(
            address(user),
            address(newFollower),
            TIP_AMOUNT,
            followerPotatoBalanceBefore,
            userPotatoBalanceBefore,
            tippingBudget
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs,
            address(newFollower),
            unicode"✅ Successfully tipped 🍠 to new follower: 0xbbe88a2f48eaa2ef04411e356d193ba3c1b37200"
        );
    }

    function test_customTipAmountSetToZeroDontTriggerTip() public {
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Set an incorrect value for the tip amount
        vm.prank(userBrowserExtensionController);
        user.setData(POTATO_TIPPER_SETTINGS_DATA_KEY, abi.encode(0, MIN_FOLLOWER_REQUIRED, MIN_POTATO_BALANCE_REQUIRED));

        // Authorize the Potato Tipper contract to be able to transfer $POTATO tokens
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");

        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));

        vm.recordLogs();

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        // CHECK that follower has NOT received a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertEq(_POTATO_TOKEN.balanceOf(address(newFollower)), followerPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(_POTATO_TOKEN.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(newFollower), unicode"❌ Invalid settings: cannot set tip amount to 0"
        );
    }

    function test_customTipAmountGreaterThanUserBalanceButLessThanTippingBudgetDontTriggerTip(
        uint256 customTipAmount,
        uint256 tippingBudget
    ) public {
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        tippingBudget = bound(tippingBudget, userPotatoBalanceBefore + 2, type(uint256).max);
        customTipAmount = bound(customTipAmount, userPotatoBalanceBefore + 1, tippingBudget - 1);

        uint256 followerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));

        vm.prank(userBrowserExtensionController);
        user.setData(
            POTATO_TIPPER_SETTINGS_DATA_KEY,
            abi.encode(customTipAmount, MIN_FOLLOWER_REQUIRED, MIN_POTATO_BALANCE_REQUIRED)
        );

        // Authorize the Potato Tipper contract to be able to transfer $POTATO tokens
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));

        vm.recordLogs();
        // CHECK for right data returned by Potato Tipper and emitted in the `UniversalReceiver` event

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        // CHECK that follower has NOT received a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertEq(_POTATO_TOKEN.balanceOf(address(newFollower)), followerPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(_POTATO_TOKEN.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(newFollower), unicode"🤷🏻‍♂️ Not enough 🥔 left in balance"
        );
    }

    function test_customTipAmountLessThanUserBalanceButGreaterThanTippingBudgetDontTriggerTip(
        uint256 customTipAmount,
        uint256 potatoTipperAllowance
    ) public {
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));

        vm.assume(potatoTipperAllowance < customTipAmount);
        uint256 tippingBudget = bound(potatoTipperAllowance, 1, userPotatoBalanceBefore);
        customTipAmount = bound(customTipAmount, tippingBudget + 1, userPotatoBalanceBefore);

        uint256 followerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));

        // Set an incorrect value for the tip amount
        vm.prank(userBrowserExtensionController);
        user.setData(
            POTATO_TIPPER_SETTINGS_DATA_KEY,
            abi.encodePacked(customTipAmount, MIN_FOLLOWER_REQUIRED, MIN_POTATO_BALANCE_REQUIRED)
        );

        // Authorize the Potato Tipper contract to be able to transfer up to 50 POTATO tokens
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");

        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));

        vm.recordLogs();

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        // CHECK that follower has NOT received a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertEq(_POTATO_TOKEN.balanceOf(address(newFollower)), followerPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(_POTATO_TOKEN.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK for right data returned by Potato Tipper and emitted in the `UniversalReceiver` event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(newFollower), unicode"❌ Not enough 🥔 left in tipping budget"
        );
    }

    function test_tippingFailsAfterTippingBudgetGoesToZero() public {
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));

        uint256 tippingBudget = TIP_AMOUNT;

        // Set custom tip amount to 5 POTATO tokens
        vm.prank(userBrowserExtensionController);
        user.setData(
            POTATO_TIPPER_SETTINGS_DATA_KEY,
            abi.encodePacked(TIP_AMOUNT, MIN_FOLLOWER_REQUIRED, MIN_POTATO_BALANCE_REQUIRED)
        );

        assertEq(abi.decode(IERC725Y(address(user)).getData(POTATO_TIPPER_SETTINGS_DATA_KEY), (uint256)), TIP_AMOUNT);

        // Authorize the Potato Tipper contract to be able to transfer up to 50 POTATO tokens
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");

        _preTippingChecks(address(user), address(newFollower), tippingBudget);

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        _postTippingChecks(
            address(user),
            address(newFollower),
            TIP_AMOUNT,
            followerPotatoBalanceBefore,
            userPotatoBalanceBefore,
            tippingBudget
        );

        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), 0);

        // Check that subsequent tipping attempt will fail, but new follower will still be registered
        UniversalProfile anotherFollower = UniversalProfile(payable(0x04063d2b65634a91221596Dc5864e3f12288fA16));

        uint256 anotherFollowerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(anotherFollower));

        assertFalse(_FOLLOWER_REGISTRY.isFollowing(address(anotherFollower), address(user)));
        assertFalse(potatoTipper.hasReceivedTip(address(anotherFollower), address(user)));

        vm.recordLogs();

        vm.prank(address(anotherFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        // CHECK that the follower did not receive any potato token
        uint256 anotherFollowerPotatoBalanceAfter = _POTATO_TOKEN.balanceOf(address(anotherFollower));
        assertEq(anotherFollowerPotatoBalanceAfter, anotherFollowerPotatoBalanceBefore);

        // CHECK that the follower is still now following the user
        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(anotherFollower), address(user)));
        assertFalse(potatoTipper.hasReceivedTip(address(anotherFollower), address(user)));

        Vm.Log[] memory logs = vm.getRecordedLogs();

        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(anotherFollower), unicode"❌ Not enough 🥔 left in tipping budget"
        );
    }

    function test_tippingFailsAfterTippingBudgetGoesBelowCustomAmount(uint256 tippingBudget) public {
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 followerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));

        tippingBudget = bound(tippingBudget, TIP_AMOUNT + 1, (TIP_AMOUNT * 2) - 1);

        // Set custom tip amount to 5 POTATO tokens
        vm.prank(userBrowserExtensionController);
        user.setData(
            POTATO_TIPPER_SETTINGS_DATA_KEY, abi.encode(TIP_AMOUNT, MIN_FOLLOWER_REQUIRED, MIN_POTATO_BALANCE_REQUIRED)
        );

        bytes memory rawSettingsValue = IERC725Y(address(user)).loadTipSettingsRaw();

        (, SettingsLib.TipSettings memory tipSettings,) = rawSettingsValue.decodeTipSettings();

        (
            uint256 tipAmountSetInProfile,
            uint256 minFollowerRequiredSetInProfile,
            uint256 minPotatoBalanceRequiredSetInProfile
        ) = (tipSettings.tipAmount, tipSettings.minimumFollowers, tipSettings.minimumPotatoBalance);

        assertEq(tipAmountSetInProfile, TIP_AMOUNT);
        assertEq(minFollowerRequiredSetInProfile, MIN_FOLLOWER_REQUIRED);
        assertEq(minPotatoBalanceRequiredSetInProfile, MIN_POTATO_BALANCE_REQUIRED);

        // Authorize the Potato Tipper contract to be able to transfer up to 50 POTATO tokens
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");

        _preTippingChecks(address(user), address(newFollower), tippingBudget);

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        _postTippingChecks(
            address(user),
            address(newFollower),
            TIP_AMOUNT,
            followerPotatoBalanceBefore,
            userPotatoBalanceBefore,
            tippingBudget
        );

        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget - TIP_AMOUNT);

        UniversalProfile anotherFollower = UniversalProfile(payable(0x04063d2b65634a91221596Dc5864e3f12288fA16));

        uint256 anotherFollowerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(anotherFollower));

        assertFalse(_FOLLOWER_REGISTRY.isFollowing(address(anotherFollower), address(user)));
        assertFalse(potatoTipper.hasReceivedTip(address(anotherFollower), address(user)));

        vm.recordLogs();

        vm.prank(address(anotherFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        // CHECK that the follower did not receive any potato token
        uint256 anotherFollowerPotatoBalanceAfter = _POTATO_TOKEN.balanceOf(address(anotherFollower));
        assertEq(anotherFollowerPotatoBalanceAfter, anotherFollowerPotatoBalanceBefore);

        // CHECK that the follower is still now following the user
        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(anotherFollower), address(user)));
        assertFalse(potatoTipper.hasReceivedTip(address(anotherFollower), address(user)));

        Vm.Log[] memory logs = vm.getRecordedLogs();

        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(anotherFollower), unicode"❌ Not enough 🥔 left in tipping budget"
        );
    }

    function test_canFollowBatchTwoUsersAndGetTipsFromBoth() public {
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 anotherUserPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(anotherUser));
        uint256 followerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        assertGe(userPotatoBalanceBefore, tippingBudget);
        assertGe(anotherUserPotatoBalanceBefore, tippingBudget);

        // Authorize the Potato Tipper contract to be able to transfer up to 10 POTATO tokens
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");
        vm.prank(address(anotherUser));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");

        uint256 potatoTipperAllowanceForUserBefore =
            _POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user));
        assertEq(potatoTipperAllowanceForUserBefore, tippingBudget);
        uint256 potatoTipperAllowanceForAnotherUserBefore =
            _POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(anotherUser));
        assertEq(potatoTipperAllowanceForAnotherUserBefore, tippingBudget);

        _preTippingChecks(address(user), address(newFollower), tippingBudget);
        _preTippingChecks(address(anotherUser), address(newFollower), tippingBudget);

        address[] memory usersToFollow = new address[](2);
        usersToFollow[0] = address(user);
        usersToFollow[1] = address(anotherUser);

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.followBatch(usersToFollow);

        // CHECK that follower is now following user
        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(newFollower), address(user)));
        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(newFollower), address(anotherUser)));

        // CHECK that follower has received 2 x tips
        assertTrue(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertTrue(potatoTipper.hasReceivedTip(address(newFollower), address(anotherUser)));

        assertTrue(potatoTipper.hasFollowedPostInstall(address(newFollower), address(user)));
        assertTrue(potatoTipper.hasFollowedPostInstall(address(newFollower), address(anotherUser)));

        assertEq(_POTATO_TOKEN.balanceOf(address(newFollower)), followerPotatoBalanceBefore + (TIP_AMOUNT * 2));

        // CHECK that the user's gave a tip
        assertEq(_POTATO_TOKEN.balanceOf(address(user)), userPotatoBalanceBefore - TIP_AMOUNT);
        assertEq(_POTATO_TOKEN.balanceOf(address(anotherUser)), anotherUserPotatoBalanceBefore - TIP_AMOUNT);

        // CHECK that the PotatoTipper allowance decreased by tip amount
        assertEq(
            _POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)),
            potatoTipperAllowanceForUserBefore - TIP_AMOUNT
        );
        assertEq(
            _POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(anotherUser)),
            potatoTipperAllowanceForAnotherUserBefore - TIP_AMOUNT
        );
    }

    // Caller context tests

    function test_onlyRunWithFollowOrUnfollowTypeId(bytes32 typeId) public {
        vm.assume(typeId != _TYPEID_LSP26_FOLLOW);
        vm.assume(typeId != _TYPEID_LSP26_UNFOLLOW);

        vm.recordLogs();

        // This cannot happen in production as the follower registry can only trigger `universalReceiver(...)`
        // with the follow and unfollow type IDs, but testing for sanity purpose
        vm.prank(address(_FOLLOWER_REGISTRY));
        user.universalReceiver(typeId, abi.encodePacked(address(12_345)));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(12_345), unicode"❌ Not a follow or unfollow notification"
        );
    }

    function test_existingFollowerCannotTriggerDirectlyToGetTipped() public {
        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(existingFollower), address(user)));

        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 existingFollowerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(existingFollower));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Authorize the Potato Tipper contract to be able to transfer up to 50 POTATO tokens
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));

        vm.recordLogs();

        vm.prank(address(existingFollower));
        user.universalReceiver(_TYPEID_LSP26_FOLLOW, abi.encodePacked(address(existingFollower)));

        // CHECK that follower did NOT receive a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertEq(_POTATO_TOKEN.balanceOf(address(existingFollower)), existingFollowerPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(_POTATO_TOKEN.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK for right data returned by Potato Tipper and emitted in the `UniversalReceiver` event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(existingFollower), unicode"❌ Not triggered by the Follower Registry"
        );
    }

    function test_OnlyCallsFromFollowerRegistry(address caller) public {
        vm.assume(caller != address(_FOLLOWER_REGISTRY));
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 callerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(caller));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        // Authorize the Potato Tipper contract to be able to transfer up to 50 POTATO tokens
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(address(caller), address(user)));

        vm.recordLogs();

        vm.prank(caller);
        user.universalReceiver(_TYPEID_LSP26_FOLLOW, abi.encodePacked(caller));

        // CHECK that follower did NOT receive a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(caller, address(user)));
        assertEq(_POTATO_TOKEN.balanceOf(caller), callerPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(_POTATO_TOKEN.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK for right data returned by Potato Tipper and emitted in the `UniversalReceiver` event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, caller, unicode"❌ Not triggered by the Follower Registry"
        );
    }

    function test_EOAsCannotReceiveTipsOnFollow() public {
        address eoa = vm.addr(0x0E0A);

        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 eoaPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(eoa));

        uint256 tippingBudget = 10 * TIP_AMOUNT;

        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK that follower has not received a tip yet
        assertFalse(potatoTipper.hasReceivedTip(eoa, address(user)));

        vm.recordLogs();

        vm.prank(eoa);
        _FOLLOWER_REGISTRY.follow(address(user));

        // CHECK that follower did NOT receive a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(eoa, address(user)));
        assertEq(_POTATO_TOKEN.balanceOf(eoa), eoaPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(_POTATO_TOKEN.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK for right data returned by Potato Tipper and emitted in the `UniversalReceiver` event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(logs, eoa, unicode"❌ Only 🆙 allowed to be tipped");
    }

    function test_onlyUniversalProfilesCanReceiveTips() public {
        // Mock a minimal LSP1 implementer that does not support the LSP0 interface
        MinimalLSP1Implementer minimalLsp1Implementer = new MinimalLSP1Implementer();

        // Mock a 🆙 minimal proxy pointing to UP implementation v0.12.1
        address universalProfile = address(uint160(0x1234));
        vm.etch(
            universalProfile,
            hex"363d3d373d3d3d363d7352c90985af970d4e0dc26cb5d052505278af32a95af43d82803e903d91602b57fd5bf3"
        );

        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 universalProfilePotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(universalProfile));
        uint256 tippingBudget = 10 * TIP_AMOUNT;

        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");

        // Test that it does not work for a contract that only supports LSP1
        _preTippingChecks(address(user), address(minimalLsp1Implementer), tippingBudget);

        vm.recordLogs();
        vm.prank(address(minimalLsp1Implementer));
        _FOLLOWER_REGISTRY.follow(address(user));

        // CHECK that follower is now following user
        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(minimalLsp1Implementer), address(user)));

        // CHECK that follower did NOT receive a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(address(minimalLsp1Implementer), address(user)));
        assertEq(_POTATO_TOKEN.balanceOf(address(minimalLsp1Implementer)), universalProfilePotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(minimalLsp1Implementer), unicode"❌ Only 🆙 allowed to be tipped"
        );

        // Test that it works for a UP
        _preTippingChecks(address(user), universalProfile, tippingBudget);

        vm.recordLogs();
        vm.prank(universalProfile);
        _FOLLOWER_REGISTRY.follow(address(user));

        _postTippingChecks(
            address(user),
            address(universalProfile),
            TIP_AMOUNT,
            universalProfilePotatoBalanceBefore,
            userPotatoBalanceBefore,
            tippingBudget
        );

        logs = vm.getRecordedLogs();

        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs,
            universalProfile,
            string.concat(unicode"✅ Successfully tipped 🍠 to new follower: ", universalProfile.toHexString())
        );
    }

    /// @dev Test user calls directly Potato Tipper with type ID = FOLLOW, address = address that does not
    /// follow
    function test_userWhoRegisteredPotatoTipperCannotCallContractDirectlyToTipUsersThatDontActuallyFollow() public {
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), TIP_AMOUNT, "");

        vm.prank(address(user));
        bytes memory returnedData = potatoTipper.universalReceiverDelegate(
            address(_FOLLOWER_REGISTRY), 0, _TYPEID_LSP26_FOLLOW, abi.encodePacked(address(newFollower))
        );

        assertEq(returnedData, unicode"❌ Not a legitimate follow");
    }

    function test_userCallsDirectlyPotatoTipperWithTypeIdFollowAndExistingFollower() public {
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), TIP_AMOUNT, "");

        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(existingFollower), address(user)));

        assertFalse(potatoTipper.hasReceivedTip(address(existingFollower), address(user)));
        assertFalse(potatoTipper.existingFollowerUnfollowedPostInstall(address(existingFollower), address(user)));
        assertFalse(potatoTipper.hasFollowedPostInstall(address(existingFollower), address(user)));

        uint256 existingFollowerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(existingFollower));
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));

        vm.prank(address(user));
        potatoTipper.universalReceiverDelegate(
            address(_FOLLOWER_REGISTRY), 0, _TYPEID_LSP26_FOLLOW, abi.encodePacked(address(existingFollower))
        );

        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(existingFollower), address(user)));
        assertFalse(potatoTipper.existingFollowerUnfollowedPostInstall(address(newFollower), address(user)));

        /// @dev This is odd behaviour as it allows the user to send a tip to an existing follower
        assertEq(_POTATO_TOKEN.balanceOf(address(existingFollower)), existingFollowerPotatoBalanceBefore + TIP_AMOUNT);
        assertEq(_POTATO_TOKEN.balanceOf(address(user)), userPotatoBalanceBefore - TIP_AMOUNT);
        assertTrue(potatoTipper.hasReceivedTip(address(existingFollower), address(user)));
        assertTrue(potatoTipper.hasFollowedPostInstall(address(existingFollower), address(user)));
    }

    function test_userCallsDirectlyPotatoTipperWithTypeIdUnfollowAndAddressThatDoesNotActuallyFollow() public {
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), TIP_AMOUNT, "");

        assertFalse(_FOLLOWER_REGISTRY.isFollowing(address(newFollower), address(user)));

        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertFalse(potatoTipper.existingFollowerUnfollowedPostInstall(address(newFollower), address(user)));
        assertFalse(potatoTipper.hasFollowedPostInstall(address(newFollower), address(user)));

        vm.prank(address(user));
        bytes memory returnedData = potatoTipper.universalReceiverDelegate(
            address(_FOLLOWER_REGISTRY), 0, _TYPEID_LSP26_UNFOLLOW, abi.encodePacked(address(newFollower))
        );

        assertEq(returnedData, unicode"👋🏻 Assuming existing follower BPT is unfollowing. Goodbye!");
        assertFalse(_FOLLOWER_REGISTRY.isFollowing(address(newFollower), address(user)));

        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertFalse(potatoTipper.hasFollowedPostInstall(address(newFollower), address(user)));

        /// @dev This is odd behaviour as it allows a user to censor other new users that will actually follow,
        // and prevent them from receiving a tip
        assertTrue(potatoTipper.existingFollowerUnfollowedPostInstall(address(newFollower), address(user)));
    }

    function test_userCallsDirectlyPotatoTipperWithTypeIdUnfollowAndExistingFollower() public {
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), TIP_AMOUNT, "");

        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(existingFollower), address(user)));

        assertFalse(potatoTipper.hasReceivedTip(address(existingFollower), address(user)));
        assertFalse(potatoTipper.existingFollowerUnfollowedPostInstall(address(newFollower), address(user)));
        assertFalse(potatoTipper.hasFollowedPostInstall(address(newFollower), address(user)));

        vm.prank(address(user));
        bytes memory returnedData = potatoTipper.universalReceiverDelegate(
            address(_FOLLOWER_REGISTRY), 0, _TYPEID_LSP26_UNFOLLOW, abi.encodePacked(address(existingFollower))
        );

        assertEq(returnedData, unicode"❌ Not a legitimate unfollow");
        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(existingFollower), address(user)));

        assertFalse(potatoTipper.hasReceivedTip(address(existingFollower), address(user)));
        assertFalse(potatoTipper.existingFollowerUnfollowedPostInstall(address(existingFollower), address(user)));
        assertFalse(potatoTipper.hasFollowedPostInstall(address(existingFollower), address(user)));
    }

    function test_existingFollowerUnfollowsAndRefollowDoesNotTriggerTip() public {
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), TIP_AMOUNT, "");

        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 existingFollowerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(existingFollower));

        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(existingFollower), address(user)));
        assertFalse(potatoTipper.hasReceivedTip(address(existingFollower), address(user)));
        assertFalse(potatoTipper.existingFollowerUnfollowedPostInstall(address(existingFollower), address(user)));
        assertFalse(potatoTipper.hasFollowedPostInstall(address(existingFollower), address(user)));

        vm.prank(address(existingFollower));
        _FOLLOWER_REGISTRY.unfollow(address(user));

        assertFalse(_FOLLOWER_REGISTRY.isFollowing(address(existingFollower), address(user)));
        assertFalse(potatoTipper.hasReceivedTip(address(existingFollower), address(user)));
        assertFalse(potatoTipper.hasFollowedPostInstall(address(existingFollower), address(user)));
        assertTrue(potatoTipper.existingFollowerUnfollowedPostInstall(address(existingFollower), address(user)));

        assertEq(_POTATO_TOKEN.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.balanceOf(address(existingFollower)), existingFollowerPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), TIP_AMOUNT);

        vm.recordLogs();

        vm.prank(address(existingFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(existingFollower), unicode"🙅🏻 Existing followers not eligible for a tip"
        );

        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(existingFollower), address(user)));
        assertFalse(potatoTipper.hasReceivedTip(address(existingFollower), address(user)));
        assertFalse(potatoTipper.hasFollowedPostInstall(address(existingFollower), address(user)));
        assertTrue(potatoTipper.existingFollowerUnfollowedPostInstall(address(existingFollower), address(user)));

        assertEq(_POTATO_TOKEN.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.balanceOf(address(existingFollower)), existingFollowerPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), TIP_AMOUNT);
    }

    function test_newFollowerFailsToGetTipBecauseNotEligibleButCanUnfollowAndRefollowToGetTip() public {
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 newFollowerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));

        uint256 tippingBudget = TIP_AMOUNT - 10; // Less than the TIP_AMOUNT of 5 POTATO tokens

        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        _preTippingChecks(address(user), address(newFollower), tippingBudget);
        assertFalse(potatoTipper.hasFollowedPostInstall(address(newFollower), address(user)));
        assertFalse(potatoTipper.existingFollowerUnfollowedPostInstall(address(newFollower), address(user)));

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        // CHECK that the Potato Tipper allowance did NOT change
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);
        assertEq(_POTATO_TOKEN.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.balanceOf(address(newFollower)), newFollowerPotatoBalanceBefore);

        assertTrue(_FOLLOWER_REGISTRY.isFollowing(address(newFollower), address(user)));
        assertTrue(potatoTipper.hasFollowedPostInstall(address(newFollower), address(user)));
        assertFalse(potatoTipper.existingFollowerUnfollowedPostInstall(address(newFollower), address(user)));

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.unfollow(address(user));

        assertFalse(_FOLLOWER_REGISTRY.isFollowing(address(newFollower), address(user)));
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertFalse(potatoTipper.existingFollowerUnfollowedPostInstall(address(newFollower), address(user)));
        assertTrue(potatoTipper.hasFollowedPostInstall(address(newFollower), address(user)));

        // Increase Potato Tipper allowance
        vm.prank(address(user));
        _POTATO_TOKEN.increaseAllowance(address(potatoTipper), 10, "");
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget + 10);

        _preTippingChecks(address(user), address(newFollower), TIP_AMOUNT);

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        _postTippingChecks(
            address(user),
            address(newFollower),
            TIP_AMOUNT,
            newFollowerPotatoBalanceBefore,
            userPotatoBalanceBefore,
            tippingBudget + 10
        );

        assertTrue(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertFalse(potatoTipper.existingFollowerUnfollowedPostInstall(address(newFollower), address(user)));
        assertTrue(potatoTipper.hasFollowedPostInstall(address(newFollower), address(user)));
    }

    // test if a user Alice (a UP) called the other user’s UP (who has the Potato Tipper connected) and
    // tried to trick the system
    // by calling with:
    // - the following notification typeId.
    // - the unfollowing notification typeId.
    // Or something along those line. To be investigated
    /// @dev Alice UP -> Bob UP.universalReceiver(FOLLOW_TYPEID, Alice UP address)
    function test_aliceUPCannotCallBobUPUniversalReceiverFunctionToGetTipped() public {
        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), TIP_AMOUNT, "");

        // caller = Alice
        // user = Bob
        uint256 callerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));

        _preTippingChecks(address(user), address(newFollower), TIP_AMOUNT);

        vm.recordLogs();

        vm.prank(address(newFollower));
        user.universalReceiver(_TYPEID_LSP26_FOLLOW, abi.encodePacked(address(newFollower)));

        // CHECK that Alice did NOT receive a tip (tipping was not triggered)
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertEq(_POTATO_TOKEN.balanceOf(address(newFollower)), callerPotatoBalanceBefore);

        // CHECK that the user's did NOT give a tip
        // - user's $POTATO balance has NOT changed
        // - `POTATOTipper` allowance has NOT changed
        assertEq(_POTATO_TOKEN.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), TIP_AMOUNT);

        // CHECK for right data returned by Potato Tipper and emitted in the `UniversalReceiver` event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            logs, address(newFollower), unicode"❌ Not triggered by the Follower Registry"
        );
    }

    // Testing bubbling up error

    function test_fallbackToDisplayGenericErrorMessageInUniversalReceiverEventIfTippingFails() public {
        // Reverts on token received when tipping 🥔
        LSP1DelegateRevertsOnLSP7TokensReceived lsp1DelegateReverts = new LSP1DelegateRevertsOnLSP7TokensReceived();

        _setUpSpecificLsp1DelegateForTokensReceived(
            newFollower, newFollowerBrowserExtensionController, lsp1DelegateReverts
        );

        // Prepare attempt to tip
        uint256 userPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(user));
        uint256 newFollowerPotatoBalanceBefore = _POTATO_TOKEN.balanceOf(address(newFollower));

        uint256 tippingBudget = TIP_AMOUNT;

        vm.prank(address(user));
        _POTATO_TOKEN.authorizeOperator(address(potatoTipper), tippingBudget, "");

        _preTippingChecks(address(user), address(newFollower), tippingBudget);

        vm.recordLogs();

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        // CHECK that follower has NOT received a tip (tipping failed)
        assertEq(_POTATO_TOKEN.balanceOf(address(newFollower)), newFollowerPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.balanceOf(address(user)), userPotatoBalanceBefore);
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget);

        // CHECK the the follower has not been marked as tipped
        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertTrue(potatoTipper.hasFollowedPostInstall(address(newFollower), address(user)));
        assertFalse(potatoTipper.existingFollowerUnfollowedPostInstall(address(newFollower), address(user)));

        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 ii = 0; ii < logs.length; ii++) {
            if (logs[ii].topics[0] == TipFailed.selector) {
                assertEq(bytes32(logs[ii].topics[1]), bytes32(abi.encode(address(user))));
                assertEq(bytes32(logs[ii].topics[2]), bytes32(abi.encode(address(newFollower))));
                assertEq(bytes32(logs[ii].topics[3]), bytes32(abi.encode(TIP_AMOUNT)));

                bytes memory errorData = abi.decode(logs[ii].data, (bytes));
                assertEq(bytes4(errorData), bytes4(keccak256(bytes("Error(string)"))));
                assertEq(errorData, abi.encodeWithSignature("Error(string)", "Force revert on LSP7TokensReceived"));
                continue;
            }

            if (logs[ii].topics[0] != ILSP1UniversalReceiver.UniversalReceiver.selector) continue;
            if (bytes32(logs[ii].topics[3]) != _TYPEID_LSP26_FOLLOW) continue;
            (bytes memory receivedNotificationData, bytes memory allReturnedLsp1DelegateValues) =
                abi.decode((logs[ii].data), (bytes, bytes));

            bytes memory expectedMessage = unicode"❌ Failed tipping 🥔. LSP7 transfer reverted";

            // CHECK LSP26 Follower registry sent follower address as notification data
            assertEq(receivedNotificationData, abi.encodePacked(address(newFollower)));
            assertEq(allReturnedLsp1DelegateValues, abi.encode("LSP1: typeId out of scope", expectedMessage));
            (bytes memory returnedDataDefaultLsp1Delegate, bytes memory returnedDataPotatoTipper) =
                abi.decode(allReturnedLsp1DelegateValues, (bytes, bytes));

            assertEq(string(returnedDataDefaultLsp1Delegate), "LSP1: typeId out of scope");
            assertEq(returnedDataPotatoTipper, expectedMessage);
        }

        // Unfollow and re-follow to test that the follower can re-try to follow to receive a tip
        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.unfollow(address(user));

        assertFalse(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertTrue(potatoTipper.hasFollowedPostInstall(address(newFollower), address(user)));
        assertFalse(potatoTipper.existingFollowerUnfollowedPostInstall(address(newFollower), address(user)));

        // Remove the specific LSP1 delegate that reverts on token received
        _setUpSpecificLsp1DelegateForTokensReceived(
            newFollower, newFollowerBrowserExtensionController, ILSP1Delegate(address(0))
        );

        vm.recordLogs();

        vm.prank(address(newFollower));
        _FOLLOWER_REGISTRY.follow(address(user));

        // CHECK that follower has NOT received a tip (tipping failed)
        assertEq(_POTATO_TOKEN.balanceOf(address(newFollower)), newFollowerPotatoBalanceBefore + TIP_AMOUNT);
        assertEq(_POTATO_TOKEN.balanceOf(address(user)), userPotatoBalanceBefore - TIP_AMOUNT);
        assertEq(_POTATO_TOKEN.authorizedAmountFor(address(potatoTipper), address(user)), tippingBudget - TIP_AMOUNT);

        // CHECK the the follower has not been marked as tipped
        assertTrue(potatoTipper.hasReceivedTip(address(newFollower), address(user)));
        assertTrue(potatoTipper.hasFollowedPostInstall(address(newFollower), address(user)));
        assertFalse(potatoTipper.existingFollowerUnfollowedPostInstall(address(newFollower), address(user)));

        Vm.Log[] memory newLogs = vm.getRecordedLogs();
        _checkReturnedDataEmittedInUniversalReceiverEvent(
            newLogs,
            address(newFollower),
            unicode"✅ Successfully tipped 🍠 to new follower: 0xbbe88a2f48eaa2ef04411e356d193ba3c1b37200"
        );
    }
}

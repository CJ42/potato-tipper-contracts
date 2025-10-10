// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// interfaces
import {IERC725X} from "@erc725/smart-contracts/contracts/interfaces/IERC725X.sol";
import {IERC725Y} from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {ILSP1UniversalReceiverDelegate as ILSP1Delegate} from
    "@lukso/lsp1-contracts/contracts/ILSP1UniversalReceiverDelegate.sol";

// libraries
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

// errors
import {
    LSP7AmountExceedsAuthorizedAmount,
    LSP7AmountExceedsBalance
} from "@lukso/lsp7-contracts/contracts/LSP7Errors.sol";

// constants
import {OPERATION_0_CALL} from "@erc725/smart-contracts/contracts/constants.sol";
import {_INTERFACEID_LSP0} from "@lukso/lsp0-contracts/contracts/LSP0Constants.sol";
import {_INTERFACEID_LSP1_DELEGATE} from "@lukso/lsp1-contracts/contracts/LSP1Constants.sol";
import {
    _TYPEID_LSP26_FOLLOW, _TYPEID_LSP26_UNFOLLOW
} from "@lukso/lsp26-contracts/contracts/LSP26Constants.sol";
import {POTATO_TIPPER_TIP_AMOUNT_DATA_KEY, _FOLLOWER_REGISTRY, _POTATO_TOKEN} from "./Constants.sol";

//       ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░                          ░░░░░░░░░░░░░░
//         ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░██████████████████████░░                      ░░░░░░░░░░
// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓██████████████████████▓▓▒▒                        ░░░░
// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓██████████████████████████▓▓▓▓          ░░        ░░░░
// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░████░░████████████████████████████████  ██████░░          ░░
// ░░░░░░░░░░░░░░░░░░░░░░░░░░  ░░████▓▓██▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██▓▓██▓▓██
// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░  ████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██████████      ░░░░░░░░░░░░░░░░░░
// ░░░░░░░░░░░░░░░░░░░░░░░░      ▓▓▓▓██████████████████████████████████▓▓████▓▓    ░░  ░░░░░░░░░░░░░░░░
//               ░░░░░░░░░░░░████████▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒██░░██████    ░░░░░░░░░░░░░░
//   ░░  ░░          ░░░░  ██░░░░░░██▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒████░░░░░░██░░░░    ░░░░░░░░
//                     ░░██░░██████▒▒▒▒██████▒▒▒▒▒▒▒▒▒▒██████▒▒▒▒▒▒▒▒▒▒▒▒▒▒██░░░░████░░██
//                     ░░██░░░░████▒▒██▓▓▓▓▓▓██▒▒▒▒▒▒██▓▓▓▓▓▓██▒▒▒▒▒▒▒▒▒▒▒▒██░░██████░░██░░
//                       ██░░░░░░██▒▒██    ░░██▒▒▒▒▒▒██      ██▒▒▒▒▒▒▒▒▒▒▒▒██░░██░░░░░░██
//                       ██░░░░░░██▒▒░░▓▓▓▓▓▓░░▒▒▒▒▒▒░░▓▓▓▓▓▓░░▒▒▒▒▒▒▒▒▒▒▒▒██░░██░░░░░░██
//                       ██░░░░██▒▒▒▒  ██████░░▒▒▒▒▒▒  ██████  ▒▒▒▒▒▒▒▒▒▒▒▒▒▒██░░░░░░░░██
//                         ██░░██▒▒▒▒  ████▓▓░░▒▒▒▒▒▒░░██████░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒██░░░░░░██
//                           ██▒▒▒▒▒▒██▓▓▓▓▓▓██▒▒▒▒▒▒██▓▓▓▓▓▓██▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒██████
//                           ██▒▒▒▒▒▒▒▒▓▓▓▓▓▓▒▒▓▓▓▓▒▒▒▒▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒██░░
//                           ██▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▒▒░░██▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒██▓▓▓▓
//                   ░░  ▓▓██▒▒▒▒▒▒▒▒▒▒▒▒▒▒██░░░░░░██▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒██      ▓▓▒▒
// ░░░░░░░░░░░░░░░░░░▓▓▓▓░░██▒▒▒▒▒▒▒▒▒▒▒▒▒▒██░░░░░░██▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒██    ░░░░░░▒▒░░░░░░░░░░
// ░░░░░░░░░░░░░░░░▓▓░░░░  ██▒▒▒▒▒▒▒▒▒▒▒▒▓▓░░░░░░░░██▓▓██▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▒▒▒▒▒▒  ░░▓▓░░░░░░░░
// ░░░░░░░░░░░░░░▓▓░░  ▓▓▓▓██▒▒▒▒▒▒▒▒▒▒██░░░░░░░░░░░░░░░░██▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒██░░▓▓▒▒░░  ▓▓░░░░░░
// ░░░░░░░░░░░░░░▓▓  ▓▓▓▓░░██▒▒▒▒▒▒▒▒▒▒██░░░░░░░░░░░░░░░░██▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒██░░░░▓▓▓▓  ▓▓░░░░░░
// ░░░░░░░░░░▒▒▒▒▓▓  ▓▓▓▓░░██▒▒▒▒▒▒▒▒▒▒██▓▓░░░░░░▓▓▓▓▓▓▓▓██▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒██░░░░▓▓▓▓  ▓▓▓▓░░░░
// ░░░░░░▒▒░░▓▓      ▓▓▓▓▓▓▓▓▒▒▒▒▒▒██████████████████████████▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒██░░▓▓▓▓▓▓      ▓▓░░
// ▒▒▒▒▒▒▒▒▓▓░░        ░░▒▒██▒▒▒▒▓▓████▓▓████▓▓████▓▓████▓▓██▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒██▓▓▒▒░░░░░░    ░░▓▓
// ▒▒▒▒▒▒▒▒▓▓  ░░        ▒▒▓▓▓▓▓▓▓▓██▓▓██████▓▓██████▓▓▓▓██▓▓████▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒██▒▒▓▓▒▒    ░░░░  ░░▓▓
// ▒▒░░▒▒▒▒▓▓        ▒▒  ▒▒▓▓▓▓▓▓▓▓██▓▓██████▓▓██████▓▓████▓▓████▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒██▒▒▓▓▒▒░░▒▒        ▓▓
// ▒▒▒▒▒▒▒▒▓▓░░      ▓▓▒▒▓▓▒▒██▓▓▒▒▒▒▒▒▓▓▓▓▒▒▓▓▓▓▒▒▓▓▓▓▒▒▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒██▒▒▒▒▓▓▓▓▒▒        ▓▓
// ▒▒▒▒▒▒▒▒▒▒▓▓░░    ▓▓▓▓▒▒▒▒▒▒▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▒▒▒▒▒▒▒▒▓▓▒▒░░    ▓▓▒▒
// ▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒▒▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓▓▓▓▒▒▒▒
// ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓██▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒
// ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▒▒▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒
// ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▒▒▒▒▒▒▒▒▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒
// ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▒▒▒▒▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒
// ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▒▒▒▒▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒
// ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒

/**
 * @title The PotatoTipper contract allows a 🆙 to react when receiving new followers,
 * and tip 🥔 $POTATO tokens to the new follower. Use it as an incentive mechanism to gain more followers.
 *
 * @author Jean Cavallera (CJ42)
 *
 * @dev Terminology:
 * - BPT = "Before Potato Tipper" = for followers that followed a user before it connected the Potato Tipper
 * - APT = "After Potato Tipper" = for followers that followed a user after it connected the Potato Tipper"
 *
 * @notice ⚠️ Disclaimer: this contract has not been formally audited by an external third party
 * auditor. The contract does not guarantee to be bug free. Use at your own risk.
 */
contract PotatoTipper is IERC165, ILSP1Delegate {
    using ERC165Checker for address;
    using Strings for address;

    /// @dev Track `follower` addresses that received a tip already from a `user`'s UP
    mapping(address user => mapping(address follower => bool tippedAPT)) internal _tipped;

    /// @dev Track `follower` addresses that followed a user's 🆙 AFTER the Potato Tipper was connected
    /// Regardless if the follower received a tip or not
    mapping(address user => mapping(address follower => bool followedAPT)) private _hasFollowedSinceDelegate;

    /// @dev Track followers that existed BEFORE the Potato Tipper was connected to the user's UP
    /// (observed via an unfollow notifications without any post-install follow ever observed)
    mapping(address user => mapping(address follower => bool followedBPT)) private _wasFollowing;

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == _INTERFACEID_LSP1_DELEGATE || interfaceId == type(IERC165).interfaceId;
    }

    /// Read functions
    /// ---------------

    function hasReceivedTip(address follower, address user) public view returns (bool) {
        return _tipped[user][follower];
    }

    function wasFollowingBeforePotatoTipper(address follower, address user) public view returns (bool) {
        return _wasFollowing[user][follower];
    }

    function followedAfterPotatoTipper(address follower, address user) public view returns (bool) {
        return _hasFollowedSinceDelegate[user][follower];
    }

    /// Write functions
    /// ---------------

    function universalReceiverDelegate(address sender, uint256, /* value */ bytes32 typeId, bytes memory data)
        external
        returns (bytes memory)
    {
        // CHECK that this call came from the Follower Registry
        if (sender != _FOLLOWER_REGISTRY) return unicode"❌ Not triggered by the Follower Registry";

        // Retrieve the follower address from the notification data sent by the LSP26 Follower Registry
        address follower = address(bytes20(data));

        // Only 🆙✅ allowed to receive tips, 🔑❌ not EOAs
        if (!follower.supportsInterface(_INTERFACEID_LSP0)) return unicode"❌ Only 🆙 allowed to be tipped";

        // CHECK notification type ID and only run if we are being notified about follow / unfollow actions
        if (typeId == _TYPEID_LSP26_FOLLOW) return _onFollow(follower);

        if (typeId == _TYPEID_LSP26_UNFOLLOW) return _onUnfollow(follower);

        return unicode"❌ Not a follow or unfollow notification";
    }

    /// Internal functions
    /// ------------------

    function _onFollow(address follower) internal returns (bytes memory message) {
        // Record when we see a new follower AFTER the PotatoTipper was connected to user's 🆙
        if (!_hasFollowedSinceDelegate[msg.sender][follower]) {
            _hasFollowedSinceDelegate[msg.sender][follower] = true;
        }

        // 🙅🏻 Cases NOT eligible for a tip
        // -----------------------------

        // CHECK user has not already received a tip after following
        // (prevent recursive follow -> unfollow -> re-follow 🥔 🚜)
        if (_tipped[msg.sender][follower]) return unicode"🙅🏻 Already tipped a potato";

        // Check this is not an initial follower that was following us
        if (_wasFollowing[msg.sender][follower]) {
            return unicode"🙅🏻 Follower followed before. Not eligible for a tip";
        }

        // 👍🏻 Cases eligible for a tip
        // -----------------------------

        // Fetch tip amount set as config in user's UP metadata
        bytes memory tipAmountDataValue = IERC725Y(msg.sender).getData(POTATO_TIPPER_TIP_AMOUNT_DATA_KEY);

        // CHECK tip amount is correctly encoded in wei (18 decimals)
        if (tipAmountDataValue.length != 32) return unicode"❌ Invalid tip amount. Must be encoded as uint256";
        uint256 tipAmount = uint256(bytes32(tipAmountDataValue));

        return _sendTip(follower, tipAmount);
    }

    function _onUnfollow(address address_) internal returns (bytes memory) {
        // Don't do anything if follower already received a tip (legitimate unfollow APT)
        if (_tipped[msg.sender][address_]) return "";

        // If `address_` never followed the user after it connected the Potato Tipper,
        // this proves that `address_` was an existing follower at install time BPT.
        //
        // Handle cases of existing followers unfollowing -> then re-following to try to get a tip
        // Lock them out and prevent from tipping them if they try to re-follow.
        if (!_hasFollowedSinceDelegate[msg.sender][address_]) {
            _wasFollowing[msg.sender][address_] = true;
            return "";
        }

        // Allow new followers to unfollow -> re-follow to try to get a tip again
        // (e.g: if tipped failed because not enough 🥔 in user's balance, tipping budget, or transfer failed)
        // This allows an `address_` APT to re-follow and still be eligible for a tip.
        return "";
    }

    function _sendTip(address follower, uint256 tipAmount) internal returns (bytes memory) {
        // CHECK the address being followed has enough 🥔 to tip.
        //
        // When doing LSP7 transfer as operators, LSP7 reverts first with operator allowance error.
        // Checking user's token balance early improves UX, to inform user of insufficient balance first
        // (= "You first need to have enough 🥔 before being able to use the POTATO Tipper to tip")
        if (_POTATO_TOKEN.balanceOf(msg.sender) < tipAmount) {
            return unicode"🤷🏻‍♂️ Not enough 🥔 to tip the follower";
        }

        // TODO: there is a bug here
        // if the transfer occured but the transfer reverted, the follower did not receive a tip
        // and the contract will still mark the user as tipped.
        // This could be fixed by checking if the transfer reverted before marking the user as tipped.
        // Or by using a try / catch block to handle the transfer revert.

        // Mark user as tipped first before making the transfer
        _tipped[msg.sender][follower] = true;

        // Transfer 🥔 $POTATO 🥔 tokens as tip to the new follower
        try _POTATO_TOKEN.transfer({
            // 🆙 that was ⬅️ followed
            from: msg.sender,
            // 🆙 that is following ➡️
            to: follower,
            // amount of 🥔🥔🥔 to tip
            amount: tipAmount,
            // Default to false, but we already checked if follower is a 🆙, so we know it supports LSP1
            force: false,
            // message data to give context to the LSP7 token transfer
            data: unicode"Thanks for following! Tipping you some 🥔"
        }) {
            // TODO: refactor to use abi.encode for easier encoding / decoding of the returned data
            // on the UI side to display notifications
            return
                abi.encodePacked(unicode"✅ Successfully tipped 🍠 to new follower: ", follower.toHexString());
        } catch (bytes memory lowLevelData) {
            // Reset state to allow re-trying to tip this follower again later
            _tipped[msg.sender][follower] = false;

            // Handle revert call gracefuly and return:
            // 1. a descriptive error message
            // 2. any custom error data (or revert reason string)
            // So a dApp can decode and display it in the UI.

            // CHECK if this contract has enough in its tipping budget left to tip
            if (bytes4(lowLevelData) == LSP7AmountExceedsAuthorizedAmount.selector) {
                // TODO: add error data to be able to decode custom error params in the UI
                return unicode"❌ Not enough allowance to tip $POTATO tokens";
            }

            // Fallback to a generic error message (still including error data for debugging purposes)
            return abi.encodePacked(
                unicode"❌🍠 Failed tipping 🥔. `transfer(...)` function reverted with following error data: ",
                lowLevelData
            );
        }
    }
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

// interfaces
import {IERC725Y} from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {ILSP1UniversalReceiverDelegate as ILSP1Delegate} from
    "@lukso/lsp1-contracts/contracts/ILSP1UniversalReceiverDelegate.sol";

// modules
import {LSP26FollowerSystem} from "@lukso/lsp26-contracts/contracts/LSP26FollowerSystem.sol";

// libraries
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

// constants
import {_INTERFACEID_LSP0} from "@lukso/lsp0-contracts/contracts/LSP0Constants.sol";
import {_INTERFACEID_LSP1_DELEGATE} from "@lukso/lsp1-contracts/contracts/LSP1Constants.sol";
import {
    _TYPEID_LSP26_FOLLOW, _TYPEID_LSP26_UNFOLLOW
} from "@lukso/lsp26-contracts/contracts/LSP26Constants.sol";
import {POTATO_TIPPER_TIP_AMOUNT_DATA_KEY, _FOLLOWER_REGISTRY, _POTATO_TOKEN} from "./Constants.sol";

// events
import {TipSent, TipFailed} from "./Events.sol";

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

        // Retrieve follower address from the notification data sent by the LSP26 Follower Registry
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
        bool isFollowing = LSP26FollowerSystem(_FOLLOWER_REGISTRY).isFollowing(follower, msg.sender);

        // CHECK to ensure this came from a legitimate notification callback from the LSP26 Registry
        if (!isFollowing) return unicode"❌ Not a legitimate follow";

        // Record when we see a new follower AFTER the PotatoTipper was connected to user's 🆙
        if (!_hasFollowedSinceDelegate[msg.sender][follower]) {
            _hasFollowedSinceDelegate[msg.sender][follower] = true;
        }

        // 🙅🏻 Cases NOT eligible for a tip
        // -----------------------------

        // CHECK user has not already received a tip after following
        // (prevent recursive follow -> unfollow -> re-follow 🥔 🚜)
        if (_tipped[msg.sender][follower]) return unicode"🙅🏻 Already tipped a potato";

        // Check this is not an existing follower that unfollowed and tried to re-follow
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

        // CHECK the address being followed has enough 🥔 to tip.
        if (_POTATO_TOKEN.balanceOf(msg.sender) < tipAmount) {
            return unicode"🤷🏻‍♂️ Not enough 🥔 to tip follower";
        }

        // CHECK if the Potato Tipper contract has enough left in its tipping budget
        if (_POTATO_TOKEN.authorizedAmountFor(address(this), msg.sender) < tipAmount) {
            return unicode"❌ Not enough 🥔 left in tipping budget";
        }

        return _sendTip(follower, tipAmount);
    }

    function _onUnfollow(address address_) internal returns (bytes memory) {
        bool isFollowing = LSP26FollowerSystem(_FOLLOWER_REGISTRY).isFollowing(address_, msg.sender);

        // CHECK to ensure this came from a legitimate notification callback from the LSP26 Registry
        if (isFollowing) return unicode"❌ Not a legitimate unfollow";

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
        _tipped[msg.sender][follower] = true;

        // TODO: emit Tipping success and failure events
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
            emit TipSent({from: msg.sender, to: follower, amount: tipAmount});
            // TODO: refactor to use abi.encode for easier encoding / decoding of the returned data
            // on the UI side to display notifications
            return
                abi.encodePacked(unicode"✅ Successfully tipped 🍠 to new follower: ", follower.toHexString());
        } catch (bytes memory errorData) {
            emit TipFailed({from: msg.sender, to: follower, amount: tipAmount, errorData: errorData});
            // Handle revert call gracefuly and return a descriptive error message.
            // So a dApp can decode the `returnedValues` from the `UniversalReceiver` event + display in UI.
            // TODO: remove any custom error data appended (or revert reason string)

            // Fallback to a generic error message (including error data for debugging purposes)
            return abi.encodePacked(
                unicode"❌ Failed tipping 🥔. LSP7 transfer reverted with following error data: ",
                errorData
            );
        }
    }
}

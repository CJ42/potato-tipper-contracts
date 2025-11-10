// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

// interfaces
import {IERC725Y} from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {
    ILSP1UniversalReceiverDelegate as ILSP1Delegate
} from "@lukso/lsp1-contracts/contracts/ILSP1UniversalReceiverDelegate.sol";

// libraries
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {PotatoLib} from "./PotatoLib.sol";

// constants
import {_INTERFACEID_LSP0} from "@lukso/lsp0-contracts/contracts/LSP0Constants.sol";
import {_INTERFACEID_LSP1_DELEGATE} from "@lukso/lsp1-contracts/contracts/LSP1Constants.sol";
import {_TYPEID_LSP26_FOLLOW, _TYPEID_LSP26_UNFOLLOW} from "@lukso/lsp26-contracts/contracts/LSP26Constants.sol";
import {POTATO_TIPPER_SETTINGS_DATA_KEY, _FOLLOWER_REGISTRY, _POTATO_TOKEN} from "./Constants.sol";

// events
import {TipSent, TipFailed} from "./Events.sol";

// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⡤⣔⢲⡒⢦⡙⡴⣒⣖⡠⣄⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⡴⡞⡹⢆⣝⣤⣣⡙⢦⣙⡴⡡⢦⡙⣱⠺⣭⣖⠤⡀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⠻⣡⢳⠵⠛⠉⠀⠀⠀⡀⢀⠀⡈⠙⢢⡝⡤⢓⠦⡜⠻⣜⡢⣄⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡴⣛⠬⣣⠋⠁⢀⠠⠐⠈⡀⢁⠀⠂⠠⠐⠀⠄⡿⣐⡟⠉⠉⠳⣌⠳⣜⢢⡀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⡞⡸⣤⠟⠀⠀⠌⢀⠀⠂⠐⠀⠄⠈⠄⢁⣄⡬⢞⡱⣡⢛⣤⣐⣀⣼⠳⡌⢧⡱⡄⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⡳⢍⡶⠁⠀⠄⠡⢀⣢⠬⡴⢓⡞⢲⠫⡝⢭⠢⡝⢢⡓⠴⣃⢆⡣⡍⢦⠓⡼⢡⠳⣸⡄⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠷⣩⠞⠀⠠⢁⡴⡺⢍⡲⣑⠎⡵⡨⢇⢳⠸⣡⠓⣍⢷⣮⢓⡜⣢⢵⡪⣥⠛⣔⡋⣷⡇⣷⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⢾⠣⡏⡀⠄⣡⡏⢖⡩⢖⡱⢜⢪⠱⣱⢊⠧⣙⡔⢫⡔⢫⡱⢎⠴⣃⠾⣽⣶⣋⢦⡹⢿⡛⣧⡇⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⢮⠣⣝⠳⡴⡚⢧⣘⢣⠜⢦⡙⡬⢎⠵⣂⢏⠲⣅⠺⣡⢎⢣⡜⣊⠶⡑⣎⢹⢺⣻⣮⡝⢦⡙⣷⣻⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡰⢏⠎⣕⢪⣱⢣⡙⢆⠮⡜⢪⡱⢜⢢⣝⢢⡍⢎⡕⡪⢕⡲⢌⡣⢜⢢⢇⡹⢤⢣⠓⣎⣛⠿⢦⢹⣷⡹⡄
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⡴⢫⡙⣬⠚⣌⠦⡹⢟⣻⡿⢶⣍⢣⡜⢪⡱⢏⡣⡜⢎⡴⡙⢦⠱⢎⡱⡩⢖⢪⡑⣎⠲⣍⠲⡌⢞⢢⣻⢞⡵⡇
// ⠀⠀⠀⠀⠀⠀⠀⣠⡾⢣⢍⡣⡜⠴⡙⢆⡳⢡⠏⡴⢩⣋⠜⣆⡚⢥⢚⡴⡑⢮⡑⢦⡙⢆⠯⣘⠲⣅⠫⢆⠳⣌⠳⣸⣷⣏⢎⡱⣯⡻⣜⡇
// ⠀⠀⠀⠀⠀⣠⣾⢟⡴⣋⠦⡱⢎⢣⠝⡸⡔⢫⢜⡸⢅⡎⠞⣤⠹⣘⠦⣒⠭⡒⣍⠦⣙⠎⣜⣡⠳⣌⠳⣉⠳⣌⠳⣩⢛⠻⡌⣾⡳⣝⢧⡇
// ⠀⠀⠀⠀⡴⢟⡹⣻⠿⡎⢖⡱⡩⢎⣚⢱⣮⠇⣎⠖⣩⠜⣱⢊⠵⡡⢞⡰⢣⡙⣤⢋⢦⡙⢆⡖⡱⣊⠵⣉⠶⣡⠓⡥⢎⢳⢸⣷⢫⡽⣺⠅
// ⠀⠀⢀⢮⡙⣆⢣⠵⡩⢜⠣⣜⣡⠳⣌⠣⣍⡚⡤⢛⡤⢛⢤⡋⡼⡑⣎⠱⢣⡱⢆⢭⠢⡝⠲⢬⡱⢜⡸⢌⠶⣡⢋⢖⡩⢎⡿⣎⢷⡹⣽⠀
// ⠀⠀⣼⢍⠖⣱⢊⡖⡍⣎⠳⡰⢆⠳⣌⢓⠦⣱⠩⢖⡡⢏⠦⣱⢡⠳⡌⡭⢣⢜⡊⡖⠭⡜⣙⠦⡱⢎⡜⣊⠶⡡⠞⣌⠖⣿⣝⣮⢳⢯⡍⠀
// ⠀⢸⣻⢜⢪⡑⡎⡴⢓⡌⢇⡓⢎⠳⣌⡚⡜⠴⣙⢬⡚⢬⠲⣅⢎⠳⢬⣑⠣⣎⠜⡜⡥⡙⢆⣧⡓⡼⣐⢣⠎⡵⢩⢆⣿⡻⣼⣎⣟⣞⠃⠀
// ⠀⣟⣿⡘⣆⢣⡕⢎⡱⢪⡑⢮⠩⡖⣡⠞⣌⠳⡜⣶⣽⣦⣓⢬⢊⡝⢢⠎⡵⡘⢎⡱⡜⣩⢎⢻⠱⡒⡍⢦⢋⡴⢋⣼⣗⣻⣿⣿⡞⡼⠀⠀
// ⢸⣽⢾⡱⡌⠶⡘⢎⡱⢣⡙⢆⡏⠴⣃⠞⣌⠳⣘⡌⢳⠽⣻⢾⣮⢜⡡⢏⡴⡙⣬⠱⡜⡔⡪⢥⢋⡕⢮⡑⠮⣔⡿⣳⢎⡷⣹⢶⣹⠃⠀⠀
// ⢸⣞⢧⣷⢉⡞⡩⢮⣵⡣⢎⢣⡜⠳⡌⠞⣌⢣⠕⣊⢇⠮⣑⢫⡙⢦⡙⢆⡖⡍⣆⠳⡜⡸⣑⢎⡱⢊⢦⡙⣼⢞⡳⣝⢾⡱⣏⡞⡏⠀⠀⠀
// ⠸⣾⣏⠾⣧⣘⠱⢫⡙⣥⢋⢖⣘⢣⠭⣙⢤⡋⡼⢡⢎⠳⣌⢣⡜⢦⡙⡲⠸⡔⢣⡓⣜⣱⣬⠒⡭⣩⢆⣽⢳⢯⡝⣮⢳⡝⣮⡝⠀⠀⠀⠀
// ⠀⣷⢫⡟⡽⣆⢏⠥⣓⢤⢋⡖⡸⡌⠶⣉⢦⠱⣱⡉⢮⢱⡘⡆⠞⣤⠓⣍⢣⠝⣢⠕⡺⢽⠻⣍⢲⣱⠾⣭⣛⢮⣝⢮⡳⡽⡞⠀⠀⠀⠀⠀
// ⠀⢸⣻⣜⡳⣝⡻⣔⢣⠎⣖⠸⣱⢘⡣⢕⡪⠕⢦⡙⢆⡇⢞⡸⣉⢦⠹⡌⢎⢎⡱⢎⡱⢎⡱⡼⡾⣭⣛⢶⡹⣞⡼⣣⢟⡝⠀⠀⠀⠀⠀⠀
// ⠀⠀⢷⣫⠷⣭⢳⣏⢷⢾⣈⡓⠦⣍⡒⠧⡜⣙⠦⡙⢦⣿⡦⢱⢊⢦⢋⡼⣉⠦⡓⣬⣱⢾⡹⣏⢷⣣⢟⣮⢳⡝⣾⣱⠏⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠈⢯⣟⡼⣳⢎⡟⣮⢯⡽⣳⢦⣙⡜⡜⡢⢝⡘⢦⡙⡴⢋⡜⣢⢍⢲⣡⠾⣵⢫⡞⣧⢻⡼⣿⣿⡾⣜⢧⡻⣶⠋⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠈⢿⢾⡵⣛⠾⣵⣿⣾⣭⢯⡝⣾⣹⢳⡟⣞⢦⡳⣜⡳⣞⢶⣫⢟⡼⣻⣼⣳⢻⣼⣣⠿⣽⣛⢷⡹⣮⠟⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠻⣽⣯⣟⣿⣿⡿⣏⢾⡹⢶⣭⢳⡝⣮⢳⡝⣧⢻⡜⣧⣛⢮⣳⢳⢾⣻⢟⣾⣽⣛⡶⣹⢮⠿⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠈⠻⣿⣷⣹⢞⡽⢮⣝⡳⣎⢷⡹⣎⢷⡹⣎⢷⣿⣧⣟⢮⣳⣛⡾⣝⡻⣞⣽⢿⡽⠟⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠈⠳⢻⡿⣼⡳⣎⢷⡹⣎⢷⡹⣎⢷⡹⣾⣿⣿⢿⣫⣿⣿⡜⣧⢟⡾⠜⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠓⠿⣹⡞⡵⢯⡞⣵⣫⣞⣵⣳⡞⣼⢣⡷⣻⡼⠽⠚⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠑⠛⠒⠛⠚⠓⠓⠛⠊⠉⠉⠀⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀

/**
 * @title The PotatoTipper contract allows a 🆙 to react when receiving a new follower,
 * and tip 🥔 $POTATO tokens to this new follower. Can be used as an automated incentive mechanism.
 *
 * @author Jean Cavallera (CJ42)
 *
 * @dev Terminology:
 * - BPT = "Before Potato Tipper" = for followers that followed a user before it connected the Potato Tipper
 * - APT = "After Potato Tipper" = for followers that followed a user after it connected the Potato Tipper"
 *
 * @notice ⚠️ Disclaimer: this contract has not been formally audited by an external third party
 * auditor. The contract does not guarantee to be bug free. Use responsibly at your own risk.
 */
contract PotatoTipper is IERC165, ILSP1Delegate {
    using ERC165Checker for address;
    using Strings for address;
    using PotatoLib for bytes;

    /// @dev Track `follower` addresses that received a tip already from a `user`'s UP
    mapping(address user => mapping(address follower => bool tippedAPT)) internal _tipped;

    /// @dev Track `follower` addresses that followed a user's 🆙 AFTER the Potato Tipper was connected
    /// Regardless if the follower received a tip or not
    mapping(address user => mapping(address follower => bool followedAPT)) internal _hasFollowedSinceDelegate;

    /// @dev Track followers that existed BEFORE the Potato Tipper was connected to the user's UP
    /// (observed via an unfollow notifications without any post-install follow ever observed)
    mapping(address user => mapping(address follower => bool followedBPT)) internal _wasFollowing;

    /// @notice Check if the contract implements a given interface
    ///
    /// @dev Only LSP1Delegate and ERC165 interfaces are supported
    ///
    /// @param interfaceId The interface identifier, as specified in ERC-165
    /// @return true if the contract implements `interfaceId`, false otherwise
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == _INTERFACEID_LSP1_DELEGATE || interfaceId == type(IERC165).interfaceId;
    }

    /// Read functions
    /// ---------------

    /// @notice Check if a `follower` address has already been attempted to be tippied from a `user`'s UP
    ///
    /// @dev The result of this function does not guarantee that the `follower` actually received a tip,
    /// only that the `user`'s UP attempted to send a tip to the new `follower`. This is because the tip transfer
    /// could have failed for various reasons during the LSP1 `universalReceiver(...)` hook call on the
    /// `follower` and `user`'s UPs.
    ///
    /// @param follower The address of the follower that has been tipped
    /// @param user The address of the user that sent the tip
    ///
    /// @return true if the `follower` has already been tipped by the `user`, false otherwise
    function hasBeenTipped(address follower, address user) external view returns (bool) {
        return _tipped[user][follower];
    }

    /// @notice Determines if a `follower` address was already following a `user`'s UP before the user
    /// connected
    /// it's UP to the Potato Tipper contract. Helps to define if a follower is eligible for a tip or not.
    ///
    /// @dev This is determined by observing if an unfollow notification was received from the
    /// LSP26 Follower Registry without any prior follow notification being observed since the
    /// Potato Tipper was connected to the user's UP.
    ///
    /// @param follower The address of the follower that has been followed
    /// @param user The address of the user that was followed
    ///
    /// @return true if `follower` was already following `user` before it connected to the Potato Tipper.
    function wasFollowingBeforePotatoTipper(address follower, address user) external view returns (bool) {
        return _wasFollowing[user][follower];
    }

    /// @notice Check if a `follower` address has followed a `user`'s UP after `user` connected its 🆙
    /// to the Potato Tipper contract.
    ///
    /// @param follower The address of the follower that followed `user`.
    /// @param user The address of the user that was followed.
    /// @return true if `follower` followed `user` after it connected to the Potato Tipper, false otherwise.
    function followedAfterPotatoTipper(address follower, address user) external view returns (bool) {
        return _hasFollowedSinceDelegate[user][follower];
    }

    /// Write functions
    /// ---------------

    /// @notice Handle follow/unfollow notifications + automatically tip 🥔  tokens to new follower
    ///
    /// @dev Called by user's 🆙 `universalReceiver(...)` function when receiving a notification from the
    /// LSP26 Follower Registry about a new follower or an unfollow action (extracted from notification `data`).
    ///
    /// @param sender The address that notified the user's UP (MUST be the LSP26 Follower Registry)
    /// @param typeId The type ID of the notification (follow or unfollow)
    /// @param data Sent by the LSP26 Follower registry when notifying user (MUST be a 20 bytes long address)
    ///
    /// @return message A human-readable message that can be decoded from the `UniversalReceiver` event log
    ///
    // solhint-disable-next-line use-natspec
    function universalReceiverDelegate(
        address sender,
        uint256, /* value */
        bytes32 typeId,
        bytes calldata data
    )
        external
        returns (bytes memory)
    {
        // CHECK that this call came from the Follower Registry
        if (sender != address(_FOLLOWER_REGISTRY)) return unicode"❌ Not triggered by the Follower Registry";

        // Retrieve follower address from the notification data sent by the LSP26 Follower Registry
        if (data.length != 20) return unicode"❌ Invalid data received. Must be a 20 bytes long address";
        // casting to 'bytes20' is safe because of check above
        // forge-lint: disable-next-line(unsafe-typecast)
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

    /// @notice Handle a new follower notification and tip 🥔 $POTATO tokens if eligible
    /// @dev This function performs various checks to ensure the follow notification is legitimate,
    /// including verifying if the follower has not already been tipped.
    /// Note that existing followers BPT are not eligible for tips.
    ///
    /// @param follower The address of the new follower that followed the user's UP
    ///
    /// @return message A human-readable message returned to the `universalReceiver(...)` function, to
    /// indicate successful tip, or an error reason if no tip was sent.
    /// This message can be decoded from the `UniversalReceiver` event log
    function _onFollow(address follower) internal returns (bytes memory message) {
        bool isFollowing = _FOLLOWER_REGISTRY.isFollowing(follower, msg.sender);

        // CHECK to ensure this came from a legitimate notification callback from the LSP26 Registry
        if (!isFollowing) return unicode"❌ Not a legitimate follow";

        // Record when we see a new follower AFTER the PotatoTipper was connected to user's 🆙
        if (!_hasFollowedSinceDelegate[msg.sender][follower]) {
            _hasFollowedSinceDelegate[msg.sender][follower] = true;
        }

        // CHECK user has not already received a tip after following
        // (prevent recursive follow -> unfollow -> re-follow 🥔 🚜)
        if (_tipped[msg.sender][follower]) return unicode"🙅🏻 Already tipped a potato";

        // Check this is not an existing follower that unfollowed and tried to re-follow
        if (_wasFollowing[msg.sender][follower]) {
            return unicode"🙅🏻 Follower followed before. Not eligible for a tip";
        }

        return _sendTip(follower);
    }

    /// @notice Handle an unfollow notification
    /// @dev This function is used to track existing followers that unfollow the user's UP.
    /// To prevent existing followers from unfollowing -> re-following to try to get tips.
    ///
    /// @param address_ The address that unfollowed the user's UP
    /// @return message A human-readable message returned to the `universalReceiver(...)` function.
    function _onUnfollow(address address_) internal returns (bytes memory) {
        bool isFollowing = _FOLLOWER_REGISTRY.isFollowing(address_, msg.sender);

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
        // (e.g: if tipped failed because not enough 🥔 in user's balance, tipping budget, or transfer
        // failed). This allows an `address_` APT to re-follow and still be eligible for a tip.
        return "";
    }

    /// @notice Internal function to send 🥔 $POTATO tokens as tips to the new follower
    ///
    /// @dev This function fetch the tip settings from the ERC725Y storage of the user's 🆙,
    /// and performs pre-checks (e.g: sufficient balance, allowance, etc...) to ensure the tip can be sent.
    /// Tipping is handled via `try {} catch {}` and emit `TipSent` or `TipFailed` events.
    /// Note that if the $POTATO token transfer fails due to any nested calls to the `universalReceiver(...)`
    /// function of the `follower` or `user`'s UP reverting, the follower will still be marked as having been
    /// tipped. See function `hasBeenTipped(...)` above for details.
    ///
    /// @param follower The address of the new follower that will receive a tip
    /// @return A human-readable message that can be decoded from the `UniversalReceiver` event
    function _sendTip(address follower) internal returns (bytes memory) {
        // Fetch configs from user's UP metadata
        bytes memory settingsValue = IERC725Y(msg.sender).getData(POTATO_TIPPER_SETTINGS_DATA_KEY);

        (bool decodingSuccess, uint256 tipAmount, uint256 minimumFollowers, uint256 minimumPotatoBalance) =
            settingsValue.decodeSettings();

        // CHECK if the settings value is valid
        if (!decodingSuccess) {
            return unicode"❌ Invalid settings value. Must be 96 bytes long encoded as (uint256,uint256,uint256)";
        }

        // CHECK the address being followed has enough 🥔 to tip.
        if (_POTATO_TOKEN.balanceOf(msg.sender) < tipAmount) {
            return unicode"🤷🏻‍♂️ Not enough 🥔 left in balance";
        }

        // CHECK if the Potato Tipper contract has enough left in its tipping budget
        if (_POTATO_TOKEN.authorizedAmountFor(address(this), msg.sender) < tipAmount) {
            return unicode"❌ Not enough 🥔 left in tipping budget";
        }

        // CHECK the follower has the minimum number of followers required
        if (_FOLLOWER_REGISTRY.followerCount(follower) < minimumFollowers) {
            return unicode"❌ Not eligible for tip: minimum follower required not met";
        }

        // CHECK if the followers has the minimum amount of $POTATO tokens required
        if (_POTATO_TOKEN.balanceOf(follower) < minimumPotatoBalance) {
            return unicode"❌ Not eligible for tip: minimum 🥔 balance required not met";
        }

        _tipped[msg.sender][follower] = true;

        // Transfer 🥔 $POTATO 🥔 tokens as tip to the new follower
        // Return a success or error message that can be decoded from the `UniversalReceiver` event
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
            return abi.encodePacked(unicode"✅ Successfully tipped 🍠 to new follower: ", follower.toHexString());
        } catch (bytes memory errorData) {
            emit TipFailed({from: msg.sender, to: follower, amount: tipAmount, errorData: errorData});
            return unicode"❌ Failed tipping 🥔. LSP7 transfer reverted";
        }
    }
}

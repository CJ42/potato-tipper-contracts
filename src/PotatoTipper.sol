// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

// modules
import {PotatoTipperConfig} from "./PotatoTipperConfig.sol";

// interfaces
import {IERC725Y} from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {
    ILSP1UniversalReceiverDelegate as ILSP1Delegate
} from "@lukso/lsp1-contracts/contracts/ILSP1UniversalReceiverDelegate.sol";

// libraries
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "./PotatoTipperSettingsLib.sol" as SettingsLib;

// constants
import {_INTERFACEID_LSP0} from "@lukso/lsp0-contracts/contracts/LSP0Constants.sol";
import {_TYPEID_LSP26_FOLLOW, _TYPEID_LSP26_UNFOLLOW} from "@lukso/lsp26-contracts/contracts/LSP26Constants.sol";
import {_FOLLOWER_REGISTRY, _POTATO_TOKEN} from "./Constants.sol";

// events
import {PotatoTipSent, PotatoTipFailed} from "./Events.sol";

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
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠑⠛⠒⠛⠚⠓⠓⠛⠊⠉⠉⠀⠁⠀⠀⠀⠀⠀⠀
using {SettingsLib.loadTipSettingsRaw} for IERC725Y;
using {SettingsLib.decodeTipSettings} for bytes;
using {ERC165Checker.supportsInterface} for address;

///
/// @title Contract allowing a 🆙 to react when receiving a new follower, by tipping 🥔 $POTATO tokens to
/// this new follower. Can be used as an automated incentive mechanism.
///
/// @author Jean Cavallera (CJ42)
///
/// @dev Terminology:
/// - BPT = "Before Potato Tipper" = for followers that already followed a user before it connected the Potato Tipper
/// - APT = "After Potato Tipper" = for followers that followed a user after it connected the Potato Tipper"
///
/// @notice ⚠️ Disclaimer: this contract has not been formally audited by an external third party
/// auditor. The contract does not guarantee to be bug free. Use responsibly at your own risk.
///
contract PotatoTipper is IERC165, ILSP1Delegate, PotatoTipperConfig {
    using Strings for address;

    /// @dev Track `follower` addresses that received a tip already from a `user`
    mapping(address user => mapping(address follower => bool tippedAPT)) internal _tipped;

    /// @dev Track followers that followed a `user` AFTER it connected the Potato Tipper.
    /// Regardless of whether they received a tip (because of LSP7 failed token transfer)
    mapping(address user => mapping(address follower => bool followedAPT)) internal _hasFollowedPostInstall;

    /// @dev Track existing followers BEFORE the user connected the Potato Tipper, to make them not eligible for a tip.
    /// Populated via `_handleOnUnfollow(...)`. Used to keep them ineligible for a tip if they re-follow.
    mapping(address user => mapping(address follower => bool followedBPT)) internal
        _existingFollowerUnfollowedPostInstall;

    /// Read functions
    /// ---------------

    /// @notice This contract only supports the LSP1 Universal Receiver Delegate and ERC165 interfaces.
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ILSP1Delegate).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @notice Check if a `follower` has already been tipped by a `user`.
    function hasReceivedTip(address follower, address user) external view returns (bool) {
        return _tipped[user][follower];
    }

    /// @notice Returns if `follower` has followed `user` since it connected its 🆙 to the Potato Tipper contract.
    function hasFollowedPostInstall(address follower, address user) external view returns (bool) {
        return _hasFollowedPostInstall[user][follower];
    }

    /// @notice Returns true if `follower` was already a follower of `user` before it connected the Potato Tipper and
    /// later unfollowed. Defines existing followers that are not eligible for a tip.
    function existingFollowerUnfollowedPostInstall(address follower, address user) external view returns (bool) {
        return _existingFollowerUnfollowedPostInstall[user][follower];
    }

    /// Handler functions
    /// ---------------

    /// @notice Handle follow/unfollow notifications + automatically tip 🥔 tokens to new follower.
    ///
    /// @dev Called by the `universalReceiver(...)` function from a user's 🆙.
    ///
    /// LSP26 notification calls don't revert, but calls from a 🆙 to this function could revert.
    /// Avoid reverting so the internal call stack trace stays clear of revert errors, and return a `messageStatus`
    /// that can be decoded from the `returnedData` parameter of the `UniversalReceiver` event on the user's 🆙.
    ///
    /// @param sender The address that notified the user's UP (MUST be the LSP26 Follower Registry)
    /// @param typeId MUST be a follow or unfollow notification type ID
    /// @param data MUST be the follower address sent by the LSP26 Follower registry when notifying
    /// @return messageStatus A user-friendly message describing how the call was handled
    function universalReceiverDelegate(
        address sender,
        uint256, // value (unused parameter)
        bytes32 typeId,
        bytes calldata data
    )
        external
        returns (bytes memory messageStatus)
    {
        if (sender != address(_FOLLOWER_REGISTRY)) return unicode"⛓️‍💥❌ Not triggered by the LSP26 Follower Registry";
        if (data.length != 20) return unicode"⛓️‍💥❌ Invalid data received. Must be a 20 bytes address";

        // Only 🆙✅ allowed to receive tips, 🔑❌ not EOAs
        address follower = address(bytes20(data));
        if (!follower.supportsInterface(_INTERFACEID_LSP0)) return unicode"⛓️‍💥❌ Only 🆙 allowed to receive tips";

        if (typeId == _TYPEID_LSP26_FOLLOW) return _handleOnFollow(follower);
        if (typeId == _TYPEID_LSP26_UNFOLLOW) return _handleOnUnfollow(follower);

        return unicode"⛓️‍💥❌ Not a follow/unfollow notification";
    }

    /// @notice Handle a new follower notification and tip 🥔 $POTATO tokens if the follower is eligible.
    ///
    /// @dev Before attempting to transfer a tip, re-validate against the LSP26 Follower Registry to ensure
    /// this function is running in the context of a legitimate follow notification and not from a spoofed call.
    /// Also rejects re-follow attempts from pre-existing followers.
    ///
    /// @return message A human-readable message returned to indicate successful tip, or an error reason.
    function _handleOnFollow(address follower) internal returns (bytes memory message) {
        bool isFollowing = _FOLLOWER_REGISTRY.isFollowing(follower, msg.sender);
        if (!isFollowing) return unicode"⛓️‍💥❌ Not a legitimate follow";

        // Prevent double tipping a follower if unfollow -> re-follow 🥔 🚜
        if (_tipped[msg.sender][follower]) return unicode"🔍❌ Follower already tipped";

        // Existing followers are not eligible. A user does not gain any benefit from tipping them if they re-follow
        if (_existingFollowerUnfollowedPostInstall[msg.sender][follower]) {
            return unicode"🔍❌ Existing followers not eligible to receive tips";
        }

        if (!_hasFollowedPostInstall[msg.sender][follower]) _hasFollowedPostInstall[msg.sender][follower] = true;

        bytes memory settingsValue = IERC725Y(msg.sender).loadTipSettingsRaw();
        (bool decodingSuccess, SettingsLib.TipSettings memory tipSettings, bytes memory decodingError) =
            settingsValue.decodeTipSettings();

        // Decoding also validates the tip settings
        if (!decodingSuccess) return decodingError;

        (bool isEligible, bytes memory eligibilityError) =
            _validateTipEligibilityCriterias(follower, tipSettings.minimumFollowers, tipSettings.minimumPotatoBalance);
        if (!isEligible) return eligibilityError;

        (bool canTransferTip, bytes memory preTransferError) = _validateCanTransferTip(tipSettings.tipAmount);
        if (!canTransferTip) return preTransferError;

        return _transferTip(follower, tipSettings.tipAmount);
    }

    /// @notice Monitor unfollow activity to mark existing followers BPT as ineligible for a tip if they re-follow.
    ///
    /// @dev Re-validate against the LSP26 Follower registry to ensure this function is running in the context of
    /// a legitimate unfollow notification and not from a spoofed call. Existing followers are tracked if we observe
    /// an unfollow without any prior follow registration AFTER the user connected the Potato Tipper (APT).
    ///
    /// @return message A human-readable message to describe the context of the unfollow action.
    function _handleOnUnfollow(address follower) internal returns (bytes memory message) {
        bool isFollowing = _FOLLOWER_REGISTRY.isFollowing(follower, msg.sender);
        if (isFollowing) return unicode"⛓️‍💥❌ Not a legitimate unfollow";

        if (_tipped[msg.sender][follower]) return unicode"👋🏻 Already tipped, now unfollowing. Goodbye!";

        if (!_hasFollowedPostInstall[msg.sender][follower]) {
            _existingFollowerUnfollowedPostInstall[msg.sender][follower] = true;
            return unicode"👋🏻 Assuming existing follower BPT is unfollowing. Goodbye!";
        }

        return unicode"👋🏻 Sorry to see you go. Hope you re-follow soon! Goodbye!";
    }

    // Internal helpers
    // ----------------

    /// @dev Check if a follower is eligible to receive a tip according to the provided user's tip settings.
    /// Returns an error message explaining why the follower is not eligible.
    function _validateTipEligibilityCriterias(
        address follower,
        uint256 minimumFollowerCountRequired,
        uint256 minimumPotatoBalanceRequired
    ) internal view returns (bool isEligible, bytes memory errorMessage) {
        if (_FOLLOWER_REGISTRY.followerCount(follower) < minimumFollowerCountRequired) {
            return (false, unicode"🔍❌ Not eligible for tip: minimum follower required not met");
        }

        if (_POTATO_TOKEN.balanceOf(follower) < minimumPotatoBalanceRequired) {
            return (false, unicode"🔍❌ Not eligible for tip: minimum 🥔 balance required not met");
        }

        return (true, "");
    }

    /// @notice Ensure this contract can transfer `tipAmount` of 🥔 $POTATO tokens on behalf of the user.
    /// Returns an error message explaining why the tip cannot be transferred.
    ///
    /// @dev These checks are also done inside the Potato token contract (LSP7), but performed earlier to:
    /// 1. Avoid making the follower pay the gas cost of a token transfer reverting (external call + return error data).
    /// 2. Return an early error message and pass it to the `returnedData` of the `UniversalReceiver` event.
    function _validateCanTransferTip(uint256 tipAmount)
        internal
        view
        returns (bool canTransferTip, bytes memory errorMessage)
    {
        if (_POTATO_TOKEN.balanceOf(msg.sender) < tipAmount) {
            return (false, unicode"⚙️⚠️ Not enough 🥔 left in user's balance");
        }

        if (_POTATO_TOKEN.authorizedAmountFor(address(this), msg.sender) < tipAmount) {
            return (false, unicode"⚙️⚠️ Not enough 🥔 left in user's tipping budget");
        }

        return (true, "");
    }

    /// @notice Transfer `tipAmount` of 🥔 $POTATO tokens to the new `follower`.
    ///
    /// @dev Use `try {} catch {}` to transfer the tip to prevent any sub-calls from making the whole call revert.
    /// Returns a success or error message to describe if the tip transfer was successful or not.
    function _transferTip(address follower, uint256 tipAmount) internal returns (bytes memory successOrErrorMessage) {
        _tipped[msg.sender][follower] = true;

        try _POTATO_TOKEN.transfer({
            from: msg.sender, // 🆙 that was ⬅️ followed
            to: follower, // 🆙 that is following ➡️
            amount: tipAmount, // amount of 🥔🥔🥔 to tip
            force: false, // Default to false, but already checked that follower is a 🆙, so we know it supports LSP1
            data: unicode"Thanks for following! Tipping you some 🥔" // context for the token transfer
        }) {
            emit PotatoTipSent({from: msg.sender, to: follower, amount: tipAmount});
            return abi.encodePacked(unicode"🥔✅ Successfully sent tip to new follower: ", follower.toHexString());
        } catch (bytes memory errorData) {
            // If the token transfer failed (because the call to the `universalReceiver(...)` function reverted when
            // notifying sender / recipient, or any sub-calls), revert state and mark the follower as not tipped.
            delete _tipped[msg.sender][follower];

            emit PotatoTipFailed({from: msg.sender, to: follower, amount: tipAmount, errorData: errorData});
            return abi.encodePacked(unicode"🥔❌ Failed to send tip to ", follower.toHexString(), ". LSP7 transfer reverted");
        }
    }
}

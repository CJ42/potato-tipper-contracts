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
import {_TYPEID_LSP26_FOLLOW} from "@lukso/lsp26-contracts/contracts/LSP26Constants.sol";
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
 * @title PotatoTipper, a contract that automatically tips 1 $POTATO token to anyone that follows
 * the account it is linked to.
 * @author Jean Cavallera (CJ42)
 * @dev ⚠️ Disclaimer: this contract has not been formally audited by an external third party
 * auditor.
 * The contract does not guarantee to be bug free. Use at your own risk.
 */
contract PotatoTipper is IERC165 {
    using ERC165Checker for address;
    using Strings for address;

    mapping(address user => mapping(address follower => bool tipped)) internal _tipped;

    mapping(address user => mapping(address follower => bool isInitialFollower)) internal _hasEverFollower;

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == _INTERFACEID_LSP1_DELEGATE || interfaceId == type(IERC165).interfaceId;
    }

    function hasReceivedTip(address follower, address user) public view returns (bool) {
        return _tipped[user][follower];
    }

    function setInitialFollowerList(address[] memory initialFollowers) public {
        for (uint256 i = 0; i < initialFollowers.length; i++) {
            _hasEverFollower[msg.sender][initialFollowers[i]] = true;
        }
    }

    function universalReceiverDelegate(address sender, uint256, /* value */ bytes32 typeId, bytes memory data)
        external
        returns (bytes memory)
    {
        // CHECK that this call came from the Follower Registry
        // TODO: test if msg.sender is a not the user UP, do not make assumptions
        if (sender != _FOLLOWER_REGISTRY) return unicode"❌ Not triggered by the Follower Registry";

        // CHECK notification type ID and only run if we are being notified about a "new follower"
        if (typeId != _TYPEID_LSP26_FOLLOW) return unicode"❌ Not a follow notification";

        // Retrieve the follower address from the notification data sent by the LSP26 Follower Registry
        address follower = address(bytes20(data));

        // Only 🆙✅ allowed to receive tips, 🔑❌ not EOAs
        if (!follower.supportsInterface(_INTERFACEID_LSP0)) return unicode"❌ Only 🆙 allowed to be tipped";

        // CHECK user has not already followed and received a tip previously
        // (prevent recursive follow -> unfollow -> re-follow 🥔 🚜)
        bool alreadyTipped = hasReceivedTip({follower: follower, user: msg.sender});
        if (alreadyTipped) return unicode"🙅🏻 Already tipped a potato";

        // Fetch tip amount set as config in user's UP metadata
        bytes memory tipAmountDataValue = IERC725Y(msg.sender).getData(POTATO_TIPPER_TIP_AMOUNT_DATA_KEY);

        // CHECK tip amount is correctly encoded in wei (18 decimals)
        if (tipAmountDataValue.length != 32) return unicode"❌ Invalid tip amount. Must be encoded as uint256";
        uint256 tipAmount = uint256(bytes32(tipAmountDataValue));

        // CHECK the address being followed has enough 🥔 to tip.
        //
        // When doing LSP7 transfer as operators, LSP7 logic reverts first with operator allowance error.
        // Checking user's token balance early improves UX clarity and semantics,
        // ensuring the user is informed of insufficient balance early.
        // (= "You first need to have enough 🥔 tokens before allowing the POTATO
        // Tipper to tip a certain amount of 🥔")
        if (_POTATO_TOKEN.balanceOf(msg.sender) < tipAmount) {
            return unicode"🤷🏻‍♂️ Not enough 🥔 to tip the follower";
        }

        // CHECK if this contract has enough in its tipping budget left to tip
        if (_POTATO_TOKEN.authorizedAmountFor(address(this), msg.sender) < tipAmount) {
            return unicode"❌ Not enough allowance to tip $POTATO tokens";
        }

        // TODO: there is a bug here
        // if the transfer occured but the transfer reverted, the follower did not receive a tip
        // and the contract will still mark the user as tipped.
        // This could be fixed by checking if the transfer reverted before marking the user as tipped.
        // Or by using a try / catch block to handle the transfer revert.
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
            // Handle revert call gracefuly and return:
            // 1. a descriptive error message
            // 2. any custom error data (or revert reason string)
            // So a dApp can decode and display it in the UI.
            if (bytes4(lowLevelData) == LSP7AmountExceedsAuthorizedAmount.selector) {
                _tipped[msg.sender][follower] = false;
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

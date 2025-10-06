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
    using Strings for address;
    // TODO: add using for ERC165Checker for address; + check interface ID LSP0

    mapping(address user => mapping(address follower => bool tipped)) internal _tipped;

    mapping(address user => mapping(address follower => bool isInitialFollower)) internal _hasEverFollower;

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == _INTERFACEID_LSP1_DELEGATE || interfaceId == type(IERC165).interfaceId;
    }

    function hasReceivedTip(address user, address follower) public view returns (bool) {
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

        // CHECK that the call is a follow notification
        // TODO: really needed? The `universalReceiver` delegate function should already get it
        // triggered for this? -> no this might be needed for security reasons
        // Or how about if you register it for the generic LSP1 Delegate?
        // Or doesn't the Follower Registry call it with the specific typeId?
        if (typeId != _TYPEID_LSP26_FOLLOW) return unicode"❌ Not a follow notification";

        // Retrieve the follower address from the notification data sent by the LSP26 Follower Registry
        address follower = address(bytes20(data));

        // Do not tip users that are trying to get tips by unfollowing and re-following.
        // Prevent 🥔 🚜 (farming), or drainer user's 🥔
        bool alreadyTipped = hasReceivedTip({user: msg.sender, follower: follower});
        if (alreadyTipped) return unicode"🙅🏻 Already tipped a potato";

        // Fetch tip amount set as config in user's UP metadata
        bytes memory tipAmountDataValue = IERC725Y(msg.sender).getData(POTATO_TIPPER_TIP_AMOUNT_DATA_KEY);
        if (tipAmountDataValue.length != 32) return unicode"❌ Invalid tip amount. Must be encoded as uint256";
        uint256 tipAmount = uint256(bytes32(tipAmountDataValue));

        // CHECK that the address being followed has enough 🥔 to tip.
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

        // Send the tip amount
        try _POTATO_TOKEN.transfer(
            msg.sender, // the UP that was followed
            follower, // the UP that is following
            tipAmount, // amount (= 1 POTATO token, the token has 18 decimals)
            // TODO: this should be set to `false` to prevent farming
            true, // force transfer (allow to send POTATO to EOAs)
            unicode"🥔 Thanks for following. I tipped you a potato!" // data
        ) {
            // TODO: refactor to use abi.encode for easier encoding / decoding on the UI side
            return abi.encodePacked(
                unicode"✅🍠 Successfully tipped 1 $POTATO token to new follower: ", follower.toHexString()
            );
        } catch (bytes memory lowLevelData) {
            if (bytes4(lowLevelData) == LSP7AmountExceedsAuthorizedAmount.selector) {
                _tipped[msg.sender][follower] = false;
                return unicode"❌ Not enough allowance to tip $POTATO tokens";
            }

            // TODO: add returned low level data to the returned message
            return
            unicode"❌🍠 Failed tipping a $POTATO token. `transfer(...)` function reverted with the following low level data: ";
        }
    }
}

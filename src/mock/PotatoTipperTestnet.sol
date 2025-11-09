// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {ILSP7DigitalAsset as ILSP7} from "@lukso/lsp7-contracts/contracts/ILSP7DigitalAsset.sol";
import {PotatoTipper} from "../PotatoTipper.sol";

// Address of the $POTATO Token contract deployed on LUKSO Testnet.
ILSP7 constant _POTATO_TOKEN = ILSP7(0x3bbb93Dfc6e238fb345301c124c84BcA53eBedB8);

/// @dev dummy PotatoTipper contract currently used on testnet for testing purposes (includes owner reset functions for
/// ease of testing) Useful to import in Remix and add in the interface
/// Note that if this contract is deployed, it will not work for tipping since the `_POTATO_TOKEN` address is not the
/// one used above but the one from `Constants.sol`
contract PotatoTipperTestnet is PotatoTipper {
    address internal _owner;

    constructor(address owner_) {
        _owner = owner_;
    }

    function resetTipped(address user, address follower) external {
        require(msg.sender == _owner, "Only owner can reset tipped status");
        _tipped[user][follower] = false;
    }

    function resetWasFollowing(address user, address follower) external {
        require(msg.sender == _owner, "Only owner can reset wasFollowing status");
        _wasFollowing[user][follower] = false;
    }

    function resetHasFollowedSinceDelegate(address user, address follower) external {
        require(msg.sender == _owner, "Only owner can reset hasFollowedSinceDelegate status");
        _hasFollowedSinceDelegate[user][follower] = false;
    }
}

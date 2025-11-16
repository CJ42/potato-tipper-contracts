# Documentation & Learn

- [Documentation \& Learn](#documentation--learn)
  - [Motivation](#motivation)
  - [Design pattern](#design-pattern)
    - [Pattern 1: Tip-on-Follow (React on Follow)](#pattern-1-tip-on-follow-react-on-follow)
    - [Pattern 2: Self-Documenting ERC725Y Data Keys Configurations](#pattern-2-self-documenting-erc725y-data-keys-configurations)
  - [Expanding \& Moving Forward](#expanding--moving-forward)
  - [Adapting for other tokens and NFTs](#adapting-for-other-tokens-and-nfts)
  - [Data Keys](#data-keys)
  - [Order of emitted events](#order-of-emitted-events)

This page describes the business logic of how the Potato Tipper contract works, as well as some potential ideas to expand its concept. If you are a developer building on LUKSO, you might find this page useful and maybe draw some inspiration from it to build your own product or protocol using this design pattern in tandem with the LSP smart contracts.

## Motivation

The Potato Tipper can be seen as a generic token tipper, that any Universal Profile can use as an _"incentive mechanism"_ to attract (and hopefully gain) more followers.

Imagine for instance a brand or a creator performing a marketing campaign to incentivize people to follow them. By following them, they get tipped tokens.

## Design pattern

### Pattern 1: Tip-on-Follow (React on Follow)

The Potato Tipper follows what I call the Tip-On-Follow (TOF) or Follow-Then-Tip (FTT) pattern. Although the name and acronym for this pattern is made up here, are made up here, this is very similar to the well-known [**hook**](https://jamesg.blog/2024/06/16/software-hooks) design pattern in software development. Hooks allow you to run code (and so perform programmed actions) before or after something happened. In our case, it is a post-action hook where:

- the **something** is _"I received a new follower"_
- the **action** being done is _"transfer some 🥔 tokens to the new follower"_.

### Pattern 2: Self-Documenting ERC725Y Data Keys Configurations

The [`PotatoTipperConfig`](./src/PotatoTipperConfig.sol) contract exposes all required ERC725Y data keys to be configured by a user
through view functions, making it easy for dApp developers and users to discover configuration requirements and set them.

- the function `configDataKeys()` returns an object describing each configuration data keys. It is useful to know the `bytes32` hex data key (smart-contract readable) corresponds to each human readable settings.

```solidity
// For configDataKeys()
PotatoTipper tipper = PotatoTipper(deployedAddress);
ConfigDataKeys memory keys = tipper.configDataKeys();
console.log("Tip settings data key:", keys.tipSettingsDataKey);
// 0xd1d57abed02d4c2d7ce00000e8211998bb257be214c7b0997830cd295066cc6a
console.log("React on follow data key:", keys.lsp1DelegateReactOnFollowDataKey);
// 0x0cfc51aec37c55a4d0b1000071e02f9f05bcd5816ec4f3134aa2e5a916669537
console.log("React on unfollow data key:", keys.lsp1DelegateReactOnUnfollowDataKey);
// 0x0cfc51aec37c55a4d0b100009d3c0b4012b69658977b099bdaa51eff0f0460f4
```

- the function `configDataKeysList()` returns an array of configuration data keys. It is useful to easily get the list of data keys that need to be set to then call `setDataBatch(bytes32[],bytes[])` on the Universal Profile of the user to with the associated value for each of them.

```solidity
bytes32[] memory configKeysList = tipper.configDataKeysList();
bytes[] memory configValues = new bytes[](3);
// ... populate values
universalProfile.setDataBatch(configKeysList, configValues);
```

- the function `encodeConfigDataKeysValues(TipSettings memory tipSettings)` is useful to encode the configuration data keys and values in one go. It returns an array of `configDataKeysToSet[]` and `configDataValuesToSet[]` that can be passed directly to the `setDataBatch(bytes32[],bytes[])` when settings the Potato Tipper config on a Universal Profile.

```solidity
TipSettings memory settings = TipSettings({
    tipAmount: 1 ether, // 1 🥔
    minimumFollowers: 5,
    minimumPotatoBalance: 100 ether // 100 🥔
});
(bytes32[] memory keys, bytes[] memory values) =
    tipper.encodeConfigDataKeysValues(settings);
universalProfile.setDataBatch(keys, values);
```

Using this design pattern eliminates the need for heavily having to manage an external documentation. Once the contract is verified, with a minimal of inline code comments, the contract source code is self-documented on-chain, making external integrations with the contract easier and more reliable.

## Expanding & Moving Forward

The Tip-On-Follow design pattern can be generalized to a Reward on Follow system.

If we expand for instance at the level of _"what is being tipped"_. If we ask ourselves the question _“what else can be tipped to a new follower?”_, we can consider that pretty much anything can be sent as a reward to a new follower.

To get creative and find ideas, we can replace the placeholder below with what you want your new followers to receive:

> When someone follows my Universal Profile, I tip you (= reward you) with `[insert what you want to send here]`.

Consider a user, a creator, or a brand having its own Universal Profile. What else could a brand tip to its new follower? Some examples of ideas:

- **any other tokens** (not only 🥔, for instance any other meme coins, or tokens created by the brand or the company)
- **an NFT** (e.g: a burnt pix, a special early follower badge, etc...)
- **discount points or vouchers**, redeemable to buy any assets sold by the brand (e.g: phygital piece of clothing, NFTs from a newly launched collection, etc…)

Regarding rewarding with NFTs, an example of promotional strategy for a brand could be to issue a specific “early follower” NFT badges to the first 100 followers as a reward. Such transactions being recorded on-chain and immutable provide a historical record of the early followers of the brand by anyone to examine.

We can expand the concept even further to think of what kind of automation could run _“after someone follow you”_, to not limit it to only _“tipping”_ or _“sending a reward”_. At the time of this writing, I could not think of anything and my ideas are limited. It's up to the developer imagination to decide what else to do after it got a new follower.

## Adapting for other tokens and NFTs

Since the Potato Tipper acts as an operator on behalf of the user (using the `authorizeOperator(...)` function from LSP7), the Solidity code of the contract can be easily adapter to work to transfer any other LSP7 token by just changing the token address and re-deploy it.

Adapting it to work for LSP8 NFTs would require more changes, such as changing the `transfer(...)` function calls to use `bytes32 tokenId` parameters instead of `uint256 tokenAmount`. However, the problem the developer will face will be for the contract to know which NFTs it should transfer. Since the current contract uses a **custom amount** stored in the ERC725Y storage of the user's UP, one would need to adjust this part of the logic for instance by storing a list of token IDs in the user's UP that the contract is allowed to transfer.

A final aspect the developer should be aware of is that the Solidity code in this current state would not work to tip native tokens (LYX). Because the contract cannot act as an operator here. It would need to have access to the user's LYX balance, which would require more complex setup (such as LSP6 Key Manager permissions for instance), or any other system in between to also allow the same feature as a _"tipping budget for native tokens"_.

---

A brand could tip its new followers in LYX, other tokens, tokens created by the brand or meme coins.

## Data Keys

The configurations and settings for tipping new followers are stored under a specific data key under each user's 🆙.

The data key is of `Mapping` key type and named after the Potato Tipper for the first part of the map name, to make it easy to remember and for future proofing (if more data keys related to the Potato Tipper should be introduced in future, new or forked versions).

Below is the LSP2 JSON Schema for tip settings:

```json
{
  "name": "PotatoTipper:Settings",
  "key": "0xd1d57abed02d4c2d7ce00000e8211998bb257be214c7b0997830cd295066cc6a",
  "keyType": "Mapping",
  "valueType": "(uint256,uint256,uint256)",
  "valueContent": "(Number,Number,Number)"
}
```

Below is an example of how the data is encoded and can be decoded. The data value is essentially abi-encoded and can be-decoded by any libraries like ethers.js, viem or erc725.js.

> Note that the values for the tip amount and minimum $POTATO tokens required in follower balance **are encoded in wei value, since the $POTATO token has 18 decimals.**

```js
example: 0x0000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000056bc75e2d63100000

- tipAmount (uint256) = 32 bytes long
// 0000000000000000000000000000000000000000000000000de0b6b3a7640000 (in hex) = 1,000,000,000,000,000,000 (in decimals)

- minimumFollowers (uint256) = 32 bytes long
// 0000000000000000000000000000000000000000000000000000000000000005

- minimumPotatoBalance (uint256) = 32 bytes long
// 0000000000000000000000000000000000000000000000056bc75e2d63100000 (in hex) = 100,000,000,000,000,000,000 (in decimals)

- Final decoded result
// => (1 $POTATO token as tip amount, 5 minimum followers, 100 $POTATO token minimum in follower balance)
```

## Order of emitted events

When a user follows another user and get tipped 🥔, the following events are emitted in the transaction in the following order. There are 6 events emitted in total with the follow-then-tip pattern. These below do not include the event from the POTATO Tipper contract itself (_to be added_).

From the logs obtained in foundry via `getRecordedLogs()`

```js
[0] -> `emit Follow` (LSP26)
    = from LSP26 Follower Registry

[1] -> `emit OperatorAuthorizationChanged` (LSP7)
    = from $POTATO token contract when allowance decreases

[2] -> `emit Transfer` (LSP7)
    = when the PotatoTipper contract transferred 🥔 as operator
    to the new follower ("tipped")

[3] -> `emit UniversalReceiver`
    = on sender's UP (user), with notification type ID "LSP7 Token Sent"

[4] -> `emit UniversalReceiver`
    = on recipient's UP (follower), with notification type ID "LSP7 Token Received"

[5] -> `emit PotatoTipSent`
    = on PotatoTipper contract, with user, follower, and tip amount as arguments

[6] -> `emit UniversalReceiver`
    = on sender's UP (user), with notification type ID "New Follower"
```

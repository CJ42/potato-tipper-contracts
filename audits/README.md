# Security notes

- [Security notes](#security-notes)
  - [Audit reports from AI Auditing tools](#audit-reports-from-ai-auditing-tools)
    - [Ackee Wake - AI Audit Report](#ackee-wake---ai-audit-report)
  - [Known issues](#known-issues)
- [Slither outputs - `PotatoTipper.sol`](#slither-outputs---potatotippersol)
  - [reentrancy-benign](#reentrancy-benign)
  - [reentrancy-events](#reentrancy-events)

## Audit reports from AI Auditing tools

This folder contains PDF reports with findings from AI auditing tools, as well as outputs from the static analysis tool Slither and known limitations.

- [Wake Arena (by Ackee)](./wake-arena-ai-audit-report.pdf)
- AI Audit Agent (by Nethermind)

### Ackee Wake - AI Audit Report

| Ref | Title                                                              | Status                               | Comments                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| :-- | :----------------------------------------------------------------- | :----------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| H1  | Incorrect memory offset parsing in PotatoLib getSettings function  | ✅ Fixed                             | Fixed in commit `00c7944`. The encoding was changed to an abi-encoded tuple of `(uint256,uint256,uint256)`, removing the need to use low-level assembly to decode the settings.                                                                                                                                                                                                                                                              |
| H2  | Sybil Attack Amplification Through Flash Loan Balance Bypass       | ☑️ Acknowledged                      | Documented in the repository and the dApp for users. Setting minimum number of required followers will also help in mitigating this issue. Furthermore, there is no ways to perform flash loans on LUKSO Mainnet since there is currently no lending protocols on LUKSO Mainnet.                                                                                                                                                             |
| M1  | Follower Count Manipulation Through Sybil Networks                 | ☑️ Acknowledged                      | Documented in the repository and the dApp for users that the lower the eligibility criterias settings, the more likely they can be subject to bot farming. A v2 version of the Potato Tipper contract could implement oracles to check the age of the new follower. There is currently no way to mitigate that fully on-chain. Considered as acceptable for an MVP.                                                                          |
| M2  | Permanent Tip Marking Despite Transfer Failure                     | ✅ Fixed                             | Fixed in commit `92325a0`. A change was added in the code to revert the user marked as tipped if the token transfer failed. Additional Foundry test was added.                                                                                                                                                                                                                                                                               |
| M3  | Front-running Vulnerability in Follow/Tip Mechanism                | ❌ False Positive                    | Seems to be a false positive. An MEV bot cannot front-run the transaction, as the follower making the follow is the one only eligible for a tip. Only issue that this could cause is to delay the follow transaction to be validated, and therefore make the follower wait longer to receive a tip.                                                                                                                                          |
| M4  | Griefing Attack via Unfollow Manipulation                          | ☑️ Acknowledged + ❌ False positive  | Not any address can trigger the unfollow handler for a user that connected the Potato Tipper. The `msg.sender` (passed from user's `universalReceiver(...)` to Potato Tipper `universalReceiverDelegate(...)` function) is checked to be the LSP26 Follower Registry. Only known limitiation is a user can block its potential new followers from receiving a tip by triggering the unfollow handler directly on the Potato Tipper contract. |
| M5  | Assembly Memory Read Overflow in Settings Parser                   | ✅ Fixed (but was ❌ False positive) | Fixed with the fix implemented for H1. However, the offset suggested in the finding seems incorrect.                                                                                                                                                                                                                                                                                                                                         |
| M6  | Cascading Failure Through Immutable External Contract Dependencies | ☑️ Acknowledged                      | LSP26 and the Potato token contract are not upgradable and cannot be changed. If these contracts have bugs or stop functioning, users can disconnect the `PotatoTipper` contract from their Universal Profile, remove the settings and remove the allowance of the PotatoTipper contract by interacting with the Potato token contract.                                                                                                      |
| L1  | Zero Tip Amount Not Validated                                      | ✅ Fixed                             | Fixed in commit `92325a0`.                                                                                                                                                                                                                                                                                                                                                                                                                   |
| W1  | Missing bounds checking in PotatoLib assembly memory access        | ✅ Fixed                             | Fixed with the fix implemented for H1 and commit `14e88b7` that refactored the codebase with the new free functions in `PotatoTipperSettingsLib.sol`.                                                                                                                                                                                                                                                                                        |

## Known issues

Since the `PotatoTipper` contract relies on follow and unfollow notifications activities to attempt to track existing followers (so that they are not eligible for a tip), this is not a 100% reliable mechanism on-chain. It can lead to some odd behaviours in the contract logic, including the ability for a user that connected the `PotatoTipper` contract to their Universal Profile to perform the following:

**1. Tipping Existing Followers Directly**

A user could send a tip directly to any existing follower, by calling from their UP the `universalReceiverDelegate` function on the `PotatoTipper` contract, passing as arguments:

- `sender`: the LSP26 Follower Registry address
- `data`: an existing follower address
- `typeId` the LSP26 Follow notification type ID

**Impact:** Low. This is a _"self-harm"_ behaviour. The user would simply waste their own $POTATO tokens by tipping followers who were already following before it started to use the Potato Tipper. If the user wants to reward existing followers, a simple LSP7 `transferBatch` on the $POTATO token contract would achieve the same and would cost less gas for the user.

**2. Pre-emptively Blocking Future Followers**

A user could prevent any potential new follower from receiving a future, by calling directly from their UP the `universalReceiverDelegate` function on the `PotatoTipper` contract, passing as arguments:

- `sender`: the LSP26 Follower Registry address
- `data`: an address of another user that does not actually follow
- `typeId`: the LSP26 Unfollow notification type ID

**Impact**: Medium. This allows a user to block specific addresses from receiving a future tip. This is considered as acceptable for meme-coin powered on-chain experiment and an MVP contract. Users abusing this feature can be called out by the community at this stage. A future version of the contract may add better safeguards to make the contract more neutral and prevent this behaviour.

# Slither outputs - `PotatoTipper.sol`

```
INFO:Detectors:
Reentrancy in PotatoTipper.\_transferTip(address,uint256) (src/PotatoTipper.sol#257-277):
      External calls:
      - \_POTATO_TOKEN.transfer({from:msg.sender,to:follower,amount:tipAmount,force:false,data:Thanks for following! Tipping you some 🥔}) (src/PotatoTipper.sol#260-276)
      State variables written after the call(s):
      - \_tipped[msg.sender][follower] = false (src/PotatoTipper.sol#272)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#reentrancy-vulnerabilities-2
INFO:Detectors:
Reentrancy in PotatoTipper.\_transferTip(address,uint256) (src/PotatoTipper.sol#257-277):
      External calls:
      - \_POTATO_TOKEN.transfer({from:msg.sender,to:follower,amount:tipAmount,force:false,data:Thanks for following! Tipping you some 🥔}) (src/PotatoTipper.sol#260-276)
      Event emitted after the call(s):
      - PotatoTipFailed({from:msg.sender,to:follower,amount:tipAmount,errorData:errorData}) (src/PotatoTipper.sol#274)
      - PotatoTipSent({from:msg.sender,to:follower,amount:tipAmount}) (src/PotatoTipper.sol#267)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#reentrancy-vulnerabilities-3
```

Summary

- [reentrancy-benign](#reentrancy-benign) (1 results) (Low)
- [reentrancy-events](#reentrancy-events) (1 results) (Low)

## reentrancy-benign

Impact: Low
Confidence: Medium

- [ ] ID-0
      Reentrancy in [PotatoTipper.\_transferTip(address,uint256)](./auditssrc/PotatoTipper.sol#L257-L277):
      External calls: - [\_POTATO_TOKEN.transfer({from:msg.sender,to:follower,amount:tipAmount,force:false,data:Thanks for following! Tipping you some 🥔})](./auditssrc/PotatoTipper.sol#L260-L276)
      State variables written after the call(s): - [\_tipped[msg.sender][follower] = false](./auditssrc/PotatoTipper.sol#L272)

./src/PotatoTipper.sol#L257-L277

## reentrancy-events

Impact: Low
Confidence: Medium

- [ ] ID-1
      Reentrancy in [PotatoTipper.\_transferTip(address,uint256)](./auditssrc/PotatoTipper.sol#L257-L277):
      External calls: - [\_POTATO_TOKEN.transfer({from:msg.sender,to:follower,amount:tipAmount,force:false,data:Thanks for following! Tipping you some 🥔})](./auditssrc/PotatoTipper.sol#L260-L276)
      Event emitted after the call(s): - [PotatoTipFailed({from:msg.sender,to:follower,amount:tipAmount,errorData:errorData})](./auditssrc/PotatoTipper.sol#L274) - [PotatoTipSent({from:msg.sender,to:follower,amount:tipAmount})](./auditssrc/PotatoTipper.sol#L267)

./src/PotatoTipper.sol#L257-L277

INFO:Slither:src/PotatoTipper.sol analyzed (10 contracts with 100 detectors), 2 result(s) found

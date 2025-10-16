# Security

## Slither output

```
'forge config --json' running
'/Users/jeancavallera/.solc-select/artifacts/solc-0.8.30/solc-0.8.30 --version' running
'/Users/jeancavallera/.solc-select/artifacts/solc-0.8.30/solc-0.8.30 @account-abstraction/=node_modules/@account-abstraction/ @erc725/=node_modules/@erc725/ @lukso/=node_modules/@lukso/ @openzeppelin/=node_modules/@openzeppelin/ forge-std/=lib/forge-std/src/ solidity-bytes-utils/=node_modules/solidity-bytes-utils/ ./src/PotatoTipper.sol --combined-json abi,ast,bin,bin-runtime,srcmap,srcmap-runtime,userdoc,devdoc,hashes --optimize --optimize-runs 1000000 --evm-version cancun --allow-paths .,/Users/jeancavallera/Repositories/Personal-Projects/potato-tipper-contract/src' running
INFO:Detectors:
Reentrancy in PotatoTipper._sendTip(address) (src/PotatoTipper.sol#258-299):
        External calls:
        - _POTATO_TOKEN.transfer({from:msg.sender,to:follower,amount:tipAmount,force:false,data:Thanks for following! Tipping you some 🥔}) (src/PotatoTipper.sol#280-298)
        Event emitted after the call(s):
        - TipFailed({from:msg.sender,to:follower,amount:tipAmount,errorData:errorData}) (src/PotatoTipper.sol#296)
        - TipSent({from:msg.sender,to:follower,amount:tipAmount}) (src/PotatoTipper.sol#292)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#reentrancy-vulnerabilities-3
INFO:Slither:./src/PotatoTipper.sol analyzed (13 contracts with 100 detectors), 1 result(s) found
```

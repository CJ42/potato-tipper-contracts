// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {LSP2Utils} from "@lukso/lsp2-contracts/contracts/LSP2Utils.sol";

import {IERC725Y} from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";

// Example:
// "0x00": [
//      "0x00Aa9761286f21437c90AD2f895ef0dcA3484306",
//      "0x0000d4659E5B1Da00C48b9D15Cf2aABA5A0f7Ece",
//      "0x00789c25A764E9CD24DCF86Ff27D3914C6dC361A",
//      "0x00ea048430d79fe31daae5CA411b567C50C0Aa75"
// ]
struct BucketEntry {
    address[] followersWithPrefix;
}

// PotatoTipper:InitialFollowersBucket:0x00> -> [...]
// PotatoTipper:InitialFollowersBucket:0x02> -> [...]
// etc...

// {
//   "name": "PotatoTipper:InitialFollowersBucket:<bytes1>",
//   "key": "0x...",
//   "keyType": "MappingWithGrouping",
//   "valueType": "bytes",
//   "valueContent": "Bytes"
// }
bytes10 constant POTATO_TIPPER_EXISTING_FOLLOWERS_BUCKET_DATA_KEY_PREFIX = 0xd1d57abed02d4d85dbea;

contract EncodeScript is Script {
    using stdJson for string;
    using LSP2Utils for bytes10;

    function run() external view {
        string memory inputDir = string.concat(vm.projectRoot(), "/script/data/");
        string memory file = "followers.json";
        string memory json = vm.readFile(string.concat(inputDir, file));

        uint256 bucketsCount;

        bytes[256] memory bucket;

        for (uint256 ii; ii <= type(uint8).max; ii++) {
            address[] memory followersWithPrefix = _extractAddressesAt(json, uint8(ii));

            if (followersWithPrefix.length == 0) {
                // console.log("No addresses at Prefix:", Strings.toHexString(ii));
                continue;
            }

            bucketsCount++;

            bytes memory packedAddresses = _abiEncodedToPacked(followersWithPrefix);
            bucket[uint8(ii)] = packedAddresses;

            // console.log("Bucket at Prefix:", Strings.toHexString(ii));
            // console.logBytes(bucket[uint8(ii)]);
        }

        bytes32[] memory dataKeys = new bytes32[](bucketsCount);
        bytes[] memory dataValues = new bytes[](bucketsCount);

        uint256 emptyBucketsCount;

        for (uint256 ii; ii <= type(uint8).max; ii++) {
            if (bucket[ii].length == 0) {
                emptyBucketsCount++;
                continue;
            }

            uint256 index = ii - emptyBucketsCount;

            bytes32 bucketDataKey = POTATO_TIPPER_EXISTING_FOLLOWERS_BUCKET_DATA_KEY_PREFIX
                .generateMappingWithGroupingKey(bytes20(uint160(ii)));

            dataKeys[index] = bucketDataKey;
            dataValues[index] = bucket[ii];

            console.log("Bucket at Prefix:", Strings.toHexString(ii));
            console.log("Data Key:", Strings.toHexString(uint256(dataKeys[index])));
            console.logBytes(bucket[uint8(ii)]);
        }

        bytes memory setDataBatchCalldata = abi.encodeCall(IERC725Y.setDataBatch, (dataKeys, dataValues));

        // console.log("setDataBatch calldata:");
        // console.logBytes(setDataBatchCalldata);

        // console.logBytes(packedAddresses);
        // console.log("data0x00", data0x00);
        // console.log("Content:", content);

        // console.log();

        // bytes memory addressesBucketData00 = vm.parseJson(content,
        // Strings.toHexString(uint8(bytes1(0x00))));
    }

    function _extractAddressesAt(string memory json, uint8 prefix) internal pure returns (address[] memory) {
        bytes memory data = json.parseRaw(string.concat(".", Strings.toHexString(prefix)));
        address[] memory followersWithPrefix = abi.decode(data, (address[]));
        return followersWithPrefix;
    }

    function _abiEncodedToPacked(address[] memory addresses) internal pure returns (bytes memory) {
        bytes memory packedAddresses;
        for (uint256 jj; jj < addresses.length; jj++) {
            packedAddresses = abi.encodePacked(packedAddresses, addresses[jj]);
        }
        return packedAddresses;
    }
}

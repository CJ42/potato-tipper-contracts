// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
 
import {Script, console} from "forge-std/Script.sol";
import {PotatoTipper} from "../src/PotatoTipper.sol";
 
contract Deploy is Script {
    PotatoTipper public potatoTipper;
 
    function setUp() public {}
 
    function run() public {
        vm.startBroadcast();
        potatoTipper = new PotatoTipper();
        vm.stopBroadcast();
    }
}
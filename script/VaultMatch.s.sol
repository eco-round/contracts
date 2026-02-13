// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {VaultMatch} from "../src/VaultMatch.sol";

contract VaultMatchScript is Script {
    VaultMatch public vaultMatch;

    function setUp() public {}

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        vaultMatch = new VaultMatch();

        vm.stopBroadcast();
    }
}

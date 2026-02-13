// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {FactoryMatch} from "../src/FactoryMatch.sol";

contract DeployFactory is Script {
    function run() public returns (address){
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address oracle = vm.envAddress("ORACLE_ADDRESS");

        vm.startBroadcast(privateKey);

        FactoryMatch factory = new FactoryMatch(owner, oracle);

        vm.stopBroadcast();

        return address(factory);
    }
}

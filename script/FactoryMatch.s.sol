// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {FactoryMatch} from "../src/FactoryMatch.sol";

contract DeployFactory is Script {
    function run() public returns (address){
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address owner = address(0x6b732552C0E06F69312D7E81969E28179E228C20);
        address oracle = address(0xc82f469Aa95a2f7792300c8d11230e9023A98600);

        vm.startBroadcast(privateKey);

        FactoryMatch factory = new FactoryMatch(owner, oracle);

        vm.stopBroadcast();

        return address(factory);
    }
}

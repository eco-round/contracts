// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {VaultMatch} from "../src/VaultMatch.sol";

/// @notice Used for verifying a deployed VaultMatch contract on the explorer
contract VaultMatchScript is Script {
    function run() public returns (address) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address owner = address(0x6b732552C0E06F69312D7E81969E28179E228C20);
        address oracle = address(0xc82f469Aa95a2f7792300c8d11230e9023A98600);
        uint256 matchId = 1;
        string memory teamA = "Team A";
        string memory teamB = "Team B";

        vm.startBroadcast(privateKey);

        VaultMatch vault = new VaultMatch(owner, oracle, matchId, teamA, teamB);

        vm.stopBroadcast();

        return address(vault);
    }
}

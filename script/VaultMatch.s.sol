// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {VaultMatch} from "../src/VaultMatch.sol";

/// @notice Used for verifying a deployed VaultMatch contract on the explorer
contract VaultMatchScript is Script {
    function run() public returns (address) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address oracle = vm.envAddress("ORACLE_ADDRESS");
        uint256 matchId = vm.envUint("MATCH_ID");
        string memory teamA = vm.envString("TEAM_A");
        string memory teamB = vm.envString("TEAM_B");

        vm.startBroadcast(privateKey);

        VaultMatch vault = new VaultMatch(owner, oracle, matchId, teamA, teamB);

        vm.stopBroadcast();

        return address(vault);
    }
}

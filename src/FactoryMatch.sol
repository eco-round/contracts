// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {VaultMatch} from "./VaultMatch.sol";

/// @title FactoryMatch
/// @notice Deploys a new VaultMatch per esports match and maintains a registry.
contract FactoryMatch is Ownable {
    uint256 public nextMatchId = 1;
    address public oracle;

    mapping(uint256 => address) public vaults;
    address[] public allVaults;

    event MatchCreated(
        uint256 indexed matchId,
        address vault,
        string teamA,
        string teamB
    );
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    constructor(address _owner, address _oracle) Ownable(_owner) {
        require(_oracle != address(0), "Invalid oracle");
        oracle = _oracle;
    }

    function createMatch(
        string calldata _teamA,
        string calldata _teamB
    ) external onlyOwner returns (uint256 matchId, address vault) {
        matchId = nextMatchId++;

        VaultMatch newVault = new VaultMatch(
            owner(),
            oracle,
            matchId,
            _teamA,
            _teamB
        );

        vault = address(newVault);
        vaults[matchId] = vault;
        allVaults.push(vault);

        emit MatchCreated(matchId, vault, _teamA, _teamB);
    }

    function setOracle(address _newOracle) external onlyOwner {
        require(_newOracle != address(0), "Invalid oracle");
        emit OracleUpdated(oracle, _newOracle);
        oracle = _newOracle;
    }

    function totalMatches() external view returns (uint256) {
        return allVaults.length;
    }

    function getVault(uint256 _matchId) external view returns (address) {
        return vaults[_matchId];
    }
}

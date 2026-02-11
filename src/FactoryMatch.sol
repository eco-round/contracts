// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {VaultMatch} from "./VaultMatch.sol";

/// @title FactoryMatch
/// @notice Deploys a new VaultMatch per esports match and maintains a registry.
contract FactoryMatch is Ownable {
    uint256 public nextMatchId = 1;
    address public oracle;
    address public depositToken;
    address public yieldProtocol;

    mapping(uint256 => address) public vaults;
    address[] public allVaults;

    event MatchCreated(uint256 indexed matchId, address vault);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    event YieldProtocolUpdated(
        address indexed oldProtocol,
        address indexed newProtocol
    );

    constructor(
        address _owner,
        address _oracle,
        address _depositToken,
        address _yieldProtocol
    ) Ownable(_owner) {
        require(_oracle != address(0), "Invalid oracle");
        require(_depositToken != address(0), "Invalid token");
        require(_yieldProtocol != address(0), "Invalid yield protocol");

        oracle = _oracle;
        depositToken = _depositToken;
        yieldProtocol = _yieldProtocol;
    }

    function createMatch()
        external
        onlyOwner
        returns (uint256 matchId, address vault)
    {
        matchId = nextMatchId++;

        VaultMatch newVault = new VaultMatch(
            owner(),
            oracle,
            matchId,
            depositToken,
            yieldProtocol
        );

        vault = address(newVault);
        vaults[matchId] = vault;
        allVaults.push(vault);

        emit MatchCreated(matchId, vault);
    }

    function setOracle(address _newOracle) external onlyOwner {
        require(_newOracle != address(0), "Invalid oracle");
        emit OracleUpdated(oracle, _newOracle);
        oracle = _newOracle;
    }

    function setYieldProtocol(address _newProtocol) external onlyOwner {
        require(_newProtocol != address(0), "Invalid protocol");
        emit YieldProtocolUpdated(yieldProtocol, _newProtocol);
        yieldProtocol = _newProtocol;
    }

    function totalMatches() external view returns (uint256) {
        return allVaults.length;
    }

    function getVault(uint256 _matchId) external view returns (address) {
        return vaults[_matchId];
    }
}

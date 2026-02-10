// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract FactoryMatch is Ownable {
    address public apiWallet;
    uint256 public matchId = 1;

    event MatchCreated(uint256 indexed matchId);
    constructor(address owner, address _apiWallet) Ownable(owner) {
        apiWallet = _apiWallet;
    }

    modifier onlyAPI() {
        require(
            msg.sender == apiWallet,
            "Only API wallet can call this function"
        );
        _;
    }

    // function setNumber(uint256 newNumber) public {
    //     number = newNumber;
    // }

    // function increment() public {
    //     number++;
    // }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract VaultMatch is Ownable {
    address public apiWallet;
    uint public matchId;
    uint public BalanceTeamA;
    uint public BalanceTeamB;
    uint public TotalBalance;
    uint public TotalEarning;
    bool public finalized;
    bool public started;
    bool public winnerTeamA;
    bool public winnerTeamB;

    event MatchStarted(uint indexed matchId);
    event MatchFinalized(uint indexed matchId, bool winnerTeamA, bool winnerTeamB);

    event DepositTeamA(address indexed user, uint amount);
    event DepositTeamB(address indexed user, uint amount);

    constructor(uint _matchId, address _owner, address _apiAddress)Ownable(_owner){
        matchId = _matchId;
        apiWallet = _apiAddress;
    }

    modifier onlyAPI() {
        require(
            msg.sender == apiWallet,
            "Only API wallet can call this function"
        );
        _;
    }

    function depositTeamA() public payable {
        require(!started,"Match Already started");
        require(!finalized, "Match Already finalized");
        BalanceTeamA += msg.value;
        TotalBalance += msg.value;
        emit DepositTeamA(msg.sender, msg.value);
    }

    function depositTeamB() public payable {
        require(!started,"Match Already started");
        require(!finalized, "Match Already finalized");
        BalanceTeamB += msg.value;
        TotalBalance += msg.value;
        emit DepositTeamB(msg.sender, msg.value);
    }

    function startMatch() public onlyOwner {
        require(!started, "Match Already started");
        started = true;
        emit MatchStarted(matchId);
    }

    function 
}

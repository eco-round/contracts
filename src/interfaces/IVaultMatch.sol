// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVaultMatch {
    enum MatchStatus {
        Open,
        Locked,
        Resolved
    }

    enum Team {
        None,
        TeamA,
        TeamB
    }

    // ─── Events ──────────────────────────────────────────────────────────

    event Deposited(address indexed user, Team team, uint256 amount);
    event MatchLocked(uint256 indexed matchId);
    event MatchResolved(uint256 indexed matchId, Team winner);
    event Claimed(address indexed user, uint256 principal, uint256 yieldShare);
    event EmergencyRefund(address indexed user, uint256 amount);
    event EmergencyYieldWithdrawn(uint256 amount);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    // ─── Errors ──────────────────────────────────────────────────────────

    error InvalidTeam();
    error ZeroAmount();
    error MatchNotOpen();
    error MatchNotLocked();
    error MatchNotResolved();
    error AlreadyClaimed();
    error NothingToClaim();
    error OnlyOracle();
    error InvalidWinner();
    error AlreadyResolved();
    error NoWinnerDeposits();
}

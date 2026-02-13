// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IVaultMatch} from "./interfaces/IVaultMatch.sol";

/// @title VaultMatch
/// @notice No-Loss Prediction Vault for EcoRound on Base Mainnet.
/// @dev Uses real USDC + Morpho ERC4626 Vault. Lifecycle: Open -> Locked -> Resolved -> Claim
contract VaultMatch is IVaultMatch, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ── Hardcoded Base Mainnet Addresses ─────────────────────────────────
    IERC20 public constant USDC =
        IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    IERC4626 public constant MORPHO_VAULT =
        IERC4626(0x050cE30b927Da55177A4914EC73480238BAD56f0);

    // ── Immutables ───────────────────────────────────────────────────────
    uint256 public immutable MATCH_ID;
    string public teamAName;
    string public teamBName;

    // ── State ────────────────────────────────────────────────────────────
    address public oracle;
    MatchStatus public status;
    Team public winner;

    uint256 public totalTeamA;
    uint256 public totalTeamB;
    uint256 public totalYield;

    mapping(address => mapping(Team => uint256)) public userDeposits;
    mapping(address => bool) public hasClaimed;

    constructor(
        address _owner,
        address _oracle,
        uint256 _matchId,
        string memory _teamA,
        string memory _teamB
    ) Ownable(_owner) {
        require(_oracle != address(0), "Invalid oracle");

        oracle = _oracle;
        MATCH_ID = _matchId;
        teamAName = _teamA;
        teamBName = _teamB;
        status = MatchStatus.Open;

        // Gas optimization: infinite approval to Morpho Vault once
        USDC.forceApprove(address(MORPHO_VAULT), type(uint256).max);
    }

    modifier onlyOracle() {
        if (msg.sender != oracle) revert OnlyOracle();
        _;
    }

    // ── User Actions ─────────────────────────────────────────────────────

    function deposit(
        Team team,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        if (status != MatchStatus.Open) revert MatchNotOpen();
        if (team != Team.TeamA && team != Team.TeamB) revert InvalidTeam();
        if (amount == 0) revert ZeroAmount();

        USDC.safeTransferFrom(msg.sender, address(this), amount);
        userDeposits[msg.sender][team] += amount;

        if (team == Team.TeamA) {
            totalTeamA += amount;
        } else {
            totalTeamB += amount;
        }

        emit Deposited(msg.sender, team, amount);
    }

    function claim() external nonReentrant whenNotPaused {
        if (status != MatchStatus.Resolved) revert MatchNotResolved();
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();

        (uint256 principal, uint256 yieldShare) = _calculatePayout(msg.sender);
        if (principal == 0) revert NothingToClaim();

        hasClaimed[msg.sender] = true;

        // Cap payout to actual balance to absorb ERC4626 rounding dust (typically 1 wei)
        uint256 payout = principal + yieldShare;
        uint256 available = USDC.balanceOf(address(this));
        if (payout > available) payout = available;

        USDC.safeTransfer(msg.sender, payout);

        emit Claimed(msg.sender, principal, yieldShare);
    }

    // ── Oracle Actions ───────────────────────────────────────────────────

    function lockMatch() external onlyOracle whenNotPaused {
        if (status != MatchStatus.Open) revert MatchNotOpen();
        status = MatchStatus.Locked;
        _depositToYield();
        emit MatchLocked(MATCH_ID);
    }

    function resolveMatch(Team _winner) external onlyOracle whenNotPaused {
        if (status != MatchStatus.Locked) revert MatchNotLocked();
        if (_winner != Team.TeamA && _winner != Team.TeamB)
            revert InvalidWinner();

        uint256 totalWinSide = (_winner == Team.TeamA)
            ? totalTeamA
            : totalTeamB;
        if (totalWinSide == 0) revert NoWinnerDeposits();

        status = MatchStatus.Resolved;
        winner = _winner;
        _withdrawFromYield();

        emit MatchResolved(MATCH_ID, _winner);
    }

    // ── Admin / Safety Module ────────────────────────────────────────────

    function setOracle(address _newOracle) external onlyOwner {
        require(_newOracle != address(0), "Invalid oracle");
        emit OracleUpdated(oracle, _newOracle);
        oracle = _newOracle;
    }

    function pause() external onlyOwner {
        _pause();
    }
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Emergency: withdraw all funds from Morpho back to this vault.
    function emergencyWithdrawFromYield() external onlyOwner whenPaused {
        uint256 shares = MORPHO_VAULT.balanceOf(address(this));
        if (shares > 0) {
            uint256 withdrawn = MORPHO_VAULT.redeem(
                shares,
                address(this),
                address(this)
            );
            emit EmergencyYieldWithdrawn(withdrawn);
        }
    }

    /// @notice Emergency: refund a specific user their full deposit.
    function emergencyRefund(
        address user
    ) external onlyOwner whenPaused nonReentrant {
        require(!hasClaimed[user], "Already claimed");

        uint256 refund = _getUserTotal(user);
        require(refund > 0, "Nothing to refund");

        hasClaimed[user] = true;
        userDeposits[user][Team.TeamA] = 0;
        userDeposits[user][Team.TeamB] = 0;

        // Cap to actual balance to absorb ERC4626 rounding dust
        uint256 available = USDC.balanceOf(address(this));
        if (refund > available) refund = available;

        USDC.safeTransfer(user, refund);
        emit EmergencyRefund(user, refund);
    }

    // ── View Helpers ─────────────────────────────────────────────────────

    function getUserTotalDeposit(address user) external view returns (uint256) {
        return _getUserTotal(user);
    }

    function getTotalDeposits() external view returns (uint256) {
        return totalTeamA + totalTeamB;
    }

    function getYieldBalance() external view returns (uint256) {
        return
            MORPHO_VAULT.convertToAssets(MORPHO_VAULT.balanceOf(address(this)));
    }

    function getExpectedPayout(address user) external view returns (uint256) {
        if (status != MatchStatus.Resolved || hasClaimed[user]) return 0;
        (uint256 principal, uint256 yieldShare) = _calculatePayout(user);
        return principal + yieldShare;
    }

    // ── Internal Helpers ─────────────────────────────────────────────────

    function _getUserTotal(address user) internal view returns (uint256) {
        return userDeposits[user][Team.TeamA] + userDeposits[user][Team.TeamB];
    }

    function _calculatePayout(
        address user
    ) internal view returns (uint256 principal, uint256 yieldShare) {
        uint256 winDeposit = userDeposits[user][winner];
        Team losingTeam = (winner == Team.TeamA) ? Team.TeamB : Team.TeamA;
        uint256 loseDeposit = userDeposits[user][losingTeam];

        principal = winDeposit + loseDeposit;

        if (winDeposit > 0 && totalYield > 0) {
            uint256 totalWinSide = (winner == Team.TeamA)
                ? totalTeamA
                : totalTeamB;
            if (totalWinSide > 0) {
                yieldShare = (totalYield * winDeposit) / totalWinSide;
            }
        }
    }

    /// @dev ERC4626: deposit(assets, receiver) returns shares
    function _depositToYield() internal {
        uint256 total = totalTeamA + totalTeamB;
        if (total > 0) {
            MORPHO_VAULT.deposit(total, address(this));
        }
    }

    /// @dev ERC4626: redeem all shares back to USDC
    function _withdrawFromYield() internal {
        uint256 shares = MORPHO_VAULT.balanceOf(address(this));
        if (shares > 0) {
            uint256 totalDeposits = totalTeamA + totalTeamB;
            uint256 totalWithdrawn = MORPHO_VAULT.redeem(
                shares,
                address(this),
                address(this)
            );
            totalYield = totalWithdrawn > totalDeposits
                ? totalWithdrawn - totalDeposits
                : 0;
        }
    }
}

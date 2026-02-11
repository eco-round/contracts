// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IYieldProtocol} from "./interfaces/IYieldProtocol.sol";
import {IVaultMatch} from "./interfaces/IVaultMatch.sol";

/// @title VaultMatch
/// @notice No-Loss Prediction Vault. Lifecycle: Open → Locked → Resolved → Claim
contract VaultMatch is IVaultMatch, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable DEPOSIT_TOKEN;
    IYieldProtocol public immutable YIELD_PROTOCOL;
    uint256 public immutable MATCH_ID;

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
        address _depositToken,
        address _yieldProtocol
    ) Ownable(_owner) {
        require(_oracle != address(0), "Invalid oracle");
        require(_depositToken != address(0), "Invalid token");
        require(_yieldProtocol != address(0), "Invalid yield protocol");

        oracle = _oracle;
        MATCH_ID = _matchId;
        DEPOSIT_TOKEN = IERC20(_depositToken);
        YIELD_PROTOCOL = IYieldProtocol(_yieldProtocol);
        status = MatchStatus.Open;
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

        DEPOSIT_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
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
        DEPOSIT_TOKEN.safeTransfer(msg.sender, principal + yieldShare);

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

    function emergencyRefund(
        address user
    ) external onlyOwner whenPaused nonReentrant {
        require(!hasClaimed[user], "Already claimed");

        uint256 refund = _getUserTotal(user);
        require(refund > 0, "Nothing to refund");

        hasClaimed[user] = true;
        userDeposits[user][Team.TeamA] = 0;
        userDeposits[user][Team.TeamB] = 0;

        DEPOSIT_TOKEN.safeTransfer(user, refund);
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
        return YIELD_PROTOCOL.getBalance(address(DEPOSIT_TOKEN));
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
            yieldShare = (totalYield * winDeposit) / totalWinSide;
        }
    }

    function _depositToYield() internal {
        uint256 total = totalTeamA + totalTeamB;
        if (total > 0) {
            DEPOSIT_TOKEN.safeIncreaseAllowance(address(YIELD_PROTOCOL), total);
            YIELD_PROTOCOL.deposit(address(DEPOSIT_TOKEN), total);
        }
    }

    function _withdrawFromYield() internal {
        uint256 totalDeposits = totalTeamA + totalTeamB;
        if (totalDeposits > 0) {
            uint256 totalWithdrawn = YIELD_PROTOCOL.withdrawAll(
                address(DEPOSIT_TOKEN)
            );
            totalYield = totalWithdrawn > totalDeposits
                ? totalWithdrawn - totalDeposits
                : 0;
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldProtocol} from "../interfaces/IYieldProtocol.sol";

/// @title MockYieldProtocol
/// @notice Simulates a lending protocol (Bonzo Finance / Aave) for testing.
///         Admin can set a yield percentage to simulate interest accrual.
/// @dev In production, replace this with a real adapter for Bonzo/Aave on Hedera.
contract MockYieldProtocol is IYieldProtocol {
    using SafeERC20 for IERC20;

    /// @notice Yield rate in basis points (e.g., 500 = 5%)
    uint256 public yieldBps;

    /// @notice Tracks deposited principal per asset per depositor
    mapping(address => mapping(address => uint256)) public deposits;

    /// @notice Admin who can configure yield
    address public admin;

    constructor(uint256 _yieldBps) {
        admin = msg.sender;
        yieldBps = _yieldBps;
    }

    /// @notice Set the simulated yield rate (basis points)
    function setYieldBps(uint256 _yieldBps) external {
        require(msg.sender == admin, "Only admin");
        yieldBps = _yieldBps;
    }

    /// @inheritdoc IYieldProtocol
    function deposit(address asset, uint256 amount) external override {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        deposits[asset][msg.sender] += amount;
    }

    /// @inheritdoc IYieldProtocol
    function withdrawAll(
        address asset
    ) external override returns (uint256 totalWithdrawn) {
        uint256 principal = deposits[asset][msg.sender];
        require(principal > 0, "No deposits");

        // Simulate yield: principal + (principal × yieldBps / 10000)
        uint256 yield_ = (principal * yieldBps) / 10_000;
        totalWithdrawn = principal + yield_;

        deposits[asset][msg.sender] = 0;

        // Transfer principal + simulated yield back
        // NOTE: The mock must hold enough tokens. Mint extra to this contract for yield.
        IERC20(asset).safeTransfer(msg.sender, totalWithdrawn);
    }

    /// @inheritdoc IYieldProtocol
    function getBalance(
        address asset
    ) external view override returns (uint256) {
        uint256 principal = deposits[asset][msg.sender];
        uint256 yield_ = (principal * yieldBps) / 10_000;
        return principal + yield_;
    }
}

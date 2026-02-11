// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IYieldProtocol
/// @notice Abstraction layer for lending protocols (Bonzo Finance, Aave, etc.)
/// @dev Implement this interface for each lending protocol integration.
///      For hackathon: use MockYieldProtocol which simulates yield accrual.
interface IYieldProtocol {
    /// @notice Deposit assets into the lending protocol to begin accruing yield
    /// @param asset The ERC20 token address to deposit
    /// @param amount The amount to deposit
    function deposit(address asset, uint256 amount) external;

    /// @notice Withdraw all assets + accrued yield from the lending protocol
    /// @param asset The ERC20 token address to withdraw
    /// @return totalWithdrawn The total amount withdrawn (principal + yield)
    function withdrawAll(
        address asset
    ) external returns (uint256 totalWithdrawn);

    /// @notice View the current balance (principal + accrued yield) in the protocol
    /// @param asset The ERC20 token address to check
    /// @return balance The current total balance
    function getBalance(address asset) external view returns (uint256 balance);
}

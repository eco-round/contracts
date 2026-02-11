// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title USDCMock
/// @notice Mock USDC token with 6 decimals (matching real USDC) and public mint.
contract USDCMock is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    /// @notice Override decimals to match real USDC (6 decimals)
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Public mint for testing — anyone can mint tokens
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

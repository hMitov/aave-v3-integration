// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MockERC20} from "./MockERC20.sol";

/// @title MockAToken
/// @notice Minimal mock of an Aave aToken with scaled balances and liquidity index.
contract MockAToken is MockERC20 {
    mapping(address => uint256) private _scaledBalances;

    /// @notice Liquidity index in RAY (1e27).
    uint256 public liquidityIndex = 1e27;

    constructor() MockERC20("Mock aToken", "maToken") {}

    /// @notice Set caller's scaled balance.
    function setScaledBalance(uint256 _scaledBalance) external {
        _scaledBalances[msg.sender] = _scaledBalance;
    }

    /// @notice Set scaled balance for a user.
    function setScaledBalanceFor(address user, uint256 _scaledBalance) external {
        _scaledBalances[user] = _scaledBalance;
    }

    /// @notice Update liquidity index.
    function setLiquidityIndex(uint256 _index) external {
        liquidityIndex = _index;
    }

    /// @notice Get the balance of a user.
    /// @dev Returns `scaled * liquidityIndex / 1e27`.
    function balanceOf(address user) public view override returns (uint256) {
        return (_scaledBalances[user] * liquidityIndex) / 1e27;
    }

    /// @notice Get scaled balance of a user.
    function scaledBalanceOf(address user) external view returns (uint256) {
        return _scaledBalances[user];
    }

    /// @notice Get caller's scaled balance.
    function getCurrentScaledBalance() external view returns (uint256) {
        return _scaledBalances[msg.sender];
    }
}

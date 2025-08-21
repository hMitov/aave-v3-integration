// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MockERC20} from "./MockERC20.sol";

/// @title MockVariableDebtToken
/// @notice Minimal mock of Aave's variable debt token with scaled balances and borrow index.
contract MockVariableDebtToken is MockERC20 {
    /// @notice Scaled (index-independent) debt shares per user.
    mapping(address => uint256) private _scaledBalances;

    /// @notice Variable borrow index in RAY (1e27).
    uint256 public variableBorrowIndex = 1e27;

    constructor() MockERC20("Mock Variable Debt", "mVDebt") {}

    /// @notice Set caller's scaled debt.
    /// @param _scaledBalance Scaled shares to assign.
    function setScaledBalance(uint256 _scaledBalance) external {
        _scaledBalances[msg.sender] = _scaledBalance;
    }

    /// @notice Set scaled debt for a user.
    /// @param user Account to set.
    /// @param _scaledBalance Scaled shares to assign.
    function setScaledBalanceFor(address user, uint256 _scaledBalance) external {
        _scaledBalances[user] = _scaledBalance;
    }

    /// @notice Update the borrow index (alias of {setDebtIndex}).
    /// @param _index New index in RAY (1e27).
    function setVariableBorrowIndex(uint256 _index) external {
        variableBorrowIndex = _index;
    }

    /// @notice Update the borrow index.
    /// @param _index New index in RAY (1e27).
    function setDebtIndex(uint256 _index) external {
        variableBorrowIndex = _index;
    }

    /// @notice Get the balance of a user.
    /// @dev Returns `scaled * variableBorrowIndex / 1e27`.
    function balanceOf(address user) public view override returns (uint256) {
        return (_scaledBalances[user] * variableBorrowIndex) / 1e27;
    }

    /// @notice Get scaled debt (shares) of a user.
    /// @param user Account to query.
    /// @return Scaled debt without index accrual.
    function scaledBalanceOf(address user) external view returns (uint256) {
        return _scaledBalances[user];
    }
}

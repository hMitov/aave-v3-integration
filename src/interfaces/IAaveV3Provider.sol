// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title IAaveV3Provider
/// @notice Interface for a pooled Aave V3 provider using scaled shares for supply/borrow.
interface IAaveV3Provider {
    /// @notice Asset support toggled.
    event AssetSupportUpdated(address indexed asset, bool supported);
    /// @notice User deposited.
    event Deposit(address indexed user, address indexed asset, uint256 amount, uint256 scaledDelta);
    /// @notice User withdrew.
    event Withdraw(address indexed user, address indexed asset, uint256 amount, uint256 scaledDelta);
    /// @notice User borrowed.
    event Borrow(address indexed user, address indexed asset, uint256 amount, uint256 scaledDelta);
    /// @notice User repaid.
    event Repay(address indexed user, address indexed asset, uint256 amount, uint256 scaledDelta);

    error CallerIsNotAdmin();
    error CallerIsNotPauser();
    error ZeroAddressNotAllowed();
    error AssetNotSupported();
    error AmountZero();
    error UserScaledIsZero();
    error NoDebt();
    error AmountExceedsMaxWithdrawable();
    error AmountExceedsMaxRepayable();
    error ATokenAddressZero();
    error DebtTokenAddressZero();
    error ContractHealthFactorBelowOne();
    error ExceedsAvailableBorrow();
    error PostHealthFactorBelowOne();

    /// @return True if `asset` is supported.
    function isSupportedAsset(address asset) external view returns (bool);

    /// @notice Enable/disable an asset.
    function setAssetSupported(address asset, bool supported) external;

    /// @notice Deposit underlying and mint scaled supply shares.
    function deposit(address asset, uint256 amount) external;

    /// @notice Withdraw underlying, burning scaled shares.
    function withdraw(address asset, uint256 amount) external returns (uint256 actualAmount);

    /// @notice Withdraw all supply for an asset.
    function withdrawAll(address asset) external returns (uint256 actualAmount);

    /// @notice Borrow underlying, minting scaled debt shares.
    function borrow(address asset, uint256 amount) external;

    /// @notice Repay debt, burning scaled shares.
    function repay(address asset, uint256 amount) external returns (uint256 actualRepaid);

    /// @notice Repay all debt for an asset.
    function repayAll(address asset) external returns (uint256 actualRepaid);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockAToken} from "./MockAToken.sol";
import {MockVariableDebtToken} from "./MockVariableDebtToken.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {MockAddressesProvider} from "./MockAddressesProvider.sol";

/// @title MockPool
/// @notice Minimal Aave-like pool mock for tests (supply/withdraw/borrow/repay + reserve data).
/// @dev Scaled math is simplified for testing; not production-accurate.
contract MockPool {
    /// @notice Underlying asset => aToken.
    mapping(address => address) public aTokens;
    /// @notice Underlying asset => variable debt token.
    mapping(address => address) public variableDebtTokens;

    /// @notice Addresses provider (returns this as oracle in tests).
    MockAddressesProvider public addressesProvider;

    // Mock state variables for testing
    uint256 public mockHealthFactor = 2e18; // Default: 2.0
    uint256 public mockAvailableBorrows = 1000e8; // Default: 1000 base units
    uint256 public mockPostBorrowHealthFactor = 1.5e18; // Default: 1.5

    /// @notice Deploys the mock and sets a simple addresses provider.
    constructor() {
        // Create a mock addresses provider with a mock price oracle
        addressesProvider = new MockAddressesProvider(address(this));
    }

    /// @notice Aave-style provider getter.
    /// @return Address of the provider.
    function ADDRESSES_PROVIDER() external view returns (address) {
        return address(addressesProvider);
    }

    /// @notice Set reserve token addresses for an asset.
    /// @param asset Underlying asset.
    /// @param aToken aToken address.
    /// @param variableDebtToken Variable debt token address.
    function setReserveData(address asset, address aToken, address variableDebtToken) external {
        aTokens[asset] = aToken;
        variableDebtTokens[asset] = variableDebtToken;
    }

    /// @notice No-op helper to hint balance provisioning in tests.
    function setTokenBalance(address, /*asset*/ uint256 /*balance*/ ) external {
        // Intentionally empty in this mock.
    }

    /// @notice Set aToken for an asset.
    function setAToken(address asset, address aToken) external {
        aTokens[asset] = aToken;
    }

    /// @notice Set variable debt token for an asset.
    function setVariableDebtToken(address asset, address variableDebtToken) external {
        variableDebtTokens[asset] = variableDebtToken;
    }

    /// @notice Get aToken for an asset.
    function getAToken(address asset) external view returns (address) {
        return aTokens[asset];
    }

    /// @notice Get variable debt token for an asset.
    function getVariableDebtToken(address asset) external view returns (address) {
        return variableDebtTokens[asset];
    }

    /// @notice Return minimal reserve data structure.
    /// @param asset Underlying asset.
    /// @return ReserveData with addresses and basic indices.
    function getReserveData(address asset) external view returns (DataTypes.ReserveData memory) {
        return DataTypes.ReserveData({
            configuration: DataTypes.ReserveConfigurationMap(0),
            liquidityIndex: 1e27,
            currentLiquidityRate: 0,
            variableBorrowIndex: 1e27,
            currentVariableBorrowRate: 0,
            currentStableBorrowRate: 0,
            lastUpdateTimestamp: uint40(block.timestamp),
            id: 0,
            aTokenAddress: aTokens[asset],
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: variableDebtTokens[asset],
            interestRateStrategyAddress: address(0),
            accruedToTreasury: 0,
            unbacked: 0,
            isolationModeTotalDebt: 0
        });
    }

    /// @notice Simulate supplying: pull tokens and mint scaled aTokens to `onBehalfOf`.
    /// @dev Scaled minting here adds `amount` directly (not divided by index) for simplicity.
    /// @param asset Underlying asset.
    /// @param amount Amount to supply.
    /// @param onBehalfOf Recipient of aTokens.
    /// @param referralCode Unused.
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external {
        bool success = IERC20(asset).transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer failed");

        address aToken = aTokens[asset];
        if (aToken != address(0)) {
            uint256 current = MockAToken(aToken).scaledBalanceOf(onBehalfOf);
            MockAToken(aToken).setScaledBalanceFor(onBehalfOf, current + amount);
        }
    }

    /// @notice Simulate withdrawing: send tokens and burn proportional scaled aTokens from caller.
    /// @param asset Underlying asset.
    /// @param amount Amount to withdraw.
    /// @param to Recipient.
    /// @return withdrawn Amount transferred.
    function withdraw(address asset, uint256 amount, address to) external returns (uint256 withdrawn) {
        bool success = IERC20(asset).transfer(to, amount);
        require(success, "Transfer failed");

        address aToken = aTokens[asset];
        if (aToken != address(0)) {
            uint256 currentScaled = MockAToken(aToken).scaledBalanceOf(msg.sender);
            uint256 currentBal = MockAToken(aToken).balanceOf(msg.sender);
            // Burn proportionally to requested amount (mocked).
            uint256 scaledToBurn = currentBal == 0 ? 0 : (amount * currentScaled) / currentBal;
            if (scaledToBurn > currentScaled) scaledToBurn = currentScaled;
            MockAToken(aToken).setScaledBalanceFor(msg.sender, currentScaled - scaledToBurn);
        }
        return amount;
    }

    /// @notice Simulate borrowing: send tokens and mint scaled debt to `onBehalfOf`.
    /// @param asset Underlying asset.
    /// @param amount Amount to borrow.
    /// @param interestRateMode Unused.
    /// @param referralCode Unused.
    /// @param onBehalfOf Borrower to receive debt.
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
        external
    {
        bool success = IERC20(asset).transfer(onBehalfOf, amount);
        require(success, "Transfer failed");

        address debt = variableDebtTokens[asset];
        if (debt != address(0)) {
            uint256 current = MockVariableDebtToken(debt).scaledBalanceOf(onBehalfOf);
            MockVariableDebtToken(debt).setScaledBalanceFor(onBehalfOf, current + amount);
        }
    }

    /// @notice Simulate repay: pull tokens and burn scaled debt from `onBehalfOf`.
    /// @param asset Underlying asset.
    /// @param amount Amount to repay.
    /// @param interestRateMode Unused.
    /// @param onBehalfOf Debtor whose position is repaid.
    /// @return repaid Amount accepted.
    function repay(address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf)
        external
        returns (uint256 repaid)
    {
        bool success = IERC20(asset).transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer failed");

        address debt = variableDebtTokens[asset];
        if (debt != address(0)) {
            uint256 current = MockVariableDebtToken(debt).scaledBalanceOf(onBehalfOf);
            uint256 burn = amount > current ? current : amount; // 1:1 in this mock
            MockVariableDebtToken(debt).setScaledBalanceFor(onBehalfOf, current - burn);
        }
        return amount;
    }

    /// @notice Minimal user account data with safe HF>1 for tests.
    /// @return totalCollateralBase Collateral in base units.
    /// @return totalDebtBase Debt in base units.
    /// @return availableBorrowsBase Borrow power.
    /// @return currentLiquidationThreshold Liquidation threshold (bps).
    /// @return ltv LTV (bps).
    /// @return healthFactor Health factor (1e18).
    function getUserAccountData(address /*user*/ )
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        // Use mock values for testing different scenarios
        return (1000e8, 0, mockAvailableBorrows, 8250, 8000, mockHealthFactor);
    }

    /// @notice Liquidity index passthrough.
    function getReserveNormalizedIncome(address asset) external view returns (uint256) {
        return MockAToken(aTokens[asset]).liquidityIndex();
    }

    /// @notice Variable debt index passthrough.
    function getReserveNormalizedVariableDebt(address asset) external view returns (uint256) {
        return MockVariableDebtToken(variableDebtTokens[asset]).variableBorrowIndex();
    }

    /// @notice Mock price oracle function
    function getAssetPrice(address asset) external view returns (uint256) {
        // Return a simple price for testing - 1 USDC = 1 base unit
        // In a real scenario, this would be the price in base currency (e.g., USD)
        return 1e8; // 1.0 in 8 decimals
    }

    /// @notice Set health factor for testing
    function setHealthFactor(uint256 _healthFactor) external {
        mockHealthFactor = _healthFactor;
    }

    /// @notice Set available borrows for testing
    function setAvailableBorrows(uint256 _availableBorrows) external {
        mockAvailableBorrows = _availableBorrows;
    }

    /// @notice Set post-borrow health factor for testing
    function setPostBorrowHealthFactor(uint256 _postBorrowHealthFactor) external {
        mockPostBorrowHealthFactor = _postBorrowHealthFactor;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20Detailed} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {SafeERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IAToken} from "@aave/core-v3/contracts/interfaces/IAToken.sol";
import {IVariableDebtToken} from "@aave/core-v3/contracts/interfaces/IVariableDebtToken.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {IAaveOracle} from "@aave/core-v3/contracts/interfaces/IAaveOracle.sol";
import {ReserveConfiguration} from "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {IAaveV3Provider} from "./interfaces/IAaveV3Provider.sol";

/**
 * @title AaveV3Provider
 * @notice Minimal pooled integration with Aave V3 across many assets.
 * @dev This contract acts as a single Aave account with shared health factor.
 *      Users receive internal "scaled shares" for supply & borrow positions.
 *      Interest flows automatically via Aave's scaled math system.
 *
 *      WARNING: All users share the same Aave account risk. If the health factor
 *      drops below 1.0, all users' positions are at risk of liquidation.
 *
 *      Key Features:
 *      - Pooled collateral and debt management
 *      - Automatic interest accrual via Aave's rate mechanisms
 *      - Scaled balance tracking for proportional share calculation
 *      - Health factor monitoring and borrow limits
 *      - Pausable operations for emergency scenarios
 *
 * @author Your Name
 * @custom:security-contact security@yourproject.com
 */
contract AaveV3Provider is IAaveV3Provider, ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    /// @notice Role for administrative functions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role for pausing/unpausing operations
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Aave rate enum
    /// @notice Aave variable rate mode constant
    uint256 private constant _VARIABLE_RATE = 2;
    /// @notice Minimum health factor threshold (1.00 in WAD)
    uint256 private constant _MIN_HF = 1e18; // 1.00 in WAD; can set > 1e18 (e.g., 1.05e18)
    /// @notice Borrow buffer percentage (95% of available borrows)
    uint256 private constant _BORROW_BUFFER_BPS = 9_500; // 95% of available borrows
    /// @notice Basis points denominator
    uint256 private constant _BPS_DENOM = 10_000;
    /// @notice WAD constant (1e18) for precision
    uint256 private constant _WAD = 1e18;
    /// @notice RAY constant (1e27) for precision
    uint256 private constant _RAY = 1e27;

    /// @notice The Aave V3 pool contract
    IPool public immutable AAVE_V3_POOL;

    /// @notice List of listed assets
    address[] private _listedAssets;

    /// @notice Asset info
    struct AssetInfo {
        uint32 index;
        bool depositsEnabled;
        bool borrowsEnabled;
    }

    /// @notice Asset -> AssetInfo
    mapping(address => AssetInfo) private _assetInfo; // index is 1-based (0 = not listed)

    /// @notice User -> asset -> scaled supply balances
    mapping(address => mapping(address => uint256)) public userScaledSupply; // user -> asset -> scaled supply balances
    /// @notice User -> asset -> scaled borrow balances
    mapping(address => mapping(address => uint256)) public userScaledBorrow;

    /**
     * @notice Constructor for AaveV3Provider
     * @param _aavePool The address of the Aave V3 pool contract
     * @dev Sets up initial roles and validates pool address
     */
    constructor(address _aavePool) {
        if (_aavePool == address(0)) revert ZeroAddressNotAllowed();
        AAVE_V3_POOL = IPool(_aavePool);

        address deployer = msg.sender;

        _grantRole(DEFAULT_ADMIN_ROLE, deployer);
        _grantRole(ADMIN_ROLE, deployer);
        _grantRole(PAUSER_ROLE, deployer);

        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);
    }

    /// @notice Modifier to restrict access to admin functions
    modifier onlyAdmin() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert CallerIsNotAdmin();
        _;
    }

    /// @notice Modifier to restrict access to pauser functions
    modifier onlyPauser() {
        if (!hasRole(PAUSER_ROLE, msg.sender)) revert CallerIsNotPauser();
        _;
    }

    /**
     * @notice Pause all operations
     * @dev Only callable by pauser role
     */
    function pause() external onlyPauser {
        _pause();
    }

    /**
     * @notice Unpause all operations
     * @dev Only callable by pauser role
     */
    function unpause() external onlyPauser {
        _unpause();
    }

    /**
     * @notice Grant pauser role to an account
     * @param account The account to grant the role to
     * @dev Only callable by admin role
     */
    function grantPauserRole(address account) external onlyAdmin {
        if (account == address(0)) revert ZeroAddressNotAllowed();
        grantRole(PAUSER_ROLE, account);
    }

    /**
     * @notice Revoke pauser role from an account
     * @param account The account to revoke the role from
     * @dev Only callable by admin role
     */
    function revokePauserRole(address account) external onlyAdmin {
        if (account == address(0)) revert ZeroAddressNotAllowed();
        revokeRole(PAUSER_ROLE, account);
    }

    /**
     * @notice List an asset for risk accounting and configure enable flags.
     * @param asset The asset to list
     * @param enableDeposits Whether to enable deposits for the asset
     * @param enableBorrows Whether to enable borrows for the asset
     * @dev Only callable by admin role
     */
    function setAssetSupported(address asset, bool enableDeposits, bool enableBorrows) external onlyAdmin {
        if (asset == address(0)) revert ZeroAddressNotAllowed();
        if (_assetInfo[asset].index == 0) {
            _listedAssets.push(asset);
            _assetInfo[asset].index = uint32(_listedAssets.length); // 1-based
            emit AssetListed(asset);
        }
        _assetInfo[asset].depositsEnabled = enableDeposits;
        _assetInfo[asset].borrowsEnabled = enableBorrows;

        emit AssetSupportUpdated(asset, enableDeposits, enableBorrows);
    }

    /**
     * @notice Enable or disable deposits for an asset
     * @param asset The asset to enable or disable deposits for
     * @param enabled Whether to enable or disable deposits
     * @dev Only callable by admin role
     */
    function setDepositsEnabled(address asset, bool enabled) external onlyAdmin {
        if (_assetInfo[asset].index == 0) revert AssetNotSupported();
        _assetInfo[asset].depositsEnabled = enabled;
        emit AssetSupportUpdated(asset, enabled, _assetInfo[asset].borrowsEnabled);
    }

    /**
     * @notice Enable or disable borrows for an asset
     * @param asset The asset to enable or disable borrows for
     * @param enabled Whether to enable or disable borrows
     * @dev Only callable by admin role
     */
    function setBorrowsEnabled(address asset, bool enabled) external onlyAdmin {
        if (_assetInfo[asset].index == 0) revert AssetNotSupported();
        _assetInfo[asset].borrowsEnabled = enabled;
        emit AssetSupportUpdated(asset, _assetInfo[asset].depositsEnabled, enabled);
    }

    /**
     * @notice Check if an asset is supported
     * @param asset The asset to check
     * @return True if the asset is supported, false otherwise
     */
    function isAssetSupported(address asset) public view returns (bool) {
        return _assetInfo[asset].index != 0;
    }

    /**
     * @notice Check if deposits are enabled for an asset
     * @param asset The asset to check
     * @return True if deposits are enabled, false otherwise
     */
    function depositsEnabled(address asset) public view returns (bool) {
        return _assetInfo[asset].depositsEnabled;
    }

    /**
     * @notice Check if borrows are enabled for an asset
     * @param asset The asset to check
     * @return True if borrows are enabled, false otherwise
     */
    function borrowsEnabled(address asset) public view returns (bool) {
        return _assetInfo[asset].borrowsEnabled;
    }

    /**
     * @notice Get the list of listed assets
     * @return The list of listed assets
     */
    function getListedAssets() external view returns (address[] memory) {
        return _listedAssets;
    }

    /**
     * @notice Deposit underlying tokens to Aave and track user's scaled supply
     * @param asset The asset to deposit
     * @param amount The amount to deposit
     * @dev Deposits tokens to Aave and mints scaled supply shares to the user
     *      The user receives scaled units representing their proportional share
     */
    function deposit(address asset, uint256 amount) external whenNotPaused nonReentrant {
        if (!isAssetSupported(asset) || !depositsEnabled(asset)) revert AssetNotSupported();
        if (amount == 0) revert AmountZero();

        address aToken = _getAToken(asset);
        uint256 scaledBefore = IAToken(aToken).scaledBalanceOf(address(this));

        IERC20 token = IERC20(asset);
        token.safeTransferFrom(msg.sender, address(this), amount);
        _approveExact(token, address(AAVE_V3_POOL), amount);
        AAVE_V3_POOL.supply(asset, amount, address(this), 0);
        _clearApproval(token, address(AAVE_V3_POOL));

        uint256 scaledDelta = IAToken(aToken).scaledBalanceOf(address(this)) - scaledBefore;
        userScaledSupply[msg.sender][asset] += scaledDelta;

        emit Deposit(msg.sender, asset, amount, scaledDelta);
    }

    /**
     * @notice Withdraw user's underlying tokens from Aave
     * @param asset The asset to withdraw
     * @param amount The amount to withdraw
     * @return actualAmount The actual amount withdrawn
     * @dev Burns scaled supply shares proportional to the withdrawal amount
     *      Interest is automatically included in the withdrawal
     */
    function withdraw(address asset, uint256 amount) public whenNotPaused nonReentrant returns (uint256 actualAmount) {
        if (!isAssetSupported(asset)) revert AssetNotSupported();
        if (amount == 0) revert AmountZero();

        uint256 userScaled = userScaledSupply[msg.sender][asset];
        if (userScaled == 0) revert UserScaledIsZero();

        uint256 max = getUserSupplyBalance(msg.sender, asset);
        if (amount > max) revert AmountExceedsMaxWithdrawable();

        // Per-user HF check
        _precheckUserWithdraw(msg.sender, asset, amount);

        address aToken = _getAToken(asset);
        uint256 scaledBefore = IAToken(aToken).scaledBalanceOf(address(this));

        actualAmount = AAVE_V3_POOL.withdraw(asset, amount, msg.sender);

        uint256 scaledBurn = scaledBefore - IAToken(aToken).scaledBalanceOf(address(this));
        if (scaledBurn > userScaled) scaledBurn = userScaled; // rounding safety
        userScaledSupply[msg.sender][asset] = userScaled - scaledBurn;

        emit Withdraw(msg.sender, asset, actualAmount, scaledBurn);
    }

    /**
     * @notice Withdraw all supply for a specific asset
     * @param asset The asset to withdraw all from
     * @return The actual amount withdrawn
     * @dev Withdraws the user's entire supply balance including accrued interest
     */
    function withdrawAll(address asset) external whenNotPaused returns (uint256) {
        uint256 max = getUserSupplyBalance(msg.sender, asset);
        return withdraw(asset, max);
    }

    /**
     * @notice Borrow underlying tokens against the pooled collateral
     * @param asset The asset to borrow
     * @param amount The amount to borrow
     * @dev Assigns scaled debt shares to the caller
     *      Performs health factor checks before allowing the borrow
     *      The borrowed amount is transferred to the caller
     */
    function borrow(address asset, uint256 amount) external whenNotPaused nonReentrant {
        if (!isAssetSupported(asset) || !borrowsEnabled(asset)) revert AssetNotSupported();
        if (amount == 0) revert AmountZero();

        // Per-user borrow gate
        _precheckUserBorrow(msg.sender, asset, amount);

        address debt = _getDebtToken(asset);
        uint256 scaledBefore = IVariableDebtToken(debt).scaledBalanceOf(address(this));

        AAVE_V3_POOL.borrow(asset, amount, _VARIABLE_RATE, 0, address(this));
        IERC20(asset).safeTransfer(msg.sender, amount);

        uint256 scaledDelta = IVariableDebtToken(debt).scaledBalanceOf(address(this)) - scaledBefore;
        userScaledBorrow[msg.sender][asset] += scaledDelta;

        emit Borrow(msg.sender, asset, amount, scaledDelta);
    }

    /**
     * @notice Repay debt assigned to the caller
     * @param asset The asset to repay
     * @param amount The amount to repay
     * @return actualRepaid The actual amount repaid
     * @dev Burns scaled debt shares proportional to the repayment amount
     *      Interest is automatically included in the debt calculation
     *      Any over-provisioned amount is refunded to the caller
     */
    function repay(address asset, uint256 amount) public whenNotPaused nonReentrant returns (uint256 actualRepaid) {
        if (!isAssetSupported(asset)) revert AssetNotSupported();
        if (amount == 0) revert AmountZero();

        uint256 userScaled = userScaledBorrow[msg.sender][asset];
        if (userScaled == 0) revert UserScaledIsZero();

        // Cap to caller's debt share
        uint256 max = getUserBorrowBalance(msg.sender, asset);
        if (amount > max) revert AmountExceedsMaxRepayable();

        // Pull funds
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Measure scaled before
        address debt = _getDebtToken(asset);
        uint256 scaledBefore = IVariableDebtToken(debt).scaledBalanceOf(address(this));

        // Approve -> repay -> clear
        _approveExact(IERC20(asset), address(AAVE_V3_POOL), amount);
        actualRepaid = AAVE_V3_POOL.repay(asset, amount, _VARIABLE_RATE, address(this));
        _clearApproval(IERC20(asset), address(AAVE_V3_POOL));

        // Refund any over-provision
        if (amount > actualRepaid) {
            IERC20(asset).safeTransfer(msg.sender, amount - actualRepaid);
        }

        // Attribute scaled burn
        uint256 scaledDelta = scaledBefore - IVariableDebtToken(debt).scaledBalanceOf(address(this));
        if (scaledDelta > userScaled) scaledDelta = userScaled;
        userScaledBorrow[msg.sender][asset] = userScaled - scaledDelta;

        emit Repay(msg.sender, asset, actualRepaid, scaledDelta);
    }

    /**
     * @notice Repay all debt for a specific asset
     * @param asset The asset to repay all debt for
     * @return The actual amount repaid
     * @dev Repays the caller's entire debt balance including accrued interest
     */
    function repayAll(address asset) external whenNotPaused returns (uint256) {
        uint256 max = getUserBorrowBalance(msg.sender, asset);
        return repay(asset, max);
    }

    /*//////////////////////////////////////////////////////////////
                               VIEW HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get user's supply balance in underlying tokens (interest-inclusive)
     * @param user The user address
     * @param asset The asset address
     * @return The user's supply balance including accrued interest
     * @dev Calculates the user's proportional share of the contract's total balance
     *      Interest is automatically included via Aave's scaled balance system
     */
    function getUserSupplyBalance(address user, address asset) public view returns (uint256) {
        uint256 userScaled = userScaledSupply[user][asset];
        if (userScaled == 0) return 0;
        uint256 li = AAVE_V3_POOL.getReserveNormalizedIncome(asset);
        return (userScaled * li) / _RAY;
    }

    /**
     * @notice Get user's variable debt balance in underlying tokens (interest-inclusive)
     * @param user The user address
     * @param asset The asset address
     * @return The user's debt balance including accrued interest
     * @dev Calculates the user's proportional share of the contract's total debt
     *      Interest is automatically included via Aave's scaled balance system
     */
    function getUserBorrowBalance(address user, address asset) public view returns (uint256) {
        uint256 userScaled = userScaledBorrow[user][asset];
        if (userScaled == 0) return 0;
        uint256 di = AAVE_V3_POOL.getReserveNormalizedVariableDebt(asset);
        return (userScaled * di) / _RAY;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL AAVE HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the aToken address for a given asset
     * @param asset The underlying asset address
     * @return The aToken address
     * @dev Reverts if the asset is not supported by Aave
     */
    function _getAToken(address asset) internal view returns (address) {
        DataTypes.ReserveData memory d = AAVE_V3_POOL.getReserveData(asset);
        if (d.aTokenAddress == address(0)) revert ATokenAddressZero();
        return d.aTokenAddress;
    }

    /**
     * @notice Get the variable debt token address for a given asset
     * @param asset The underlying asset address
     * @return The variable debt token address
     * @dev Reverts if the asset is not supported by Aave
     */
    function _getDebtToken(address asset) internal view returns (address) {
        DataTypes.ReserveData memory d = AAVE_V3_POOL.getReserveData(asset);
        if (d.variableDebtTokenAddress == address(0)) revert DebtTokenAddressZero();
        return d.variableDebtTokenAddress;
    }

    /**
     * @notice Approve exact amount for a spender
     * @param token The token to approve
     * @param spender The spender address
     * @param amount The amount to approve
     * @dev Handles USDT-like tokens that require approval to be set to 0 first
     */
    function _approveExact(IERC20 token, address spender, uint256 amount) internal {
        uint256 allow = token.allowance(address(this), spender);
        if (allow != amount) {
            if (allow != 0) {
                token.safeApprove(spender, 0); // USDT-like safety
            }
            token.safeApprove(spender, amount);
        }
    }

    /**
     * @notice Clear approval for a spender
     * @param token The token to clear approval for
     * @param spender The spender address
     * @dev Sets approval to 0 for security
     */
    function _clearApproval(IERC20 token, address spender) internal {
        uint256 allow = token.allowance(address(this), spender);
        if (allow != 0) {
            token.safeApprove(spender, 0);
        }
    }

    /**
     * @notice Pre-check user borrow to ensure health factor remains safe
     * @param user The user to check
     * @param borrowAsset The asset to borrow
     * @param amount The amount to borrow
     * @dev Performs comprehensive checks:
     *      - Current health factor > 1.0
     *      - Borrow amount within available capacity (95% buffer)
     *      - Post-borrow health factor > 1.0
     *      This prevents the contract from becoming liquidatable
     */
    function _precheckUserBorrow(address user, address borrowAsset, uint256 amount) internal view {
        // Per user risk snapshot
        (uint256 collAdjBase, uint256 collLtvBase, uint256 debtBase) = _userRisk(user);

        // Current per-user HF (only meaningful if user already has debt)
        if (debtBase > 0) {
            uint256 hf = (collAdjBase * _WAD) / debtBase;
            if (hf <= _MIN_HF) revert UserHealthFactorBelowMin();
        }

        IAaveOracle oracle = IAaveOracle(AAVE_V3_POOL.ADDRESSES_PROVIDER().getPriceOracle());
        uint256 priceBase = oracle.getAssetPrice(borrowAsset);
        uint8 dec = IERC20Detailed(borrowAsset).decimals();
        uint256 addDebtBase = amount * priceBase / (10 ** dec);

        // LTV capacity with buffer
        uint256 roomBase = collLtvBase > debtBase ? (collLtvBase - debtBase) : 0;
        if (addDebtBase > (roomBase * _BORROW_BUFFER_BPS) / _BPS_DENOM) revert ExceedsUserLTVCapacity();

        // Post-borrow per-user HF (LT-based safety)
        uint256 hfPrime = (collAdjBase * _WAD) / (debtBase + addDebtBase);
        if (hfPrime <= _MIN_HF) revert PostHealthFactorBelowOne();
    }

    /**
     * @notice Pre-check user withdraw to ensure health factor remains safe
     * @param user The user to check
     * @param asset The asset to withdraw
     * @param amount The amount to withdraw
     * @dev Performs comprehensive checks:
     *      - Current health factor > 1.0
     *      - Withdraw amount within available capacity (95% buffer)
     *      - Post-withdraw health factor > 1.0
     *      This prevents the contract from becoming liquidatable
     */
    function _precheckUserWithdraw(address user, address asset, uint256 amount) internal view {
        // Per user risk snapshot
        (uint256 collAdjBase,, uint256 debtBase) = _userRisk(user);
        if (debtBase == 0) return; // no personal debt => no per-user HF risk

        // Enforce current per-user HF
        uint256 currentHf = (collAdjBase * _WAD) / debtBase;
        if (currentHf <= _MIN_HF) revert UserHealthFactorBelowMin();

        IAaveOracle oracle = IAaveOracle(AAVE_V3_POOL.ADDRESSES_PROVIDER().getPriceOracle());
        uint256 priceBase = oracle.getAssetPrice(asset);
        uint8 dec = IERC20Detailed(asset).decimals();
        DataTypes.ReserveConfigurationMap memory cfg = AAVE_V3_POOL.getConfiguration(asset);
        uint256 ltBps = cfg.getLiquidationThreshold();

        // Value of the withdrawal in base currency
        uint256 wBase = amount * priceBase / (10 ** dec);

        // Reduce user's LT-adjusted collateral by the portion removed
        uint256 delta = (wBase * ltBps) / _BPS_DENOM;
        if (delta >= collAdjBase) revert WithdrawLTExceedsUserCollateral();
        uint256 collAdjPrime = collAdjBase - delta;

        // Enforce post-withdraw per-user HF
        uint256 hfPrime = (collAdjPrime * _WAD) / debtBase;
        if (hfPrime <= _MIN_HF) revert PostHealthFactorBelowOne();
    }

    /**
     * @notice Calculate risk contributions for a user
     * @param user The user to calculate risk for
     * @return collAdjBase The total collateral adjustment
     * @return collLtvBase The total collateral LTV
     * @return debtBase The total debt
     */
    function _userRisk(address user)
        internal
        view
        returns (uint256 collAdjBase, uint256 collLtvBase, uint256 debtBase)
    {
        IAaveOracle oracle = IAaveOracle(AAVE_V3_POOL.ADDRESSES_PROVIDER().getPriceOracle());
        address[] memory assets = _listedAssets;
        for (uint256 i = 0; i < assets.length;) {
            (uint256 a, uint256 l, uint256 d) = _perAssetRisk(user, assets[i], oracle);
            collAdjBase += a;
            collLtvBase += l;
            debtBase += d;

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Calculate risk contributions for a single asset
     * @param user The user to calculate risk for
     * @param asset The asset to calculate risk for
     * @param oracle The Aave Oracle contract
     * @return collAdjAdd The "safe" collateral value that counts toward preventing liquidation
     * @return collLtvAdd The maximum debt value that can be borrowed against this collateral
     * @return debtAdd The additional debt
     */
    function _perAssetRisk(address user, address asset, IAaveOracle oracle)
        internal
        view
        returns (uint256 collAdjAdd, uint256 collLtvAdd, uint256 debtAdd)
    {
        uint256 supplyScaled = userScaledSupply[user][asset];
        uint256 borrowScaled = userScaledBorrow[user][asset];
        if (supplyScaled == 0 && borrowScaled == 0) return (0, 0, 0);

        // cache shared values once
        DataTypes.ReserveConfigurationMap memory cfg = AAVE_V3_POOL.getConfiguration(asset);
        uint256 ltBps = cfg.getLiquidationThreshold();
        uint256 ltvBps = cfg.getLtv();
        uint256 price = oracle.getAssetPrice(asset);
        uint8 dec = IERC20Detailed(asset).decimals();

        if (supplyScaled != 0) {
            uint256 li = AAVE_V3_POOL.getReserveNormalizedIncome(asset);
            uint256 supplyUnderlying = (supplyScaled * li) / _RAY;
            uint256 valueBase = (supplyUnderlying * price) / (10 ** dec);
            collAdjAdd = (valueBase * ltBps) / _BPS_DENOM;
            collLtvAdd = (valueBase * ltvBps) / _BPS_DENOM;
        }
        if (borrowScaled != 0) {
            uint256 di = AAVE_V3_POOL.getReserveNormalizedVariableDebt(asset);
            uint256 debtUnderlying = (borrowScaled * di) / _RAY;
            debtAdd = (debtUnderlying * price) / (10 ** dec);
        }
    }
}

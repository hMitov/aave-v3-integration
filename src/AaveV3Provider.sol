// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@aave/core-v3/contracts/interfaces/IAToken.sol";
import "@aave/core-v3/contracts/interfaces/IVariableDebtToken.sol";
import "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import "@aave/core-v3/contracts/interfaces/IAaveOracle.sol";
import "./interfaces/IAaveV3Provider.sol";

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

    /// @notice Role for administrative functions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role for pausing/unpausing operations
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Aave rate enum
    /// @notice Aave variable rate mode constant
    uint256 private constant VARIABLE_RATE = 2;
    /// @notice Minimum health factor threshold (1.00 in WAD)
    uint256 private constant MIN_HF = 1e18; // 1.00 in WAD; can set > 1e18 (e.g., 1.05e18)
    /// @notice Borrow buffer percentage (95% of available borrows)
    uint256 private constant BORROW_BUFFER_BPS = 9_500; // 95% of available borrows
    /// @notice Basis points denominator
    uint256 private constant BPS_DENOM = 10_000;
    /// @notice WAD constant (1e18) for precision
    uint256 private constant WAD = 1e18;
    /// @notice RAY constant (1e27) for precision
    uint256 private constant RAY = 1e27;

    /// @notice The Aave V3 pool contract
    IPool public immutable aavePool;

    /// @notice Mapping of supported assets
    mapping(address => bool) public isSupportedAsset;

    /// @notice User -> asset -> scaled supply balances
    mapping(address => mapping(address => uint256)) public userScaledSupply;
    /// @notice User -> asset -> scaled borrow balances
    mapping(address => mapping(address => uint256)) public userScaledBorrow;

    /// @notice Total scaled supply balances for this provider (critical for isolated accounting)
    mapping(address => uint256) public totalScaledSupply;
    /// @notice Total scaled borrow balances for this provider (critical for isolated accounting)
    mapping(address => uint256) public totalScaledBorrow;

    /**
     * @notice Constructor for AaveV3Provider
     * @param _aavePool The address of the Aave V3 pool contract
     * @dev Sets up initial roles and validates pool address
     */
    constructor(address _aavePool) {
        if (_aavePool == address(0)) revert ZeroAddressNotAllowed();
        aavePool = IPool(_aavePool);

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
     * @notice Enable or disable support for an asset
     * @param asset The asset address to configure
     * @param supported Whether the asset should be supported
     * @dev Only callable by admin role
     */
    function setAssetSupported(address asset, bool supported) external onlyAdmin {
        if (asset == address(0)) revert ZeroAddressNotAllowed();
        isSupportedAsset[asset] = supported;
        emit AssetSupportUpdated(asset, supported);
    }

    /**
     * @notice Deposit underlying tokens to Aave and track user's scaled supply
     * @param asset The asset to deposit
     * @param amount The amount to deposit
     * @dev Deposits tokens to Aave and mints scaled supply shares to the user
     *      The user receives scaled units representing their proportional share
     */
    function deposit(address asset, uint256 amount) external whenNotPaused nonReentrant {
        if (!isSupportedAsset[asset]) revert AssetNotSupported();
        if (amount == 0) revert AmountZero();

        address aToken = _getAToken(asset);
        uint256 scaledBefore = IAToken(aToken).scaledBalanceOf(address(this));

        IERC20 token = IERC20(asset);
        token.safeTransferFrom(msg.sender, address(this), amount);
        _approveExact(token, address(aavePool), amount);
        aavePool.supply(asset, amount, address(this), 0);
        _clearApproval(token, address(aavePool));

        uint256 scaledDelta = IAToken(aToken).scaledBalanceOf(address(this)) - scaledBefore;
        userScaledSupply[msg.sender][asset] += scaledDelta;
        totalScaledSupply[asset] += scaledDelta;

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
        if (!isSupportedAsset[asset]) revert AssetNotSupported();
        if (amount == 0) revert AmountZero();

        uint256 userScaled = userScaledSupply[msg.sender][asset];
        if (userScaled == 0) revert UserScaledIsZero();

        uint256 max = getUserSupplyBalance(msg.sender, asset);
        if (amount > max) revert AmountExceedsMaxWithdrawable();

        address aToken = _getAToken(asset);
        uint256 scaledBefore = IAToken(aToken).scaledBalanceOf(address(this));

        actualAmount = aavePool.withdraw(asset, amount, msg.sender);

        uint256 scaledBurn = scaledBefore - IAToken(aToken).scaledBalanceOf(address(this));
        if (scaledBurn > userScaled) scaledBurn = userScaled; // rounding safety

        userScaledSupply[msg.sender][asset] = userScaled - scaledBurn;
        totalScaledSupply[asset] -= scaledBurn;

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
        if (!isSupportedAsset[asset]) revert AssetNotSupported();
        if (amount == 0) revert AmountZero();

        _precheckContractBorrow(asset, amount);

        address debt = _getDebtToken(asset);
        uint256 scaledBefore = IVariableDebtToken(debt).scaledBalanceOf(address(this));

        aavePool.borrow(asset, amount, VARIABLE_RATE, 0, address(this));
        IERC20(asset).safeTransfer(msg.sender, amount);

        uint256 scaledDelta = IVariableDebtToken(debt).scaledBalanceOf(address(this)) - scaledBefore;
        userScaledBorrow[msg.sender][asset] += scaledDelta;
        totalScaledBorrow[asset] += scaledDelta; // Track our own totals

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
        if (!isSupportedAsset[asset]) revert AssetNotSupported();
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
        _approveExact(IERC20(asset), address(aavePool), amount);
        actualRepaid = aavePool.repay(asset, amount, VARIABLE_RATE, address(this));
        _clearApproval(IERC20(asset), address(aavePool));

        // Refund any over-provision
        if (amount > actualRepaid) {
            IERC20(asset).safeTransfer(msg.sender, amount - actualRepaid);
        }

        // Attribute scaled burn
        uint256 scaledDelta = scaledBefore - IVariableDebtToken(debt).scaledBalanceOf(address(this));
        if (scaledDelta > userScaled) scaledDelta = userScaled;

        userScaledBorrow[msg.sender][asset] = userScaled - scaledDelta;
        totalScaledBorrow[asset] -= scaledDelta; // Track our own totals

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

        uint256 li = aavePool.getReserveNormalizedIncome(asset);
        return (userScaled * li) / RAY;
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

        uint256 di = aavePool.getReserveNormalizedVariableDebt(asset);
        return (userScaled * di) / RAY;
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
        DataTypes.ReserveData memory d = aavePool.getReserveData(asset);
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
        DataTypes.ReserveData memory d = aavePool.getReserveData(asset);
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
     * @notice Pre-check contract borrow to ensure health factor remains safe
     * @param asset The asset to borrow
     * @param amount The amount to borrow
     * @dev Performs comprehensive checks:
     *      - Current health factor > 1.0
     *      - Borrow amount within available capacity (95% buffer)
     *      - Post-borrow health factor > 1.0
     *      This prevents the contract from becoming liquidatable
     */
    function _precheckContractBorrow(address asset, uint256 amount) internal view {
        (
            uint256 totalColBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 liqThresholdBps, // e.g. 8250 for 82.5%
            , // ltv
            uint256 hf
        ) = aavePool.getUserAccountData(address(this));

        if (hf <= MIN_HF) revert ContractHealthFactorBelowOne();

        IAaveOracle oracle = IAaveOracle(aavePool.ADDRESSES_PROVIDER().getPriceOracle());
        uint256 priceBase = oracle.getAssetPrice(asset); // base currency per 1 unit of asset
        uint8 dec = IERC20Detailed(asset).decimals();
        uint256 borrowValueBase = amount * priceBase / (10 ** dec);

        // keep a buffer of available borrows (e.g. 95%)
        if (borrowValueBase > (availableBorrowsBase * BORROW_BUFFER_BPS) / BPS_DENOM) revert ExceedsAvailableBorrow();

        // simulate post-borrow HF: HF' = (collateral * LT) / (debt + newBorrow)
        uint256 colAdj = (totalColBase * liqThresholdBps) / BPS_DENOM;
        uint256 hfPrime = (colAdj * WAD) / (totalDebtBase + borrowValueBase);
        if (hfPrime <= MIN_HF) revert PostHealthFactorBelowOne();
    }
}

# Aave V3 Integration

## Overview

This repository implements a comprehensive Aave V3 lending and borrowing solution that provides a simplified interface for users to interact with Aave's lending protocol. The system handles deposits, withdrawals, borrows, and repayments with automatic interest accrual and health factor management.

**Key Features:**
- **Supply Operations**: Deposit and withdraw assets with automatic interest accrual via liquidity index
- **Borrow Operations**: Borrow and repay assets with health factor validation and debt index tracking
- **Multi-User Support**: Individual balance tracking and scaled balance management for each user
- **Risk Management**: Comprehensive health factor monitoring, LTV validation, and borrow capacity checks
- **Access Control**: Role-based permissions with emergency pause functionality
- **Asset Management**: Dynamic asset whitelist with configurable deposit and borrow enablement
- **Interest Accrual**: Automatic interest calculation using Aave's liquidity and debt indices
- **Security Features**: Reentrancy protection, approval management, and comprehensive validation
- **Testing Suite**: 51+ unit tests, integration tests, and comprehensive mock contracts
- **Gas Optimization**: Efficient approval management and balance updates

**Interest Accrual:**
- **Supply Balances:** Automatically accrue interest via Aave's liquidity index mechanism
- **Borrow Balances:** Track debt with interest via Aave's debt index mechanism
- **Scaled Balances:** Users hold scaled units representing their proportional share of pool assets

## Architecture

The system operates through a clean separation of concerns where the `AaveV3Provider` handles all lending operations while maintaining individual user balances and health factor monitoring.

```
User → AaveV3Provider → Aave V3 Pool

```

**Core Components:**
- `_getAToken`: Retrieves aToken address for supply operations
- `_getDebtToken`: Retrieves debt token address for borrow operations
- `_approveExact`: Manages token approvals with reset to 0 for USDT compatibility
- `_clearApproval`: Clears approvals after operations for security
- `_precheckUserBorrow`: Validates user's borrow capacity and health factor
- `_precheckUserWithdraw`: Validates user's withdrawal capacity and health factor
- `_userRisk`: Calculates user's aggregated risk metrics across all assets
- `_perAssetRisk`: Calculates per-asset risk metrics for specific operations
- `getUserSupplyBalance`: Calculates user's supply balance with accrued interest
- `getUserBorrowBalance`: Calculates user's borrow balance with accrued interest
- `_calculateHealthFactor`: Internal health factor calculation for risk validation

## Contracts

### AaveV3Provider.sol

**Purpose:** Main contract that provides a simplified interface for Aave V3 operations including deposits, withdrawals, borrows, and repayments.

**Roles:** `DEFAULT_ADMIN_ROLE`, `ADMIN_ROLE`, `PAUSER_ROLE`

**Key Storage:**
- `aavePool`: Aave V3 Pool contract address (immutable)
- `isSupportedAsset`: Mapping of supported asset addresses
- `userScaledSupply`: User's scaled supply balance per asset
- `userScaledBorrow`: User's scaled borrow balance per asset
- `totalScaledSupply`: Total scaled supply balances for the provider
- `totalScaledBorrow`: Total scaled borrow balances for the provider

**Core Functions:**

**Supply Operations:**
- `deposit(asset, amount)`: Deposit assets to Aave V3 with automatic interest accrual
- `withdraw(asset, amount)`: Withdraw assets from Aave V3 (partial or full)
- `withdrawAll(asset)`: Withdraw all user's supply for a specific asset
- `getUserSupplyBalance(user, asset)`: Get user's supply balance including accrued interest

**Borrow Operations:**
- `borrow(asset, amount)`: Borrow assets from Aave V3 with health factor validation
- `repay(asset, amount)`: Repay borrowed assets (partial or full)
- `repayAll(asset)`: Repay all user's debt for a specific asset
- `getUserBorrowBalance(user, asset)`: Get user's borrow balance including accrued interest

**Asset Management:**
- `setAssetSupported(asset, depositsEnabled, borrowsEnabled)`: Enable/disable asset support for deposits and/or borrows
- `isAssetSupported(asset)`: Check if an asset is supported
- `depositsEnabled(asset)`: Check if deposits are enabled for an asset
- `borrowsEnabled(asset)`: Check if borrows are enabled for an asset
- `getListedAssets()`: Get the list of all supported assets

**User Management:**
- `userScaledSupply(user, asset)`: Get user's scaled supply balance for an asset
- `userScaledBorrow(user, asset)`: Get user's scaled borrow balance for an asset
- `totalScaledSupply(asset)`: Get total scaled supply balance for an asset
- `totalScaledBorrow(asset)`: Get total scaled borrow balance for an asset

**Access Control:**
- `grantPauserRole(account)`: Grant pauser role to an account
- `revokePauserRole(account)`: Revoke pauser role from an account
- `pause()`: Pause all operations (emergency stop)
- `unpause()`: Unpause all operations
- `paused()`: Check if contract is paused

**Health Factor & Risk Management:**
- `_precheckUserBorrow(user, asset, amount)`: Validate user's borrow capacity and health factor
- `_precheckUserWithdraw(user, asset, amount)`: Validate user's withdrawal capacity and health factor
- `_userRisk(user)`: Calculate user's aggregated risk metrics
- `_perAssetRisk(user, asset)`: Calculate per-asset risk metrics

**Safety Features:**
- **Reentrancy Protection**: `nonReentrant` modifier on all external functions
- **Approval Management**: Automatic approval reset to 0 for USDT compatibility
- **Health Factor Validation**: Pre and post-operation health factor checks
- **Borrow Capacity Checks**: Validation against available borrow capacity
- **Pausable Operations**: Emergency pause functionality with role-based access
- **Asset Support Validation**: Comprehensive asset whitelist management
- **Input Validation**: Zero address and amount validation
- **State Validation**: User balance and debt validation before operations
- **Risk Management**: Liquidation threshold and LTV capacity validation
- **Gas Optimization**: Efficient approval management and balance updates

**Events:**
- `AssetListed`: Emitted when a new asset is added to the supported list
- `AssetSupportUpdated`: Emitted when asset support settings are updated
- `Deposit`: Emitted when user deposits assets (includes scaled delta)
- `Withdraw`: Emitted when user withdraws assets (includes scaled burn amount)
- `Borrow`: Emitted when user borrows assets (includes scaled debt delta)
- `Repay`: Emitted when user repays debt (includes scaled debt burn)
- `RoleGranted`: Emitted when roles are granted to accounts
- `RoleRevoked`: Emitted when roles are revoked from accounts
- `RoleAdminChanged`: Emitted when role admin is changed
- `Paused`: Emitted when contract is paused
- `Unpaused`: Emitted when contract is unpaused

**Error Handling:**
The contract includes comprehensive error handling with custom error types for better gas efficiency and debugging:

**Access Control Errors:**
- `CallerIsNotAdmin`: Thrown when non-admin users try to call admin-only functions
- `CallerIsNotPauser`: Thrown when non-pauser users try to call pause-related functions

**Input Validation Errors:**
- `ZeroAddressNotAllowed`: Thrown when functions receive `address(0)` as a parameter
- `AssetNotSupported`: Thrown when trying to use an asset not in the supported list
- `AmountZero`: Thrown when trying to deposit, withdraw, borrow, or repay 0 amount

**State Validation Errors:**
- `UserScaledIsZero`: Thrown when user has no scaled supply/debt for an asset
- `AmountExceedsMaxWithdrawable`: Thrown when withdrawal exceeds user's available balance
- `AmountExceedsMaxRepayable`: Thrown when repayment exceeds user's debt amount

**Aave Integration Errors:**
- `ATokenAddressZero`: Thrown when Aave returns `address(0)` for aToken
- `DebtTokenAddressZero`: Thrown when Aave returns `address(0)` for debt token

**Risk Management Errors:**
- `UserHealthFactorBelowMin`: Thrown when user's health factor is below minimum threshold
- `ExceedsUserLTVCapacity`: Thrown when borrowing would exceed Loan-to-Value ratio limit
- `WithdrawLTExceedsUserCollateral`: Thrown when withdrawal would make liquidation threshold exceed collateral
- `PostHealthFactorBelowOne`: Thrown when an action would make user's health factor drop below 1.0

**Error Usage Examples:**
```solidity
// Test for AssetNotSupported error
vm.expectRevert(IAaveV3Provider.AssetNotSupported.selector);
provider.deposit(unsupportedAsset, amount);

// Test for AmountZero error
vm.expectRevert(IAaveV3Provider.AmountZero.selector);
provider.deposit(asset, 0);

// Test for UserScaledIsZero error
vm.expectRevert(IAaveV3Provider.UserScaledIsZero.selector);
provider.withdraw(asset, amount);
```

**Configuration Constants:**
- `_MIN_HF`: Minimum health factor threshold (1.00 in WAD format)
- `_BORROW_BUFFER_BPS`: Borrow buffer percentage (95% of available borrows)
- `_BPS_DENOM`: Basis points denominator (10,000)
- `_WAD`: Precision constant (1e18)
- `_RAY`: Aave precision constant (1e27)
- `_VARIABLE_RATE`: Aave variable rate mode constant (2)
- `AAVE_V3_POOL`: Immutable Aave V3 Pool contract address
- `ADDRESSES_PROVIDER`: Immutable Aave addresses provider contract address

### Mock Contracts

**Purpose:** Comprehensive mock contracts for development and testing environments.

**Components:**
- **MockERC20:** Full ERC20 implementation with minting capabilities
- **MockAToken:** Simulates Aave aToken with liquidity index and scaled balance management
- **MockVariableDebtToken:** Simulates Aave debt token with debt index and scaled balance management
- **MockPool:** Simulates Aave V3 Pool with health factor, borrow capacity, and reserve data simulation
- **MockAddressesProvider:** Simulates Aave addresses provider for price oracle access

**Mock Features:**
- **Health Factor Simulation:** Configurable health factor values for testing risk scenarios
- **Borrow Capacity:** Mock available borrows for capacity testing and validation
- **Reserve Data:** Complete reserve data structure with configurable liquidity and debt indices
- **Token Management:** Setter functions for configuring mock token addresses and balances
- **Balance Tracking:** Scaled balance management for supply and borrow operations
- **Interest Simulation:** Configurable liquidity index and debt index for interest accrual testing
- **Pool Integration:** Simulates Aave V3 Pool interface for comprehensive testing
- **Price Oracle:** Mock price oracle for asset price simulation
- **Configuration Management:** Dynamic asset support and borrow enablement testing

## Internal Functions & Risk Management

**Risk Validation Functions:**
- `_precheckUserBorrow(user, asset, amount)`: Validates user's borrow capacity, health factor, and post-borrow risk
- `_precheckUserWithdraw(user, asset, amount)`: Validates user's withdrawal capacity and post-withdrawal health factor
- `_userRisk(user)`: Aggregates user's total collateral and debt across all assets for risk assessment
- `_perAssetRisk(user, asset)`: Calculates per-asset risk metrics including LTV and liquidation threshold
- `_calculateHealthFactor(collateral, debt)`: Internal health factor calculation using price oracle data

**Approval Management:**
- `_approveExact(token, spender, amount)`: Manages token approvals with reset to 0 for USDT compatibility
- `_clearApproval(token, spender)`: Clears approvals after operations for security

**Aave Integration Helpers:**
- `_getAToken(asset)`: Retrieves aToken address from Aave V3 Pool
- `_getDebtToken(asset)`: Retrieves debt token address from Aave V3 Pool

## Interest Accrual & Scaled Balances

**Aave V3 Balance Calculation:**
The system uses Aave's scaled balance mechanism where users hold "scaled units" representing their proportional share of the pool's total assets.

**Supply Balance Formula:**
```solidity
Actual Balance = Scaled Balance × Liquidity Index ÷ 1e27
```

**Borrow Balance Formula:**
```solidity
Actual Debt = Scaled Debt × Debt Index ÷ 1e27
```

**Example:**
- **User deposits 1000 USDC** → gets 1000 scaled balance
- **Liquidity index increases to 1.05** (5% interest)
- **User's actual balance** → automatically becomes 1050 USDC
- **Formula:** `(1000 × 1.05e27) ÷ 1e27 = 1050 USDC`

**Why This Works:**
- **External users** → Change Aave's global liquidity/borrow indexes
- **Your provider** → Gets updated balances via those indexes
- **Your users** → Get their proportional share of your provider's updated balances

## Role System & Access Control

**Role Hierarchy:**
- `DEFAULT_ADMIN_ROLE`: Super admin with ability to grant/revoke all roles
- `ADMIN_ROLE`: Administrative functions like asset management and role management
- `PAUSER_ROLE`: Emergency pause functionality for security incidents

**Role Management:**
- `grantRole(role, account)`: Grant a specific role to an account
- `revokeRole(role, account)`: Revoke a specific role from an account
- `hasRole(role, account)`: Check if an account has a specific role
- `getRoleAdmin(role)`: Get the admin role for a specific role

**Security Features:**
- **Role-based Access Control**: Granular permissions for different operations
- **Emergency Pause**: Ability to pause all operations in emergency situations
- **Multi-signature Support**: Compatible with Safe wallets for multi-sig operations
- **Role Revocation**: Immediate role revocation for security incidents

## Configuration (.env)

Create a `.env` file with the following configuration:

```bash
# RPC & Keys
DEPLOYER_PRIVATE_KEY=                # deployer key (no 0x prefix)
ETHEREUM_SEPOLIA_RPC_URL=            # Sepolia testnet RPC
MAINNET_RPC_URL=                     # Mainnet RPC

```

## Install & Build

**Prerequisites:**
- [Foundry](https://getfoundry.sh/) (`curl -L https://foundry.paradigm.xyz | bash`, then `foundryup`)

**Build Commands:**
```bash
forge install
forge build
```

**Note:** Solidity 0.8.29 with OpenZeppelin v4.x and Aave V3 Core dependencies.

## Testing

**Run Tests:**
```bash
# Run all tests
forge test -vvv

# Run specific test contract
forge test --match-contract AaveV3ProviderTest

# Run specific test
forge test --match-test testDeposit -vvv
```

**Test Coverage:**
- **Unit Tests:** 51+ comprehensive tests covering all major functions
- **Integration Tests:** Real-world scenarios with actual Aave V3 contracts
- **Mock Testing:** Extensive use of mock contracts for isolated testing
- **Branch Coverage:** High coverage of conditional logic and edge cases

**Test Categories:**
- **Core Operations:** Deposit, withdraw, borrow, repay with comprehensive validation
- **Interest Accrual:** Liquidity index and debt index calculations with precision testing
- **Health Factor:** Borrow capacity and health factor validation with risk scenarios
- **Access Control:** Role management and pausing functionality with security testing
- **Edge Cases:** Zero amounts, unsupported assets, paused operations, and error conditions
- **Multi-User Scenarios:** Concurrent operations and balance isolation testing
- **Interest Rate Scenarios:** Various interest rate environments and index calculations
- **Risk Management:** Health factor thresholds, LTV validation, and liquidation scenarios
- **Integration Testing:** Real Aave V3 pool integration with mainnet forking
- **Gas Optimization:** Gas usage analysis and optimization testing

**Foundry Configuration:**
- Solidity 0.8.29 with OpenZeppelin v4.x and Aave V3 dependencies
- Standard library remappings for clean imports

## Deployment

**Deployment Scripts:**

1. **DeployAaveV3Provider.s.sol** — Deploy provider with Aave V3 Pool integration
2. **EnvLoader.s.sol** — Base class for environment variable loading

**Deployment Commands:**
```bash
# Load environment variables
source .env

# Deploy Aave V3 Provider
forge script script/DeployAaveV3Provider.s.sol:DeployAaveV3ProviderScript \
  --rpc-url $ETHEREUM_SEPOLIA_RPC_URL --broadcast --verify -vvvv
```

**Verification:** Use `--verify` flag with Etherscan API key for contract verification.

## Usage Examples

### Deposit Assets
```bash
cast send <PROVIDER_ADDRESS> "deposit(address,uint256)" \
  $SEPOLIA_USDC 1000000 \
  --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $ETHEREUM_SEPOLIA_RPC_URL
```

### Withdraw Assets
```bash
cast send <PROVIDER_ADDRESS> "withdraw(address,uint256)" \
  $SEPOLIA_USDC 500000 \
  --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $ETHEREUM_SEPOLIA_RPC_URL
```

### Borrow Assets
```bash
cast send <PROVIDER_ADDRESS> "borrow(address,uint256)" \
  $SEPOLIA_USDC 100000 \
  --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $ETHEREUM_SEPOLIA_RPC_URL
```

### Repay Assets
```bash
cast send <PROVIDER_ADDRESS> "repay(address,uint256)" \
  $SEPOLIA_USDC 100000 \
  --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $ETHEREUM_SEPOLIA_RPC_URL
```

### Check User Balance
```bash
cast call <PROVIDER_ADDRESS> "getUserSupplyBalance(address,address)" \
  $USER_ADDRESS $SEPOLIA_USDC \
  --rpc-url $ETHEREUM_SEPOLIA_RPC_URL
```

**Notes:**
- **Amounts:** Use token decimals (e.g., USDC: 6 decimals, WETH: 18 decimals)
- **Health Factor:** Borrows require sufficient collateral and health factor > 1.0
- **Interest:** Balances automatically accrue interest via Aave's index mechanism
- **Gas:** Operations include approval management and balance updates

## Security & Operational Notes

**Health Factor Management:**
- Minimum health factor: 1.0 (configurable)
- Borrow capacity validation before operations
- Post-borrow health factor checks

**Access Control:**
- Only grant `PAUSER_ROLE` to trusted operations
- Consider using a [Safe](https://safe.global/) for multi-sig operations
- Always reset approvals to zero (implemented in contract)

**Interest Accrual:**
- Liquidity index updates automatically via Aave V3
- Debt index tracks borrow interest over time
- Scaled balances maintain proportional ownership

**Common Failure Modes:**
- "Health factor below minimum" → Add more collateral or reduce borrow
- "Borrow capacity exceeded" → Check available borrows and health factor
- "Asset not supported" → Enable asset via `setAssetSupported()`
- "Contract paused" → Check if operations are paused by admin

## Testing & Development

**Mock Contracts:**
- **MockERC20:** Full ERC20 implementation with minting
- **MockAToken:** Simulates Aave aToken with liquidity index
- **MockVariableDebtToken:** Simulates Aave debt token with debt index
- **MockPool:** Simulates Aave V3 Pool with health factor and borrow capacity
- **MockAddressesProvider:** Simulates Aave addresses provider

**Test Scenarios:**
- **Interest Accrual:** Test liquidity index and debt index calculations
- **Health Factor:** Test borrow capacity and health factor validation
- **Multi-User:** Test concurrent operations and balance isolation
- **Edge Cases:** Test zero amounts, unsupported assets, paused operations

**Coverage Report:**
```bash
# Generate coverage report
forge coverage --report lcov --match-contract AaveV3Provider

# View coverage in browser (requires genhtml)
genhtml lcov.info --output-directory coverage
```

## Troubleshooting

**"Stack too deep" Errors:**
- Use scoped blocks in complex functions
- Consider breaking functions into smaller helpers

**Health Factor Issues:**
- Ensure sufficient collateral before borrowing
- Check borrow capacity and health factor thresholds
- Monitor post-borrow health factor calculations

**Interest Calculation Issues:**
- Verify liquidity index and debt index values
- Check scaled balance calculations
- Ensure proper index precision (1e27)

**Gas Optimization:**
- Batch operations where possible
- Use appropriate approval strategies
- Consider gas price strategies for mainnet deployment

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Disclaimer:** This software is provided "as is" without warranty. Use at your own risk and ensure proper testing before mainnet deployment. The integration with Aave V3 involves complex DeFi operations; thorough testing and security audits are recommended.

# Aave V3 Integration

## Overview

This repository implements a comprehensive Aave V3 lending and borrowing solution that provides a simplified interface for users to interact with Aave's lending protocol. The system handles deposits, withdrawals, borrows, and repayments with automatic interest accrual and health factor management.

**Key Features:**
- **Deposit and withdraw** assets with automatic interest accrual via liquidity index
- **Borrow and repay** assets with health factor validation and debt index tracking
- **Multi-user support** with individual balance tracking and scaled balance management
- **Health factor monitoring** and borrow capacity validation
- **Pausable operations** with role-based access control
- **Comprehensive testing** with 51+ unit tests and integration tests
- **Mock contracts** for development and testing environments

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
- `_getAToken`: Retrieves aToken for supply operations
- `_getDebtToken`: Retrieves debt token for borrow operations
- `_approveExact`: Manages token approvals with reset to 0
- `_clearApproval`: Clears approvals after operations
- `_precheckContractBorrow`: Validates health factor and borrow capacity
- `getUserSupplyBalance`: Calculates user's supply balance with interest
- `getUserBorrowBalance`: Calculates user's borrow balance with interest

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

**APIs:**
- `deposit(asset, amount)`: Deposit assets to Aave V3
- `withdraw(asset, amount)`: Withdraw assets from Aave V3
- `withdrawAll(asset)`: Withdraw all user's supply for an asset
- `borrow(asset, amount)`: Borrow assets from Aave V3
- `repay(asset, amount)`: Repay borrowed assets
- `repayAll(asset)`: Repay all user's debt for an asset
- `getUserSupplyBalance(user, asset)`: Get user's supply balance with interest
- `getUserBorrowBalance(user, asset)`: Get user's borrow balance with interest
- `setAssetSupported(asset, supported)`: Enable/disable asset support
- `grantPauserRole(account)`: Grant pauser role to account
- `revokePauserRole(account)`: Revoke pauser role from account
- `pause()`: Pause all operations
- `unpause()`: Unpause all operations

**Safety Features:**
- Reentrancy protection
- Approval reset to 0
- Health factor validation
- Borrow capacity checks
- Pausable operations
- Asset support validation

**Events:**
- `AssetSupportUpdated`: Emitted when asset support is toggled
- `Deposit`: Emitted when user deposits assets
- `Withdraw`: Emitted when user withdraws assets
- `Borrow`: Emitted when user borrows assets
- `Repay`: Emitted when user repays debt

**Error Handling:**
- `CallerIsNotAdmin`: Access control validation
- `CallerIsNotPauser`: Pauser role validation
- `ZeroAddressNotAllowed`: Address validation
- `AssetNotSupported`: Asset support validation
- `AmountZero`: Amount validation
- `UserScaledIsZero`: Balance validation
- `NoDebt`: Debt existence validation
- `AmountExceedsMaxWithdrawable`: Withdrawal limit validation
- `AmountExceedsMaxRepayable`: Repayment limit validation
- `ATokenAddressZero`: aToken address validation
- `DebtTokenAddressZero`: Debt token address validation
- `ContractHealthFactorBelowOne`: Health factor validation
- `ExceedsAvailableBorrow`: Borrow capacity validation
- `PostHealthFactorBelowOne`: Post-borrow health factor validation

**Configuration Constants:**
- `MIN_HF`: Minimum health factor threshold (1.00 in WAD)
- `BORROW_BUFFER_BPS`: Borrow buffer percentage (95% of available borrows)
- `BPS_DENOM`: Basis points denominator (10,000)
- `WAD`: Precision constant (1e18)
- `VARIABLE_RATE`: Aave variable rate mode constant (2)

### Mock Contracts

**Purpose:** Comprehensive mock contracts for development and testing environments.

**Components:**
- **MockERC20:** Full ERC20 implementation with minting capabilities
- **MockAToken:** Simulates Aave aToken with liquidity index and scaled balance management
- **MockVariableDebtToken:** Simulates Aave debt token with debt index and scaled balance management
- **MockPool:** Simulates Aave V3 Pool with health factor, borrow capacity, and reserve data simulation
- **MockAddressesProvider:** Simulates Aave addresses provider for price oracle access

**Mock Features:**
- **Health Factor Simulation:** Configurable health factor values for testing
- **Borrow Capacity:** Mock available borrows for capacity testing
- **Reserve Data:** Complete reserve data structure with configurable indices
- **Token Management:** Setter functions for configuring mock token addresses
- **Balance Tracking:** Scaled balance management for supply and borrow operations

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
- **Core Operations:** Deposit, withdraw, borrow, repay
- **Interest Accrual:** Liquidity index and debt index calculations
- **Health Factor:** Borrow capacity and health factor validation
- **Access Control:** Role management and pausing functionality
- **Edge Cases:** Zero amounts, unsupported assets, paused operations

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

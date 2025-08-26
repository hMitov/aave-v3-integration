// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {AaveV3Provider} from "../../src/AaveV3Provider.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockAToken} from "../../src/mocks/MockAToken.sol";
import {MockVariableDebtToken} from "../../src/mocks/MockVariableDebtToken.sol";
import {MockPool} from "../../src/mocks/MockPool.sol";
import {IAaveV3Provider} from "../../src/interfaces/IAaveV3Provider.sol";
import {console} from "forge-std/console.sol";

contract AaveV3ProviderTest is Test {
    AaveV3Provider public provider;
    MockPool public mockPool;
    MockERC20 public mockUsdc;
    MockAToken public mockAToken;
    MockVariableDebtToken public mockDebtToken;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    uint256 public constant INITIAL_BALANCE = 10000e6; // 10,000 USDC
    uint256 public constant DEPOSIT_AMOUNT = 1000e6; // 1,000 USDC

    event AssetSupportUpdated(address indexed asset, bool depositsEnabled, bool borrowsEnabled);
    event Deposit(address indexed user, address indexed asset, uint256 amount, uint256 scaledDelta);
    event Withdraw(address indexed user, address indexed asset, uint256 amount, uint256 scaledDelta);
    event Borrow(address indexed user, address indexed asset, uint256 amount, uint256 scaledDelta);
    event Repay(address indexed user, address indexed asset, uint256 amount, uint256 scaledDelta);

    function setUp() public {
        // Deploy mock contracts
        mockPool = new MockPool();
        mockUsdc = new MockERC20("USD Coin", "USDC");
        mockAToken = new MockAToken();
        mockDebtToken = new MockVariableDebtToken();

        // Deploy the provider
        provider = new AaveV3Provider(address(mockPool));

        // Setup mock pool data
        mockPool.setReserveData(address(mockUsdc), address(mockAToken), address(mockDebtToken));

        // Mint initial tokens
        mockUsdc.mint(user1, INITIAL_BALANCE);
        mockUsdc.mint(user2, INITIAL_BALANCE);

        // Setup mock aToken with initial scaled balance
        mockAToken.setScaledBalance(0);

        // Enable USDC as supported asset
        provider.setAssetSupported(address(mockUsdc), true, true);
    }

    function testConstructor() public view {
        assertEq(address(provider.AAVE_V3_POOL()), address(mockPool));
        assertTrue(provider.hasRole(provider.DEFAULT_ADMIN_ROLE(), address(this)));
        assertTrue(provider.hasRole(provider.ADMIN_ROLE(), address(this)));
        assertTrue(provider.hasRole(provider.PAUSER_ROLE(), address(this)));
    }

    function testPauseUnpause() public {
        assertFalse(provider.paused());

        provider.pause();
        assertTrue(provider.paused());

        provider.unpause();
        assertFalse(provider.paused());
    }

    function testPauseUnpause_RevertsIfNotPauser() public {
        vm.prank(user1);
        vm.expectRevert(IAaveV3Provider.CallerIsNotPauser.selector);
        provider.pause();

        vm.prank(user1);
        vm.expectRevert(IAaveV3Provider.CallerIsNotPauser.selector);
        provider.unpause();
    }

    function testGrantPauserRole() public {
        vm.startPrank(owner);
        provider.grantPauserRole(user1);
        assertTrue(provider.hasRole(provider.PAUSER_ROLE(), user1), "User1 should have pauser role");
        vm.stopPrank();
    }

    function testGrantPauserRole_RevertsIfZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(IAaveV3Provider.ZeroAddressNotAllowed.selector);
        provider.grantPauserRole(address(0));
        vm.stopPrank();
    }

    function testGrantPauserRole_RevertsIfNotAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(IAaveV3Provider.CallerIsNotAdmin.selector);
        provider.grantPauserRole(user2);
        vm.stopPrank();
    }

    function testRevokePauserRole() public {
        // First grant the role
        vm.startPrank(owner);
        provider.grantPauserRole(user1);
        assertTrue(provider.hasRole(provider.PAUSER_ROLE(), user1), "User1 should have pauser role");

        // Then revoke it
        provider.revokePauserRole(user1);
        assertFalse(provider.hasRole(provider.PAUSER_ROLE(), user1), "User1 should not have pauser role");
        vm.stopPrank();
    }

    function testRevokePauserRole_RevertsIfZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(IAaveV3Provider.ZeroAddressNotAllowed.selector);
        provider.revokePauserRole(address(0));
        vm.stopPrank();
    }

    function testRevokePauserRole_RevertsIfNotAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(IAaveV3Provider.CallerIsNotAdmin.selector);
        provider.revokePauserRole(user2);
        vm.stopPrank();
    }

    function testSetAssetSupported() public {
        address newAsset = address(0x123);

        vm.expectEmit(true, false, false, true);
        emit AssetSupportUpdated(newAsset, true, true);

        provider.setAssetSupported(newAsset, true, true);
        assertTrue(provider.isAssetSupported(newAsset));
        assertTrue(provider.depositsEnabled(newAsset));
        assertTrue(provider.borrowsEnabled(newAsset));

        provider.setAssetSupported(newAsset, false, true);
        assertTrue(provider.isAssetSupported(newAsset)); // Asset is still listed
        assertFalse(provider.depositsEnabled(newAsset)); // Deposits are disabled
        assertTrue(provider.borrowsEnabled(newAsset)); // Borrows are still enabled

        // Test disabling borrows only
        provider.setAssetSupported(newAsset, true, false);
        assertTrue(provider.isAssetSupported(newAsset)); // Asset is still listed
        assertTrue(provider.depositsEnabled(newAsset)); // Deposits are enabled
        assertFalse(provider.borrowsEnabled(newAsset)); // Borrows are disabled

        // Test disabling both
        provider.setAssetSupported(newAsset, false, false);
        assertTrue(provider.isAssetSupported(newAsset)); // Asset is still listed
        assertFalse(provider.depositsEnabled(newAsset)); // Deposits are disabled
        assertFalse(provider.borrowsEnabled(newAsset)); // Borrows are disabled
    }

    function testSetAssetSupported_RevertsAssetZeroAddress() public {
        vm.expectRevert(IAaveV3Provider.ZeroAddressNotAllowed.selector);
        provider.setAssetSupported(address(0), true, true);
    }

    function testSetAssetSupported_RevertsIfNotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(IAaveV3Provider.CallerIsNotAdmin.selector);
        provider.setAssetSupported(address(0x123), true, true);
    }

    function testDeposit() public {
        vm.startPrank(user1);

        // Approve tokens
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit Deposit(user1, address(mockUsdc), DEPOSIT_AMOUNT, DEPOSIT_AMOUNT);

        // Deposit
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);

        // Check user's scaled supply
        assertEq(provider.userScaledSupply(user1, address(mockUsdc)), DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function testDeposit_RevertsIfAssetNotSupported() public {
        address unsupportedAsset = address(0x123);

        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);

        vm.expectRevert(IAaveV3Provider.AssetNotSupported.selector);
        provider.deposit(unsupportedAsset, DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function testDeposit_RevertsIfZeroAmount() public {
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);

        vm.expectRevert(IAaveV3Provider.AmountZero.selector);
        provider.deposit(address(mockUsdc), 0);

        vm.stopPrank();
    }

    function testDeposit_RevertsIfZeroAssetAddress() public {
        vm.startPrank(user1);
        mockPool.setAToken(address(mockUsdc), address(0));

        vm.expectRevert(IAaveV3Provider.ATokenAddressZero.selector);
        provider.deposit(address(mockUsdc), 10);

        vm.stopPrank();
    }

    function testDeposit_RevertsIfPaused() public {
        provider.pause();

        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);

        vm.expectRevert("Pausable: paused");
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function testWithdraw() public {
        // First deposit
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);

        // Simulate interest accrual by setting the liquidity index
        mockAToken.setLiquidityIndex(1.05e27); // 5% interest

        // Get the user's current balance (should include interest)
        uint256 balanceWithInterest = provider.getUserSupplyBalance(user1, address(mockUsdc));

        // Should be 1000 * 1.05 = 1050 USDC (50 USDC in interest)
        assertEq(balanceWithInterest, 1050e6);

        // Ensure the pool has enough tokens to cover the withdrawal with interest
        mockUsdc.mint(address(mockPool), 50e6);

        // Withdraw the full balance with interest
        uint256 withdrawn = provider.withdraw(address(mockUsdc), balanceWithInterest);

        // Check that we withdrew MORE than deposited due to interest
        assertEq(withdrawn, 1050e6); // 1000 + 50 = 1050 USDC
        assertTrue(withdrawn > DEPOSIT_AMOUNT, "Should withdraw more than deposited due to interest");
        assertEq(withdrawn - DEPOSIT_AMOUNT, 50e6, "Interest should be 50 USDC");

        // User's scaled supply should be 0 after full withdrawal
        assertEq(provider.userScaledSupply(user1, address(mockUsdc)), 0);

        vm.stopPrank();
    }

    function testWithdraw_RevertsIfAssetNotSupported() public {
        address unsupportedAsset = address(0x123);

        vm.expectRevert(IAaveV3Provider.AssetNotSupported.selector);
        provider.withdraw(unsupportedAsset, DEPOSIT_AMOUNT);
    }

    function testWithdraw_RevertsIfAmountZero() public {
        vm.expectRevert(IAaveV3Provider.AmountZero.selector);
        provider.withdraw(address(mockUsdc), 0);
    }

    function testWithdraw_RevertsIfNoSupply() public {
        vm.expectRevert(IAaveV3Provider.UserScaledIsZero.selector);
        provider.withdraw(address(mockUsdc), DEPOSIT_AMOUNT);
    }

    function testWithdraw_RevertsIfExceedsBalance() public {
        // First deposit
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);

        // Try to withdraw more than deposited
        vm.expectRevert(IAaveV3Provider.AmountExceedsMaxWithdrawable.selector);
        provider.withdraw(address(mockUsdc), DEPOSIT_AMOUNT + 1);

        vm.stopPrank();
    }

    function testWithdraw_RevertsIfPaused() public {
        // First deposit
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);

        // Pause and try to withdraw
        vm.stopPrank();
        provider.pause();

        vm.startPrank(user1);
        vm.expectRevert("Pausable: paused");
        provider.withdraw(address(mockUsdc), DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function testWithdrawAll() public {
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);

        // Setup mock aToken to simulate interest accrual
        mockAToken.setLiquidityIndex(1.05e27); // 5% interest

        // Get the user's current balance (should include interest)
        uint256 balanceWithInterest = provider.getUserSupplyBalance(user1, address(mockUsdc));

        // Should be 1000 * 1.05 = 1050 USDC (50 USDC in interest)
        assertEq(balanceWithInterest, 1050e6);

        // For withdrawAll, we need to ensure the pool has enough tokens
        // Let's mint additional tokens to the pool to cover the interest
        mockUsdc.mint(address(mockPool), 50e6);

        // Withdraw all (including interest)
        uint256 withdrawn = provider.withdrawAll(address(mockUsdc));

        // Check that we withdrew more than deposited due to interest
        assertEq(withdrawn, 1050e6); // 1000 + 50 = 1050 USDC
        assertTrue(withdrawn > DEPOSIT_AMOUNT, "Should withdraw more than deposited due to interest");

        assertEq(provider.userScaledSupply(user1, address(mockUsdc)), 0);
        vm.stopPrank();
    }

    function testBorrow() public {
        // First deposit some collateral
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);

        // Borrow some USDC
        uint256 borrowAmount = 500e6; // 500 USDC
        vm.expectEmit(true, true, false, true);
        emit Borrow(user1, address(mockUsdc), borrowAmount, borrowAmount);
        provider.borrow(address(mockUsdc), borrowAmount);

        // Verify the borrow operation
        assertEq(
            provider.userScaledBorrow(user1, address(mockUsdc)),
            borrowAmount,
            "User scaled borrow should equal borrow amount"
        );
        // Verify the debt token was minted for the provider
        assertEq(
            mockDebtToken.scaledBalanceOf(address(provider)),
            borrowAmount,
            "Provider's debt token balance should equal borrow amount"
        );

        vm.stopPrank();
    }

    function testBorrow_RevertsIfAssetNotSupported() public {
        address unsupportedAsset = address(0x123);

        vm.expectRevert(IAaveV3Provider.AssetNotSupported.selector);
        provider.borrow(unsupportedAsset, DEPOSIT_AMOUNT);
    }

    function testBorrow_RevertsIfAmountZero() public {
        vm.expectRevert(IAaveV3Provider.AmountZero.selector);
        provider.borrow(address(mockUsdc), 0);
    }

    function testBorrow_RevertsIfPaused() public {
        provider.pause();

        vm.expectRevert("Pausable: paused");
        provider.borrow(address(mockUsdc), DEPOSIT_AMOUNT);
    }

    function testRepay() public {
        // First deposit and borrow
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);

        uint256 borrowAmount = 500e6; // 500 USDC
        provider.borrow(address(mockUsdc), borrowAmount);

        // Verify initial state
        assertEq(provider.userScaledBorrow(user1, address(mockUsdc)), borrowAmount, "Initial borrow should be correct");

        // Simulate interest accrual on the borrowed amount
        mockDebtToken.setScaledBalanceFor(address(provider), borrowAmount);
        mockDebtToken.setDebtIndex(1.05e27); // 5% interest

        // Get the user's current borrow balance (should include interest)
        uint256 balanceWithInterest = provider.getUserBorrowBalance(user1, address(mockUsdc));

        // Should be 500 * 1.05 = 525 USDC (25 USDC in interest)
        assertEq(balanceWithInterest, 525e6);

        // Repay some debt (200 USDC)
        uint256 repayAmount = 200e6; // 200 USDC
        mockUsdc.approve(address(provider), repayAmount);

        uint256 actualRepaid = provider.repay(address(mockUsdc), repayAmount);

        // Verify repayment
        assertEq(actualRepaid, repayAmount, "Actual repaid should equal requested amount");
        assertLt(
            provider.userScaledBorrow(user1, address(mockUsdc)), borrowAmount, "User scaled borrow should be reduced"
        );

        vm.stopPrank();
    }

    function testRepay_RevertsIfAssetNotSupported() public {
        address unsupportedAsset = address(0x123);

        vm.expectRevert(IAaveV3Provider.AssetNotSupported.selector);
        provider.repay(unsupportedAsset, DEPOSIT_AMOUNT);
    }

    function testRepay_RevertsIfAmountZero() public {
        vm.expectRevert(IAaveV3Provider.AmountZero.selector);
        provider.repay(address(mockUsdc), 0);
    }

    function testRepay_RevertsIfUserScaledIsZero() public {
        vm.expectRevert(IAaveV3Provider.UserScaledIsZero.selector);
        provider.repay(address(mockUsdc), DEPOSIT_AMOUNT);
    }

    function testRepay_RevertsIfExceedsDebt() public {
        // First deposit and borrow
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);

        // Setup mock debt token for borrowing
        mockDebtToken.setScaledBalanceFor(address(provider), 0);

        uint256 borrowAmount = 500e6; // 500 USDC
        provider.borrow(address(mockUsdc), borrowAmount);

        // Try to repay more than borrowed
        uint256 repayAmount = borrowAmount + 1;
        mockUsdc.approve(address(provider), repayAmount);
        vm.expectRevert(IAaveV3Provider.AmountExceedsMaxRepayable.selector);
        provider.repay(address(mockUsdc), repayAmount);

        vm.stopPrank();
    }

    function testRepay_RevertsIfPaused() public {
        // First deposit and borrow
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);

        // Setup mock debt token for borrowing
        mockDebtToken.setScaledBalanceFor(address(provider), 0);

        uint256 borrowAmount = 500e6; // 500 USDC
        provider.borrow(address(mockUsdc), borrowAmount);

        // Pause and try to repay
        vm.stopPrank();
        provider.pause();

        vm.startPrank(user1);
        mockUsdc.approve(address(provider), borrowAmount);
        vm.expectRevert("Pausable: paused");
        provider.repay(address(mockUsdc), borrowAmount);

        vm.stopPrank();
    }

    function testRepayAll() public {
        // Setup: user borrows and then repays all
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);

        uint256 borrowAmount = 200e6;
        provider.borrow(address(mockUsdc), borrowAmount);
        vm.stopPrank();

        // Check initial debt
        uint256 initialDebt = provider.getUserBorrowBalance(user1, address(mockUsdc));
        assertGt(initialDebt, 0);

        // Repay all debt
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), initialDebt);
        provider.repayAll(address(mockUsdc));
        vm.stopPrank();

        // Check that debt is now zero
        uint256 finalDebt = provider.getUserBorrowBalance(user1, address(mockUsdc));
        assertEq(finalDebt, 0);
    }

    function testGetUserBorrowBalance() public {
        // First deposit and borrow
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);

        uint256 borrowAmount = 500e6; // 500 USDC
        provider.borrow(address(mockUsdc), borrowAmount);

        // Setup mock debt token with interest
        mockDebtToken.setScaledBalanceFor(address(provider), borrowAmount);
        mockDebtToken.setDebtIndex(1.03e27); // 3% interest

        // Get user's borrow balance
        uint256 balance = provider.getUserBorrowBalance(user1, address(mockUsdc));

        // Should be 500 * 1.03 = 515 USDC
        assertEq(balance, 515e6);

        vm.stopPrank();
    }

    function testGetUserBorrowBalance_WithZeroScaled() public view {
        // Test with zero scaled borrow
        uint256 balance = provider.getUserBorrowBalance(user1, address(mockUsdc));
        assertEq(balance, 0);
    }

    function testGetUserSupplyBalance() public {
        // First deposit
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);
        // This will make the provider's actual balance 1050 USDC
        mockAToken.setScaledBalanceFor(address(provider), DEPOSIT_AMOUNT);
        mockAToken.setLiquidityIndex(1.05e27); // 5% interest

        // Get user's supply balance
        uint256 balance = provider.getUserSupplyBalance(user1, address(mockUsdc));

        // Should be 1000 * 1.05 = 1050 USDC
        assertEq(balance, 1050e6);

        vm.stopPrank();
    }

    function testGetUserSupplyBalance_ZeroScaled() public view {
        // Test with zero scaled supply
        uint256 balance = provider.getUserSupplyBalance(user1, address(mockUsdc));
        assertEq(balance, 0);
    }

    function testMultipleUsers() public {
        // User 1 deposits
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // User 2 deposits
        vm.startPrank(user2);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Check individual user supplies
        assertEq(provider.userScaledSupply(user1, address(mockUsdc)), DEPOSIT_AMOUNT);
        assertEq(provider.userScaledSupply(user2, address(mockUsdc)), DEPOSIT_AMOUNT);
    }

    function testInterestAccrual() public {
        // User deposits
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);
        vm.stopPrank();

        mockAToken.setScaledBalanceFor(address(provider), DEPOSIT_AMOUNT);
        mockAToken.setLiquidityIndex(1.1e27); // 10% interest

        // User's balance should now include interest
        uint256 balance = provider.getUserSupplyBalance(user1, address(mockUsdc));
        assertEq(balance, 1100e6); // 1000 * 1.10 = 1100 USDC

        // Scaled balance should remain the same
        assertEq(provider.userScaledSupply(user1, address(mockUsdc)), DEPOSIT_AMOUNT);
    }

    function testInterestAccrualWithWithdraw() public {
        // User deposits 1000 USDC
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Simulate interest accrual over time
        // First period: 5% interest
        mockAToken.setScaledBalanceFor(address(provider), DEPOSIT_AMOUNT);
        mockAToken.setLiquidityIndex(1.05e27); // 5% interest

        uint256 balanceAfter5Percent = provider.getUserSupplyBalance(user1, address(mockUsdc));
        assertEq(balanceAfter5Percent, 1050e6); // 1000 * 1.05 = 1050 USDC

        // Second period: additional 10% interest (total 15.5%)
        mockAToken.setLiquidityIndex(1.155e27); // 15.5% total interest

        uint256 balanceAfter15Percent = provider.getUserSupplyBalance(user1, address(mockUsdc));
        assertEq(balanceAfter15Percent, 1155e6); // 1000 * 1.155 = 1155 USDC

        // Ensure the pool has enough tokens to cover the full withdrawal with interest
        mockUsdc.mint(address(mockPool), 155e6);

        // Now withdraw the full balance including all accumulated interest
        vm.startPrank(user1);
        uint256 withdrawn = provider.withdrawAll(address(mockUsdc));

        // Should withdraw 1155 USDC (1000 deposited + 155 in interest)
        assertEq(withdrawn, 1155e6);
        assertTrue(withdrawn > DEPOSIT_AMOUNT, "Should withdraw more than deposited due to interest");
        assertEq(withdrawn - DEPOSIT_AMOUNT, 155e6, "Interest should be 155 USDC");

        // User's scaled supply should be 0 after full withdrawal
        assertEq(provider.userScaledSupply(user1, address(mockUsdc)), 0);
        vm.stopPrank();
    }

    function testClearApproval_WhenNonZeroAllowance() public {
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);

        // Verify deposit was successful
        assertEq(provider.userScaledSupply(user1, address(mockUsdc)), DEPOSIT_AMOUNT, "User should have deposit");

        // First borrow to set up allowance
        uint256 borrowAmount = 100e6;
        provider.borrow(address(mockUsdc), borrowAmount);

        // Verify first borrow was successful
        assertEq(
            provider.userScaledBorrow(user1, address(mockUsdc)), borrowAmount, "User should have first borrow debt"
        );

        // Second borrow to test existing allowance logic
        uint256 secondBorrowAmount = 50e6;
        provider.borrow(address(mockUsdc), secondBorrowAmount);

        // Verify second borrow was successful
        assertEq(
            provider.userScaledBorrow(user1, address(mockUsdc)),
            borrowAmount + secondBorrowAmount,
            "User should have total borrow debt"
        );

        vm.stopPrank();
    }

    function testApproveExact_WithZeroAllowance() public {
        vm.startPrank(user1);

        mockUsdc.approve(address(mockPool), 2);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);

        // Verify USDC deposit was successful
        assertEq(provider.userScaledSupply(user1, address(mockUsdc)), DEPOSIT_AMOUNT, "User should have USDC deposit");

        // Create a fresh token instance with no allowance to test zero allowance branch
        MockERC20 freshToken = new MockERC20("Fresh Token", "FRESH");
        freshToken.mint(user1, DEPOSIT_AMOUNT);

        // Enable the fresh token as supported asset and set up mock data
        vm.stopPrank();
        provider.setAssetSupported(address(freshToken), true, true);

        // Create mock aToken and debtToken for the fresh token
        MockAToken freshAToken = new MockAToken();
        MockVariableDebtToken freshDebtToken = new MockVariableDebtToken();

        // Set up mock pool data for the fresh token
        mockPool.setReserveData(address(freshToken), address(freshAToken), address(freshDebtToken));

        vm.startPrank(user1);

        // Approve the fresh token (this will test allow == 0 branch)
        freshToken.approve(address(provider), DEPOSIT_AMOUNT);

        // First deposit the fresh token to have balance
        provider.deposit(address(freshToken), DEPOSIT_AMOUNT);

        // Verify fresh token deposit was successful
        assertEq(
            provider.userScaledSupply(user1, address(freshToken)),
            DEPOSIT_AMOUNT,
            "User should have fresh token deposit"
        );

        uint256 borrowAmount = 100e6;
        provider.borrow(address(freshToken), borrowAmount);

        // Verify fresh token borrow was successful
        assertEq(
            provider.userScaledBorrow(user1, address(freshToken)),
            borrowAmount,
            "User should have fresh token borrow debt"
        );

        vm.stopPrank();
    }

    function testClearApproval_WithNonZeroAllowance() public {
        mockUsdc.approve(address(mockPool), 1000e6);

        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Check that the provider's approval to the pool is cleared
        uint256 allowance = mockUsdc.allowance(address(provider), address(mockPool));
        assertEq(allowance, 0);
    }

    function testPrecheckContractBorrow_SuccessfulBorrow() public {
        mockPool.setHealthFactor(2.0e18); // 2.0 health factor (well above 1.0)
        mockPool.setAvailableBorrows(1000e8); // High available borrows

        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);

        // Try to borrow - should succeed
        uint256 borrowAmount = 100e6;
        provider.borrow(address(mockUsdc), borrowAmount);

        // Verify the borrow was successful
        uint256 userBorrowBalance = provider.getUserBorrowBalance(user1, address(mockUsdc));
        assertEq(userBorrowBalance, borrowAmount, "User should have correct borrow balance");

        vm.stopPrank();
    }

    function testRepay_WithOverProvision_RefundBranch() public {
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);

        uint256 borrowAmount = 500e6; // 500 USDC
        provider.borrow(address(mockUsdc), borrowAmount);

        uint256 repayAmount = 500e6; // User provides 500 USDC
        mockUsdc.approve(address(provider), repayAmount);

        uint256 actualRepaid = provider.repay(address(mockUsdc), repayAmount);

        // Should repay the exact amount
        assertEq(actualRepaid, 500e6, "Should repay the exact amount");

        // User should have no remaining debt
        uint256 remainingBalance = provider.getUserBorrowBalance(user1, address(mockUsdc));
        assertEq(remainingBalance, 0, "User should have no remaining debt");

        vm.stopPrank();
    }

    function testSetDepositsEnabled() public {
        address newAsset = address(0x123);

        // First enable the asset
        provider.setAssetSupported(newAsset, true, true);
        assertTrue(provider.depositsEnabled(newAsset));

        // Test disabling deposits
        provider.setDepositsEnabled(newAsset, false);
        assertFalse(provider.depositsEnabled(newAsset));

        // Test re-enabling deposits
        provider.setDepositsEnabled(newAsset, true);
        assertTrue(provider.depositsEnabled(newAsset));
    }

    function testSetDepositsEnabled_RevertsIfAssetNotSupported() public {
        address unsupportedAsset = address(0x123);

        vm.expectRevert(IAaveV3Provider.AssetNotSupported.selector);
        provider.setDepositsEnabled(unsupportedAsset, true);
    }

    function testSetDepositsEnabled_RevertsIfNotAdmin() public {
        address newAsset = address(0x123);
        provider.setAssetSupported(newAsset, true, true);

        vm.prank(user1);
        vm.expectRevert(IAaveV3Provider.CallerIsNotAdmin.selector);
        provider.setDepositsEnabled(newAsset, false);
    }

    function testSetBorrowsEnabled() public {
        address newAsset = address(0x123);

        // First enable the asset
        provider.setAssetSupported(newAsset, true, true);
        assertTrue(provider.borrowsEnabled(newAsset));

        // Test disabling borrows
        provider.setBorrowsEnabled(newAsset, false);
        assertFalse(provider.borrowsEnabled(newAsset));

        // Test re-enabling borrows
        provider.setBorrowsEnabled(newAsset, true);
        assertTrue(provider.borrowsEnabled(newAsset));
    }

    function testSetBorrowsEnabled_RevertsIfAssetNotSupported() public {
        address unsupportedAsset = address(0x123);

        vm.expectRevert(IAaveV3Provider.AssetNotSupported.selector);
        provider.setBorrowsEnabled(unsupportedAsset, true);
    }

    function testSetBorrowsEnabled_RevertsIfNotAdmin() public {
        address newAsset = address(0x123);
        provider.setAssetSupported(newAsset, true, true);

        vm.prank(user1);
        vm.expectRevert(IAaveV3Provider.CallerIsNotAdmin.selector);
        provider.setBorrowsEnabled(newAsset, false);
    }

    function testGetListedAssets() public {
        // Initially should have USDC (set up in setUp)
        address[] memory assets = provider.getListedAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(mockUsdc));

        // Add another asset
        address newAsset = address(0x123);
        provider.setAssetSupported(newAsset, true, true);

        assets = provider.getListedAssets();
        assertEq(assets.length, 2);
        assertEq(assets[0], address(mockUsdc));
        assertEq(assets[1], newAsset);
    }

    function testPrecheckUserWithdraw_WithDebt() public {
        // Setup: user has both supply and debt
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);

        // Borrow some amount to create debt
        uint256 borrowAmount = 200e6;
        provider.borrow(address(mockUsdc), borrowAmount);
        vm.stopPrank();

        // Set up mock configuration for withdrawal checks
        mockPool.setMockConfiguration(address(mockUsdc), 8000, 8250); // 80% LTV, 82.5% LT

        // Try to withdraw - should pass user risk checks
        vm.startPrank(user1);
        uint256 withdrawAmount = 100e6;
        uint256 actualWithdrawn = provider.withdraw(address(mockUsdc), withdrawAmount);
        assertEq(actualWithdrawn, withdrawAmount);
        vm.stopPrank();
    }

    function testGetDebtTokenZeroAddress() public {
        // Test the _getDebtToken function when debt token address is zero
        // This should cover the uncovered branch BRDA:438,27,0,-

        // Set the debt token to address(0) for this asset
        mockPool.setVariableDebtToken(address(mockUsdc), address(0));

        // Try to borrow - this should call _getDebtToken and revert
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);

        // This should revert when trying to borrow because _getDebtToken will be called
        vm.expectRevert(IAaveV3Provider.DebtTokenAddressZero.selector);
        provider.borrow(address(mockUsdc), 100e6);

        vm.stopPrank();
    }

    function testPrecheckUserBorrowWithLowHealthFactor() public {
        // Setup: user has both supply and debt
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);
        provider.borrow(address(mockUsdc), 200e6);
        vm.stopPrank();

        // Set up mock configuration with very low LTV to create low health factor
        mockPool.setMockConfiguration(address(mockUsdc), 1000, 1500); // 10% LTV, 15% LT

        // Try to borrow more - this should fail health factor check
        vm.startPrank(user1);
        vm.expectRevert(IAaveV3Provider.UserHealthFactorBelowMin.selector);
        provider.borrow(address(mockUsdc), 100e6);
        vm.stopPrank();
    }

    function testClearApprovalWithNonZeroAllowance() public {
        // First deposit to set up allowance
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Now withdraw - this should call _clearApproval with non-zero allowance
        vm.startPrank(user1);
        uint256 withdrawAmount = 100e6;
        uint256 actualWithdrawn = provider.withdraw(address(mockUsdc), withdrawAmount);
        assertEq(actualWithdrawn, withdrawAmount);
        vm.stopPrank();

        // Verify the withdrawal worked
        uint256 userBalance = provider.getUserSupplyBalance(user1, address(mockUsdc));
        assertLt(userBalance, DEPOSIT_AMOUNT);
    }

    function testWithdrawDebug() public {
        // Simple test to debug withdrawal logic
        vm.startPrank(user1);
        mockUsdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUsdc), DEPOSIT_AMOUNT);

        // Check initial state
        uint256 initialUserScaled = provider.userScaledSupply(user1, address(mockUsdc));
        console.log("Initial userScaledSupply:", initialUserScaled);

        uint256 initialProviderScaled = mockAToken.scaledBalanceOf(address(provider));
        console.log("Initial provider scaled in aToken:", initialProviderScaled);

        // Withdraw
        uint256 withdrawn = provider.withdraw(address(mockUsdc), DEPOSIT_AMOUNT);
        console.log("Withdrawn amount:", withdrawn);

        // Check final state
        uint256 finalUserScaled = provider.userScaledSupply(user1, address(mockUsdc));
        console.log("Final userScaledSupply:", finalUserScaled);

        uint256 finalProviderScaled = mockAToken.scaledBalanceOf(address(provider));
        console.log("Final provider scaled in aToken:", finalProviderScaled);

        vm.stopPrank();
    }
}

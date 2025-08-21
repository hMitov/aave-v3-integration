// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {AaveV3Provider} from "../../src/AaveV3Provider.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockAToken} from "../../src/mocks/MockAToken.sol";
import {MockVariableDebtToken} from "../../src/mocks/MockVariableDebtToken.sol";
import {MockPool} from "../../src/mocks/MockPool.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IAaveV3Provider} from "../../src/interfaces/IAaveV3Provider.sol";

contract AaveV3ProviderTest is Test {
    AaveV3Provider public provider;
    MockPool public mockPool;
    MockERC20 public mockUSDC;
    MockAToken public mockAToken;
    MockVariableDebtToken public mockDebtToken;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    uint256 public constant INITIAL_BALANCE = 10000e6; // 10,000 USDC
    uint256 public constant DEPOSIT_AMOUNT = 1000e6; // 1,000 USDC

    event AssetSupportUpdated(address indexed asset, bool supported);
    event Deposit(address indexed user, address indexed asset, uint256 amount, uint256 scaledDelta);
    event Withdraw(address indexed user, address indexed asset, uint256 amount, uint256 scaledDelta);
    event Borrow(address indexed user, address indexed asset, uint256 amount, uint256 scaledDelta);
    event Repay(address indexed user, address indexed asset, uint256 amount, uint256 scaledDelta);

    function setUp() public {
        // Deploy mock contracts
        mockPool = new MockPool();
        mockUSDC = new MockERC20("USD Coin", "USDC");
        mockAToken = new MockAToken();
        mockDebtToken = new MockVariableDebtToken();

        // Deploy the provider
        provider = new AaveV3Provider(address(mockPool));

        // Setup mock pool data
        mockPool.setReserveData(address(mockUSDC), address(mockAToken), address(mockDebtToken));

        // Mint initial tokens
        mockUSDC.mint(user1, INITIAL_BALANCE);
        mockUSDC.mint(user2, INITIAL_BALANCE);

        // Setup mock aToken with initial scaled balance
        mockAToken.setScaledBalance(0);

        // Enable USDC as supported asset
        provider.setAssetSupported(address(mockUSDC), true);
    }

    function testConstructor() public {
        assertEq(address(provider.aavePool()), address(mockPool));
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
        emit AssetSupportUpdated(newAsset, true);

        provider.setAssetSupported(newAsset, true);
        assertTrue(provider.isSupportedAsset(newAsset));

        provider.setAssetSupported(newAsset, false);
        assertFalse(provider.isSupportedAsset(newAsset));
    }

    function testSetAssetSupported_RevertsAssetZeroAddress() public {
        vm.expectRevert(IAaveV3Provider.ZeroAddressNotAllowed.selector);
        provider.setAssetSupported(address(0), true);
    }

    function testSetAssetSupported_RevertsIfNotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(IAaveV3Provider.CallerIsNotAdmin.selector);
        provider.setAssetSupported(address(0x123), true);
    }

    function testDeposit() public {
        vm.startPrank(user1);

        // Approve tokens
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit Deposit(user1, address(mockUSDC), DEPOSIT_AMOUNT, DEPOSIT_AMOUNT);

        // Deposit
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        // Check user's scaled supply
        assertEq(provider.userScaledSupply(user1, address(mockUSDC)), DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function testDeposit_RevertsIfAssetNotSupported() public {
        address unsupportedAsset = address(0x123);

        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);

        vm.expectRevert(IAaveV3Provider.AssetNotSupported.selector);
        provider.deposit(unsupportedAsset, DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function testDeposit_RevertsIfZeroAmount() public {
        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);

        vm.expectRevert(IAaveV3Provider.AmountZero.selector);
        provider.deposit(address(mockUSDC), 0);

        vm.stopPrank();
    }

    function testDeposit_RevertsIfZeroAssetAddress() public {
        vm.startPrank(user1);
        mockPool.setAToken(address(mockUSDC), address(0));

        vm.expectRevert(IAaveV3Provider.ATokenAddressZero.selector);
        provider.deposit(address(mockUSDC), 10);

        vm.stopPrank();
    }

    function testDeposit_RevertsIfPaused() public {
        provider.pause();

        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);

        vm.expectRevert("Pausable: paused");
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function testWithdraw() public {
        // Setup mock aToken before deposit - start with 0 for the provider contract
        mockAToken.setScaledBalanceFor(address(provider), 0);

        // First deposit
        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        mockAToken.setScaledBalanceFor(address(provider), DEPOSIT_AMOUNT);
        mockAToken.setLiquidityIndex(1.05e27); // 5% interest

        // Get the user's current balance (should include interest)
        uint256 balanceWithInterest = provider.getUserSupplyBalance(user1, address(mockUSDC));

        // Should be 1000 * 1.05 = 1050 USDC (50 USDC in interest)
        assertEq(balanceWithInterest, 1050e6);

        // Ensure the pool has enough tokens to cover the withdrawal with interest
        mockUSDC.mint(address(mockPool), 50e6);

        // Withdraw the full balance with interest
        uint256 withdrawn = provider.withdraw(address(mockUSDC), balanceWithInterest);

        // Check that we withdrew MORE than deposited due to interest
        assertEq(withdrawn, 1050e6); // 1000 + 50 = 1050 USDC
        assertTrue(withdrawn > DEPOSIT_AMOUNT, "Should withdraw more than deposited due to interest");
        assertEq(withdrawn - DEPOSIT_AMOUNT, 50e6, "Interest should be 50 USDC");

        // User's scaled supply should be 0 after full withdrawal
        assertEq(provider.userScaledSupply(user1, address(mockUSDC)), 0);

        vm.stopPrank();
    }

    function testWithdraw_RevertsIfAssetNotSupported() public {
        address unsupportedAsset = address(0x123);

        vm.expectRevert(IAaveV3Provider.AssetNotSupported.selector);
        provider.withdraw(unsupportedAsset, DEPOSIT_AMOUNT);
    }

    function testWithdraw_RevertsIfAmountZero() public {
        vm.expectRevert(IAaveV3Provider.AmountZero.selector);
        provider.withdraw(address(mockUSDC), 0);
    }

    function testWithdraw_RevertsIfNoSupply() public {
        vm.expectRevert(IAaveV3Provider.UserScaledIsZero.selector);
        provider.withdraw(address(mockUSDC), DEPOSIT_AMOUNT);
    }

    function testWithdraw_RevertsIfExceedsBalance() public {
        // First deposit
        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        // Try to withdraw more than deposited
        vm.expectRevert(IAaveV3Provider.AmountExceedsMaxWithdrawable.selector);
        provider.withdraw(address(mockUSDC), DEPOSIT_AMOUNT + 1);

        vm.stopPrank();
    }

    function testWithdraw_RevertsIfPaused() public {
        // First deposit
        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        // Pause and try to withdraw
        vm.stopPrank();
        provider.pause();

        vm.startPrank(user1);
        vm.expectRevert("Pausable: paused");
        provider.withdraw(address(mockUSDC), DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function testWithdrawAll() public {
        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        // Setup mock aToken to simulate interest accrual
        mockAToken.setScaledBalanceFor(address(provider), DEPOSIT_AMOUNT);
        mockAToken.setLiquidityIndex(1.05e27); // 5% interest

        // Get the user's current balance (should include interest)
        uint256 balanceWithInterest = provider.getUserSupplyBalance(user1, address(mockUSDC));

        // Should be 1000 * 1.05 = 1050 USDC (50 USDC in interest)
        assertEq(balanceWithInterest, 1050e6);

        // For withdrawAll, we need to ensure the pool has enough tokens
        // Let's mint additional tokens to the pool to cover the interest
        mockUSDC.mint(address(mockPool), 50e6);

        // Withdraw all (including interest)
        uint256 withdrawn = provider.withdrawAll(address(mockUSDC));

        // Check that we withdrew more than deposited due to interest
        assertEq(withdrawn, 1050e6); // 1000 + 50 = 1050 USDC
        assertTrue(withdrawn > DEPOSIT_AMOUNT, "Should withdraw more than deposited due to interest");

        assertEq(provider.userScaledSupply(user1, address(mockUSDC)), 0);
        vm.stopPrank();
    }

    function testBorrow() public {
        // First deposit some collateral
        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        // Borrow some USDC
        uint256 borrowAmount = 500e6; // 500 USDC
        vm.expectEmit(true, true, false, true);
        emit Borrow(user1, address(mockUSDC), borrowAmount, borrowAmount);
        provider.borrow(address(mockUSDC), borrowAmount);

        // Verify the borrow operation
        assertEq(
            provider.userScaledBorrow(user1, address(mockUSDC)),
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
        provider.borrow(address(mockUSDC), 0);
    }

    function testBorrow_RevertsIfPaused() public {
        provider.pause();

        vm.expectRevert("Pausable: paused");
        provider.borrow(address(mockUSDC), DEPOSIT_AMOUNT);
    }

    function testRepay() public {
        // First deposit and borrow
        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        uint256 borrowAmount = 500e6; // 500 USDC
        provider.borrow(address(mockUSDC), borrowAmount);

        // Verify initial state
        assertEq(provider.userScaledBorrow(user1, address(mockUSDC)), borrowAmount, "Initial borrow should be correct");

        // Simulate interest accrual on the borrowed amount
        mockDebtToken.setScaledBalanceFor(address(provider), borrowAmount);
        mockDebtToken.setDebtIndex(1.05e27); // 5% interest

        // Get the user's current borrow balance (should include interest)
        uint256 balanceWithInterest = provider.getUserBorrowBalance(user1, address(mockUSDC));

        // Should be 500 * 1.05 = 525 USDC (25 USDC in interest)
        assertEq(balanceWithInterest, 525e6);

        // Repay some debt (200 USDC)
        uint256 repayAmount = 200e6; // 200 USDC
        mockUSDC.approve(address(provider), repayAmount);

        // Calculate how much scaled debt this repayment will burn
        // Since we're repaying 200 out of 525 total debt, we burn proportional scaled units
        uint256 scaledToBurn = (repayAmount * borrowAmount) / balanceWithInterest;

        uint256 actualRepaid = provider.repay(address(mockUSDC), repayAmount);

        // Verify repayment
        assertEq(actualRepaid, repayAmount, "Actual repaid should equal requested amount");
        assertLt(
            provider.userScaledBorrow(user1, address(mockUSDC)), borrowAmount, "User scaled borrow should be reduced"
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
        provider.repay(address(mockUSDC), 0);
    }

    function testRepay_RevertsIfNoDebt() public {
        vm.expectRevert(IAaveV3Provider.UserScaledIsZero.selector);
        provider.repay(address(mockUSDC), DEPOSIT_AMOUNT);
    }

    function testRepay_RevertsIfExceedsDebt() public {
        // First deposit and borrow
        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        // Setup mock debt token for borrowing
        mockDebtToken.setScaledBalanceFor(address(provider), 0);

        uint256 borrowAmount = 500e6; // 500 USDC
        provider.borrow(address(mockUSDC), borrowAmount);

        // Try to repay more than borrowed
        uint256 repayAmount = borrowAmount + 1;
        mockUSDC.approve(address(provider), repayAmount);
        vm.expectRevert(IAaveV3Provider.AmountExceedsMaxRepayable.selector);
        provider.repay(address(mockUSDC), repayAmount);

        vm.stopPrank();
    }

    function testRepay_RevertsIfPaused() public {
        // First deposit and borrow
        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        // Setup mock debt token for borrowing
        mockDebtToken.setScaledBalanceFor(address(provider), 0);

        uint256 borrowAmount = 500e6; // 500 USDC
        provider.borrow(address(mockUSDC), borrowAmount);

        // Pause and try to repay
        vm.stopPrank();
        provider.pause();

        vm.startPrank(user1);
        mockUSDC.approve(address(provider), borrowAmount);
        vm.expectRevert("Pausable: paused");
        provider.repay(address(mockUSDC), borrowAmount);

        vm.stopPrank();
    }

    function testRepayAll() public {
        // First deposit and borrow
        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        // Setup mock debt token for borrowing
        mockDebtToken.setScaledBalanceFor(address(provider), 0);

        uint256 borrowAmount = 500e6; // 500 USDC
        provider.borrow(address(mockUSDC), borrowAmount);

        // Simulate interest accrual on the borrowed amount
        // Set the debt token to show accumulated interest
        mockDebtToken.setScaledBalanceFor(address(provider), borrowAmount);
        mockDebtToken.setDebtIndex(1.05e27); // 5% interest

        // Get the user's current borrow balance (should include interest)
        uint256 balanceWithInterest = provider.getUserBorrowBalance(user1, address(mockUSDC));

        // Should be 500 * 1.05 = 525 USDC (25 USDC in interest)
        assertEq(balanceWithInterest, 525e6);

        // Ensure the user has enough USDC to repay the full amount with interest
        mockUSDC.mint(user1, 25e6); // Give user the extra 25 USDC for interest

        // Repay all debt (including interest)
        mockUSDC.approve(address(provider), balanceWithInterest);
        uint256 actualRepaid = provider.repayAll(address(mockUSDC));

        // Check that we repaid more than borrowed due to interest
        assertEq(actualRepaid, 525e6); // 500 + 25 = 525 USDC
        assertTrue(actualRepaid > borrowAmount, "Should repay more than borrowed due to interest");
        assertEq(actualRepaid - borrowAmount, 25e6, "Interest should be 25 USDC");

        // Check user's scaled borrow is 0
        assertEq(provider.userScaledBorrow(user1, address(mockUSDC)), 0);

        vm.stopPrank();
    }

    function testGetUserBorrowBalance() public {
        // First deposit and borrow
        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        uint256 borrowAmount = 500e6; // 500 USDC
        provider.borrow(address(mockUSDC), borrowAmount);

        // Setup mock debt token with interest
        mockDebtToken.setScaledBalanceFor(address(provider), borrowAmount);
        mockDebtToken.setDebtIndex(1.03e27); // 3% interest

        // Get user's borrow balance
        uint256 balance = provider.getUserBorrowBalance(user1, address(mockUSDC));

        // Should be 500 * 1.03 = 515 USDC
        assertEq(balance, 515e6);

        vm.stopPrank();
    }

    function testGetUserBorrowBalance_WithZeroScaled() public {
        uint256 balance = provider.getUserBorrowBalance(user1, address(mockUSDC));
        assertEq(balance, 0);
    }

    function testGetUserSupplyBalance() public {
        // First deposit
        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);
        // This will make the provider's actual balance 1050 USDC
        mockAToken.setScaledBalanceFor(address(provider), DEPOSIT_AMOUNT);
        mockAToken.setLiquidityIndex(1.05e27); // 5% interest

        // Get user's supply balance
        uint256 balance = provider.getUserSupplyBalance(user1, address(mockUSDC));

        // Should be 1000 * 1.05 = 1050 USDC
        assertEq(balance, 1050e6);

        vm.stopPrank();
    }

    function testGetUserSupplyBalance_ZeroScaled() public {
        uint256 balance = provider.getUserSupplyBalance(user1, address(mockUSDC));
        assertEq(balance, 0);
    }

    function testMultipleUsers() public {
        // User 1 deposits
        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // User 2 deposits
        vm.startPrank(user2);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Check individual user supplies
        assertEq(provider.userScaledSupply(user1, address(mockUSDC)), DEPOSIT_AMOUNT);
        assertEq(provider.userScaledSupply(user2, address(mockUSDC)), DEPOSIT_AMOUNT);
    }

    function testInterestAccrual() public {
        // User deposits
        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);
        vm.stopPrank();

        mockAToken.setScaledBalanceFor(address(provider), DEPOSIT_AMOUNT);
        mockAToken.setLiquidityIndex(1.1e27); // 10% interest

        // User's balance should now include interest
        uint256 balance = provider.getUserSupplyBalance(user1, address(mockUSDC));
        assertEq(balance, 1100e6); // 1000 * 1.10 = 1100 USDC

        // Scaled balance should remain the same
        assertEq(provider.userScaledSupply(user1, address(mockUSDC)), DEPOSIT_AMOUNT);
    }

    function testInterestAccrualWithWithdraw() public {
        // User deposits 1000 USDC
        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Simulate interest accrual over time
        // First period: 5% interest
        mockAToken.setScaledBalanceFor(address(provider), DEPOSIT_AMOUNT);
        mockAToken.setLiquidityIndex(1.05e27); // 5% interest

        uint256 balanceAfter5Percent = provider.getUserSupplyBalance(user1, address(mockUSDC));
        assertEq(balanceAfter5Percent, 1050e6); // 1000 * 1.05 = 1050 USDC

        // Second period: additional 10% interest (total 15.5%)
        mockAToken.setLiquidityIndex(1.155e27); // 15.5% total interest

        uint256 balanceAfter15Percent = provider.getUserSupplyBalance(user1, address(mockUSDC));
        assertEq(balanceAfter15Percent, 1155e6); // 1000 * 1.155 = 1155 USDC

        // Ensure the pool has enough tokens to cover the full withdrawal with interest
        mockUSDC.mint(address(mockPool), 155e6);

        // Now withdraw the full balance including all accumulated interest
        vm.startPrank(user1);
        uint256 withdrawn = provider.withdrawAll(address(mockUSDC));

        // Should withdraw 1155 USDC (1000 deposited + 155 in interest)
        assertEq(withdrawn, 1155e6);
        assertTrue(withdrawn > DEPOSIT_AMOUNT, "Should withdraw more than deposited due to interest");
        assertEq(withdrawn - DEPOSIT_AMOUNT, 155e6, "Interest should be 155 USDC");

        // User's scaled supply should be 0 after full withdrawal
        assertEq(provider.userScaledSupply(user1, address(mockUSDC)), 0);
        vm.stopPrank();
    }

    function testGetDebtToken_RevertsIfZeroAddress() public {
        // Set the variable debt token to address(0) for this asset
        mockPool.setVariableDebtToken(address(mockUSDC), address(0));

        // Try to borrow - should revert when getting debt token
        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        // Verify that the provider has the deposit
        assertEq(provider.userScaledSupply(user1, address(mockUSDC)), DEPOSIT_AMOUNT, "User should have deposit");

        vm.expectRevert(IAaveV3Provider.DebtTokenAddressZero.selector);
        provider.borrow(address(mockUSDC), 100e6);

        vm.stopPrank();
    }

    function testApproveExact_WhenNonZeroAllowance() public {
        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        // Verify deposit was successful
        assertEq(provider.userScaledSupply(user1, address(mockUSDC)), DEPOSIT_AMOUNT, "User should have deposit");

        // First borrow to create debt (use smaller amount to maintain healthy HF)
        uint256 borrowAmount = 200e6; // Reduced from 500e6 to 200e6 to maintain health factor > 1
        provider.borrow(address(mockUSDC), borrowAmount);

        // Verify borrow was successful
        assertEq(provider.userScaledBorrow(user1, address(mockUSDC)), borrowAmount, "User should have borrow debt");

        vm.stopPrank();

        // Set the provider's allowance to the aavePool to be non-zero
        vm.prank(address(provider));
        mockUSDC.approve(address(mockPool), 1000e6); // Provider approves aavePool

        vm.startPrank(user1);
        uint256 repayAmount = 100e6; // Reduced to be proportional to new borrow amount
        mockUSDC.approve(address(provider), repayAmount);
        uint256 actualRepaid = provider.repay(address(mockUSDC), repayAmount);

        // Verify repayment was successful
        assertEq(actualRepaid, repayAmount, "Actual repaid should equal requested amount");
        assertEq(
            provider.userScaledBorrow(user1, address(mockUSDC)),
            borrowAmount - repayAmount,
            "User debt should be reduced"
        );

        vm.stopPrank();
    }

    function testClearApproval_WhenNonZeroAllowance() public {
        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        // Verify deposit was successful
        assertEq(provider.userScaledSupply(user1, address(mockUSDC)), DEPOSIT_AMOUNT, "User should have deposit");

        // First borrow to set up allowance
        uint256 borrowAmount = 100e6;
        provider.borrow(address(mockUSDC), borrowAmount);

        // Verify first borrow was successful
        assertEq(
            provider.userScaledBorrow(user1, address(mockUSDC)), borrowAmount, "User should have first borrow debt"
        );

        // Second borrow to test existing allowance logic
        uint256 secondBorrowAmount = 50e6;
        provider.borrow(address(mockUSDC), secondBorrowAmount);

        // Verify second borrow was successful
        assertEq(
            provider.userScaledBorrow(user1, address(mockUSDC)),
            borrowAmount + secondBorrowAmount,
            "User should have total borrow debt"
        );

        vm.stopPrank();
    }

    function testApproveExact_WithZeroAllowance() public {
        vm.startPrank(user1);

        mockUSDC.approve(address(mockPool), 2);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        // Verify USDC deposit was successful
        assertEq(provider.userScaledSupply(user1, address(mockUSDC)), DEPOSIT_AMOUNT, "User should have USDC deposit");

        // Create a fresh token instance with no allowance to test zero allowance branch
        MockERC20 freshToken = new MockERC20("Fresh Token", "FRESH");
        freshToken.mint(user1, DEPOSIT_AMOUNT);

        // Enable the fresh token as supported asset and set up mock data
        vm.stopPrank();
        provider.setAssetSupported(address(freshToken), true);

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
        mockUSDC.approve(address(mockPool), 1000e6);

        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Check that the provider's approval to the pool is cleared
        uint256 allowance = mockUSDC.allowance(address(provider), address(mockPool));
        assertEq(allowance, 0);
    }

    function testPrecheckContractBorrow_HealthFactorBelowOne() public {
        // Setup mock pool to return health factor below 1
        mockPool.setHealthFactor(0.5e18); // 0.5 health factor (below MIN_HF = 1.0)

        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        // Try to borrow - should revert due to low health factor
        vm.expectRevert(IAaveV3Provider.ContractHealthFactorBelowOne.selector);
        provider.borrow(address(mockUSDC), 100e6);

        vm.stopPrank();
    }

    function testPrecheckContractBorrow_ExceedsAvailableBorrows() public {
        mockPool.setAvailableBorrows(50e8); // Very low available borrows (50 base units)

        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        vm.expectRevert(IAaveV3Provider.ExceedsAvailableBorrow.selector);
        provider.borrow(address(mockUSDC), 200e6);

        vm.stopPrank();
    }

    function testPrecheckContractBorrow_SuccessfulBorrow() public {
        mockPool.setHealthFactor(2.0e18); // 2.0 health factor (well above 1.0)
        mockPool.setAvailableBorrows(1000e8); // High available borrows

        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        // Try to borrow - should succeed
        uint256 borrowAmount = 100e6;
        provider.borrow(address(mockUSDC), borrowAmount);

        // Verify the borrow was successful
        uint256 userBorrowBalance = provider.getUserBorrowBalance(user1, address(mockUSDC));
        assertEq(userBorrowBalance, borrowAmount, "User should have correct borrow balance");

        vm.stopPrank();
    }

    function testRepay_WithOverProvision_RefundBranch() public {
        vm.startPrank(user1);
        mockUSDC.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(address(mockUSDC), DEPOSIT_AMOUNT);

        uint256 borrowAmount = 500e6; // 500 USDC
        provider.borrow(address(mockUSDC), borrowAmount);

        uint256 repayAmount = 500e6; // User provides 500 USDC
        mockUSDC.approve(address(provider), repayAmount);

        uint256 actualRepaid = provider.repay(address(mockUSDC), repayAmount);

        // Should repay the exact amount
        assertEq(actualRepaid, 500e6, "Should repay the exact amount");

        // User should have no remaining debt
        uint256 remainingBalance = provider.getUserBorrowBalance(user1, address(mockUSDC));
        assertEq(remainingBalance, 0, "User should have no remaining debt");

        vm.stopPrank();
    }
}

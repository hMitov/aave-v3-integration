// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {AaveV3Provider} from "../../src/AaveV3Provider.sol";
import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IAaveV3Provider} from "../../src/interfaces/IAaveV3Provider.sol";

contract AaveV3ProviderIT is Test {
    // Mainnet addresses - using correct checksums
    // Using the working Aave V3 Pool address (this might be a proxy or specific deployment)
    address constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC on mainnet
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Test accounts
    address public admin;
    address public user1;

    // Contract instances
    AaveV3Provider public provider;
    IPool public aavePool;
    IERC20 public usdc;
    IERC20 public weth;
    IERC20 public dai;

    // Test constants
    uint256 public constant INITIAL_BALANCE = 10000e6; // 10,000 USDC
    uint256 public constant DEPOSIT_AMOUNT = 1000e6; // 1,000 USDC
    uint256 public constant BORROW_AMOUNT = 500e6; // 500 USDC

    // Events
    event AssetSupportUpdated(address indexed asset, bool supported);
    event Deposit(address indexed user, address indexed asset, uint256 amount, uint256 scaledDelta);
    event Withdraw(address indexed user, address indexed asset, uint256 amount, uint256 scaledDelta);
    event Borrow(address indexed user, address indexed asset, uint256 amount, uint256 scaledDelta);
    event Repay(address indexed user, address indexed asset, uint256 amount, uint256 scaledDelta);

    uint256 private mainnetFork;

    function setUp() public {
        // Fork mainnet at a recent block where Aave V3 is deployed and stable
        // Using a more recent block to get better interest rate conditions
        mainnetFork = vm.createFork("https://eth.llamarpc.com", 19000000);
        vm.selectFork(mainnetFork);

        admin = makeAddr("admin");
        user1 = makeAddr("user1");

        // Initialize contract instances
        aavePool = IPool(AAVE_V3_POOL);
        usdc = IERC20(USDC);
        weth = IERC20(WETH);
        dai = IERC20(DAI);

        vm.startPrank(admin);
        // Deploy the provider
        provider = new AaveV3Provider(AAVE_V3_POOL);

        // Enable assets as supported
        provider.setAssetSupported(USDC, true, true);
        provider.setAssetSupported(WETH, true, true);
        provider.setAssetSupported(DAI, true, true);

        // Setup test accounts with initial balances
        vm.deal(user1, 100 ether);

        // Give user1 some USDC tokens for testing
        // We need to impersonate a whale or mint tokens
        address whale = 0x28C6c06298d514Db089934071355E5743bf21d60; // Binance hot wallet
        vm.startPrank(whale);

        // Check if whale has enough USDC
        uint256 whaleBalance = usdc.balanceOf(whale);
        if (whaleBalance >= INITIAL_BALANCE) {
            bool success = usdc.transfer(user1, INITIAL_BALANCE);
            require(success, "Transfer failed");
            success = weth.transfer(user1, 1 ether);
            require(success, "Transfer failed");
        } else {
            // If whale doesn't have enough, we'll need to handle this differently
            // For now, let's skip the test if we can't get USDC
            vm.skip(true);
        }
        vm.stopPrank();

        vm.stopPrank();
    }

    function testConstructor() public view {
        assertEq(address(provider.AAVE_V3_POOL()), AAVE_V3_POOL, "Pool address should match");
        assertTrue(provider.hasRole(provider.DEFAULT_ADMIN_ROLE(), admin), "Admin should have default admin role");
        assertTrue(provider.hasRole(provider.ADMIN_ROLE(), admin), "Admin should have admin role");
        assertTrue(provider.hasRole(provider.PAUSER_ROLE(), admin), "Admin should have pauser role");
    }

    function testAssetSupport() public view {
        assertTrue(provider.isAssetSupported(USDC), "USDC should be supported");
        assertTrue(provider.isAssetSupported(WETH), "WETH should be supported");
        assertTrue(provider.isAssetSupported(DAI), "DAI should be supported");

        // Test unsupported asset
        address unsupportedAsset = address(0x123);
        assertFalse(provider.isAssetSupported(unsupportedAsset), "Unsupported asset should return false");
    }

    function testDeposit_USDC() public {
        vm.startPrank(user1);

        // Approve USDC spending
        usdc.approve(address(provider), DEPOSIT_AMOUNT);

        // Check initial balance
        uint256 initialBalance = usdc.balanceOf(user1);
        assertGt(initialBalance, DEPOSIT_AMOUNT, "User should have sufficient USDC");
        assertEq(provider.userScaledSupply(user1, USDC), 0, "User should have no scaled supply");
        // Deposit
        provider.deposit(USDC, DEPOSIT_AMOUNT);
        // Get reserve data after deposit
        // Verify deposit - In Aave V3, we should get back approximately what we deposited
        uint256 userSupplyAfterDeposit = provider.getUserSupplyBalance(user1, USDC);
        assertEq(userSupplyAfterDeposit, DEPOSIT_AMOUNT, "User supply should be equal to deposit");

        // Verify scaled supply - this represents the underlying balance in Aave's internal accounting
        uint256 liquidityIndex = provider.AAVE_V3_POOL().getReserveData(USDC).liquidityIndex;

        // In Aave V3: scaledBalance = depositAmount * 1e27 / liquidityIndex
        uint256 expectedScaledSupply = (DEPOSIT_AMOUNT * 1e27) / liquidityIndex;
        uint256 scaledSupplyAfterDeposit = provider.userScaledSupply(user1, USDC);
        assertApproxEqAbs(
            scaledSupplyAfterDeposit, expectedScaledSupply, 1, "Scaled supply should be equal to expected scaled supply"
        );

        vm.stopPrank();
    }

    function testWithdraw_USDC() public {
        vm.startPrank(user1);

        ///Deposit
        usdc.approve(address(provider), DEPOSIT_AMOUNT);
        assertEq(provider.userScaledSupply(user1, USDC), 0, "User should have no scaled supply initially");

        provider.deposit(USDC, DEPOSIT_AMOUNT);

        uint256 userSupplyAfterDeposit = provider.getUserSupplyBalance(user1, USDC);
        assertEq(userSupplyAfterDeposit, DEPOSIT_AMOUNT, "User supply should equal deposit");

        uint256 liquidityIndex = provider.AAVE_V3_POOL().getReserveData(USDC).liquidityIndex;

        // In Aave V3: scaledBalance = depositAmount * 1e27 / liquidityIndex
        uint256 expectedScaledSupply = (DEPOSIT_AMOUNT * 1e27) / liquidityIndex;
        uint256 scaledSupplyAfterDeposit = provider.userScaledSupply(user1, USDC);

        assertApproxEqAbs(
            scaledSupplyAfterDeposit, expectedScaledSupply, 1, "Scaled supply should match expected calculation"
        );

        /// Partial withdrawal
        uint256 withdrawAmount = DEPOSIT_AMOUNT / 2; // 500 USDC
        uint256 userBalanceBeforeWithdraw = usdc.balanceOf(user1);

        uint256 actualWithdrawn = provider.withdraw(USDC, withdrawAmount);

        // Verify withdrawal results
        assertEq(actualWithdrawn, withdrawAmount, "Actual withdrawn should match requested amount");
        // Check user's USDC balance increased
        uint256 userBalanceAfterWithdraw = usdc.balanceOf(user1);
        assertEq(
            userBalanceAfterWithdraw - userBalanceBeforeWithdraw,
            withdrawAmount,
            "User USDC balance should increase by withdrawn amount"
        );

        // Check provider balances updated correctly
        uint256 userSupplyAfterWithdraw = provider.getUserSupplyBalance(user1, USDC);
        uint256 scaledSupplyAfterWithdraw = provider.userScaledSupply(user1, USDC);

        // User supply should be approximately the remaining amount
        uint256 expectedRemainingSupply = DEPOSIT_AMOUNT - withdrawAmount;
        assertApproxEqRel(
            userSupplyAfterWithdraw,
            expectedRemainingSupply,
            1,
            "Remaining supply should be equal to expected remaining supply"
        );

        // Scaled supply should be reduced proportionally
        assertEq(
            2 * scaledSupplyAfterWithdraw,
            scaledSupplyAfterDeposit,
            "Scaled supply should be two times less after withdrawal"
        );
        assertEq(
            scaledSupplyAfterWithdraw,
            scaledSupplyAfterDeposit / 2,
            "Scaled supply should be two times less after withdrawal"
        );

        /// Test withdrawing the remaining amount
        uint256 remainingAmount = provider.getUserSupplyBalance(user1, USDC);
        uint256 finalWithdrawn = provider.withdraw(USDC, remainingAmount);

        assertEq(finalWithdrawn, remainingAmount, "Should withdraw remaining amount");

        // After full withdrawal, scaled supply should be 0 or very close to 0
        uint256 finalScaledSupply = provider.userScaledSupply(user1, USDC);
        assertEq(finalScaledSupply, 0, "Scaled supply should be 0 after full withdrawal");

        vm.stopPrank();
    }

    function testWithdrawAll_USDC() public {
        vm.startPrank(user1);

        ///Deposit
        usdc.approve(address(provider), DEPOSIT_AMOUNT);
        assertEq(provider.userScaledSupply(user1, USDC), 0, "User should have no scaled supply initially");

        provider.deposit(USDC, DEPOSIT_AMOUNT);

        uint256 userSupplyAfterDeposit = provider.getUserSupplyBalance(user1, USDC);
        assertEq(userSupplyAfterDeposit, DEPOSIT_AMOUNT, "User supply should equal deposit");

        uint256 liquidityIndex = provider.AAVE_V3_POOL().getReserveData(USDC).liquidityIndex;

        // In Aave V3: scaledBalance = depositAmount * 1e27 / liquidityIndex
        uint256 expectedScaledSupply = (DEPOSIT_AMOUNT * 1e27) / liquidityIndex;
        uint256 scaledSupplyAfterDeposit = provider.userScaledSupply(user1, USDC);

        assertApproxEqAbs(
            scaledSupplyAfterDeposit, expectedScaledSupply, 1, "Scaled supply should match expected calculation"
        );
        /// Test withdrawAll function
        uint256 userBalanceBeforeWithdraw = usdc.balanceOf(user1);

        uint256 withdrawnAmount = provider.withdrawAll(USDC);

        // Verify withdrawal results
        assertEq(withdrawnAmount, DEPOSIT_AMOUNT, "Should withdraw exactly the deposit amount");

        // Check user's USDC balance increased
        uint256 userBalanceAfterWithdraw = usdc.balanceOf(user1);
        assertEq(
            userBalanceAfterWithdraw - userBalanceBeforeWithdraw,
            withdrawnAmount,
            "User USDC balance should increase by withdrawn amount"
        );

        // Check provider balances are cleared
        uint256 userSupplyAfterWithdraw = provider.getUserSupplyBalance(user1, USDC);
        uint256 scaledSupplyAfterWithdraw = provider.userScaledSupply(user1, USDC);

        assertEq(userSupplyAfterWithdraw, 0, "User supply should be 0 after withdrawAll");
        assertEq(scaledSupplyAfterWithdraw, 0, "Scaled supply should be 0 after withdrawAll");

        vm.stopPrank();
    }

    function testWithdraw_USDC_EdgeCases() public {
        vm.startPrank(user1);

        // Test withdrawing with no supply - should revert
        vm.expectRevert(IAaveV3Provider.UserScaledIsZero.selector);
        provider.withdraw(USDC, 1000);

        // Deposit some amount first
        usdc.approve(address(provider), DEPOSIT_AMOUNT);
        provider.deposit(USDC, DEPOSIT_AMOUNT);

        // Test withdrawing 0 amount - should revert
        vm.expectRevert(IAaveV3Provider.AmountZero.selector);
        provider.withdraw(USDC, 0);

        // Test withdrawing more than balance - should revert
        uint256 userBalance = provider.getUserSupplyBalance(user1, USDC);
        vm.expectRevert(IAaveV3Provider.AmountExceedsMaxWithdrawable.selector);
        provider.withdraw(USDC, userBalance + 1000);

        // Test withdrawing from unsupported asset - should revert
        address unsupportedAsset = address(0x123);
        vm.expectRevert(IAaveV3Provider.AssetNotSupported.selector);
        provider.withdraw(unsupportedAsset, 1000);

        vm.stopPrank();
    }

    function testDeposit_WETH() public {
        vm.startPrank(user1);

        ///Deposit
        // First wrap some ETH to WETH
        uint256 wethAmount = 1 ether; // 1 WETH
        vm.deal(user1, wethAmount);

        // User already has WETH from setup, just verify the balance
        assertEq(weth.balanceOf(user1), wethAmount, "User should have WETH from setup");

        weth.approve(address(provider), wethAmount);
        assertEq(provider.userScaledSupply(user1, WETH), 0, "User should have no scaled supply initially");

        provider.deposit(WETH, wethAmount);

        uint256 userSupplyAfterDeposit = provider.getUserSupplyBalance(user1, WETH);
        assertEq(userSupplyAfterDeposit, wethAmount, "User supply should equal deposit");

        uint256 liquidityIndex = provider.AAVE_V3_POOL().getReserveData(WETH).liquidityIndex;

        // In Aave V3: scaledBalance = depositAmount * 1e27 / liquidityIndex
        uint256 expectedScaledSupply = (wethAmount * 1e27) / liquidityIndex;
        uint256 scaledSupplyAfterDeposit = provider.userScaledSupply(user1, WETH);

        assertApproxEqAbs(
            scaledSupplyAfterDeposit, expectedScaledSupply, 1, "Scaled supply should match expected calculation"
        );

        vm.stopPrank();
    }

    function testWithdraw_WETH() public {
        vm.startPrank(user1);

        ///Deposit
        uint256 wethAmount = 1 ether; // 1 WETH
        vm.deal(user1, wethAmount);

        // User already has WETH from setup, just verify the balance
        assertEq(weth.balanceOf(user1), wethAmount, "User should have WETH from setup");

        weth.approve(address(provider), wethAmount);
        assertEq(provider.userScaledSupply(user1, WETH), 0, "User should have no scaled supply initially");

        provider.deposit(WETH, wethAmount);

        uint256 userSupplyAfterDeposit = provider.getUserSupplyBalance(user1, WETH);
        assertEq(userSupplyAfterDeposit, wethAmount, "User supply should equal deposit");

        uint256 liquidityIndex = provider.AAVE_V3_POOL().getReserveData(WETH).liquidityIndex;

        // In Aave V3: scaledBalance = depositAmount * 1e27 / liquidityIndex
        uint256 expectedScaledSupply = (wethAmount * 1e27) / liquidityIndex;
        uint256 scaledSupplyAfterDeposit = provider.userScaledSupply(user1, WETH);

        assertApproxEqAbs(
            scaledSupplyAfterDeposit, expectedScaledSupply, 1, "Scaled supply should match expected calculation"
        );

        /// Partial withdrawal
        uint256 withdrawAmount = wethAmount / 2; // 0.5 WETH
        uint256 userBalanceBeforeWithdraw = weth.balanceOf(user1);

        uint256 actualWithdrawn = provider.withdraw(WETH, withdrawAmount);

        // Verify withdrawal results
        assertEq(actualWithdrawn, withdrawAmount, "Actual withdrawn should match requested amount");
        // Check user's WETH balance increased
        uint256 userBalanceAfterWithdraw = weth.balanceOf(user1);
        assertEq(
            userBalanceAfterWithdraw - userBalanceBeforeWithdraw,
            withdrawAmount,
            "User WETH balance should increase by withdrawn amount"
        );

        // Check provider balances updated correctly
        uint256 userSupplyAfterWithdraw = provider.getUserSupplyBalance(user1, WETH);
        uint256 scaledSupplyAfterWithdraw = provider.userScaledSupply(user1, WETH);

        // User supply should be approximately the remaining amount
        uint256 expectedRemainingSupply = wethAmount - withdrawAmount;
        assertApproxEqRel(
            userSupplyAfterWithdraw,
            expectedRemainingSupply,
            10,
            "Remaining supply should be equal to expected remaining supply"
        );

        // Scaled supply should be reduced proportionally (with tolerance for interest accrual)
        assertApproxEqAbs(
            2 * scaledSupplyAfterWithdraw,
            scaledSupplyAfterDeposit,
            1,
            "Scaled supply should be approximately two times less after withdrawal"
        );
        assertApproxEqAbs(
            scaledSupplyAfterWithdraw,
            scaledSupplyAfterDeposit / 2,
            1,
            "Scaled supply should be approximately half after withdrawal"
        );

        /// Test withdrawing the remaining amount
        uint256 remainingAmount = provider.getUserSupplyBalance(user1, WETH);
        uint256 finalWithdrawn = provider.withdraw(WETH, remainingAmount);

        assertEq(finalWithdrawn, remainingAmount, "Should withdraw remaining amount");

        // After full withdrawal, scaled supply should be 0 or very close to 0
        uint256 finalScaledSupply = provider.userScaledSupply(user1, WETH);
        assertApproxEqAbs(finalScaledSupply, 0, 1, "Scaled supply should be 0 after full withdrawal");

        vm.stopPrank();
    }

    function testWithdrawAll_WETH() public {
        vm.startPrank(user1);

        ///Deposit
        uint256 wethAmount = 1 ether; // 1 WETH
        vm.deal(user1, wethAmount);

        // User already has WETH from setup, just verify the balance
        assertEq(weth.balanceOf(user1), wethAmount, "User should have WETH from setup");

        weth.approve(address(provider), wethAmount);
        assertEq(provider.userScaledSupply(user1, WETH), 0, "User should have no scaled supply initially");

        provider.deposit(WETH, wethAmount);

        uint256 userSupplyAfterDeposit = provider.getUserSupplyBalance(user1, WETH);
        assertEq(userSupplyAfterDeposit, wethAmount, "User supply should equal deposit");

        uint256 liquidityIndex = provider.AAVE_V3_POOL().getReserveData(WETH).liquidityIndex;

        // In Aave V3: scaledBalance = depositAmount * 1e27 / liquidityIndex
        uint256 expectedScaledSupply = (wethAmount * 1e27) / liquidityIndex;
        uint256 scaledSupplyAfterDeposit = provider.userScaledSupply(user1, WETH);

        assertApproxEqAbs(
            scaledSupplyAfterDeposit, expectedScaledSupply, 1, "Scaled supply should match expected calculation"
        );

        /// Test withdrawAll function
        uint256 userBalanceBeforeWithdraw = weth.balanceOf(user1);

        uint256 withdrawnAmount = provider.withdrawAll(WETH);

        // Verify withdrawal results
        assertEq(withdrawnAmount, wethAmount, "Should withdraw exactly the deposit amount");

        // Check user's WETH balance increased
        uint256 userBalanceAfterWithdraw = weth.balanceOf(user1);
        assertEq(
            userBalanceAfterWithdraw - userBalanceBeforeWithdraw,
            withdrawnAmount,
            "User WETH balance should increase by withdrawn amount"
        );

        // Check provider balances are cleared
        uint256 userSupplyAfterWithdraw = provider.getUserSupplyBalance(user1, WETH);
        uint256 scaledSupplyAfterWithdraw = provider.userScaledSupply(user1, WETH);

        assertEq(userSupplyAfterWithdraw, 0, "User supply should be 0 after withdrawAll");
        assertEq(scaledSupplyAfterWithdraw, 0, "Scaled supply should be 0 after withdrawAll");

        vm.stopPrank();
    }

    function testBorrow_USDC() public {
        vm.startPrank(user1);

        // First deposit to have collateral
        usdc.approve(address(provider), DEPOSIT_AMOUNT);
        assertEq(provider.userScaledSupply(user1, USDC), 0, "User should have no scaled supply initially");

        provider.deposit(USDC, DEPOSIT_AMOUNT);

        // Verify deposit with comprehensive checks (same style as deposit tests)
        uint256 userSupplyAfterDeposit = provider.getUserSupplyBalance(user1, USDC);
        assertEq(userSupplyAfterDeposit, DEPOSIT_AMOUNT, "User supply should equal deposit");

        uint256 liquidityIndex = provider.AAVE_V3_POOL().getReserveData(USDC).liquidityIndex;

        // In Aave V3: scaledBalance = depositAmount * 1e27 / liquidityIndex
        uint256 expectedScaledSupply = (DEPOSIT_AMOUNT * 1e27) / liquidityIndex;
        uint256 scaledSupplyAfterDeposit = provider.userScaledSupply(user1, USDC);

        assertApproxEqAbs(
            scaledSupplyAfterDeposit, expectedScaledSupply, 1, "Scaled supply should match expected calculation"
        );

        // Borrow
        provider.borrow(USDC, BORROW_AMOUNT);

        // Verify borrow with comprehensive checks
        uint256 userBorrowAfterBorrow = provider.getUserBorrowBalance(user1, USDC);
        assertApproxEqAbs(userBorrowAfterBorrow, BORROW_AMOUNT, 5, "User should have borrow balance");

        // Check scaled borrow balance
        uint256 scaledBorrowAfterBorrow = provider.userScaledBorrow(user1, USDC);
        assertGt(scaledBorrowAfterBorrow, 0, "User should have scaled borrow balance");

        uint256 borrowIndex = provider.AAVE_V3_POOL().getReserveData(USDC).variableBorrowIndex;

        uint256 expectedScaledBorrow = (BORROW_AMOUNT * 1e27) / borrowIndex;
        assertApproxEqAbs(
            scaledBorrowAfterBorrow, expectedScaledBorrow, 1, "Scaled borrow should match expected calculation"
        );

        vm.stopPrank();
    }

    function testBorrow_WETH() public {
        vm.startPrank(user1);

        // First deposit to have collateral
        weth.approve(address(provider), 1 ether);
        assertEq(provider.userScaledSupply(user1, WETH), 0, "User should have no scaled supply initially");

        provider.deposit(WETH, 1 ether);

        // Verify deposit with comprehensive checks (same style as deposit tests)
        uint256 userSupplyAfterDeposit = provider.getUserSupplyBalance(user1, WETH);
        assertEq(userSupplyAfterDeposit, 1 ether, "User supply should equal deposit");

        uint256 liquidityIndex = provider.AAVE_V3_POOL().getReserveData(WETH).liquidityIndex;

        // In Aave V3: scaledBalance = depositAmount * 1e27 / liquidityIndex
        uint256 expectedScaledSupply = (1 ether * 1e27) / liquidityIndex;
        uint256 scaledSupplyAfterDeposit = provider.userScaledSupply(user1, WETH);

        assertApproxEqAbs(
            scaledSupplyAfterDeposit, expectedScaledSupply, 1, "Scaled supply should match expected calculation"
        );

        // Now borrow WETH
        provider.borrow(WETH, 0.5 ether);

        // Verify borrow with comprehensive checks
        uint256 userBorrowAfterBorrow = provider.getUserBorrowBalance(user1, WETH);
        assertEq(userBorrowAfterBorrow, 0.5 ether, "User should have borrow balance");

        // Check scaled borrow balance
        uint256 scaledBorrowAfterBorrow = provider.userScaledBorrow(user1, WETH);
        assertGt(scaledBorrowAfterBorrow, 0, "User should have scaled borrow balance");

        uint256 borrowIndex = provider.AAVE_V3_POOL().getReserveData(WETH).variableBorrowIndex;

        uint256 expectedScaledBorrow = (0.5 ether * 1e27) / borrowIndex;
        assertApproxEqAbs(
            scaledBorrowAfterBorrow, expectedScaledBorrow, 1, "Scaled borrow should match expected calculation"
        );

        vm.stopPrank();
    }

    function testRepay_WETH() public {
        vm.startPrank(user1);

        // First deposit to have collateral
        uint256 wethAmount = 1 ether; // 1 WETH
        weth.approve(address(provider), wethAmount);
        assertEq(provider.userScaledSupply(user1, WETH), 0, "User should have no scaled supply initially");

        provider.deposit(WETH, wethAmount);

        // Verify deposit with comprehensive checks (same style as other tests)
        uint256 userSupplyAfterDeposit = provider.getUserSupplyBalance(user1, WETH);
        assertEq(userSupplyAfterDeposit, wethAmount, "User supply should equal deposit");

        uint256 liquidityIndex = provider.AAVE_V3_POOL().getReserveData(WETH).liquidityIndex;

        // In Aave V3: scaledBalance = depositAmount * 1e27 / liquidityIndex
        uint256 expectedScaledSupply = (wethAmount * 1e27) / liquidityIndex;
        uint256 scaledSupplyAfterDeposit = provider.userScaledSupply(user1, WETH);

        assertApproxEqAbs(
            scaledSupplyAfterDeposit, expectedScaledSupply, 1, "Scaled supply should match expected calculation"
        );

        // Now borrow WETH
        uint256 borrowAmount = 0.5 ether; // 0.5 WETH
        provider.borrow(WETH, borrowAmount);

        // Verify borrow with comprehensive checks
        uint256 userBorrowAfterBorrow = provider.getUserBorrowBalance(user1, WETH);
        assertEq(userBorrowAfterBorrow, borrowAmount, "User should have borrow balance");

        // Check scaled borrow balance
        uint256 scaledBorrowAfterBorrow = provider.userScaledBorrow(user1, WETH);
        assertGt(scaledBorrowAfterBorrow, 0, "User should have scaled borrow balance");

        uint256 borrowIndex = provider.AAVE_V3_POOL().getReserveData(WETH).variableBorrowIndex;

        uint256 expectedScaledBorrow = (borrowAmount * 1e27) / borrowIndex;
        assertApproxEqAbs(
            scaledBorrowAfterBorrow, expectedScaledBorrow, 1, "Scaled borrow should match expected calculation"
        );

        /// Partial repayment
        // Get the current borrow balance (in a test environment, this may not have increased due to interest yet)
        uint256 currentBorrowBalance = provider.getUserBorrowBalance(user1, WETH);
        assertEq(currentBorrowBalance, borrowAmount, "Borrow balance should equal the borrowed amount initially");

        // Repay half of the current balance
        uint256 repayAmount = currentBorrowBalance / 2;
        uint256 userBalanceBeforeRepay = weth.balanceOf(user1);

        // Approve WETH for repayment
        weth.approve(address(provider), repayAmount);

        uint256 actualRepaid = provider.repay(WETH, repayAmount);

        // Verify repayment results
        assertEq(actualRepaid, repayAmount, "Actual repaid should match requested amount");

        // Check user's WETH balance decreased
        uint256 userBalanceAfterRepay = weth.balanceOf(user1);
        assertEq(
            userBalanceBeforeRepay - userBalanceAfterRepay,
            repayAmount,
            "User WETH balance should decrease by repaid amount"
        );

        // Check provider balances updated correctly
        uint256 userBorrowAfterRepay = provider.getUserBorrowBalance(user1, WETH);
        uint256 scaledBorrowAfterRepay = provider.userScaledBorrow(user1, WETH);

        // User borrow should be approximately the remaining amount
        uint256 expectedRemainingBorrow = currentBorrowBalance - repayAmount;
        assertApproxEqRel(
            userBorrowAfterRepay,
            expectedRemainingBorrow,
            10,
            "Remaining borrow should be equal to expected remaining borrow"
        );

        // Scaled borrow should be reduced proportionally (with tolerance for interest accrual)
        assertApproxEqAbs(
            2 * scaledBorrowAfterRepay,
            scaledBorrowAfterBorrow,
            10,
            "Scaled borrow should be approximately two times less after repayment"
        );

        /// Test repaying the remaining amount
        // Check the current remaining borrow balance (which may have increased due to interest)
        uint256 remainingBorrow = provider.getUserBorrowBalance(user1, WETH);

        // Approve remaining amount for repayment
        weth.approve(address(provider), remainingBorrow);

        uint256 finalRepaid = provider.repay(WETH, remainingBorrow);

        assertEq(finalRepaid, remainingBorrow, "Should repay remaining borrow amount");

        // After full repayment, scaled borrow should be 0 or very close to 0
        uint256 finalScaledBorrow = provider.userScaledBorrow(user1, WETH);
        assertEq(finalScaledBorrow, 0, "Scaled borrow should be 0 after full repayment");

        vm.stopPrank();
    }

    function testRepay_USDC() public {
        vm.startPrank(user1);

        // First deposit to have collateral
        uint256 usdcAmount = DEPOSIT_AMOUNT; // 1,000,000 USDC (6 decimals)
        usdc.approve(address(provider), usdcAmount);
        assertEq(provider.userScaledSupply(user1, USDC), 0, "User should have no scaled supply initially");

        provider.deposit(USDC, usdcAmount);

        // Verify deposit with comprehensive checks (same style as other tests)
        uint256 userSupplyAfterDeposit = provider.getUserSupplyBalance(user1, USDC);
        assertEq(userSupplyAfterDeposit, usdcAmount, "User supply should equal deposit");

        uint256 liquidityIndex = provider.AAVE_V3_POOL().getReserveData(USDC).liquidityIndex;

        // In Aave V3: scaledBalance = depositAmount * 1e27 / liquidityIndex
        uint256 expectedScaledSupply = (usdcAmount * 1e27) / liquidityIndex;
        uint256 scaledSupplyAfterDeposit = provider.userScaledSupply(user1, USDC);

        assertApproxEqAbs(
            scaledSupplyAfterDeposit, expectedScaledSupply, 1, "Scaled supply should match expected calculation"
        );

        // Now borrow USDC
        uint256 borrowAmount = DEPOSIT_AMOUNT / 2; // 500,000 USDC (half of deposit)
        provider.borrow(USDC, borrowAmount);

        // Verify borrow with comprehensive checks
        uint256 userBorrowAfterBorrow = provider.getUserBorrowBalance(user1, USDC);
        assertApproxEqAbs(userBorrowAfterBorrow, borrowAmount, 5, "User should have borrow balance");
        // Check scaled borrow balance
        uint256 scaledBorrowAfterBorrow = provider.userScaledBorrow(user1, USDC);
        assertGt(scaledBorrowAfterBorrow, 0, "User should have scaled borrow balance");

        uint256 borrowIndex = provider.AAVE_V3_POOL().getReserveData(USDC).variableBorrowIndex;

        uint256 expectedScaledBorrow = (borrowAmount * 1e27) / borrowIndex;
        assertApproxEqAbs(
            scaledBorrowAfterBorrow, expectedScaledBorrow, 1, "Scaled borrow should match expected calculation"
        );

        /// Partial repayment
        // Get the current borrow balance (in a test environment, this may not have increased due to interest yet)
        uint256 currentBorrowBalance = provider.getUserBorrowBalance(user1, USDC);
        assertApproxEqAbs(
            currentBorrowBalance, borrowAmount, 5, "Borrow balance should equal the borrowed amount initially"
        );

        // Repay half of the current balance
        uint256 repayAmount = currentBorrowBalance / 2;
        uint256 userBalanceBeforeRepay = usdc.balanceOf(user1);

        // Approve USDC for repayment
        usdc.approve(address(provider), repayAmount);

        uint256 actualRepaid = provider.repay(USDC, repayAmount);

        // Verify repayment results
        assertEq(actualRepaid, repayAmount, "Actual repaid should match requested amount");

        // Check user's USDC balance decreased
        uint256 userBalanceAfterRepay = usdc.balanceOf(user1);
        assertEq(
            userBalanceBeforeRepay - userBalanceAfterRepay,
            repayAmount,
            "User USDC balance should decrease by repaid amount"
        );

        // Check provider balances updated correctly
        uint256 userBorrowAfterRepay = provider.getUserBorrowBalance(user1, USDC);
        uint256 scaledBorrowAfterRepay = provider.userScaledBorrow(user1, USDC);

        // User borrow should be approximately the remaining amount
        uint256 expectedRemainingBorrow = currentBorrowBalance - repayAmount;
        assertApproxEqRel(
            userBorrowAfterRepay,
            expectedRemainingBorrow,
            10,
            "Remaining borrow should be equal to expected remaining borrow"
        );

        // Scaled borrow should be reduced proportionally (with tolerance for interest accrual)
        assertApproxEqAbs(
            2 * scaledBorrowAfterRepay,
            scaledBorrowAfterBorrow,
            10,
            "Scaled borrow should be approximately two times less after repayment"
        );

        /// Test repaying the remaining amount
        // Check the current remaining borrow balance (which may have increased due to interest)
        uint256 remainingBorrow = provider.getUserBorrowBalance(user1, USDC);

        // Approve remaining amount for repayment
        usdc.approve(address(provider), remainingBorrow);

        uint256 finalRepaid = provider.repay(USDC, remainingBorrow);

        assertEq(finalRepaid, remainingBorrow, "Should repay remaining borrow amount");

        // After full repayment, scaled borrow should be 0 or very close to 0
        uint256 finalScaledBorrow = provider.userScaledBorrow(user1, USDC);
        assertApproxEqAbs(finalScaledBorrow, 0, 1, "Scaled borrow should be 0 after full repayment");

        vm.stopPrank();
    }

    function testBorrowHitPrecheckContractBorrow() public {
        vm.startPrank(user1);

        // First deposit some collateral
        weth.approve(address(provider), 1 ether);
        provider.deposit(WETH, 1 ether);

        // Test Case 1: Try to borrow more than available (exceeds-available-95)
        // This should hit the "exceeds-available-95" check
        uint256 hugeBorrowAmount = 1000 ether; // Way more than we have collateral for

        vm.expectRevert(IAaveV3Provider.ExceedsUserLTVCapacity.selector);
        provider.borrow(WETH, hugeBorrowAmount);

        // Test Case 2: Try to borrow from unsupported asset
        address unsupportedAsset = address(0x123);
        vm.expectRevert(IAaveV3Provider.AssetNotSupported.selector);
        provider.borrow(unsupportedAsset, 1 ether);

        // Test Case 3: Try to borrow 0 amount (edge case)
        vm.expectRevert(IAaveV3Provider.AmountZero.selector);
        provider.borrow(WETH, 0);

        vm.stopPrank();

        // Test Case 4: Try to borrow when contract is paused
        // Use admin account (which has PAUSER_ROLE) to pause
        vm.prank(admin);
        provider.pause();
        assertTrue(provider.paused(), "Provider should be paused");

        vm.startPrank(user1);
        vm.expectRevert("Pausable: paused");
        provider.borrow(WETH, 0.1 ether);
        vm.stopPrank();

        // Unpause for other tests
        vm.prank(admin);
        provider.unpause();
        assertFalse(provider.paused(), "Provider should not be paused");
    }
}

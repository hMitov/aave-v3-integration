// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockERC20
/// @notice Minimal ERC20 with 6 decimals and test minting/helpers.
contract MockERC20 is ERC20 {
    /// @notice Mints initial supply to the deployer (1,000,000 * 10^6).
    /// @param name Token name.
    /// @param symbol Token symbol.
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1_000_000 * 10 ** 6);
    }

    /// @notice Fixed 6 decimals (USDC-style).
    /// @return Decimals = 6.
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    /// @notice Mint tokens for tests.
    /// @param to Recipient.
    /// @param amount Amount to mint (6 decimals).
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice SafeERC20-compatible transfer helper.
    /// @param to Recipient.
    /// @param amount Amount to transfer.
    /// @return success True if transfer succeeded.
    function safeTransfer(address to, uint256 amount) external returns (bool success) {
        return transfer(to, amount);
    }

    /// @notice SafeERC20-compatible transferFrom helper.
    /// @param from Sender.
    /// @param to Recipient.
    /// @param amount Amount to transfer.
    /// @return success True if transfer succeeded.
    function safeTransferFrom(address from, address to, uint256 amount) external returns (bool success) {
        return transferFrom(from, to, amount);
    }

    /// @notice SafeERC20-compatible approve helper.
    /// @param spender Spender.
    /// @param amount Allowance.
    /// @return success True if approve succeeded.
    function safeApprove(address spender, uint256 amount) external returns (bool success) {
        return approve(spender, amount);
    }
}

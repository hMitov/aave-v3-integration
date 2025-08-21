// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title MockAddressesProvider
/// @notice Minimal mock of an Aave-style AddressesProvider exposing only a price oracle getter.
/// @dev Useful for unit tests where contracts expect an AddressesProvider with `getPriceOracle()`.
contract MockAddressesProvider {
    /// @notice Address of the price oracle contract used by consumers in tests.
    address public priceOracle;

    /// @notice Deploy the mock with a preset price oracle address.
    /// @dev This mock does not validate the address and allows the zero address for flexibility in tests.
    /// @param _priceOracle The address to be returned by {getPriceOracle}.
    constructor(address _priceOracle) {
        priceOracle = _priceOracle;
    }

    /// @notice Returns the current configured price oracle address.
    /// @dev Mirrors the Aave interface shape (`IPoolAddressesProvider.getPriceOracle()`).
    /// @return The address of the price oracle.
    function getPriceOracle() external view returns (address) {
        return priceOracle;
    }
}

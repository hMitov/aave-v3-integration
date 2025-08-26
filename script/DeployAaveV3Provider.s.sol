// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {EnvLoader} from "./EnvLoader.s.sol";
import {AaveV3Provider} from "../src/AaveV3Provider.sol";
import {console} from "forge-std/console.sol";

/**
 * @title DeployAaveV3ProviderScript
 * @notice Deployment script for AaveV3Provider on Ethereum Sepolia testnet
 * @dev Deploys AaveV3Provider with Aave V3 pool configuration
 *      Requires: DEPLOYER_PRIVATE_KEY, ETHEREUM_SEPOLIA_POOL_ADDRESS env vars
 */
contract DeployAaveV3ProviderScript is EnvLoader {
    /// @notice Deployer's private key
    uint256 private privateKey;
    /// @notice Aave V3 pool address on Sepolia
    address private poolAddress;

    /**
     * @notice Execute deployment
     * @dev Deploys AaveV3Provider and logs deployment details
     */
    function run() external {
        loadEnvVars();

        vm.startBroadcast(privateKey);
        AaveV3Provider provider = new AaveV3Provider(poolAddress);
        vm.stopBroadcast();

        console.log("AaveV3Provider deployed at:", address(provider));
        console.log("Pool:", poolAddress);
        console.log("Deployer:", vm.addr(privateKey));
    }

    /**
     * @notice Load environment variables
     * @dev Sets privateKey and poolAddress from env vars
     */
    function loadEnvVars() internal override {
        privateKey = getEnvPrivateKey("DEPLOYER_PRIVATE_KEY");
        poolAddress = getEnvAddress("ETHEREUM_SEPOLIA_POOL_ADDRESS");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {LiquidityManager} from "../contracts/liquidity/LiquidityManager.sol";
import {ILiquidityManager} from "../contracts/liquidity/interfaces/ILiquidityManager.sol";
import {TransparentProxy} from "../contracts/proxy/TransparentProxy.sol";

contract DeployLiquidityManager is Script {
    function run() public returns (ILiquidityManager, LiquidityManager) {
        address pREWAAddress = vm.envAddress("PREWA_TOKEN_ADDRESS");
        address routerAddress = vm.envAddress("ROUTER_ADDRESS");
        address accessControlAddress = vm.envAddress("ACCESS_CONTROL_ADDRESS");
        address emergencyControllerAddress = vm.envAddress("EMERGENCY_CONTROLLER_ADDRESS");
        address oracleIntegrationAddress = vm.envAddress("ORACLE_INTEGRATION_ADDRESS");
        address priceGuardAddress = vm.envAddress("PRICE_GUARD_ADDRESS");
        address proxyAdminAddress = vm.envAddress("PROXY_ADMIN_ADDRESS");

        if (pREWAAddress == address(0) || routerAddress == address(0) || accessControlAddress == address(0) || emergencyControllerAddress == address(0) || oracleIntegrationAddress == address(0) || priceGuardAddress == address(0) || proxyAdminAddress == address(0)) {
            revert("A required address was not set in the .env file");
        }

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Implementation
        LiquidityManager implementation = new LiquidityManager();

        // 2. Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            LiquidityManager.initialize.selector,
            pREWAAddress, routerAddress,
            accessControlAddress, emergencyControllerAddress,
            oracleIntegrationAddress, priceGuardAddress
        );

        // 3. Deploy Proxy
        TransparentProxy proxy = new TransparentProxy(address(implementation), proxyAdminAddress, initData);

        vm.stopBroadcast();
        
        console.log("LiquidityManager Implementation deployed at:", address(implementation));
        console.log("LiquidityManager Proxy deployed at:", address(proxy));

        return (ILiquidityManager(address(proxy)), implementation);
    }
}
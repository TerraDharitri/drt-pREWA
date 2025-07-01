// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
// ... all your other imports for this file ...
import {PREWAToken} from "../contracts/core/pREWAToken.sol";
import {IpREWAToken} from "../contracts/core/interfaces/IpREWAToken.sol";
import {OracleIntegration} from "../contracts/oracle/OracleIntegration.sol";
import {PriceGuard} from "../contracts/security/PriceGuard.sol";
import {SecurityModule} from "../contracts/security/SecurityModule.sol";
import {LiquidityManager} from "../contracts/liquidity/LiquidityManager.sol";
import {ILiquidityManager} from "../contracts/liquidity/interfaces/ILiquidityManager.sol";
import {TransparentProxy} from "../contracts/proxy/TransparentProxy.sol";


contract DeployPhase2_Core is Script {

    // --- CONFIGURATION ---
    string constant PREWA_NAME = "pREWA Token";
    string constant PREWA_SYMBOL = "PREWA";
    uint8 constant PREWA_DECIMALS = 18;
    uint256 constant PREWA_INITIAL_SUPPLY = 1_000_000_000 * (10**18);
    uint256 constant PREWA_CAP = 2_000_000_000 * (10**18);
    uint256 constant ORACLE_STALENESS_THRESHOLD = 1 hours;
    
    struct DeployedPhase2Addresses {
        IpREWAToken pREWA;
        PREWAToken pREWATokenImplementation;
        OracleIntegration oracleIntegration;
        PriceGuard priceGuard;
        SecurityModule securityModule;
        SecurityModule securityModuleImplementation;
        ILiquidityManager liquidityManager;
        LiquidityManager liquidityManagerImplementation;
    }

    // --- State variables to hold addresses between function calls ---
    address private magsAddress;
    address private routerAddress;
    address private accessControlAddress;
    address private emergencyControllerAddress;
    address private proxyAdminAddress;

    function run() public returns (DeployedPhase2Addresses memory addresses) {
        // Load dependencies into state variables
        loadDependencies();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("--- Deploying Phase 2: Core Contracts ---");
        
        // --- FIX IS HERE ---
        // Declare local variables to receive the multiple return values
        IpREWAToken pREWA_local;
        PREWAToken pREWA_impl_local;
        SecurityModule sm_local;
        SecurityModule sm_impl_local;
        ILiquidityManager lm_local;
        LiquidityManager lm_impl_local;
        
        // Call helper functions and assign to local variables
        (pREWA_local, pREWA_impl_local) = deployPREWAToken();
        addresses.oracleIntegration = deployOracle();
        addresses.priceGuard = deployPriceGuard(address(addresses.oracleIntegration));
        (sm_local, sm_impl_local) = deploySecurityModule(address(addresses.oracleIntegration));
        (lm_local, lm_impl_local) = deployLiquidityManager(address(pREWA_local), address(addresses.priceGuard));
        
        // Now, assign the local variables to the struct members
        addresses.pREWA = pREWA_local;
        addresses.pREWATokenImplementation = pREWA_impl_local;
        addresses.securityModule = sm_local;
        addresses.securityModuleImplementation = sm_impl_local;
        addresses.liquidityManager = lm_local;
        addresses.liquidityManagerImplementation = lm_impl_local;
        // --- END OF FIX ---
        
        vm.stopBroadcast();
        return addresses;
    }

    function loadDependencies() internal {
        magsAddress = vm.envAddress("MAGS_ADDRESS");
        routerAddress = vm.envAddress("ROUTER_ADDRESS");
        accessControlAddress = vm.envAddress("ACCESS_CONTROL_ADDRESS");
        emergencyControllerAddress = vm.envAddress("EMERGENCY_CONTROLLER_ADDRESS");
        proxyAdminAddress = vm.envAddress("PROXY_ADMIN_ADDRESS");
    }

    function deployPREWAToken() internal returns (IpREWAToken, PREWAToken) {
        PREWAToken implementation = new PREWAToken();
        bytes memory pREWAInitData = abi.encodeWithSelector(
            PREWAToken.initialize.selector,
            PREWA_NAME, PREWA_SYMBOL, PREWA_DECIMALS,
            PREWA_INITIAL_SUPPLY, PREWA_CAP,
            accessControlAddress, emergencyControllerAddress, magsAddress
        );
        TransparentProxy pREWATokenProxy = new TransparentProxy(address(implementation), proxyAdminAddress, pREWAInitData);
        console.log("pREWA Deployed:", address(pREWATokenProxy));
        return (IpREWAToken(address(pREWATokenProxy)), implementation);
    }
    
    function deployOracle() internal returns (OracleIntegration) {
        OracleIntegration oracle = new OracleIntegration();
        oracle.initialize(magsAddress, ORACLE_STALENESS_THRESHOLD);
        console.log("OracleIntegration Deployed:", address(oracle));
        return oracle;
    }

    function deployPriceGuard(address oracleAddress) internal returns (PriceGuard) {
        PriceGuard priceGuard = new PriceGuard();
        priceGuard.initialize(magsAddress, oracleAddress, emergencyControllerAddress);
        console.log("PriceGuard Deployed:", address(priceGuard));
        return priceGuard;
    }

    function deploySecurityModule(address oracleAddress) internal returns (SecurityModule, SecurityModule) {
        SecurityModule implementation = new SecurityModule();
        bytes memory smInitData = abi.encodeWithSelector(
            SecurityModule.initialize.selector,
            accessControlAddress, emergencyControllerAddress, oracleAddress
        );
        TransparentProxy securityModuleProxy = new TransparentProxy(address(implementation), proxyAdminAddress, smInitData);
        console.log("SecurityModule Deployed:", address(securityModuleProxy));
        return (SecurityModule(address(securityModuleProxy)), implementation);
    }

    function deployLiquidityManager(address prewa, address pGuard) internal returns (ILiquidityManager, LiquidityManager) {
        LiquidityManager implementation = new LiquidityManager();
        bytes memory lmInitData = abi.encodeWithSelector(
            LiquidityManager.initialize.selector,
            prewa, routerAddress,
            accessControlAddress, emergencyControllerAddress,
            vm.envAddress("ORACLE_INTEGRATION_ADDRESS"), // Re-fetch or pass as arg
            pGuard
        );
        TransparentProxy liquidityManagerProxy = new TransparentProxy(address(implementation), proxyAdminAddress, lmInitData);
        console.log("LiquidityManager Deployed:", address(liquidityManagerProxy));
        return (ILiquidityManager(address(liquidityManagerProxy)), implementation);
    }
}
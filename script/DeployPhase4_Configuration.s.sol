// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Import all necessary contracts and interfaces
import {AccessControl} from "../contracts/access/AccessControl.sol";
import {ProxyAdmin} from "../contracts/proxy/ProxyAdmin.sol";
import {EmergencyController} from "../contracts/controllers/EmergencyController.sol";
import {ContractRegistry} from "../contracts/core/ContractRegistry.sol";
import {OracleIntegration} from "../contracts/oracle/OracleIntegration.sol";
import {ILiquidityManager} from "../contracts/liquidity/interfaces/ILiquidityManager.sol";
import {ITokenStaking} from "../contracts/core/interfaces/ITokenStaking.sol";
import {ILPStaking} from "../contracts/liquidity/interfaces/ILPStaking.sol";
import {IpREWAToken} from "../contracts/core/interfaces/IpREWAToken.sol";
import {SecurityModule} from "../contracts/security/SecurityModule.sol";
import {PriceGuard} from "../contracts/security/PriceGuard.sol";
import {VestingFactory} from "../contracts/vesting/VestingFactory.sol";

contract DeployPhase4_Configuration is Script {
    // --- State variables to avoid stack depth issues ---
    // Core Addresses
    address private magsAddress;
    address private edsAddress;

    // Phase 1 Contracts
    AccessControl private accessControl;
    ProxyAdmin private proxyAdmin;
    EmergencyController private emergencyController;
    ContractRegistry private contractRegistry;

    // Phase 2 Contracts
    IpREWAToken private pREWA;
    address private pREWAImplAddr;
    OracleIntegration private oracleIntegration;
    PriceGuard private priceGuard;
    SecurityModule private securityModule;
    address private securityModuleImplAddr;
    ILiquidityManager private liquidityManager;
    address private liquidityManagerImplAddr;

    // Phase 3 Contracts
    VestingFactory private vestingFactory;
    ITokenStaking private tokenStaking;
    address private tokenStakingImplAddr;
    ILPStaking private lpStaking;
    address private lpStakingImplAddr;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("--- Executing Phase 4: Post-Deployment Configuration ---");
        
        // Step 1: Load all addresses from env and cast to contract types
        _loadAndCastContracts();
        
        // Step 2: Execute configuration in modular, low-stack-pressure functions
        _grantRoles();
        _registerContractsInRegistry();
        _registerEmergencyAwareContracts();
        _addImplementationsToProxyAdmin();
        _linkDependencies();

        console.log("--- Configuration Complete ---");
        vm.stopBroadcast();
    }

    /**
     * @dev Loads all required addresses from the environment and casts them to
     * their contract types, storing them in state to avoid stack issues.
     */
    function _loadAndCastContracts() internal {
        console.log("Loading and casting contract addresses...");
        magsAddress = vm.envAddress("MAGS_ADDRESS");
        edsAddress = vm.envAddress("EDS_ADDRESS");

        // Phase 1
        accessControl = AccessControl(payable(vm.envAddress("ACCESS_CONTROL_ADDRESS")));
        proxyAdmin = ProxyAdmin(payable(vm.envAddress("PROXY_ADMIN_ADDRESS")));
        emergencyController = EmergencyController(payable(vm.envAddress("EMERGENCY_CONTROLLER_ADDRESS")));
        contractRegistry = ContractRegistry(payable(vm.envAddress("CONTRACT_REGISTRY_ADDRESS")));
        
        // Phase 2
        pREWA = IpREWAToken(vm.envAddress("PREWA_TOKEN_ADDRESS"));
        pREWAImplAddr = vm.envAddress("PREWA_IMPLEMENTATION_ADDRESS");
        oracleIntegration = OracleIntegration(payable(vm.envAddress("ORACLE_INTEGRATION_ADDRESS")));
        priceGuard = PriceGuard(payable(vm.envAddress("PRICE_GUARD_ADDRESS")));
        securityModule = SecurityModule(payable(vm.envAddress("SECURITY_MODULE_ADDRESS")));
        securityModuleImplAddr = vm.envAddress("SECURITY_MODULE_IMPL_ADDRESS");
        liquidityManager = ILiquidityManager(vm.envAddress("LIQUIDITY_MANAGER_ADDRESS"));
        liquidityManagerImplAddr = vm.envAddress("LIQUIDITY_MANAGER_IMPL_ADDRESS");
        
        // Phase 3
        vestingFactory = VestingFactory(payable(vm.envAddress("VESTING_FACTORY_ADDRESS")));
        tokenStaking = ITokenStaking(vm.envAddress("TOKEN_STAKING_ADDRESS"));
        tokenStakingImplAddr = vm.envAddress("TOKEN_STAKING_IMPL_ADDRESS");
        lpStaking = ILPStaking(vm.envAddress("LP_STAKING_ADDRESS"));
        lpStakingImplAddr = vm.envAddress("LP_STAKING_IMPL_ADDRESS");
    }

    function _grantRoles() internal {
        console.log("Granting administrative roles...");
        accessControl.grantRole(accessControl.UPGRADER_ROLE(), magsAddress);
        accessControl.grantRole(accessControl.PARAMETER_ROLE(), magsAddress);
        accessControl.grantRole(accessControl.PAUSER_ROLE(), magsAddress);
        accessControl.grantRole(accessControl.EMERGENCY_ROLE(), edsAddress);
    }

    function _registerContractsInRegistry() internal {
        console.log("Registering all contracts in ContractRegistry...");
        contractRegistry.registerContract("AccessControl", address(accessControl), "Core", "1.0.0");
        contractRegistry.registerContract("ProxyAdmin", address(proxyAdmin), "Core", "1.0.0");
        contractRegistry.registerContract("EmergencyController", address(emergencyController), "Core", "1.0.0");
        contractRegistry.registerContract("ContractRegistry", address(contractRegistry), "Core", "1.0.0");
        contractRegistry.registerContract("pREWAToken", address(pREWA), "Core", "1.0.0");
        contractRegistry.registerContract("OracleIntegration", address(oracleIntegration), "Core", "1.0.0");
        contractRegistry.registerContract("PriceGuard", address(priceGuard), "Security", "1.0.0");
        contractRegistry.registerContract("SecurityModule", address(securityModule), "Security", "1.0.0");
        contractRegistry.registerContract("VestingFactory", address(vestingFactory), "Vesting", "1.0.0");
        contractRegistry.registerContract("TokenStaking", address(tokenStaking), "Staking", "1.0.0");
        contractRegistry.registerContract("LPStaking", address(lpStaking), "Staking", "1.0.0");
        contractRegistry.registerContract("LiquidityManager", address(liquidityManager), "Liquidity", "1.0.0");
    }

    function _registerEmergencyAwareContracts() internal {
        console.log("Registering contracts with EmergencyController...");
        emergencyController.registerEmergencyAwareContract(address(pREWA));
        emergencyController.registerEmergencyAwareContract(address(priceGuard));
        emergencyController.registerEmergencyAwareContract(address(securityModule));
        emergencyController.registerEmergencyAwareContract(address(tokenStaking));
        emergencyController.registerEmergencyAwareContract(address(lpStaking));
        emergencyController.registerEmergencyAwareContract(address(liquidityManager));
    }

    function _addImplementationsToProxyAdmin() internal {
        console.log("Adding implementations to ProxyAdmin allowlist...");
        proxyAdmin.addValidImplementation(pREWAImplAddr);
        proxyAdmin.addValidImplementation(securityModuleImplAddr);
        proxyAdmin.addValidImplementation(liquidityManagerImplAddr);
        proxyAdmin.addValidImplementation(tokenStakingImplAddr);
        proxyAdmin.addValidImplementation(lpStakingImplAddr);
    }

    function _linkDependencies() internal {
        console.log("Linking remaining dependencies...");
        oracleIntegration.setLiquidityManagerAddress(address(liquidityManager));
    }
}
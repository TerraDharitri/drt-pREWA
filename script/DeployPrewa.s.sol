// script/DeployPrewa.s.sol

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Production Contracts and Interfaces
import {AccessControl} from "../contracts/access/AccessControl.sol";
import {ProxyAdmin} from "../contracts/proxy/ProxyAdmin.sol";
import {TransparentProxy} from "../contracts/proxy/TransparentProxy.sol";
import {EmergencyController} from "../contracts/controllers/EmergencyController.sol";
import {EmergencyTimelockController} from "../contracts/controllers/EmergencyTimelockController.sol";
import {ContractRegistry} from "../contracts/core/ContractRegistry.sol";
import {PREWAToken} from "../contracts/core/pREWAToken.sol";
import {IpREWAToken} from "../contracts/core/interfaces/IpREWAToken.sol";
import {OracleIntegration} from "../contracts/oracle/OracleIntegration.sol";
import {PriceGuard} from "../contracts/security/PriceGuard.sol";
import {SecurityModule} from "../contracts/security/SecurityModule.sol";
import {VestingImplementation} from "../contracts/vesting/VestingImplementation.sol";
import {VestingFactory} from "../contracts/vesting/VestingFactory.sol";
import {TokenStaking} from "../contracts/core/TokenStaking.sol";
import {ITokenStaking} from "../contracts/core/interfaces/ITokenStaking.sol";
import {LPStaking} from "../contracts/liquidity/LPStaking.sol";
import {ILPStaking} from "../contracts/liquidity/interfaces/ILPStaking.sol";
import {LiquidityManager} from "../contracts/liquidity/LiquidityManager.sol";
import {ILiquidityManager} from "../contracts/liquidity/interfaces/ILiquidityManager.sol";


/**
 * @title DeployPrewa Script
 * @author Rewa
 * @notice A Foundry script to deploy and configure the entire pREWA Protocol Suite.
 * @dev This script orchestrates a multi-phase deployment.
 *      Phase 1: Deploys foundational contracts (AccessControl, Emergency Controllers, ProxyAdmin, Registry).
 *      Phase 2: Deploys core protocol logic contracts behind transparent proxies.
 *      Phase 3: Deploys staking and vesting infrastructure.
 *      Phase 4: Performs critical post-deployment configuration to wire up the system.
 *      It relies on environment variables for critical addresses (multisigs, router).
 *      Run with: `forge script script/DeployPrewa.s.sol:DeployPrewa --rpc-url <your_rpc> --broadcast --verify`
 */
contract DeployPrewa is Script {

    // --- CONFIGURATION ---
    /// @notice The multisig address for high-level administrative control (e.g., Gnosis Safe).
    /// @dev Holds DEFAULT_ADMIN_ROLE, PROXY_ADMIN_ROLE, etc.
    address public MAGS_ADDRESS;
    /// @notice The multisig address for emergency response actions.
    /// @dev Holds EMERGENCY_ROLE. Should be a "hotter" multisig for faster response times.
    address public EDS_ADDRESS;
    /// @notice The address of the DEX Router (e.g., PancakeSwap V2 Router).
    address public ROUTER_ADDRESS;

    // pREWA Token Params
    string constant PREWA_NAME = "pREWA Token";
    string constant PREWA_SYMBOL = "PREWA";
    uint8 constant PREWA_DECIMALS = 18;
    uint256 constant PREWA_INITIAL_SUPPLY = 1_000_000_000 * (10**18);
    uint256 constant PREWA_CAP = 2_000_000_000 * (10**18);

    // ProxyAdmin Timelock
    uint256 constant PROXY_ADMIN_TIMELOCK = 2 days;

    // EmergencyController Params
    uint256 constant EC_L3_REQUIRED_APPROVALS = 1;
    uint256 constant EC_L3_TIMELOCK_DURATION = 1 days;

    // OracleIntegration Params
    uint256 constant ORACLE_STALENESS_THRESHOLD = 1 hours;

    // Staking Params
    uint256 constant TS_BASE_REWARD_RATE = 1000; // 10% APR
    uint256 constant TS_MIN_STAKE_DURATION = 1 days;
    uint256 constant TS_MAX_POSITIONS = 10;
    uint256 constant LPS_MIN_STAKE_DURATION = 1 days;

    // Deployed Contract Addresses
    AccessControl public accessControl;
    ProxyAdmin public proxyAdminMain;
    EmergencyController public emergencyController;
    EmergencyTimelockController public emergencyTimelockController;
    ContractRegistry public contractRegistry;
    PREWAToken public pREWATokenImplementation;
    TransparentProxy public pREWATokenProxy;
    IpREWAToken public pREWA;
    OracleIntegration public oracleIntegration;
    PriceGuard public priceGuard;
    SecurityModule public securityModuleImplementation;
    TransparentProxy public securityModuleProxy;
    SecurityModule public securityModule;
    VestingImplementation public vestingImplementationLogic;
    VestingFactory public vestingFactory;
    TokenStaking public tokenStakingImplementation;
    TransparentProxy public tokenStakingProxy;
    ITokenStaking public tokenStaking;
    LPStaking public lpStakingImplementation;
    TransparentProxy public lpStakingProxy;
    ILPStaking public lpStaking;
    LiquidityManager public liquidityManagerImplementation;
    TransparentProxy public liquidityManagerProxy;
    ILiquidityManager public liquidityManager;


    /**
     * @notice Main execution function for the deployment script.
     * @dev Orchestrates the deployment and configuration of all protocol contracts.
     */
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        MAGS_ADDRESS = vm.envAddress("MAGS_ADDRESS");
        EDS_ADDRESS = vm.envAddress("EDS_ADDRESS");
        ROUTER_ADDRESS = vm.envAddress("ROUTER_ADDRESS");

        // --- PRE-DEPLOYMENT CHECKS ---
        if (MAGS_ADDRESS == address(0)) {
            revert("MAGS_ADDRESS not set in .env file");
        }
        if (EDS_ADDRESS == address(0)) {
            revert("EDS_ADDRESS not set in .env file");
        }
         if (ROUTER_ADDRESS == address(0)) {
            revert("ROUTER_ADDRESS not set in .env file");
        }
        if (deployerPrivateKey == 0) {
            revert("PRIVATE_KEY not set in .env file");
        }

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deployer Address:", deployerAddress);
        console.log("MAGS Address (Admin Multisig):", MAGS_ADDRESS);
        console.log("EDS Address (Emergency Multisig):", EDS_ADDRESS);
        console.log("Router Address:", ROUTER_ADDRESS);

        // --- Phase 1: Foundation Contracts ---
        console.log("\nDeploying Foundation Contracts...");
        accessControl = new AccessControl();
        // The deployer initializes AccessControl, granting DEFAULT_ADMIN_ROLE to MAGS_ADDRESS.
        accessControl.initialize(MAGS_ADDRESS);

        emergencyTimelockController = new EmergencyTimelockController();
        emergencyTimelockController.initialize(address(accessControl), EC_L3_TIMELOCK_DURATION);

        emergencyController = new EmergencyController();
        emergencyController.initialize(
            address(accessControl),
            address(emergencyTimelockController),
            EC_L3_REQUIRED_APPROVALS,
            EC_L3_TIMELOCK_DURATION,
            MAGS_ADDRESS
        );

        proxyAdminMain = new ProxyAdmin();
        // The deployer initializes ProxyAdmin, granting PROXY_ADMIN_ROLE to MAGS_ADDRESS via AccessControl.
        proxyAdminMain.initialize(
            address(accessControl),
            address(emergencyController),
            PROXY_ADMIN_TIMELOCK,
            MAGS_ADDRESS
        );

        contractRegistry = new ContractRegistry();
        contractRegistry.initialize(MAGS_ADDRESS, address(accessControl));

        // --- Phase 2: Core Protocol Contracts ---
        console.log("\nDeploying Core Protocol Contracts...");

        pREWATokenImplementation = new PREWAToken();
        bytes memory pREWAInitData = abi.encodeWithSelector(
            PREWAToken.initialize.selector,
            PREWA_NAME, PREWA_SYMBOL, PREWA_DECIMALS,
            PREWA_INITIAL_SUPPLY, PREWA_CAP,
            address(accessControl),
            address(emergencyController), MAGS_ADDRESS
        );
        pREWATokenProxy = new TransparentProxy(address(pREWATokenImplementation), address(proxyAdminMain), pREWAInitData);
        pREWA = IpREWAToken(address(pREWATokenProxy));

        oracleIntegration = new OracleIntegration();
        oracleIntegration.initialize(MAGS_ADDRESS, ORACLE_STALENESS_THRESHOLD);

        priceGuard = new PriceGuard();
        priceGuard.initialize(MAGS_ADDRESS, address(oracleIntegration), address(emergencyController));

        securityModuleImplementation = new SecurityModule();
        bytes memory smInitData = abi.encodeWithSelector(
            SecurityModule.initialize.selector,
            address(accessControl), 
            address(emergencyController), 
            address(oracleIntegration)
        );
        securityModuleProxy = new TransparentProxy(address(securityModuleImplementation), address(proxyAdminMain), smInitData);
        securityModule = SecurityModule(address(securityModuleProxy));

        liquidityManagerImplementation = new LiquidityManager();
        bytes memory lmInitData = abi.encodeWithSelector(
            LiquidityManager.initialize.selector,
            address(pREWA), ROUTER_ADDRESS,
            address(accessControl), address(emergencyController),
            address(oracleIntegration), address(priceGuard)
        );
        liquidityManagerProxy = new TransparentProxy(address(liquidityManagerImplementation), address(proxyAdminMain), lmInitData);
        liquidityManager = ILiquidityManager(address(liquidityManagerProxy));

        // --- Phase 3: Staking & Vesting Infrastructure ---
        console.log("\nDeploying Staking & Vesting Infrastructure...");

        vestingImplementationLogic = new VestingImplementation();

        vestingFactory = new VestingFactory();
        vestingFactory.initialize(
            MAGS_ADDRESS, address(pREWA),
            address(vestingImplementationLogic), address(proxyAdminMain)
        );
        
        tokenStakingImplementation = new TokenStaking();
        bytes memory tsInitData = abi.encodeWithSelector(
            TokenStaking.initialize.selector,
            address(pREWA),
            address(accessControl), address(emergencyController),
            address(oracleIntegration), TS_BASE_REWARD_RATE,
            TS_MIN_STAKE_DURATION, MAGS_ADDRESS, TS_MAX_POSITIONS
        );
        tokenStakingProxy = new TransparentProxy(address(tokenStakingImplementation), address(proxyAdminMain), tsInitData);
        tokenStaking = ITokenStaking(address(tokenStakingProxy));

        lpStakingImplementation = new LPStaking();
        bytes memory lpsInitData = abi.encodeWithSelector(
            LPStaking.initialize.selector,
            address(pREWA),
            address(liquidityManager),
            MAGS_ADDRESS, LPS_MIN_STAKE_DURATION,
            address(accessControl), address(emergencyController)
        );
        lpStakingProxy = new TransparentProxy(address(lpStakingImplementation), address(proxyAdminMain), lpsInitData);
        lpStaking = ILPStaking(address(lpStakingProxy));

        // --- Phase 4: Post-Deployment Configuration ---
        _configureSystem();

        console.log("\n--- Core Deployment & Configuration Complete ---");
        _printAddresses();

        vm.stopBroadcast();
    }

    /**
     * @notice Performs all necessary post-deployment configurations to link the contracts together.
     * @dev This function grants roles, registers contracts in the registry and emergency controller,
     * and sets up dependencies. It should be called from within the main `run()` broadcast.
     */
    function _configureSystem() private {
        console.log("\n--- Phase 4: Starting Post-Deployment Configuration ---");

        // 1. Grant Roles
        console.log("Granting administrative roles...");
        accessControl.grantRole(accessControl.UPGRADER_ROLE(), MAGS_ADDRESS);
        accessControl.grantRole(accessControl.PARAMETER_ROLE(), MAGS_ADDRESS);
        accessControl.grantRole(accessControl.PAUSER_ROLE(), MAGS_ADDRESS);
        accessControl.grantRole(accessControl.EMERGENCY_ROLE(), EDS_ADDRESS);
        
        // 2. Register Contracts in the ContractRegistry
        console.log("Registering contracts in the ContractRegistry...");
        contractRegistry.registerContract("AccessControl", address(accessControl), "Core", "1.0.0");
        contractRegistry.registerContract("ProxyAdmin", address(proxyAdminMain), "Core", "1.0.0");
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

        // 3. Register EmergencyAware contracts with the EmergencyController
        console.log("Registering contracts with the EmergencyController...");
        emergencyController.registerEmergencyAwareContract(address(pREWA));
        emergencyController.registerEmergencyAwareContract(address(priceGuard));
        emergencyController.registerEmergencyAwareContract(address(securityModule));
        emergencyController.registerEmergencyAwareContract(address(tokenStaking));
        emergencyController.registerEmergencyAwareContract(address(lpStaking));
        emergencyController.registerEmergencyAwareContract(address(liquidityManager));

        // 4. Add valid implementations to the ProxyAdmin allowlist
        console.log("Adding implementations to ProxyAdmin allowlist...");
        proxyAdminMain.addValidImplementation(address(pREWATokenImplementation));
        proxyAdminMain.addValidImplementation(address(securityModuleImplementation));
        proxyAdminMain.addValidImplementation(address(liquidityManagerImplementation));
        proxyAdminMain.addValidImplementation(address(tokenStakingImplementation));
        proxyAdminMain.addValidImplementation(address(lpStakingImplementation));

        // 5. Link other contract dependencies
        console.log("Linking contract dependencies...");
        oracleIntegration.setLiquidityManagerAddress(address(liquidityManager));
    }

    /**
     * @notice Prints the addresses of all deployed contracts for verification and use in other scripts.
     */
    function _printAddresses() internal view {
        console.log("\n--- Addresses for Gnosis Safe Configuration & Verification ---");
        console.log("MAGS_ADDRESS (Target for Ownership/Admin):", MAGS_ADDRESS);
        console.log("EDS_ADDRESS (Target for EMERGENCY_ROLE):", EDS_ADDRESS);
        console.log("AccessControl_ADDRESS:", address(accessControl));
        console.log("ProxyAdmin_Main_ADDRESS:", address(proxyAdminMain));
        console.log("EmergencyController_ADDRESS:", address(emergencyController));
        console.log("EmergencyTimelockController_ADDRESS:", address(emergencyTimelockController));
        console.log("ContractRegistry_ADDRESS:", address(contractRegistry));
        console.log("pREWA_Token_Implementation_ADDRESS:", address(pREWATokenImplementation));
        console.log("pREWA_Token_PROXY_ADDRESS (pREWA):", address(pREWA));
        console.log("OracleIntegration_ADDRESS:", address(oracleIntegration));
        console.log("PriceGuard_ADDRESS:", address(priceGuard));
        console.log("SecurityModule_Implementation_ADDRESS:", address(securityModuleImplementation));
        console.log("SecurityModule_PROXY_ADDRESS (securityModule):", address(securityModule));
        console.log("LiquidityManager_Implementation_ADDRESS:", address(liquidityManagerImplementation));
        console.log("LiquidityManager_PROXY_ADDRESS (liquidityManager):", address(liquidityManager));
        console.log("VestingImplementation_Logic_ADDRESS:", address(vestingImplementationLogic));
        console.log("VestingFactory_ADDRESS:", address(vestingFactory));
        console.log("TokenStaking_Implementation_ADDRESS:", address(tokenStakingImplementation));
        console.log("TokenStaking_PROXY_ADDRESS (tokenStaking):", address(tokenStaking));
        console.log("LPStaking_Implementation_ADDRESS:", address(lpStakingImplementation));
        console.log("LPStaking_PROXY_ADDRESS (lpStaking):", address(lpStaking));
    }
}
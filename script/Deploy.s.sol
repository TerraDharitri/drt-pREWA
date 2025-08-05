// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Import all necessary contract interfaces and implementations
import {AccessControl} from "../contracts/access/AccessControl.sol";
import {ContractRegistry} from "../contracts/core/ContractRegistry.sol";
import {EmergencyController} from "../contracts/controllers/EmergencyController.sol";
import {EmergencyTimelockController} from "../contracts/controllers/EmergencyTimelockController.sol";
import {LiquidityManager} from "../contracts/liquidity/LiquidityManager.sol";
import {LPStaking} from "../contracts/liquidity/LPStaking.sol";
import {OracleIntegration} from "../contracts/oracle/OracleIntegration.sol";
import {PREWAToken} from "../contracts/core/pREWAToken.sol";
import {PriceGuard} from "../contracts/security/PriceGuard.sol";
import {ProxyAdmin} from "../contracts/proxy/ProxyAdmin.sol";
import {SecurityModule} from "../contracts/security/SecurityModule.sol";
import {TokenStaking} from "../contracts/core/TokenStaking.sol";
import {VestingFactory} from "../contracts/vesting/VestingFactory.sol";
import {VestingImplementation} from "../contracts/vesting/VestingImplementation.sol";
// import {DonationTrackerUpgradeable} from "../contracts/donate/DonationTrackerUpgradeable.sol"; // De-scoped for now
import {TransparentProxy} from "../contracts/proxy/TransparentProxy.sol";
import {Constants} from "../contracts/libraries/Constants.sol";

contract DeployedContracts {
    // Deployed proxy addresses
    address payable public accessControl;
    address payable public contractRegistry;
    address payable public emergencyController;
    address payable public emergencyTimelockController;
    address payable public liquidityManager;
    address payable public lpStaking;
    address payable public oracleIntegration;
    address payable public pREWA;
    address payable public priceGuard;
    address payable public proxyAdmin;
    address payable public securityModule;
    address payable public tokenStaking;
    address payable public vestingFactory;
    address public vestingImplementation;
    // address payable public donationTracker; // De-scoped for now
}

contract DeployScript is Script, DeployedContracts {
    // =================================
    //       Configuration
    // =================================
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    uint256 tempAdminPrivateKey = vm.envUint("TEMP_ADMIN_PRIVATE_KEY");

    address finalAdmin = vm.envAddress("FINAL_ADMIN_ADDRESS");
    address treasury = vm.envAddress("TREASURY_ADDRESS");
    address recoveryAdmin = vm.envAddress("RECOVERY_ADMIN_ADDRESS");
    address pancakeRouter = vm.envAddress("PANCAKESWAP_V2_ROUTER");
    address wbnb = vm.envAddress("WBNB_ADDRESS");
    address usdt = vm.envAddress("USDT_ADDRESS");

    // <<< REFACTOR: Store logic addresses as state variables to avoid stack depth issues >>>
    address internal paLogic;
    address internal acLogic;
    address internal crLogic;
    address internal ecLogic;
    address internal etcLogic;
    address internal pREWALogic;
    address internal oracleLogic;
    address internal pgLogic;
    address internal smLogic;
    address internal lmLogic;
    address internal tsLogic;
    address internal lpsLogic;
    address internal vfLogic;
    // address internal dtLogic; // De-scoped for now

    function run() external {
        address deployer = vm.addr(deployerPrivateKey);
        address tempAdmin = vm.addr(tempAdminPrivateKey);

        // --- PHASE 1: Deploy All Logic Contracts ---
        vm.startBroadcast(deployerPrivateKey);
        console.log("Phase 1: Deploying all logic contracts...");
        _deployLogicContracts();
        vm.stopBroadcast();
        
        // --- PHASE 2: Deploy & Initialize Proxies with a Temporary Admin ---
        console.log("\nPhase 2: Deploying proxies and initializing contracts...");
        _deployAndInitializeProxies(deployer, tempAdmin);

        // --- PHASE 3: Wire Dependencies and Grant Roles (as Deployer) ---
        vm.startBroadcast(deployerPrivateKey);
        console.log("\nPhase 3: Wiring dependencies and granting roles...");
        _wireAndConfigureContracts(deployer);

        // --- PHASE 4: Perform Initial Protocol Setup (as Deployer) ---
        console.log("\nPhase 4: Performing initial protocol setup...");
        _initialSetup();

        // --- PHASE 5: Register Contracts in the Registry (as Deployer) ---
        console.log("\nPhase 5: Registering contracts in ContractRegistry...");
        _registerAllContracts();
        vm.stopBroadcast();

        // --- PHASE 6: Transfer Proxy Adminship (as Temp Admin) ---
        console.log("\nPhase 6: Transferring final proxy admin ownership...");
        _transferProxyAdmins(tempAdminPrivateKey);

        // --- PHASE 7: Transfer Final Ownership & Renounce Roles (as Deployer) ---
        vm.startBroadcast(deployerPrivateKey);
        console.log("\nPhase 7: Transferring final ownership and renouncing roles...");
        _transferFinalOwnerships();
        vm.stopBroadcast();

        console.log(unicode"\n✅ Deployment and setup complete!");
    }

    // <<< REFACTOR: This function now assigns to state variables instead of returning values >>>
    function _deployLogicContracts() internal {
        acLogic = address(new AccessControl());
        crLogic = address(new ContractRegistry());
        paLogic = address(new ProxyAdmin());
        etcLogic = address(new EmergencyTimelockController());
        ecLogic = address(new EmergencyController());
        vestingImplementation = address(new VestingImplementation());
        console.log("  - Core logic contracts deployed.");

        pREWALogic = address(new PREWAToken());
        oracleLogic = address(new OracleIntegration());
        pgLogic = address(new PriceGuard());
        smLogic = address(new SecurityModule());
        lmLogic = address(new LiquidityManager());
        tsLogic = address(new TokenStaking());
        lpsLogic = address(new LPStaking());
        vfLogic = address(new VestingFactory());
        // dtLogic = address(new DonationTrackerUpgradeable()); // De-scoped for now
        console.log("  - Module logic contracts deployed.");
    }

    // <<< REFACTOR: This function now has a simple signature and reads logic addresses from state >>>
    function _deployAndInitializeProxies(address deployer, address tempAdmin) internal {
        vm.startBroadcast(deployerPrivateKey);
        console.log("  - Using temporary admin for proxy setup:", tempAdmin);

        accessControl = payable(address(new TransparentProxy(acLogic, tempAdmin, abi.encodeWithSelector(AccessControl.initialize.selector, deployer))));
        console.log("  - AccessControl (proxy) deployed at:", accessControl);

        emergencyTimelockController = payable(address(new TransparentProxy(etcLogic, tempAdmin, abi.encodeWithSelector(EmergencyTimelockController.initialize.selector, accessControl, Constants.MIN_TIMELOCK_DURATION))));
        console.log("  - EmergencyTimelockController (proxy) deployed at:", emergencyTimelockController);

        emergencyController = payable(address(new TransparentProxy(ecLogic, tempAdmin, abi.encodeWithSelector(EmergencyController.initialize.selector, accessControl, emergencyTimelockController, 2, Constants.MIN_TIMELOCK_DURATION, recoveryAdmin))));
        console.log("  - EmergencyController (proxy) deployed at:", emergencyController);

        proxyAdmin = payable(address(new TransparentProxy(paLogic, tempAdmin, bytes(""))));
        console.log("  - ProxyAdmin (proxy) deployed at:", proxyAdmin);
        
        AccessControl(accessControl).grantRole(AccessControl(accessControl).DEFAULT_ADMIN_ROLE(), proxyAdmin);
        console.log("  - Granted ProxyAdmin contract the DEFAULT_ADMIN_ROLE.");

        ProxyAdmin(proxyAdmin).initialize(accessControl, emergencyController, Constants.MIN_TIMELOCK_DURATION, deployer);
        console.log("  - ProxyAdmin logic initialized.");

        contractRegistry = payable(address(new TransparentProxy(crLogic, proxyAdmin, abi.encodeWithSelector(ContractRegistry.initialize.selector, deployer, accessControl))));
        console.log("  - ContractRegistry (proxy) deployed at:", contractRegistry);

        pREWA = payable(address(new TransparentProxy(pREWALogic, proxyAdmin, abi.encodeWithSelector(PREWAToken.initialize.selector, "pREWA Token", "pREWA", 18, 1e9 * 1e18, accessControl, emergencyController, deployer))));
        console.log("  - pREWA (proxy) deployed at:", pREWA);

        oracleIntegration = payable(address(new TransparentProxy(oracleLogic, proxyAdmin, abi.encodeWithSelector(OracleIntegration.initialize.selector, deployer, Constants.ORACLE_MAX_STALENESS))));
        console.log("  - OracleIntegration (proxy) deployed at:", oracleIntegration);
        
        priceGuard = payable(address(new TransparentProxy(pgLogic, proxyAdmin, abi.encodeWithSelector(PriceGuard.initialize.selector, deployer, oracleIntegration, emergencyController))));
        console.log("  - PriceGuard (proxy) deployed at:", priceGuard);

        securityModule = payable(address(new TransparentProxy(smLogic, proxyAdmin, abi.encodeWithSelector(SecurityModule.initialize.selector, accessControl, emergencyController, oracleIntegration))));
        console.log("  - SecurityModule (proxy) deployed at:", securityModule);

        liquidityManager = payable(address(new TransparentProxy(lmLogic, proxyAdmin, abi.encodeWithSelector(LiquidityManager.initialize.selector, pREWA, pancakeRouter, accessControl, emergencyController, oracleIntegration, priceGuard))));
        console.log("  - LiquidityManager (proxy) deployed at:", liquidityManager);

        tokenStaking = payable(address(new TransparentProxy(tsLogic, proxyAdmin, abi.encodeWithSelector(TokenStaking.initialize.selector, pREWA, accessControl, emergencyController, oracleIntegration, 1000, Constants.MIN_STAKING_DURATION, deployer, 10))));
        console.log("  - TokenStaking (proxy) deployed at:", tokenStaking);

        lpStaking = payable(address(new TransparentProxy(lpsLogic, proxyAdmin, abi.encodeWithSelector(LPStaking.initialize.selector, pREWA, liquidityManager, deployer, Constants.MIN_STAKING_DURATION, accessControl, emergencyController))));
        console.log("  - LPStaking (proxy) deployed at:", lpStaking);

        vestingFactory = payable(address(new TransparentProxy(vfLogic, proxyAdmin, abi.encodeWithSelector(VestingFactory.initialize.selector, deployer, pREWA, vestingImplementation, proxyAdmin))));
        console.log("  - VestingFactory (proxy) deployed at:", vestingFactory);

        // donationTracker = payable(address(new TransparentProxy(dtLogic, proxyAdmin, abi.encodeWithSelector(DonationTrackerUpgradeable.initialize.selector, accessControl, treasury, new address[](0), new string[](0), new uint8[](0))))); // De-scoped for now
        // console.log("  - DonationTracker (proxy) deployed at:", donationTracker); // De-scoped for now

        vm.stopBroadcast();
    }

    function _wireAndConfigureContracts(address deployer) internal {
        AccessControl ac = AccessControl(accessControl);
        
        console.log("  - Granting essential system roles...");
        ac.grantRole(ac.UPGRADER_ROLE(), address(proxyAdmin));
        ac.grantRole(ac.PROXY_ADMIN_ROLE(), address(proxyAdmin));
        ac.grantRole(ac.EMERGENCY_ROLE(), address(emergencyController));
        ac.grantRole(ac.EMERGENCY_ROLE(), deployer);
        ac.grantRole(ac.PAUSER_ROLE(), deployer);
        ac.grantRole(ac.PARAMETER_ROLE(), deployer);
        ac.grantRole(ac.MINTER_ROLE(), deployer);
        
        // --- DonationTracker Roles De-scoped ---

        console.log("  - Setting inter-contract dependencies...");
        OracleIntegration(oracleIntegration).setLiquidityManagerAddress(liquidityManager);
        
        console.log("  - Registering all emergency-aware contracts with the controller...");
        EmergencyController ec = EmergencyController(emergencyController);
        ec.registerEmergencyAwareContract(pREWA);
        ec.registerEmergencyAwareContract(proxyAdmin);
        ec.registerEmergencyAwareContract(priceGuard);
        ec.registerEmergencyAwareContract(securityModule);
        ec.registerEmergencyAwareContract(liquidityManager);
        ec.registerEmergencyAwareContract(tokenStaking);
        ec.registerEmergencyAwareContract(lpStaking);
    }
    
    function _initialSetup() internal {
        console.log("  - Funding staking contracts with pREWA...");
        PREWAToken(pREWA).transfer(tokenStaking, 20_000_000 * 1e18);
        PREWAToken(pREWA).transfer(lpStaking, 20_000_000 * 1e18);
        
        console.log("  - Adding 4 initial staking tiers to TokenStaking...");
        TokenStaking(tokenStaking).addTier(90 days, 10000, 1500);
        TokenStaking(tokenStaking).addTier(180 days, 12500, 1200);
        TokenStaking(tokenStaking).addTier(270 days, 15000, 1000);
        TokenStaking(tokenStaking).addTier(365 days, 20000, 800);
        
        console.log("  - Adding 4 initial staking tiers to LPStaking...");
        LPStaking(lpStaking).addTier(90 days, 10000, 1500);
        LPStaking(lpStaking).addTier(180 days, 12500, 1200);
        LPStaking(lpStaking).addTier(270 days, 15000, 1000);
        LPStaking(lpStaking).addTier(365 days, 20000, 800);

        console.log("  - Registering pREWA/WBNB and pREWA/USDT pairs in LiquidityManager...");
        LiquidityManager(liquidityManager).registerPair(wbnb);
        LiquidityManager(liquidityManager).registerPair(usdt);
    }

    function _registerAllContracts() internal {
        ContractRegistry cr = ContractRegistry(contractRegistry);
        cr.registerContract("AccessControl", accessControl, "Core", "1.0.0");
        cr.registerContract("ProxyAdmin", proxyAdmin, "Core", "1.0.0");
        cr.registerContract("EmergencyTimelockController", emergencyTimelockController, "Core", "1.0.0");
        cr.registerContract("EmergencyController", emergencyController, "Core", "1.0.0");
        cr.registerContract("ContractRegistry", contractRegistry, "Core", "1.0.0");
        cr.registerContract("pREWAToken", pREWA, "Token", "1.0.0");
        cr.registerContract("OracleIntegration", oracleIntegration, "Oracle", "1.0.0");
        cr.registerContract("PriceGuard", priceGuard, "Security", "1.0.0");
        cr.registerContract("SecurityModule", securityModule, "Security", "1.0.0");
        cr.registerContract("LiquidityManager", liquidityManager, "DeFi", "1.0.0");
        cr.registerContract("TokenStaking", tokenStaking, "Staking", "1.0.0");
        cr.registerContract("LPStaking", lpStaking, "Staking", "1.0.0");
        cr.registerContract("VestingFactory", vestingFactory, "Vesting", "1.0.0");
        cr.registerContract("VestingImplementation", vestingImplementation, "Vesting", "1.0.0");
        // cr.registerContract("DonationTracker", donationTracker, "Utility", "1.0.0"); // De-scoped
    }

    function _transferProxyAdmins(uint256 tempAdminPk) internal {
        vm.startBroadcast(tempAdminPk);
        console.log("  - Temporary admin is now transferring ownership of core proxies...");
        TransparentProxy(accessControl).changeAdmin(proxyAdmin);
        TransparentProxy(emergencyTimelockController).changeAdmin(proxyAdmin);
        TransparentProxy(emergencyController).changeAdmin(proxyAdmin);
        TransparentProxy(proxyAdmin).changeAdmin(proxyAdmin);
        console.log("  - Core proxy ownership transferred to final ProxyAdmin.");
        vm.stopBroadcast();
    }

    function _transferFinalOwnerships() internal {
        AccessControl ac = AccessControl(accessControl);
        
        console.log("  - Transferring Ownable contracts ownership to finalAdmin...");
        ContractRegistry(contractRegistry).transferOwnership(finalAdmin);
        OracleIntegration(oracleIntegration).transferOwnership(finalAdmin);
        PriceGuard(priceGuard).transferOwnership(finalAdmin);
        TokenStaking(tokenStaking).transferOwnership(finalAdmin);
        LPStaking(lpStaking).transferOwnership(finalAdmin);
        VestingFactory(vestingFactory).transferOwnership(finalAdmin);
        PREWAToken(pREWA).transferOwnership(finalAdmin);
        
        console.log("  - Granting all operational roles to finalAdmin...");
        ac.grantRole(ac.EMERGENCY_ROLE(), finalAdmin);
        ac.grantRole(ac.PAUSER_ROLE(), finalAdmin);
        ac.grantRole(ac.PARAMETER_ROLE(), finalAdmin);
        ac.grantRole(ac.MINTER_ROLE(), finalAdmin);

        // --- DonationTracker Roles De-scoped ---

        console.log("  - Transferring ultimate system control to finalAdmin and renouncing deployer's admin role...");
        ac.grantRole(ac.DEFAULT_ADMIN_ROLE(), finalAdmin);
        ac.renounceRole(ac.DEFAULT_ADMIN_ROLE());
    }
}
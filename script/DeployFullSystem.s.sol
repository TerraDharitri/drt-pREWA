// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

// Import LOGIC contracts and interfaces
import "../contracts/access/AccessControl.sol";
import "../contracts/controllers/EmergencyController.sol";
import "../contracts/controllers/EmergencyTimelockController.sol";
import "../contracts/proxy/ProxyAdmin.sol";
import "../contracts/core/ContractRegistry.sol";
import "../contracts/oracle/OracleIntegration.sol";
import "../contracts/core/pREWAToken.sol";
import "../contracts/security/PriceGuard.sol";
import "../contracts/security/SecurityModule.sol";
import "../contracts/vesting/VestingImplementation.sol";
import "../contracts/vesting/VestingFactory.sol";
import "../contracts/core/TokenStaking.sol";
import "../contracts/liquidity/LiquidityManager.sol";
import "../contracts/liquidity/LPStaking.sol";
import "../contracts/proxy/TransparentProxy.sol";

contract DeployFullSystem is Script {
    address internal constant PANCAKE_ROUTER_V2_TESTNET = 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3;
    
    // ===> CORRECTED LOCATION FOR THE CONSTANT <===
    address internal constant USDT_TESTNET = 0x337610d27c682E347C9cD60BD4b3b107C9d34dDd;

    function run() external {
        // --- 0. SETUP ---
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address adminAddress = vm.envAddress("ADMIN_ADDRESS");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        // Create a temporary wallet for the "admin dance" required by Transparent Proxies
        Vm.Wallet memory temporaryAdmin = vm.createWallet("tempAdmin");
        
        console.log("Deployer Address:", deployerAddress);
        console.log("Final Admin Address (Multisig):", adminAddress);
        console.log("Temporary Admin Address:", temporaryAdmin.addr);

        vm.startBroadcast(deployerPrivateKey);

        // Fund the temporary admin wallet so it can pay gas fees later
        uint256 fundingAmount = 0.1 ether; 
        (bool success, ) = payable(temporaryAdmin.addr).call{value: fundingAmount}("");
        require(success, "Failed to fund temporary admin");
        console.log("Funded temporary admin with 0.1 tBNB");


        // --- PHASE 1: Deploy Foundational Contracts & Controllers ---
        console.log("\n--- Phase 1: Deploying Foundational Contracts & Controllers ---");

        // 1.1 AccessControl. The deployer is the temporary proxy admin and initial role admin.
        AccessControl acLogic = new AccessControl();
        bytes memory acInitData = abi.encodeWithSelector(AccessControl.initialize.selector, deployerAddress);
        TransparentProxy acProxy = new TransparentProxy(address(acLogic), deployerAddress, acInitData);
        AccessControl accessControl = AccessControl(address(acProxy));
        console.log("AccessControl (Proxy) deployed at:", address(accessControl));

        // 1.2 Deploy other foundational proxies, also with deployer as temporary admin.
        EmergencyTimelockController etcLogic = new EmergencyTimelockController();
        bytes memory etcInitData = abi.encodeWithSelector(EmergencyTimelockController.initialize.selector, address(accessControl), 1 days);
        TransparentProxy etcProxy = new TransparentProxy(address(etcLogic), deployerAddress, etcInitData);
        EmergencyTimelockController timelockController = EmergencyTimelockController(address(etcProxy));
        console.log("EmergencyTimelockController (Proxy) deployed at:", address(timelockController));

        EmergencyController ecLogic = new EmergencyController();
        bytes memory ecInitData = abi.encodeWithSelector(EmergencyController.initialize.selector, address(accessControl), address(timelockController), 2, 3 days, adminAddress);
        TransparentProxy ecProxy = new TransparentProxy(address(ecLogic), deployerAddress, ecInitData);
        EmergencyController emergencyController = EmergencyController(address(ecProxy));
        console.log("EmergencyController (Proxy) deployed at:", address(emergencyController));
        
        // 1.3 ProxyAdmin (Uninitialized)
        ProxyAdmin proxyAdminLogic = new ProxyAdmin();
        TransparentProxy proxyForProxyAdmin = new TransparentProxy(address(proxyAdminLogic), deployerAddress, "");
        ProxyAdmin proxyAdmin = ProxyAdmin(address(proxyForProxyAdmin));
        console.log("ProxyAdmin (Proxy, Uninitialized) deployed at:", address(proxyAdmin));

        // --- PHASE 2: Initialize ProxyAdmin with Permissions Workaround (The Admin Dance) ---
        console.log("\n--- Phase 2: Securely Initializing ProxyAdmin ---");
        
        // Transfer proxy adminship to temp admin. This is required so the deployer can call grantRole on AccessControl.
        acProxy.changeAdmin(temporaryAdmin.addr);
        proxyForProxyAdmin.changeAdmin(temporaryAdmin.addr);
        console.log("Temporarily changed AccessControl and ProxyAdmin admins to:", temporaryAdmin.addr);

        // Grant ProxyAdmin the DEFAULT_ADMIN_ROLE (required by ProxyAdmin.initialize)
        accessControl.grantRole(accessControl.DEFAULT_ADMIN_ROLE(), address(proxyAdmin));
        console.log("Granted DEFAULT_ADMIN_ROLE to ProxyAdmin contract.");

        // Initialize ProxyAdmin (Deployer can call this because it's no longer the proxy admin)
        proxyAdmin.initialize(address(accessControl), address(emergencyController), 1 days, adminAddress);
        console.log("ProxyAdmin Initialized.");
        
        // Revoke the temporary DEFAULT_ADMIN_ROLE from the ProxyAdmin contract itself
        accessControl.revokeRole(accessControl.DEFAULT_ADMIN_ROLE(), address(proxyAdmin));
        console.log("Revoked DEFAULT_ADMIN_ROLE from ProxyAdmin contract.");

        // --- PHASE 3: Transfer All Proxy Ownership to ProxyAdmin ---
        console.log("\n--- Phase 3: Finalizing Proxy Ownership ---");
        
        // Switch broadcasting identity to the funded temporary admin
        vm.stopBroadcast(); 
        vm.startBroadcast(temporaryAdmin.privateKey); 

        // Use temporary admin's power to transfer AccessControl and ProxyAdmin itself to ProxyAdmin
        acProxy.changeAdmin(address(proxyAdmin));
        proxyForProxyAdmin.changeAdmin(address(proxyAdmin));

        // Switch back to the main deployer
        vm.stopBroadcast(); 
        vm.startBroadcast(deployerPrivateKey); 
        
        // Transfer the remaining controllers owned by the deployer
        etcProxy.changeAdmin(address(proxyAdmin));
        ecProxy.changeAdmin(address(proxyAdmin));
        console.log("All foundational proxy ownership transferred to ProxyAdmin.");

        // --- PHASE 4: Deploy the rest of the ecosystem ---
        console.log("\n--- Phase 4: Deploying Application-Level Contracts ---");
        
        ContractRegistry crLogic = new ContractRegistry();
        bytes memory crInitData = abi.encodeWithSelector(ContractRegistry.initialize.selector, adminAddress, address(accessControl));
        TransparentProxy crProxy = new TransparentProxy(address(crLogic), address(proxyAdmin), crInitData);
        ContractRegistry contractRegistry = ContractRegistry(address(crProxy));
        console.log("ContractRegistry (Proxy) deployed at:", address(contractRegistry));
        
        OracleIntegration oiLogic = new OracleIntegration();
        bytes memory oiInitData = abi.encodeWithSelector(OracleIntegration.initialize.selector, adminAddress, 1 hours);
        TransparentProxy oiProxy = new TransparentProxy(address(oiLogic), address(proxyAdmin), oiInitData);
        OracleIntegration oracleIntegration = OracleIntegration(address(oiProxy));
        console.log("OracleIntegration (Proxy) deployed at:", address(oracleIntegration));

        PREWAToken pRewaLogic = new PREWAToken();
        // --- CORRECTED pREWAToken INITIALIZATION ---
        // The `cap` parameter (5th arg) is removed, and the initial supply is now the full 1B tokens, sent to the DEPLOYER.
        bytes memory pRewaInitData = abi.encodeWithSelector(
            PREWAToken.initialize.selector,
            "Dharitri preREWA",             // name_
            "pREWA",                        // symbol_
            18,                             // decimals_
            1_000_000_000 * 1e18,           // initialSupply_
            address(accessControl),         // accessControlAddress_
            address(emergencyController),   // emergencyControllerAddress_
            deployerAddress                 // admin_ (receives initial supply)
        );
        TransparentProxy pRewaProxy = new TransparentProxy(address(pRewaLogic), address(proxyAdmin), pRewaInitData);
        PREWAToken pREWAToken = PREWAToken(address(pRewaProxy));
        console.log("pREWAToken (Proxy) deployed at:", address(pREWAToken));

        PriceGuard pgLogic = new PriceGuard();
        bytes memory pgInitData = abi.encodeWithSelector(PriceGuard.initialize.selector, adminAddress, address(oracleIntegration), address(emergencyController));
        TransparentProxy pgProxy = new TransparentProxy(address(pgLogic), address(proxyAdmin), pgInitData);
        PriceGuard priceGuard = PriceGuard(address(pgProxy));
        console.log("PriceGuard (Proxy) deployed at:", address(priceGuard));

        SecurityModule smLogic = new SecurityModule();
        bytes memory smInitData = abi.encodeWithSelector(SecurityModule.initialize.selector, address(accessControl), address(emergencyController), address(oracleIntegration));
        TransparentProxy smProxy = new TransparentProxy(address(smLogic), address(proxyAdmin), smInitData);
        SecurityModule securityModule = SecurityModule(address(smProxy));
        console.log("SecurityModule (Proxy) deployed at:", address(securityModule));

        VestingImplementation vestingImplementation = new VestingImplementation();
        console.log("VestingImplementation (Logic only) deployed at:", address(vestingImplementation));

        VestingFactory vfLogic = new VestingFactory();
        bytes memory vfInitData = abi.encodeWithSelector(VestingFactory.initialize.selector, adminAddress, address(pREWAToken), address(vestingImplementation), address(proxyAdmin));
        TransparentProxy vfProxy = new TransparentProxy(address(vfLogic), address(proxyAdmin), vfInitData);
        VestingFactory vestingFactory = VestingFactory(address(vfProxy));
        console.log("VestingFactory (Proxy) deployed at:", address(vestingFactory));
        
        TokenStaking tsLogic = new TokenStaking();
        bytes memory tsInitData = abi.encodeWithSelector(TokenStaking.initialize.selector, address(pREWAToken), address(accessControl), address(emergencyController), address(oracleIntegration), 1000, 1 days, adminAddress, 10);
        TransparentProxy tsProxy = new TransparentProxy(address(tsLogic), address(proxyAdmin), tsInitData);
        TokenStaking tokenStaking = TokenStaking(address(tsProxy));
        console.log("TokenStaking (Proxy) deployed at:", address(tokenStaking));
        
        LiquidityManager lmLogic = new LiquidityManager();
        bytes memory lmInitData = abi.encodeWithSelector(LiquidityManager.initialize.selector, address(pREWAToken), PANCAKE_ROUTER_V2_TESTNET, address(accessControl), address(emergencyController), address(oracleIntegration), address(priceGuard));
        TransparentProxy lmProxy = new TransparentProxy(address(lmLogic), address(proxyAdmin), lmInitData);
        LiquidityManager liquidityManager = LiquidityManager(payable(address(lmProxy)));
        console.log("LiquidityManager (Proxy) deployed at:", address(liquidityManager));

        LPStaking lpsLogic = new LPStaking();
        bytes memory lpsInitData = abi.encodeWithSelector(LPStaking.initialize.selector, address(pREWAToken), address(liquidityManager), adminAddress, 1 days, address(accessControl), address(emergencyController));
        TransparentProxy lpsProxy = new TransparentProxy(address(lpsLogic), address(proxyAdmin), lpsInitData);
        LPStaking lpStaking = LPStaking(address(lpsProxy));
        console.log("LPStaking (Proxy) deployed at:", address(lpStaking));

        // --- PHASE 5: FINAL WIRING AND CONFIGURATION ---
        console.log("\n--- Phase 5: Granting Roles, Wiring, and Funding ---");

        accessControl.grantRole(accessControl.PARAMETER_ROLE(), adminAddress);
        accessControl.grantRole(accessControl.PAUSER_ROLE(), adminAddress);
        accessControl.grantRole(accessControl.UPGRADER_ROLE(), adminAddress);
        accessControl.grantRole(accessControl.EMERGENCY_ROLE(), adminAddress);
        
        // At this point, the deployer has DEFAULT_ADMIN_ROLE, which is the admin of PARAMETER_ROLE.
        // This allows the deployer to call `registerPair` before renouncing its ultimate control.
        console.log("Creating pREWA/USDT Liquidity Pool Pair on PancakeSwap Testnet...");
        liquidityManager.registerPair(USDT_TESTNET);
        console.log("pREWA/USDT pair registration call executed.");

        // Final transfer of ultimate control (DEFAULT_ADMIN_ROLE)
        if (deployerAddress != adminAddress) {
            accessControl.grantRole(accessControl.DEFAULT_ADMIN_ROLE(), adminAddress);
            accessControl.renounceRole(accessControl.DEFAULT_ADMIN_ROLE());
            console.log("Final admin granted role and deployer role renounced.");
        } else {
            console.log("Deployer is the final admin. Skipping DEFAULT_ADMIN_ROLE transfer.");
        }

        oracleIntegration.setLiquidityManagerAddress(address(liquidityManager));
        console.log("Set LiquidityManager address in OracleIntegration.");

        console.log("Registering contracts with EmergencyController...");
        emergencyController.registerEmergencyAwareContract(address(pREWAToken));
        emergencyController.registerEmergencyAwareContract(address(tokenStaking));
        emergencyController.registerEmergencyAwareContract(address(lpStaking));
        emergencyController.registerEmergencyAwareContract(address(liquidityManager));
        emergencyController.registerEmergencyAwareContract(address(proxyAdmin));
        emergencyController.registerEmergencyAwareContract(address(securityModule));
        emergencyController.registerEmergencyAwareContract(address(priceGuard));
        console.log("All emergency-aware contracts registered.");
        
        console.log("Funding staking contracts with reward tokens...");
        uint256 rewardAmount = 20_000_000 * 1e18;
        // --- CORRECTED FUNDING LOGIC ---
        // The mint call is removed. The deployer now holds the full supply from initialization
        // and can directly transfer the funds to the staking contracts.
        pREWAToken.transfer(address(tokenStaking), rewardAmount);
        pREWAToken.transfer(address(lpStaking), rewardAmount);
        console.log("Staking contracts funded.");

        console.log("Registering key contracts in ContractRegistry...");
        contractRegistry.registerContract("pREWAToken", address(pREWAToken), "Token", "1.0.0");
        contractRegistry.registerContract("TokenStaking", address(tokenStaking), "Staking", "1.0.0");
        contractRegistry.registerContract("LPStaking", address(lpStaking), "Staking", "1.0.0");
        contractRegistry.registerContract("LiquidityManager", address(liquidityManager), "Liquidity", "1.0.0");
        console.log("Key contracts registered.");

        vm.stopBroadcast();

        console.log(unicode"\n✅✅✅ System Deployment and Configuration Complete! ✅✅✅");
    }
}
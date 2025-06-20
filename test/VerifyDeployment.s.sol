// test/VerifyDeployment.s.sol

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../script/DeployPrewa.s.sol";

// Import interfaces
import "../contracts/access/interfaces/IAccessControl.sol";
import "../contracts/core/interfaces/IpREWAToken.sol";
import "../contracts/liquidity/interfaces/ILiquidityManager.sol";

// Import implementations to access their specific public members
import "../contracts/access/AccessControl.sol";
import "../contracts/core/pREWAToken.sol";
import "../contracts/liquidity/LiquidityManager.sol";
import "../contracts/proxy/ProxyAdmin.sol";
import "../contracts/controllers/EmergencyController.sol";
import "../contracts/core/ContractRegistry.sol";
import "../contracts/oracle/OracleIntegration.sol";
import "../contracts/vesting/VestingFactory.sol";

contract VerifyDeployment is Test {
    function run() external {
        // First, run the main deployment script to get the addresses
        DeployPrewa deployment = new DeployPrewa();
        deployment.run();
        
        // Retrieve constants and deployed contract instances
        address magsAddress = deployment.MAGS_ADDRESS();
        
        IAccessControl ac = IAccessControl(address(deployment.accessControl()));
        IpREWAToken pREWA = deployment.pREWA();
        ILiquidityManager lm = deployment.liquidityManager();
        ProxyAdmin pa = deployment.proxyAdminMain();
        EmergencyController ec = deployment.emergencyController();
        ContractRegistry cr = deployment.contractRegistry();
        OracleIntegration oi = deployment.oracleIntegration();
        VestingFactory vf = deployment.vestingFactory();

        console.log("\n--- Starting Deployment Verification ---");

        // --- Verify Ownership and Admin Roles ---
        bytes32 DEFAULT_ADMIN_ROLE = 0x00;
        
        assertTrue(ac.hasRole(DEFAULT_ADMIN_ROLE, magsAddress), "MAGS should have DEFAULT_ADMIN_ROLE");
        assertTrue(pa.accessControl().hasRole(pa.accessControl().PROXY_ADMIN_ROLE(), magsAddress), "MAGS should have PROXY_ADMIN_ROLE");
        assertEq(ec.recoveryAdminAddress(), magsAddress, "EC recovery admin should be MAGS");
        assertEq(cr.owner(), magsAddress, "ContractRegistry owner should be MAGS");
        assertEq(pREWA.owner(), magsAddress, "pREWA owner should be MAGS");
        assertEq(oi.owner(), magsAddress, "OracleIntegration owner should be MAGS");
        assertEq(vf.owner(), magsAddress, "VestingFactory owner should be MAGS");
        
        // --- Verify Contract Wiring ---
        // <<< FIX: Cast proxy addresses to their implementation types to access public state variables >>>
        assertEq(address(LiquidityManager(payable(address(lm))).accessControl()), address(ac), "LM AC mismatch");
        assertEq(address(LiquidityManager(payable(address(lm))).emergencyController()), address(ec), "LM EC mismatch");
        assertEq(address(LiquidityManager(payable(address(lm))).oracleIntegration()), address(oi), "LM OI mismatch");
        assertEq(address(PREWAToken(payable(address(pREWA))).accessControl()), address(ac), "pREWA AC mismatch");
        assertEq(address(PREWAToken(payable(address(pREWA))).emergencyController()), address(ec), "pREWA EC mismatch");
        assertEq(vf.getTokenAddress(), address(pREWA), "VestingFactory token mismatch");
        assertEq(VestingFactory(address(vf)).proxyAdminAddress(), address(pa), "VestingFactory proxy admin mismatch");

        console.log(unicode"✅ Deployment Verification Successful!");
    }
}
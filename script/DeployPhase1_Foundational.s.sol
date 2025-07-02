// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {AccessControl} from "../contracts/access/AccessControl.sol";
import {ProxyAdmin} from "../contracts/proxy/ProxyAdmin.sol";
import {EmergencyController} from "../contracts/controllers/EmergencyController.sol";
import {EmergencyTimelockController} from "../contracts/controllers/EmergencyTimelockController.sol";
import {ContractRegistry} from "../contracts/core/ContractRegistry.sol";

contract DeployPhase1_Foundational is Script {

    // --- CONFIGURATION ---
    uint256 constant PROXY_ADMIN_TIMELOCK = 2 days;
    uint256 constant EC_L3_REQUIRED_APPROVALS = 1;
    uint256 constant EC_L3_TIMELOCK_DURATION = 1 days;

    struct DeployedPhase1Addresses {
        AccessControl accessControl;
        ProxyAdmin proxyAdmin;
        EmergencyController emergencyController;
        EmergencyTimelockController emergencyTimelockController;
        ContractRegistry contractRegistry;
    }

    function run() public returns (DeployedPhase1Addresses memory addresses) {
        address magsAddress = vm.envAddress("MAGS_ADDRESS");
        if (magsAddress == address(0)) {
            revert("MAGS_ADDRESS not set in .env file");
        }

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("--- Deploying Phase 1: Foundational Contracts ---");
        
        // 1. AccessControl
        addresses.accessControl = new AccessControl();
        addresses.accessControl.initialize(magsAddress);
        console.log("AccessControl deployed at:", address(addresses.accessControl));

        // 2. EmergencyTimelockController
        addresses.emergencyTimelockController = new EmergencyTimelockController();
        addresses.emergencyTimelockController.initialize(address(addresses.accessControl), EC_L3_TIMELOCK_DURATION);
        console.log("EmergencyTimelockController deployed at:", address(addresses.emergencyTimelockController));

        // 3. EmergencyController
        addresses.emergencyController = new EmergencyController();
        addresses.emergencyController.initialize(
            address(addresses.accessControl),
            address(addresses.emergencyTimelockController),
            EC_L3_REQUIRED_APPROVALS,
            EC_L3_TIMELOCK_DURATION,
            magsAddress
        );
        console.log("EmergencyController deployed at:", address(addresses.emergencyController));

        // 4. ProxyAdmin
        addresses.proxyAdmin = new ProxyAdmin();
        addresses.proxyAdmin.initialize(
            address(addresses.accessControl),
            address(addresses.emergencyController),
            PROXY_ADMIN_TIMELOCK,
            magsAddress
        );
        console.log("ProxyAdmin deployed at:", address(addresses.proxyAdmin));

        // 5. ContractRegistry
        addresses.contractRegistry = new ContractRegistry();
        addresses.contractRegistry.initialize(magsAddress, address(addresses.accessControl));
        console.log("ContractRegistry deployed at:", address(addresses.contractRegistry));

        vm.stopBroadcast();
        return addresses;
    }
}
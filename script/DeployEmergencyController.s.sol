// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {EmergencyController} from "../contracts/controllers/EmergencyController.sol";

contract DeployEmergencyController is Script {
    uint256 constant EC_L3_REQUIRED_APPROVALS = 1;
    uint256 constant EC_L3_TIMELOCK_DURATION = 1 days;

    function run() public returns (EmergencyController) {
        address accessControlAddress = vm.envAddress("ACCESS_CONTROL_ADDRESS");
        address timelockAddress = vm.envAddress("EMERGENCY_TIMELOCK_ADDRESS");
        address magsAddress = vm.envAddress("MAGS_ADDRESS");

        if (accessControlAddress == address(0) || timelockAddress == address(0) || magsAddress == address(0)) {
            revert("Required addresses not set in .env file");
        }

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        EmergencyController ec = new EmergencyController();
        ec.initialize(
            accessControlAddress,
            timelockAddress,
            EC_L3_REQUIRED_APPROVALS,
            EC_L3_TIMELOCK_DURATION,
            magsAddress
        );

        vm.stopBroadcast();

        console.log("EmergencyController deployed at:", address(ec));
        return ec;
    }
}
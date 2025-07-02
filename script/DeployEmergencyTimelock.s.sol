// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {EmergencyTimelockController} from "../contracts/controllers/EmergencyTimelockController.sol";

contract DeployEmergencyTimelock is Script {
    uint256 constant EC_L3_TIMELOCK_DURATION = 1 days;

    function run() public returns (EmergencyTimelockController) {
        address accessControlAddress = vm.envAddress("ACCESS_CONTROL_ADDRESS");
        if (accessControlAddress == address(0)) {
            revert("ACCESS_CONTROL_ADDRESS not set in .env file");
        }

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        EmergencyTimelockController timelock = new EmergencyTimelockController();
        timelock.initialize(accessControlAddress, EC_L3_TIMELOCK_DURATION);

        vm.stopBroadcast();

        console.log("EmergencyTimelockController deployed at:", address(timelock));
        return timelock;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {ProxyAdmin} from "../contracts/proxy/ProxyAdmin.sol";

contract DeployProxyAdmin is Script {
    uint256 constant PROXY_ADMIN_TIMELOCK = 2 days;

    function run() public returns (ProxyAdmin) {
        address accessControlAddress = vm.envAddress("ACCESS_CONTROL_ADDRESS");
        address emergencyControllerAddress = vm.envAddress("EMERGENCY_CONTROLLER_ADDRESS");
        address magsAddress = vm.envAddress("MAGS_ADDRESS");

        if (accessControlAddress == address(0) || emergencyControllerAddress == address(0) || magsAddress == address(0)) {
            revert("Required addresses not set in .env file");
        }

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ProxyAdmin pa = new ProxyAdmin();
        pa.initialize(
            accessControlAddress,
            emergencyControllerAddress,
            PROXY_ADMIN_TIMELOCK,
            magsAddress
        );

        vm.stopBroadcast();
        
        console.log("ProxyAdmin deployed at:", address(pa));
        return pa;
    }
}
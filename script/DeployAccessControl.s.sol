// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {AccessControl} from "../contracts/access/AccessControl.sol";

contract DeployAccessControl is Script {
    function run() public returns (AccessControl) {
        address magsAddress = vm.envAddress("MAGS_ADDRESS");
        if (magsAddress == address(0)) {
            revert("MAGS_ADDRESS not set in .env file");
        }

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        AccessControl accessControl = new AccessControl();
        accessControl.initialize(magsAddress);

        vm.stopBroadcast();
        
        console.log("AccessControl deployed at:", address(accessControl));
        return accessControl;
    }
}
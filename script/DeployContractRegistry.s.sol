// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {ContractRegistry} from "../contracts/core/ContractRegistry.sol";

contract DeployContractRegistry is Script {
    function run() public returns (ContractRegistry) {
        address magsAddress = vm.envAddress("MAGS_ADDRESS");
        address accessControlAddress = vm.envAddress("ACCESS_CONTROL_ADDRESS");

        if (magsAddress == address(0) || accessControlAddress == address(0)) {
            revert("Required addresses not set in .env file");
        }

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ContractRegistry registry = new ContractRegistry();
        registry.initialize(magsAddress, accessControlAddress);

        vm.stopBroadcast();

        console.log("ContractRegistry deployed at:", address(registry));
        return registry;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {OracleIntegration} from "../contracts/oracle/OracleIntegration.sol";

contract DeployOracleIntegration is Script {
    uint256 constant ORACLE_STALENESS_THRESHOLD = 1 hours;

    function run() public returns (OracleIntegration) {
        address magsAddress = vm.envAddress("MAGS_ADDRESS");
        if (magsAddress == address(0)) {
            revert("MAGS_ADDRESS not set in .env file");
        }
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        OracleIntegration oracle = new OracleIntegration();
        oracle.initialize(magsAddress, ORACLE_STALENESS_THRESHOLD);

        vm.stopBroadcast();
        
        console.log("OracleIntegration deployed at:", address(oracle));
        return oracle;
    }
}
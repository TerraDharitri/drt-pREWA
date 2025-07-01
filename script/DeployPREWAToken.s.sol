// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PREWAToken} from "../contracts/core/pREWAToken.sol";
import {IpREWAToken} from "../contracts/core/interfaces/IpREWAToken.sol";
import {TransparentProxy} from "../contracts/proxy/TransparentProxy.sol";

contract DeployPREWAToken is Script {
    string constant PREWA_NAME = "pREWA Token";
    string constant PREWA_SYMBOL = "PREWA";
    uint8 constant PREWA_DECIMALS = 18;
    uint256 constant PREWA_INITIAL_SUPPLY = 1_000_000_000 * (10**18);
    uint256 constant PREWA_CAP = 2_000_000_000 * (10**18);

    function run() public returns (IpREWAToken, PREWAToken) {
        address accessControlAddress = vm.envAddress("ACCESS_CONTROL_ADDRESS");
        address emergencyControllerAddress = vm.envAddress("EMERGENCY_CONTROLLER_ADDRESS");
        address proxyAdminAddress = vm.envAddress("PROXY_ADMIN_ADDRESS");
        address magsAddress = vm.envAddress("MAGS_ADDRESS");

        if (accessControlAddress == address(0) || emergencyControllerAddress == address(0) || proxyAdminAddress == address(0) || magsAddress == address(0)) {
            revert("Required addresses not set in .env file");
        }
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Implementation
        PREWAToken implementation = new PREWAToken();

        // 2. Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            PREWAToken.initialize.selector,
            PREWA_NAME, PREWA_SYMBOL, PREWA_DECIMALS,
            PREWA_INITIAL_SUPPLY, PREWA_CAP,
            accessControlAddress, emergencyControllerAddress, magsAddress
        );

        // 3. Deploy Proxy
        TransparentProxy proxy = new TransparentProxy(address(implementation), proxyAdminAddress, initData);

        vm.stopBroadcast();

        console.log("pREWAToken Implementation deployed at:", address(implementation));
        console.log("pREWAToken Proxy deployed at:", address(proxy));

        return (IpREWAToken(address(proxy)), implementation);
    }
}
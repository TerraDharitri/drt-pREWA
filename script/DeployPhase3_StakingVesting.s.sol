// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {VestingImplementation} from "../contracts/vesting/VestingImplementation.sol";
import {VestingFactory} from "../contracts/vesting/VestingFactory.sol";
import {TokenStaking} from "../contracts/core/TokenStaking.sol";
import {ITokenStaking} from "../contracts/core/interfaces/ITokenStaking.sol";
import {LPStaking} from "../contracts/liquidity/LPStaking.sol";
import {ILPStaking} from "../contracts/liquidity/interfaces/ILPStaking.sol";
import {TransparentProxy} from "../contracts/proxy/TransparentProxy.sol";


contract DeployPhase3_StakingVesting is Script {

    // --- CONFIGURATION ---
    uint256 constant TS_BASE_REWARD_RATE = 1000; // 10% APR
    uint256 constant TS_MIN_STAKE_DURATION = 1 days;
    uint256 constant TS_MAX_POSITIONS = 10;
    uint256 constant LPS_MIN_STAKE_DURATION = 1 days;

    struct DeployedPhase3Addresses {
        VestingImplementation vestingImplementation;
        VestingFactory vestingFactory;
        ITokenStaking tokenStaking;
        TokenStaking tokenStakingImplementation;
        ILPStaking lpStaking;
        LPStaking lpStakingImplementation;
    }

    function run() public returns (DeployedPhase3Addresses memory addresses) {
        // --- Load Dependencies ---
        address magsAddress = vm.envAddress("MAGS_ADDRESS");
        address pREWAAddress = vm.envAddress("PREWA_TOKEN_ADDRESS");
        address accessControlAddress = vm.envAddress("ACCESS_CONTROL_ADDRESS");
        address emergencyControllerAddress = vm.envAddress("EMERGENCY_CONTROLLER_ADDRESS");
        address proxyAdminAddress = vm.envAddress("PROXY_ADMIN_ADDRESS");
        address oracleIntegrationAddress = vm.envAddress("ORACLE_INTEGRATION_ADDRESS");
        address liquidityManagerAddress = vm.envAddress("LIQUIDITY_MANAGER_ADDRESS");

        if (magsAddress == address(0) || pREWAAddress == address(0) || accessControlAddress == address(0) || emergencyControllerAddress == address(0) || proxyAdminAddress == address(0) || oracleIntegrationAddress == address(0) || liquidityManagerAddress == address(0)) {
            revert("A required address from Phase 1 or 2 was not set in the environment.");
        }

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("--- Deploying Phase 3: Staking & Vesting Infrastructure ---");

        // 1. Vesting
        addresses.vestingImplementation = new VestingImplementation();
        addresses.vestingFactory = new VestingFactory();
        addresses.vestingFactory.initialize(
            magsAddress, pREWAAddress,
            address(addresses.vestingImplementation), proxyAdminAddress
        );
        console.log("VestingImplementation Logic deployed at:", address(addresses.vestingImplementation));
        console.log("VestingFactory deployed at:", address(addresses.vestingFactory));

        // 2. TokenStaking
        addresses.tokenStakingImplementation = new TokenStaking();
        bytes memory tsInitData = abi.encodeWithSelector(
            TokenStaking.initialize.selector,
            pREWAAddress, accessControlAddress, emergencyControllerAddress,
            oracleIntegrationAddress, TS_BASE_REWARD_RATE,
            TS_MIN_STAKE_DURATION, magsAddress, TS_MAX_POSITIONS
        );
        TransparentProxy tokenStakingProxy = new TransparentProxy(address(addresses.tokenStakingImplementation), proxyAdminAddress, tsInitData);
        addresses.tokenStaking = ITokenStaking(address(tokenStakingProxy));
        console.log("TokenStaking Implementation deployed at:", address(addresses.tokenStakingImplementation));
        console.log("TokenStaking Proxy deployed at:", address(addresses.tokenStaking));

        // 3. LPStaking
        addresses.lpStakingImplementation = new LPStaking();
        bytes memory lpsInitData = abi.encodeWithSelector(
            LPStaking.initialize.selector,
            pREWAAddress, liquidityManagerAddress,
            magsAddress, LPS_MIN_STAKE_DURATION,
            accessControlAddress, emergencyControllerAddress
        );
        TransparentProxy lpStakingProxy = new TransparentProxy(address(addresses.lpStakingImplementation), proxyAdminAddress, lpsInitData);
        addresses.lpStaking = ILPStaking(address(lpStakingProxy));
        console.log("LPStaking Implementation deployed at:", address(addresses.lpStakingImplementation));
        console.log("LPStaking Proxy deployed at:", address(addresses.lpStaking));

        vm.stopBroadcast();
        return addresses;
    }
}
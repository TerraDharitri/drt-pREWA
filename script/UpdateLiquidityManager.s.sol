// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Minimal interface for your LiquidityManager
interface ILiquidityManager {
    function setRouterAddress(address routerAddr) external returns (bool successFlag);
}

/**
 * @title UpdateLiquidityManager
 * @notice A script to update the PancakeSwap Router address in the deployed LiquidityManager contract.
 * @dev This is a critical administrative task to ensure the contract interacts with the correct DEX.
 *      The wallet executing this script MUST have the DEFAULT_ADMIN_ROLE in the AccessControl contract.
 */
contract UpdateLiquidityManager is Script {

    // --- CONFIGURATION ---
    // The official PancakeSwap V2 Router address for BSC Testnet
    address constant CORRECT_ROUTER_ADDRESS = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1;

    // --- FIX: Use the EIP-55 checksummed address for YOUR LiquidityManager ---
    address constant LIQUIDITY_MANAGER_ADDRESS = 0x5A36f36d7387acD2D8C7e8A35372F20CB6910d12;
                                                 
    // -------------------

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("-----------------------------------------");
        console.log("Executing UpdateLiquidityManager Script");
        console.log("-----------------------------------------");
        console.log("  Target Contract (LiquidityManager):", LIQUIDITY_MANAGER_ADDRESS);
        console.log("  New Router Address:", CORRECT_ROUTER_ADDRESS);
        console.log("  Executing from:", vm.addr(deployerPrivateKey));
        console.log("-----------------------------------------");

        vm.startBroadcast(deployerPrivateKey);

        ILiquidityManager lm = ILiquidityManager(LIQUIDITY_MANAGER_ADDRESS);
        lm.setRouterAddress(CORRECT_ROUTER_ADDRESS);

        vm.stopBroadcast();

        console.log(unicode"✅ Transaction broadcasted successfully!");
        console.log("LiquidityManager has been updated to point to the correct PancakeSwap V2 Router.");
    }
}
// forge script script/UpdateLiquidityManager.s.sol:UpdateLiquidityManager --rpc-url ${BSC_TESTNET_RPC_URL} --broadcast -vvvv
// cast storage 0xF699b6d664f74dd6ADCFd65cc93A1A8Bf945fB28 2 --rpc-url ${BSC_TESTNET_RPC_URL}
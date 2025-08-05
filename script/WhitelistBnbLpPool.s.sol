// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/access/AccessControl.sol";
import "../contracts/liquidity/interfaces/ILPStaking.sol";

/**
 * @title WhitelistBnbLpPool
 * @author drt-pREWA (Professionally Audited & Finalized)
 * @notice A professional script to whitelist a new LP token pool in the LPStaking contract.
 * @dev This script calls the `addPool` function. The wallet executing this MUST
 *      have the DEFAULT_ADMIN_ROLE to grant itself the necessary PARAMETER_ROLE.
 */
contract WhitelistBnbLpPool is Script {

    // --- YOUR DEPLOYED PROXY ADDRESSES (CHECKSUMMED AND VERIFIED) ---
    // NOTE: Using the addresses you confirmed from your latest deployment.
    address constant LP_STAKING_PROXY      = 0x2543Ee5C77d1a1D45Ba31b91F44e77e4945A6b70;
    address constant ACCESS_CONTROL_PROXY  = 0xf0B56BFc6E7e4e0421Ec25b4B943D3e141b07494;
    // --- END: DEPLOYED ADDRESSES ---

    // --- CONFIGURATION FOR THE NEW POOL ---
    // !!! IMPORTANT: REPLACE THIS with the new pREWA-BNB LP token address you just created !!!
    address constant LP_TOKEN_TO_WHITELIST = 0x49669ea1cff5c4B82964Ed11d5E01c7871f97bAE;

    // The desired base APR for the pool, in Basis Points (10000 = 100.00% APR)
    uint256 constant BASE_APR_BPS = 10000;
    // --- END: CONFIGURATION ---

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // --- Instantiate interfaces for the contracts we need to interact with ---
        ILPStaking lpStaking = ILPStaking(LP_STAKING_PROXY);
        AccessControl accessControl = AccessControl(ACCESS_CONTROL_PROXY);

        console.log("--- Whitelisting New LP Staking Pool ---");
        console.log("  Target Contract (LPStaking):", LP_STAKING_PROXY);
        console.log("  LP Token to Whitelist:", LP_TOKEN_TO_WHITELIST);
        console.log("  Base APR to Set:", BASE_APR_BPS / 100, ".");
        if (BASE_APR_BPS % 100 < 10) {
            console.log(0, BASE_APR_BPS % 100, "%%");
        } else {
            console.log(BASE_APR_BPS % 100, "%%");
        }
        console.log("  Executing from address:", deployerAddress);
        console.log("-----------------------------------------");

        vm.startBroadcast(deployerPrivateKey);
        
        // --- Step 1: Temporarily Grant PARAMETER_ROLE to Self for Configuration ---
        bytes32 parameterRole = accessControl.PARAMETER_ROLE();
        accessControl.grantRole(parameterRole, deployerAddress);
        console.log("1. Granted PARAMETER_ROLE to self for configuration.");

        // --- Step 2: Call addPool to Whitelist the LP Token ---
        console.log("\n2. Calling addPool on LPStaking contract...");
        lpStaking.addPool(LP_TOKEN_TO_WHITELIST, BASE_APR_BPS);
        console.log("   -> Pool whitelisted successfully.");

        // --- Step 3: Clean Up Permissions ---
        accessControl.revokeRole(parameterRole, deployerAddress);
        console.log("\n3. Revoked PARAMETER_ROLE from self. Configuration complete.");
        
        vm.stopBroadcast();

        console.log(unicode"\n✅✅✅ The LP Staking pool has been successfully whitelisted and activated. ✅✅✅");
    }
}
// forge script script/WhitelistLpPool.s.sol:WhitelistLpPool --rpc-url bsc_testnet --broadcast -vvvv
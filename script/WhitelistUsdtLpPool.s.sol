// script/WhitelistUsdtLpPool.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/access/AccessControl.sol";
import "../contracts/liquidity/interfaces/ILPStaking.sol";

/**
 * @title WhitelistUsdtLpPool
 * @author drt-pREWA
 * @notice A script to whitelist the pREWA-USDT LP token pool in the LPStaking contract.
 */
contract WhitelistUsdtLpPool is Script {

    // --- YOUR DEPLOYED PROXY ADDRESSES (VERIFIED) ---
    address constant LP_STAKING_PROXY      = 0x2543Ee5C77d1a1D45Ba31b91F44e77e4945A6b70;
    address constant ACCESS_CONTROL_PROXY  = 0xf0B56BFc6E7e4e0421Ec25b4B943D3e141b07494;
    // --- END: DEPLOYED ADDRESSES ---

    // --- CONFIGURATION FOR THE NEW POOL ---
    // !!! IMPORTANT: REPLACE THIS with the new pREWA-USDT LP token address you just created !!!
    address constant LP_TOKEN_TO_WHITELIST = 0xf0B56BFc6E7e4e0421Ec25b4B943D3e141b07494;

    // The desired base APR for the pool, in Basis Points (10000 = 100.00% APR)
    uint256 constant BASE_APR_BPS = 12000; // Example: Set a different APR for this pool, e.g., 120%
    // --- END: CONFIGURATION ---

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        ILPStaking lpStaking = ILPStaking(LP_STAKING_PROXY);
        AccessControl accessControl = AccessControl(ACCESS_CONTROL_PROXY);

        console.log("--- Whitelisting New pREWA-USDT LP Staking Pool ---");
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
        
        bytes32 parameterRole = accessControl.PARAMETER_ROLE();
        accessControl.grantRole(parameterRole, deployerAddress);
        console.log("1. Granted PARAMETER_ROLE to self for configuration.");

        lpStaking.addPool(LP_TOKEN_TO_WHITELIST, BASE_APR_BPS);
        console.log("\n2. pREWA-USDT Pool whitelisted successfully.");

        accessControl.revokeRole(parameterRole, deployerAddress);
        console.log("\n3. Revoked PARAMETER_ROLE from self. Configuration complete.");
        
        vm.stopBroadcast();

        console.log(unicode"\n✅✅✅ The pREWA-USDT LP Staking pool has been successfully whitelisted. ✅✅✅");
    }
}
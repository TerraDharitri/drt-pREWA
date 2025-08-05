// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/access/AccessControl.sol";
import "../contracts/core/interfaces/ITokenStaking.sol";
import "../contracts/liquidity/interfaces/ILPStaking.sol";

/**
 * @title ConfigureStakingParameters (Definitive Final Version)
 * @author drt-pREWA (Professionally Audited & Finalized)
 * @notice A comprehensive script to configure all valid staking parameters based on the
 *         contract's hardcoded 365-day maximum duration limit.
 */
contract ConfigureStakingParameters is Script {

    address constant TOKEN_STAKING_PROXY   = 0x3e89dFeb90b3d1EFCa5338a2059c51454bf89DDf;
    address constant LP_STAKING_PROXY      = 0x2543Ee5C77d1a1D45Ba31b91F44e77e4945A6b70;
    address constant ACCESS_CONTROL_PROXY  = 0xf0B56BFc6E7e4e0421Ec25b4B943D3e141b07494;

    struct TierConfig { uint256 duration; uint256 rewardMultiplier; uint256 earlyWithdrawalPenalty; }

    function run(uint256 newMaxPositions) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        ITokenStaking tokenStaking = ITokenStaking(TOKEN_STAKING_PROXY);
        ILPStaking lpStaking = ILPStaking(LP_STAKING_PROXY);
        AccessControl accessControl = AccessControl(ACCESS_CONTROL_PROXY);

        // --- FIX: Define only the tiers that are VALID within the 365-day limit ---
        TierConfig[] memory tiersToCreate = new TierConfig[](4);
        tiersToCreate[0] = TierConfig({ duration: 90 days, rewardMultiplier: 10000, earlyWithdrawalPenalty: 1500 });
        tiersToCreate[1] = TierConfig({ duration: 180 days, rewardMultiplier: 12000, earlyWithdrawalPenalty: 1200 });
        tiersToCreate[2] = TierConfig({ duration: 270 days, rewardMultiplier: 15000, earlyWithdrawalPenalty: 800 });
        tiersToCreate[3] = TierConfig({ duration: 365 days, rewardMultiplier: 20000, earlyWithdrawalPenalty: 600 });

        vm.startBroadcast(deployerPrivateKey);
        
        console.log("--- Starting Full Staking Parameter Configuration ---");
        
        bytes32 parameterRole = accessControl.PARAMETER_ROLE();
        accessControl.grantRole(parameterRole, deployerAddress);
        console.log("1. Granted PARAMETER_ROLE to self for configuration.");

        console.log("\n2. Configuring TokenStaking...");
        tokenStaking.setMaxPositionsPerUser(newMaxPositions);
        console.log("   -> Max positions set to", newMaxPositions);
        for (uint256 i = 0; i < tiersToCreate.length; i++) {
            tokenStaking.addTier(tiersToCreate[i].duration, tiersToCreate[i].rewardMultiplier, tiersToCreate[i].earlyWithdrawalPenalty);
        }
        console.log("   -> All 4 valid staking tiers created.");
        
        console.log("\n3. Configuring LPStaking...");
        console.log("   -> NOTE: Max positions is not configurable for this contract.");
        for (uint256 i = 0; i < tiersToCreate.length; i++) {
            lpStaking.addTier(tiersToCreate[i].duration, tiersToCreate[i].rewardMultiplier, tiersToCreate[i].earlyWithdrawalPenalty);
        }
        console.log("   -> All 4 valid staking tiers created.");

        accessControl.revokeRole(parameterRole, deployerAddress);
        console.log("\n4. Revoked PARAMETER_ROLE from self.");
        
        vm.stopBroadcast();
        console.log(unicode"\n✅✅✅ All Staking Parameters have been successfully configured. ✅✅✅");
    }
}

// forge script script/ConfigureStakingParameters.s.sol:ConfigureStakingParameters --rpc-url bsc_testnet --broadcast --sig "run(uint256)" 500 -vvvv
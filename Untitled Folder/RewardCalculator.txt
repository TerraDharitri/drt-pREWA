// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./storage/LPStakingStorage.sol";
import "../libraries/RewardMath.sol";

/**
 * @title RewardCalculator
 * @author Rewa
 * @notice A library for calculating staking rewards for the LPStaking contract.
 * @dev This library contains the core logic for calculating rewards based on a staking position's
 * details, the associated pool's reward rate, and the tier's multiplier. It is designed to be
 * stateless and purely computational.
 */
library RewardCalculator {
    /**
     * @notice Calculates the pending rewards for a given LP staking position.
     * @dev The calculation considers the time elapsed since the last claim, the staked amount,
     * the pool's base reward rate, and the position's tier multiplier. Rewards stop accruing
     * after the position's end time.
     * @param position The user's staking position struct.
     * @param pool The LP pool struct the position belongs to.
     * @param tier The tier struct the position belongs to.
     * @param currentTime The current timestamp (e.g., `block.timestamp`).
     * @return amount The calculated amount of pending rewards.
     */
    function calculateRewards(
        LPStakingStorage.LPStakingPosition memory position,
        LPStakingStorage.LPPool memory pool,
        LPStakingStorage.Tier memory tier,
        uint256 currentTime
    ) public pure returns (uint256 amount) {
        if (!position.active) {
            return 0;
        }
        
        if (pool.lpTokenAddress == address(0)) {
            return 0;
        }
        
        if (!pool.active) {
            return 0;
        }

        uint256 timeElapsed;

        if (currentTime > position.endTime) {
            if (position.lastClaimTime >= position.endTime) {
                return 0;
            }
            timeElapsed = position.endTime - position.lastClaimTime;
        } else {
           if (currentTime <= position.lastClaimTime) {
                return 0;
            }
            timeElapsed = currentTime - position.lastClaimTime;
        }

        amount = RewardMath.calculateReward(
            position.amount,          
            pool.baseRewardRate,      
            timeElapsed,              
            tier.rewardMultiplier     
        );
        
        return amount;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./Constants.sol";

/**
 * @title RewardMath
 * @author Rewa
 * @notice A library for calculating staking rewards with high precision.
 * @dev This library uses internal scaling factors to perform reward calculations on integers
 * while preserving precision, avoiding the need for floating-point math.
 */
library RewardMath {
    /// @dev An internal scaling factor to maintain precision for reward rates.
    uint256 public constant SCALE_RATE = 1e10;
    /// @dev An internal scaling factor to maintain precision for time-based calculations.
    uint256 public constant SCALE_TIME = 1e8;

    /**
     * @notice Calculates the reward earned over a period of time.
     * @dev The formula is effectively: `reward = (stakedAmount * rewardRate * timeElapsed * multiplierBps) / (BPS_MAX * SCALE_RATE * SCALE_TIME)`.
     * @param stakedAmount The principal amount staked.
     * @param rewardRate The base reward rate, pre-scaled by `SCALE_RATE` and `SCALE_TIME`.
     * @param timeElapsed The duration in seconds for which to calculate the reward.
     * @param multiplierBps The reward multiplier in basis points (e.g., 10000 = 1x).
     * @return reward The calculated reward amount.
     */
    function calculateReward(
        uint256 stakedAmount,
        uint256 rewardRate, 
        uint256 timeElapsed,
        uint256 multiplierBps
    ) internal pure returns (uint256 reward) {
        if (stakedAmount == 0 || rewardRate == 0 || timeElapsed == 0) {
            return 0;
        }

        uint256 numerator = Math.mulDiv(stakedAmount, rewardRate, 1); 
        numerator = Math.mulDiv(numerator, timeElapsed, 1);           

        if (multiplierBps != Constants.BPS_MAX) { 
            numerator = Math.mulDiv(numerator, multiplierBps, Constants.BPS_MAX);
        }

        uint256 scalingDenominator = SCALE_RATE * SCALE_TIME;

        reward = Math.mulDiv(numerator, 1, scalingDenominator);

        return reward;
    }

    /**
     * @notice Calculates the Annual Percentage Rate (APR) from an internal scaled reward rate.
     * @param rewardRate The internal scaled reward rate.
     * @param multiplierBps The reward multiplier in basis points to apply to the base APR.
     * @return aprInBps The calculated APR in basis points.
     */
    function calculateAPR(
        uint256 rewardRate, 
        uint256 multiplierBps
    ) internal pure returns (uint256 aprInBps) {
        if (rewardRate == 0) {
            return 0;
        }

        uint256 annualFactor = Constants.SECONDS_PER_YEAR * Constants.BPS_MAX; 
        uint256 scalingDivisor = SCALE_RATE * SCALE_TIME;                     

        uint256 baseAprInBps = Math.mulDiv(rewardRate, annualFactor, scalingDivisor);

        if (multiplierBps != Constants.BPS_MAX) { 
            return Math.mulDiv(baseAprInBps, multiplierBps, Constants.BPS_MAX);
        }

        return baseAprInBps;
    }
}
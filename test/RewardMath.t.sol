// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/StdError.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../contracts/libraries/RewardMath.sol";
import "../contracts/libraries/Constants.sol";

contract RewardMathTest is Test {

    uint256 constant ONE_E18 = 1e18;
    uint256 constant SCALE_RATE_RM = RewardMath.SCALE_RATE;
    uint256 constant SCALE_TIME_RM = RewardMath.SCALE_TIME;
    uint256 constant TOTAL_SCALING_RM = SCALE_RATE_RM * SCALE_TIME_RM;

    function calculateInputRewardRate(uint256 aprBps) internal pure returns (uint256 scaledRewardRate) {
        if (aprBps == 0) {
            return 0;
        }
        return Math.mulDiv(aprBps, TOTAL_SCALING_RM, Constants.BPS_MAX * Constants.SECONDS_PER_YEAR);
    }

    function calculateExpectedRewardUsingScaledRate(
        uint256 stakedAmount,
        uint256 scaledInputRewardRate,
        uint256 timeElapsedSeconds,
        uint256 multiplierBps
    ) internal pure returns (uint256 expectedReward) {
        if (stakedAmount == 0 || scaledInputRewardRate == 0 || timeElapsedSeconds == 0) {
            return 0;
        }

        uint256 numerator = Math.mulDiv(stakedAmount, scaledInputRewardRate, 1);
        numerator = Math.mulDiv(numerator, timeElapsedSeconds, 1);

        if (multiplierBps != Constants.BPS_MAX) {
            numerator = Math.mulDiv(numerator, multiplierBps, Constants.BPS_MAX);
        }
        expectedReward = Math.mulDiv(numerator, 1, TOTAL_SCALING_RM);
        return expectedReward;
    }

    function test_CalculateReward_ZeroInputs() public pure {
        uint256 rewardRate = calculateInputRewardRate(1000);
        assertEq(RewardMath.calculateReward(0, rewardRate, 1 days, 10000), 0, "Zero stakedAmount");
        assertEq(RewardMath.calculateReward(100 * ONE_E18, 0, 1 days, 10000), 0, "Zero rewardRate");
        assertEq(RewardMath.calculateReward(100 * ONE_E18, rewardRate, 0, 10000), 0, "Zero timeElapsed");
    }

    function test_CalculateReward_Basic_1xMultiplier() public pure {
        uint256 stakedAmount = 100 * ONE_E18;
        uint256 aprBps = 1000;
        uint256 timeElapsed = 365 days;
        uint256 multiplierBps = 10000;

        uint256 inputRewardRate = calculateInputRewardRate(aprBps);
        uint256 calculatedReward = RewardMath.calculateReward(stakedAmount, inputRewardRate, timeElapsed, multiplierBps);
        uint256 expectedReward = calculateExpectedRewardUsingScaledRate(stakedAmount, inputRewardRate, timeElapsed, multiplierBps);

        assertEq(calculatedReward, expectedReward, "Basic 1x - 1 year");
    }

    function test_CalculateReward_Basic_1_5xMultiplier() public pure {
        uint256 stakedAmount = 100 * ONE_E18;
        uint256 aprBps = 1000;
        uint256 timeElapsed = 365 days;
        uint256 multiplierBps = 15000;

        uint256 inputRewardRate = calculateInputRewardRate(aprBps);
        uint256 calculatedReward = RewardMath.calculateReward(stakedAmount, inputRewardRate, timeElapsed, multiplierBps);
        uint256 expectedReward = calculateExpectedRewardUsingScaledRate(stakedAmount, inputRewardRate, timeElapsed, multiplierBps);

        assertEq(calculatedReward, expectedReward, "Basic 1.5x - 1 year");
    }

    function test_CalculateReward_ShortDuration() public pure {
        uint256 stakedAmount = 1000 * ONE_E18;
        uint256 aprBps = 2000;
        uint256 timeElapsed = 1 days;
        uint256 multiplierBps = 10000;

        uint256 inputRewardRate = calculateInputRewardRate(aprBps);
        uint256 calculatedReward = RewardMath.calculateReward(stakedAmount, inputRewardRate, timeElapsed, multiplierBps);
        uint256 expectedReward = calculateExpectedRewardUsingScaledRate(stakedAmount, inputRewardRate, timeElapsed, multiplierBps);

        assertEq(calculatedReward, expectedReward, "Short duration");
    }

    function test_CalculateReward_LongDuration_HighAmount() public pure {
        uint256 stakedAmount = 1_000_000 * ONE_E18;
        uint256 aprBps = 500;
        uint256 timeElapsed = 4 * 365 days;
        uint256 multiplierBps = 12500;

        uint256 inputRewardRate = calculateInputRewardRate(aprBps);
        uint256 calculatedReward = RewardMath.calculateReward(stakedAmount, inputRewardRate, timeElapsed, multiplierBps);
        uint256 expectedReward = calculateExpectedRewardUsingScaledRate(stakedAmount, inputRewardRate, timeElapsed, multiplierBps);
        
        assertEq(calculatedReward, expectedReward, "Long duration, high amount");
    }

    function test_CalculateReward_MaxMultiplier() public pure {
        uint256 stakedAmount = 100 * ONE_E18;
        uint256 aprBps = 1000;
        uint256 timeElapsed = 180 days;
        uint256 multiplierBps = Constants.MAX_REWARD_MULTIPLIER;

        uint256 inputRewardRate = calculateInputRewardRate(aprBps);
        uint256 calculatedReward = RewardMath.calculateReward(stakedAmount, inputRewardRate, timeElapsed, multiplierBps);
        uint256 expectedReward = calculateExpectedRewardUsingScaledRate(stakedAmount, inputRewardRate, timeElapsed, multiplierBps);

        assertEq(calculatedReward, expectedReward, "Max multiplier");
    }

    function test_CalculateReward_MinMultiplier() public pure {
        uint256 stakedAmount = 100 * ONE_E18;
        uint256 aprBps = 1000;
        uint256 timeElapsed = 180 days;
        uint256 multiplierBps = Constants.MIN_REWARD_MULTIPLIER;

        uint256 inputRewardRate = calculateInputRewardRate(aprBps);
        uint256 calculatedReward = RewardMath.calculateReward(stakedAmount, inputRewardRate, timeElapsed, multiplierBps);
        uint256 expectedReward = calculateExpectedRewardUsingScaledRate(stakedAmount, inputRewardRate, timeElapsed, multiplierBps);

        assertEq(calculatedReward, expectedReward, "Min multiplier");
    }

    function test_CalculateReward_VeryLargeInputs_NoOverflow() public pure {
        uint256 stakedAmount = 1e26;
        uint256 aprBps = 50000;
        uint256 timeElapsed = 10 * 365 days;
        uint256 multiplierBps = 10000;

        uint256 inputRewardRate = calculateInputRewardRate(aprBps);
        uint256 calculatedReward = RewardMath.calculateReward(stakedAmount, inputRewardRate, timeElapsed, multiplierBps);
        uint256 expectedReward = calculateExpectedRewardUsingScaledRate(stakedAmount, inputRewardRate, timeElapsed, multiplierBps);
        
        assertEq(calculatedReward, expectedReward, "Very large inputs");
    }

    function test_CalculateAPR_ZeroRate() public pure {
        assertEq(RewardMath.calculateAPR(0, 10000), 0, "Zero rewardRate for APR");
    }

    function test_CalculateAPR_Basic_1xMultiplier() public pure {
        uint256 targetAprBps = 1000;
        uint256 inputRewardRate = calculateInputRewardRate(targetAprBps);
        uint256 multiplierBps = 10000;

        uint256 calculatedAprBps = RewardMath.calculateAPR(inputRewardRate, multiplierBps);
        assertApproxEqAbs(calculatedAprBps, targetAprBps, 1, "APR basic 1x");
    }

    function test_CalculateAPR_WithMultiplier() public pure {
        uint256 baseTargetAprBps = 1234;
        uint256 inputRewardRate = calculateInputRewardRate(baseTargetAprBps);
        uint256 multiplierBps = 15000;

        uint256 calculatedAprBps = RewardMath.calculateAPR(inputRewardRate, multiplierBps);
        uint256 expectedTierAprBps = Math.mulDiv(baseTargetAprBps, multiplierBps, Constants.BPS_MAX);

        assertApproxEqAbs(calculatedAprBps, expectedTierAprBps, 2, "APR with 1.5x multiplier");
    }
    
    function test_CalculateAPR_HighRate() public pure {
        uint256 targetAprBps = 50000;
        uint256 inputRewardRate = calculateInputRewardRate(targetAprBps);
        uint256 multiplierBps = 10000;

        uint256 calculatedAprBps = RewardMath.calculateAPR(inputRewardRate, multiplierBps);
        assertApproxEqAbs(calculatedAprBps, targetAprBps, 5, "APR high rate");
    }

    function test_CalculateAPR_LowRate() public pure {
        uint256 targetAprBps = 1;
        uint256 inputRewardRate = calculateInputRewardRate(targetAprBps);
        uint256 multiplierBps = 10000;

        uint256 calculatedAprBps = RewardMath.calculateAPR(inputRewardRate, multiplierBps);
        if (inputRewardRate == 0) {
            assertEq(calculatedAprBps, 0, "APR low rate (expected 0 due to input rate precision)");
        } else {
            assertApproxEqAbs(calculatedAprBps, targetAprBps, 1, "APR low rate");
        }
    }

    function test_CalculateAPR_MaxMultiplier() public pure {
        uint256 baseTargetAprBps = 1000;
        uint256 inputRewardRate = calculateInputRewardRate(baseTargetAprBps);
        uint256 multiplierBps = Constants.MAX_REWARD_MULTIPLIER;

        uint256 calculatedAprBps = RewardMath.calculateAPR(inputRewardRate, multiplierBps);
        uint256 expectedTierAprBps = Math.mulDiv(baseTargetAprBps, multiplierBps, Constants.BPS_MAX);

        assertApproxEqAbs(calculatedAprBps, expectedTierAprBps, 3, "APR with max multiplier");
    }

    function test_CalculateAPR_MinMultiplier() public pure {
        uint256 baseTargetAprBps = 10000;
        uint256 inputRewardRate = calculateInputRewardRate(baseTargetAprBps);
        uint256 multiplierBps = Constants.MIN_REWARD_MULTIPLIER;

        uint256 calculatedAprBps = RewardMath.calculateAPR(inputRewardRate, multiplierBps);
        uint256 expectedTierAprBps = Math.mulDiv(baseTargetAprBps, multiplierBps, Constants.BPS_MAX);
        
        assertApproxEqAbs(calculatedAprBps, expectedTierAprBps, 1, "APR with min multiplier");
    }

    function test_CalculateAPR_LargeRate_NoOverflow() public pure {
        uint256 inputRewardRate = calculateInputRewardRate(50000 * 100); 
        uint256 multiplierBps = 10000;

        uint256 calculatedAprBps = RewardMath.calculateAPR(inputRewardRate, multiplierBps);
        assertApproxEqAbs(calculatedAprBps, 50000 * 100, 500, "APR for extremely high input rate");
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../contracts/liquidity/RewardCalculator.sol";
import "../contracts/liquidity/storage/LPStakingStorage.sol";
import "../contracts/libraries/RewardMath.sol";
import "../contracts/libraries/Constants.sol";

contract RewardCalculatorTest is Test {

    function calculatePoolInputRate(uint256 aprBps) internal pure returns (uint256) {
        if (aprBps == 0) return 0;
        uint256 totalScaling = RewardMath.SCALE_RATE * RewardMath.SCALE_TIME; 
        uint256 denominator = Constants.BPS_MAX * Constants.SECONDS_PER_YEAR; 

        return Math.mulDiv(aprBps, totalScaling, denominator);
    }

    function test_CalculateRewards_Basic() public {
        vm.warp(365 days);
        uint256 currentTime = block.timestamp;

        LPStakingStorage.LPStakingPosition memory pos = LPStakingStorage.LPStakingPosition({
            amount: 100 * 1e18,
            startTime: currentTime - 10 days,
            endTime: currentTime + 20 days,
            lastClaimTime: currentTime - 5 days,
            tierId: 0,
            lpToken: address(0x1),
            active: true
        });

        LPStakingStorage.Tier memory tier = LPStakingStorage.Tier({
            duration: 30 days,
            rewardMultiplier: 10000,
            earlyWithdrawalPenalty: 0,
            active: true
        });

        LPStakingStorage.LPPool memory pool = LPStakingStorage.LPPool({
            lpTokenAddress: address(0x1),
            baseRewardRate: calculatePoolInputRate(1000),
            active: true
        });

        uint256 timeElapsedSinceLastClaim = currentTime - pos.lastClaimTime;
        uint256 expectedReward = RewardMath.calculateReward(
            pos.amount,
            pool.baseRewardRate,
            timeElapsedSinceLastClaim,
            tier.rewardMultiplier
        );

        uint256 calculated = RewardCalculator.calculateRewards(pos, pool, tier, currentTime);
        assertEq(calculated, expectedReward, "Basic reward calculation failed");
    }

    function test_CalculateRewards_NotActivePosition() public view {
        LPStakingStorage.LPStakingPosition memory pos;
        pos.active = false;
        pos.amount = 100e18;
        pos.startTime = block.timestamp;
        pos.endTime = block.timestamp + 1;
        pos.lastClaimTime = block.timestamp;
        pos.tierId = 0;
        pos.lpToken = address(0x1);

        LPStakingStorage.LPPool memory pool;
        pool.baseRewardRate = 1;
        pool.active = true;
        pool.lpTokenAddress = address(0x1);

        LPStakingStorage.Tier memory tier;
        tier.rewardMultiplier = 10000;
        tier.active = true;

        assertEq(RewardCalculator.calculateRewards(pos, pool, tier, block.timestamp), 0, "Inactive position should yield 0 rewards");
    }

    function test_CalculateRewards_PoolNotActiveOrInvalid() public view {
        uint256 currentTime = block.timestamp;
        LPStakingStorage.LPStakingPosition memory pos;
        pos.active = true; 
        pos.amount = 100e18; 
        pos.startTime = currentTime > 0 ? currentTime -1 : 0;
        pos.endTime = currentTime + 10; 
        pos.lastClaimTime = currentTime > 0 ? currentTime -1 : 0; 
        pos.tierId = 0; 
        pos.lpToken = address(0x1);

        LPStakingStorage.Tier memory tier;
        tier.rewardMultiplier = 10000; tier.active = true;

        LPStakingStorage.LPPool memory zeroAddrPool;
        zeroAddrPool.lpTokenAddress = address(0);
        zeroAddrPool.baseRewardRate = 1;
        zeroAddrPool.active = true;
        assertEq(RewardCalculator.calculateRewards(pos, zeroAddrPool, tier, currentTime), 0, "Pool with zero address should yield 0 rewards");

        LPStakingStorage.LPPool memory inactivePool;
        inactivePool.lpTokenAddress = address(0x1);
        inactivePool.baseRewardRate = 1;
        inactivePool.active = false;
        assertEq(RewardCalculator.calculateRewards(pos, inactivePool, tier, currentTime), 0, "Inactive pool should yield 0 rewards");
    }

    function test_CalculateRewards_TimeElapsedZero_LastClaimEqualsCurrentTime() public {
        vm.warp(10 days);
        uint256 currentTime = block.timestamp;

        LPStakingStorage.LPStakingPosition memory pos;
        pos.amount = 100e18; 
        pos.startTime = currentTime - 10;
        pos.endTime = currentTime + 10;
        pos.lastClaimTime = currentTime;
        pos.tierId = 0; 
        pos.lpToken = address(0x1); 
        pos.active = true;

        LPStakingStorage.LPPool memory pool;
        pool.lpTokenAddress = address(0x1); 
        pool.baseRewardRate = calculatePoolInputRate(1000); 
        pool.active = true;

        LPStakingStorage.Tier memory tier;
        tier.rewardMultiplier = 10000; 
        tier.active = true;

        assertEq(RewardCalculator.calculateRewards(pos, pool, tier, currentTime), 0, "Zero time elapsed (lastClaim == current) failed");
    }

    function test_CalculateRewards_TimeElapsedZero_CurrentTimeBeforeLastClaim() public {
        vm.warp(20 days);
        uint256 currentTime = block.timestamp;

        LPStakingStorage.LPStakingPosition memory pos;
        pos.amount = 100e18; 
        pos.startTime = currentTime - 20 days;
        pos.endTime = currentTime + 10 days;
        pos.lastClaimTime = currentTime + 5 days;
        pos.tierId = 0; 
        pos.lpToken = address(0x1); 
        pos.active = true;

        LPStakingStorage.LPPool memory pool;
        pool.lpTokenAddress = address(0x1); 
        pool.baseRewardRate = calculatePoolInputRate(1000); 
        pool.active = true;

        LPStakingStorage.Tier memory tier;
        tier.rewardMultiplier = 10000; 
        tier.active = true;
        assertEq(RewardCalculator.calculateRewards(pos, pool, tier, currentTime), 0, "Zero time elapsed (current < lastClaim) failed");
    }


    function test_CalculateRewards_EndTimePassed_LastClaimBeforeEndTime() public {
        vm.warp(60 days);
        uint256 currentTime = block.timestamp;

        LPStakingStorage.LPStakingPosition memory pos;
        pos.amount = 100e18;
        pos.startTime = currentTime - 30 days;
        pos.endTime = currentTime - 10 days;
        pos.lastClaimTime = currentTime - 20 days;
        pos.tierId = 0; 
        pos.lpToken = address(0x1); 
        pos.active = true;

        LPStakingStorage.Tier memory tier;
        tier.rewardMultiplier = 10000; 
        tier.active = true;
        tier.duration = 20 days;

        LPStakingStorage.LPPool memory pool;
        pool.lpTokenAddress = address(0x1); 
        pool.baseRewardRate = calculatePoolInputRate(1000); 
        pool.active = true;

        uint256 rewardableTime = pos.endTime - pos.lastClaimTime;
        uint256 expectedReward = RewardMath.calculateReward(
            pos.amount,
            pool.baseRewardRate,
            rewardableTime,
            tier.rewardMultiplier
        );

        assertEq(RewardCalculator.calculateRewards(pos, pool, tier, currentTime), expectedReward, "EndTime passed, last claim before end failed");
    }

    function test_CalculateRewards_EndTimePassed_LastClaimAtOrAfterEndTime() public {
        vm.warp(60 days);
        uint256 currentTime = block.timestamp;

        LPStakingStorage.LPPool memory pool;
        pool.lpTokenAddress = address(0x1); 
        pool.baseRewardRate = calculatePoolInputRate(1000); 
        pool.active =true;

        LPStakingStorage.Tier memory tier;
        tier.rewardMultiplier = 10000; 
        tier.active =true;
        tier.duration = 20 days;

        LPStakingStorage.LPStakingPosition memory pos1;
        pos1.amount = 100e18; 
        pos1.startTime = currentTime - 30 days; 
        pos1.endTime = currentTime - 10 days;
        pos1.lastClaimTime = currentTime - 10 days;
        pos1.tierId = 0; 
        pos1.lpToken = address(0x1); 
        pos1.active = true;
        assertEq(RewardCalculator.calculateRewards(pos1, pool, tier, currentTime), 0, "EndTime passed, last claim at end failed");

        LPStakingStorage.LPStakingPosition memory pos2;
        pos2.amount = 100e18; 
        pos2.startTime = currentTime - 30 days; 
        pos2.endTime = currentTime - 10 days;
        pos2.lastClaimTime = currentTime - 5 days;
        pos2.tierId = 0; 
        pos2.lpToken = address(0x1); 
        pos2.active = true;
        assertEq(RewardCalculator.calculateRewards(pos2, pool, tier, currentTime), 0, "EndTime passed, last claim after end failed");
    }

    function test_CalculateRewards_UsesRewardMathCorrectly() public {
        vm.warp(500 days);
        uint256 currentTime = block.timestamp;

        LPStakingStorage.LPStakingPosition memory pos;
        pos.amount = 12345 * 1e18;
        pos.startTime = currentTime - (100 * 24 * 3600);
        pos.endTime = currentTime + (265 * 24 * 3600);
        pos.lastClaimTime = currentTime - (50 * 24 * 3600);
        pos.tierId = 0; 
        pos.lpToken = address(0xABC);
        pos.active = true;

        LPStakingStorage.Tier memory tier;
        tier.duration = 365 * 24 * 3600;
        tier.rewardMultiplier = 12000;
        tier.earlyWithdrawalPenalty = 1000;
        tier.active = true;

        LPStakingStorage.LPPool memory pool;
        pool.lpTokenAddress = address(0xABC);
        pool.baseRewardRate = calculatePoolInputRate(500);
        pool.active = true;

        uint256 timeElapsedForMath = currentTime - pos.lastClaimTime;
        uint256 mathLibReward = RewardMath.calculateReward(
            pos.amount,
            pool.baseRewardRate,
            timeElapsedForMath,
            tier.rewardMultiplier
        );

        uint256 calculatorLibReward = RewardCalculator.calculateRewards(pos, pool, tier, currentTime);

        assertEq(calculatorLibReward, mathLibReward, "RewardCalculator output differs from direct RewardMath call");
    }
}
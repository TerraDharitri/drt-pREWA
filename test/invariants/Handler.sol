// test/invariants/Handler.sol

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {TokenStaking} from "../../contracts/core/TokenStaking.sol";
import {PREWAToken} from "../../contracts/core/pREWAToken.sol";
import {Constants} from "../../contracts/libraries/Constants.sol";

contract Handler is Test {
    TokenStaking public stakingContract;
    PREWAToken public pREWAToken;

    // Keep track of user stakes
    mapping(address => mapping(uint256 => uint256)) public userStakes;
    mapping(address => uint256) public positionCounts;
    address[] public stakers;

    uint256 public totalActiveStakeValue;

    constructor(TokenStaking _stakingContract) {
        stakingContract = _stakingContract;
        // The address points to the real PREWAToken, so we cast it to the real type.
        pREWAToken = PREWAToken(payable(stakingContract.getStakingTokenAddress()));
        
        // NOTE: All state setup (like funding) is moved to the test's setUp function
        // to ensure the Handler remains a passive, stateless actor.
    }
    
    function stake(address staker, uint96 amount) public {
        if (amount == 0) return;
        
        if (positionCounts[staker] == 0) {
            stakers.push(staker);
        }
        
        // Minting is now done by the authorized admin in the test's setUp.
        // For fuzzing, we can simulate the user having tokens by just dealing them.
        vm.deal(staker, pREWAToken.balanceOf(staker) + amount);
        
        vm.prank(staker);
        pREWAToken.approve(address(stakingContract), amount);

        vm.prank(staker);
        uint256 positionId = stakingContract.stake(amount, 0);

        userStakes[staker][positionId] = amount;
        positionCounts[staker]++;
        totalActiveStakeValue += amount;
    }

    function unstake(address staker, uint256 posId) public {
        uint256 numPositions = positionCounts[staker];
        if (numPositions == 0 || posId >= numPositions) return;

        (,,uint256 endTime,,,) = stakingContract.getStakingPosition(staker, posId);
        
        if (block.timestamp < endTime) {
            vm.warp(endTime + 1);
        }

        uint256 stakeAmount = userStakes[staker][posId];
        if (stakeAmount == 0) return;

        vm.prank(staker);
        stakingContract.unstake(posId);
        
        totalActiveStakeValue -= stakeAmount;
        userStakes[staker][posId] = 0;
    }

    function warp(uint256 time) public {
        vm.warp(block.timestamp + time % (365 days));
    }
    
    function sumOfBalances() public view returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < stakers.length; i++) {
            sum += pREWAToken.balanceOf(stakers[i]);
        }
        return sum;
    }
    
    function getUsers() public view returns (address[] memory) {
        return stakers;
    }
}
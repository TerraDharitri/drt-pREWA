// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "contracts/core/interfaces/ITokenStaking.sol";
import "contracts/core/interfaces/IpREWAToken.sol";
import "./mocks/DeployedAddresses.s.sol"; 

contract TestClaimRewards is Script, Test {
    address constant STAKER_ADDRESS = 0xd80F79d95b6520C8a5125df9ea669e5f6DA48969; 
    uint256 constant TIER_ID_TO_TEST = 0;
    uint256 constant AMOUNT_TO_STAKE = 100 * 1e18;
    
    ITokenStaking tokenStaking = ITokenStaking(DeployedContracts.TokenStaking_97);
    IpREWAToken pREWA = IpREWAToken(DeployedContracts.pREWAToken_97);

    function run() external {
        uint256 stakerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 initialPositionCount = tokenStaking.getPositionCount(STAKER_ADDRESS);
        
        // --- 1. Stake Transaction ---
        vm.startBroadcast(stakerPrivateKey);
        pREWA.approve(address(tokenStaking), AMOUNT_TO_STAKE);
        uint256 newPositionId = tokenStaking.stake(AMOUNT_TO_STAKE, TIER_ID_TO_TEST);
        vm.stopBroadcast();
        
        assertEq(newPositionId, initialPositionCount, "Position ID mismatch.");
        console.log("Staking successful. New position created with ID:", newPositionId);
        
        uint256 balanceBeforeClaim = pREWA.balanceOf(STAKER_ADDRESS);
        
        // --- 2. Advance Time ---
        // THIS IS THE KEY CHANGE: Explicitly mine a new block
        // This ensures the next transaction has a new, later timestamp.
        vm.roll(block.number + 1); 
        vm.warp(block.timestamp + 91 days);
        
        console.log("\n>>> Warped time forward 91 days <<<");

        // --- 3. Check Rewards ---
        uint256 rewardsAvailable = tokenStaking.calculateRewards(STAKER_ADDRESS, newPositionId);
        console.log("pREWA Rewards Available:", rewardsAvailable / 1e18);
        assertTrue(rewardsAvailable > 0, "No rewards accrued after time warp.");

        // --- 4. Claim Transaction ---
        vm.startBroadcast(stakerPrivateKey);
        tokenStaking.claimRewards(newPositionId);
        vm.stopBroadcast();
        
        // --- 5. Verify ---
        uint256 balanceAfterClaim = pREWA.balanceOf(STAKER_ADDRESS);
        console.log("\nTransaction successful!");
        assertEq(balanceAfterClaim, balanceBeforeClaim + rewardsAvailable, "Final balance mismatch.");
        
        console.log("\nTest Passed: Staked and claimed successfully.");
    }
}
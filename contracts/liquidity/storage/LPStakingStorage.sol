// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../access/AccessControl.sol";        
import "../../controllers/EmergencyController.sol"; 

/**
 * @title LPStakingStorage
 * @author Rewa
 * @notice Defines the storage layout for the LPStaking contract.
 * @dev This contract is not meant to be deployed. It is inherited by LPStaking to separate
 * storage variables from logic, which can help in managing upgrades.
 */
contract LPStakingStorage {
    /**
     * @notice Represents a user's single LP staking position.
     * @param amount The amount of LP tokens staked.
     * @param startTime The timestamp when the stake was created.
     * @param endTime The timestamp when the stake matures and rewards stop accruing.
     * @param lastClaimTime The timestamp of the last reward claim for this position.
     * @param tierId The ID of the tier this position belongs to.
     * @param lpToken The address of the LP token staked.
     * @param active A flag indicating if the position is currently active.
     */
    struct LPStakingPosition {
        uint256 amount;         
        uint256 startTime;      
        uint256 endTime;        
        uint256 lastClaimTime;  
        uint256 tierId;         
        address lpToken;        
        bool active;            
    }

    /**
     * @notice Represents a staking tier with specific parameters.
     * @param duration The required staking duration in seconds.
     * @param rewardMultiplier The reward multiplier for this tier, in basis points (10000 = 1x).
     * @param earlyWithdrawalPenalty The penalty for unstaking before maturity, in basis points.
     * @param active A flag indicating if the tier is available for new stakes.
     */
    struct Tier {
        uint256 duration;               
        uint256 rewardMultiplier;       
        uint256 earlyWithdrawalPenalty; 
        bool active;                    
    }

    /**
     * @notice Represents a pool for a specific LP token.
     * @param lpTokenAddress The address of the LP token for this pool.
     * @param baseRewardRate The base reward rate, scaled for internal calculations.
     * @param active A flag indicating if the pool is active for new stakes.
     */
    struct LPPool {
        address lpTokenAddress; 
        uint256 baseRewardRate; 
        bool active;            
    }

    /// @dev The owner of the contract, with administrative privileges.
    address internal _owner;

    /// @dev The total amount of all LP tokens (by value) staked in the contract. This is a conceptual value and not directly tracked as a sum.
    uint256 internal _totalStaked; 
    /// @dev The minimum staking duration allowed for any tier.
    uint256 internal _minStakeDuration;

    /// @dev The penalty applied for emergency withdrawals, in basis points.
    uint256 internal _emergencyWithdrawalPenalty;
    /// @dev A flag indicating whether emergency withdrawals are enabled.
    bool internal _emergencyWithdrawalEnabled;

    /// @dev A mapping from a user's address to their array of staking positions.
    mapping(address => LPStakingPosition[]) internal _userStakingPositions;
    /// @dev A mapping from a tier ID to its corresponding Tier struct.
    mapping(uint256 => Tier) internal _tiers;
    /// @dev A mapping from an LP token address to its corresponding LPPool struct.
    mapping(address => LPPool) internal _pools;
    /// @dev A mapping from an LP token address to the total amount of that token staked.
    mapping(address => uint256) internal _poolTotalStaked; 
    /// @notice A mapping to quickly check if a token address is a registered LP token.
    mapping(address => bool) public isLPToken;
    /// @dev The total number of created tiers, which also serves as the next tier ID.
    uint256 internal _tierCount;

    /// @dev A mapping to prevent a user from creating multiple stakes in the same block.
    mapping(address => uint256) internal _lastStakeBlockNumberLP;

    /**
     * @dev Reserved storage space to allow for future upgrades without storage collisions.
     * This is a best practice for upgradeable contracts.
     */
    uint256[40] private __gap;
}
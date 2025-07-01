// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title TokenStakingStorage
 * @author Rewa
 * @notice Defines the storage layout for the TokenStaking contract.
 * @dev This contract is not meant to be deployed. It is inherited by TokenStaking to separate
 * storage variables from logic, which can help in managing upgrades.
 */
contract TokenStakingStorage {
    /**
     * @notice Represents a user's single staking position.
     * @param amount The amount of tokens staked in this position.
     * @param startTime The timestamp when the stake was created.
     * @param endTime The timestamp when the stake matures and rewards stop accruing.
     * @param lastClaimTime The timestamp of the last reward claim for this position.
     * @param tierId The ID of the tier this position belongs to.
     * @param active A flag indicating if the position is currently active.
     */
    struct StakingPosition {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        uint256 lastClaimTime;
        uint256 tierId;
        bool active;
    }

    /**
     * @notice Represents a staking tier with specific parameters.
     * @param duration The required staking duration in seconds.
     * @param rewardMultiplier The reward multiplier for this tier, in basis points (10000 = 1x).
     * @param earlyWithdrawalPenalty The penalty for unstaking before the duration ends, in basis points.
     * @param active A flag indicating if the tier is available for new stakes.
     */
    struct Tier {
        uint256 duration;
        uint256 rewardMultiplier;
        uint256 earlyWithdrawalPenalty;
        bool active;
    }

    /// @dev The address of the staking token.
    address internal _tokenAddress;
    /// @dev The base Annual Percentage Rate for rewards, in basis points.
    uint256 internal _baseAPRBps;
    /// @dev The total amount of tokens currently staked in the contract.
    uint256 internal _totalStaked;
    /// @dev The minimum staking duration allowed for any tier.
    uint256 internal _minStakeDuration;
    /// @dev The penalty applied for emergency withdrawals, in basis points.
    uint256 internal _emergencyWithdrawalPenalty;
    /// @dev A flag indicating whether emergency withdrawals are enabled.
    bool internal _emergencyWithdrawalEnabled;
    /// @dev A mapping from a user's address to their array of staking positions.
    mapping(address => StakingPosition[]) internal _userStakingPositions;
    /// @dev A mapping from a tier ID to its corresponding Tier struct.
    mapping(uint256 => Tier) internal _tiers;
    /// @dev The total number of created tiers, which also serves as the next tier ID.
    uint256 internal _tierCount;
    /// @notice The maximum number of active staking positions a single user can have.
    uint256 internal _maxPositionsPerUser; 
    /// @dev A mapping to prevent a user from creating multiple stakes in the same block.
    mapping(address => uint256) internal _lastStakeBlockNumber; 
    
    /**
     * @dev Reserved storage space to allow for future upgrades without storage collisions.
     * This is a best practice for upgradeable contracts.
     */
    uint256[50] private __gap;
}
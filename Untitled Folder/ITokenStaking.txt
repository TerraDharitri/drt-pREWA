// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../../interfaces/IEmergencyAware.sol";

/**
 * @title ITokenStaking Interface
 * @notice Defines the external interface for the TokenStaking contract.
 */
interface ITokenStaking is IEmergencyAware {
    /**
     * @notice Emitted when a user stakes tokens.
     * @param user The address of the staker.
     * @param amount The amount of tokens staked.
     * @param tierId The ID of the staking tier.
     * @param positionId The ID of the newly created staking position.
     */
    event Staked(address indexed user, uint256 amount, uint256 indexed tierId, uint256 positionId);

    /**
     * @notice Emitted when a user unstakes tokens from a position.
     * @param user The address of the staker.
     * @param amount The amount of tokens unstaked (after any penalty).
     * @param positionId The ID of the unstaked position.
     * @param penaltyAmount The amount of tokens deducted as a penalty.
     */
    event Unstaked(address indexed user, uint256 amount, uint256 indexed positionId, uint256 penaltyAmount);

    /**
     * @notice Emitted when a user claims rewards from a staking position.
     * @param user The address of the claimant.
     * @param amount The amount of reward tokens claimed.
     * @param positionId The ID of the position from which rewards were claimed.
     */
    event RewardsClaimed(address indexed user, uint256 amount, uint256 indexed positionId);

    /**
     * @notice Emitted when the emergency withdrawal settings are updated.
     * @param enabled True if emergency withdrawal is enabled.
     * @param penalty The new penalty in basis points.
     * @param updater The address that performed the update.
     */
    event EmergencyWithdrawalSettingsUpdated(bool enabled, uint256 penalty, address indexed updater);

    /**
     * @notice Emitted when a new staking tier is added.
     * @param tierId The ID of the new tier.
     * @param duration The staking duration of the tier in seconds.
     * @param rewardMultiplier The reward multiplier of the tier in basis points.
     * @param earlyWithdrawalPenalty The penalty for early withdrawal from the tier in basis points.
     * @param creator The address that added the tier.
     */
    event TierAdded(uint256 indexed tierId, uint256 duration, uint256 rewardMultiplier, uint256 earlyWithdrawalPenalty, address indexed creator);

    /**
     * @notice Emitted when an existing staking tier is updated.
     * @param tierId The ID of the updated tier.
     * @param duration The new duration for the tier.
     * @param rewardMultiplier The new reward multiplier for the tier.
     * @param earlyWithdrawalPenalty The new early withdrawal penalty for the tier.
     * @param active The new active status of the tier.
     * @param updater The address that updated the tier.
     */
    event TierUpdated(uint256 indexed tierId, uint256 duration, uint256 rewardMultiplier, uint256 earlyWithdrawalPenalty, bool active, address indexed updater);

    /**
     * @notice Emitted when the base APR for staking rewards is updated.
     * @param oldBaseAPRBps The previous base APR in basis points.
     * @param newBaseAPRBps The new base APR in basis points.
     * @param correspondingScaledRate The internal scaled rate representation of the new APR.
     * @param updater The address that performed the update.
     */
    event BaseAPRUpdated(uint256 oldBaseAPRBps, uint256 newBaseAPRBps, uint256 correspondingScaledRate, address indexed updater);

    /**
     * @notice Emitted when the minimum staking duration is updated.
     * @param oldDuration The previous minimum duration.
     * @param newDuration The new minimum duration.
     * @param updater The address that performed the update.
     */
    event MinStakeDurationUpdated(uint256 oldDuration, uint256 newDuration, address indexed updater);

    /**
     * @notice Emitted when the maximum number of positions per user is updated.
     * @param oldMax The previous maximum number of positions.
     * @param newMax The new maximum number of positions.
     * @param updater The address that performed the update.
     */
    event MaxPositionsPerUserUpdated(uint256 oldMax, uint256 newMax, address indexed updater);

    /**
     * @notice Emitted when staking is paused.
     * @param account The address that initiated the pause.
     */
    event StakingPaused(address account);

    /**
     * @notice Emitted when staking is unpaused.
     * @param account The address that initiated the unpause.
     */
    event StakingUnpaused(address account);

    /**
     * @notice Initializes the TokenStaking contract.
     * @param stakingTokenAddress_ The address of the pREWA token to be staked.
     * @param accessControlAddr_ Address of the AccessControl contract.
     * @param emergencyControllerAddr_ Address of the EmergencyController contract.
     * @param oracleIntegrationAddr_ Address of the OracleIntegration contract (can be address(0)).
     * @param initialBaseAPRBps_ The initial base Annual Percentage Rate in basis points.
     * @param minStakeDurationVal_ The minimum duration for any staking tier.
     * @param adminAddr_ The initial owner/admin of the contract.
     * @param initialMaxPositionsPerUser_ The maximum number of active staking positions a user can have.
     */
    function initialize(
        address stakingTokenAddress_,
        address accessControlAddr_,
        address emergencyControllerAddr_,
        address oracleIntegrationAddr_,
        uint256 initialBaseAPRBps_,
        uint256 minStakeDurationVal_,
        address adminAddr_,
        uint256 initialMaxPositionsPerUser_
    ) external;

    /**
     * @notice Stakes a specified amount of tokens into a chosen tier.
     * @param amount The amount of tokens to stake.
     * @param tierId The ID of the staking tier.
     * @return positionId The ID of the newly created staking position.
     */
    function stake(uint256 amount, uint256 tierId) external returns (uint256 positionId);

    /**
     * @notice Unstakes a position, claims any pending rewards, and returns the principal tokens.
     * @param positionId The ID of the user's staking position to unstake.
     * @return amountUnstaked The amount of tokens returned to the user after any penalties.
     */
    function unstake(uint256 positionId) external returns (uint256 amountUnstaked);

    /**
     * @notice Claims pending rewards for a specific staking position without unstaking.
     * @param positionId The ID of the user's staking position.
     * @return amountClaimed The amount of reward tokens claimed.
     */
    function claimRewards(uint256 positionId) external returns (uint256 amountClaimed);

    /**
     * @notice Allows a user to withdraw their staked tokens during an emergency.
     * @param positionId The ID of the user's staking position to withdraw.
     * @return amountWithdrawn The amount of tokens returned to the user after the emergency penalty.
     */
    function emergencyWithdraw(uint256 positionId) external returns (uint256 amountWithdrawn);

    /**
     * @notice Adds a new staking tier.
     * @param duration The staking duration for this tier in seconds.
     * @param rewardMultiplier The reward multiplier for this tier in basis points.
     * @param earlyWithdrawalPenalty The penalty for early unstaking in basis points.
     * @return tierId The ID of the newly created tier.
     */
    function addTier(uint256 duration, uint256 rewardMultiplier, uint256 earlyWithdrawalPenalty) external returns (uint256 tierId);

    /**
     * @notice Updates an existing staking tier's parameters.
     * @param tierId The ID of the tier to update.
     * @param duration The new staking duration for the tier.
     * @param rewardMultiplier The new reward multiplier for the tier.
     * @param earlyWithdrawalPenalty The new early withdrawal penalty for the tier.
     * @param active The new active status for the tier.
     * @return success True if the operation was successful.
     */
    function updateTier(uint256 tierId, uint256 duration, uint256 rewardMultiplier, uint256 earlyWithdrawalPenalty, bool active) external returns (bool success);

    /**
     * @notice Configures the emergency withdrawal settings.
     * @param enabled Whether to enable or disable emergency withdrawals.
     * @param penalty The penalty to apply on emergency withdrawals in basis points.
     * @return success True if the operation was successful.
     */
    function setEmergencyWithdrawal(bool enabled, uint256 penalty) external returns (bool success);

    /**
     * @notice Sets the base Annual Percentage Rate for staking rewards.
     * @param newBaseAPRBps The new base APR in basis points.
     * @return success True if the operation was successful.
     */
    function setBaseAnnualPercentageRate(uint256 newBaseAPRBps) external returns (bool success);

    /**
     * @notice Sets the minimum staking duration for all tiers.
     * @param duration The new minimum duration in seconds.
     * @return success True if the operation was successful.
     */
    function setMinStakeDuration(uint256 duration) external returns (bool success);

    /**
     * @notice Sets the maximum number of active staking positions a user can have.
     * @param maxPositions The new maximum number of positions.
     * @return success True if the operation was successful.
     */
    function setMaxPositionsPerUser(uint256 maxPositions) external returns (bool success);

    /**
     * @notice Pauses the staking functionality.
     * @return success True if the operation was successful.
     */
    function pauseStaking() external returns (bool success);

    /**
     * @notice Unpauses the staking functionality.
     * @return success True if the operation was successful.
     */
    function unpauseStaking() external returns (bool success);

    /**
     * @notice Checks if the staking contract is currently paused.
     * @return True if staking is paused.
     */
    function isStakingPaused() external view returns (bool);

    /**
     * @notice Retrieves information about a specific staking tier.
     * @param tierId The ID of the tier.
     * @return duration The staking duration of the tier.
     * @return rewardMultiplier The reward multiplier of the tier.
     * @return earlyWithdrawalPenalty The early withdrawal penalty of the tier.
     * @return active True if the tier is active.
     */
    function getTierInfo(uint256 tierId) external view returns (uint256 duration, uint256 rewardMultiplier, uint256 earlyWithdrawalPenalty, bool active);

    /**
     * @notice Retrieves the details of a specific staking position.
     * @param user The address of the staker.
     * @param positionId The ID of the staking position.
     * @return amount The staked amount.
     * @return startTime The timestamp when the stake was created.
     * @return endTime The timestamp when the stake matures.
     * @return lastClaimTime The timestamp of the last reward claim.
     * @return tierId The ID of the staking tier.
     * @return active True if the position is active.
     */
    function getStakingPosition(address user, uint256 positionId) external view returns (
        uint256 amount,
        uint256 startTime,
        uint256 endTime,
        uint256 lastClaimTime,
        uint256 tierId,
        bool active
    );

    /**
     * @notice Calculates the pending rewards for a specific staking position.
     * @param user The address of the staker.
     * @param positionId The ID of the staking position.
     * @return rewardsAmount The amount of pending rewards.
     */
    function calculateRewards(address user, uint256 positionId) external view returns (uint256 rewardsAmount);

    /**
     * @notice Gets the total amount of tokens staked in the contract.
     * @return totalStakedAmount The total staked amount.
     */
    function totalStaked() external view returns (uint256 totalStakedAmount);

    /**
     * @notice Gets the total number of staking positions for a user.
     * @param user The address of the user.
     * @return count The number of positions.
     */
    function getPositionCount(address user) external view returns (uint256 count);

    /**
     * @notice Gets the address of the token being staked.
     * @return The address of the staking token.
     */
    function getStakingTokenAddress() external view returns (address);

    /**
     * @notice Gets the current base APR for staking rewards.
     * @return aprBps The base APR in basis points.
     */
    function getBaseAnnualPercentageRate() external view returns (uint256 aprBps);

    /**
     * @notice Gets the current emergency withdrawal settings.
     * @return enabled True if emergency withdrawal is enabled.
     * @return penaltyBps The penalty in basis points.
     */
    function getEmergencyWithdrawalSettings() external view returns (bool enabled, uint256 penaltyBps);

    /**
     * @notice Gets the maximum number of active staking positions per user.
     * @return maxPositions The maximum number of positions.
     */
    function getMaxPositionsPerUser() external view returns (uint256 maxPositions);
}
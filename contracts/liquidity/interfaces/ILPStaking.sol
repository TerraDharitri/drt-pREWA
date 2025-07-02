// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../interfaces/IEmergencyAware.sol";
import "../../access/AccessControl.sol";
import "../../controllers/EmergencyController.sol";

/**
 * @title ILPStaking Interface
 * @notice Defines the external interface for the LPStaking contract.
 */
interface ILPStaking is IEmergencyAware {
    /**
     * @notice Emitted when a user stakes LP tokens.
     * @param user The address of the staker.
     * @param amount The amount of LP tokens staked.
     * @param lpToken The address of the staked LP token.
     * @param tierId The ID of the staking tier.
     * @param positionId The ID of the newly created staking position.
     */
    event LPStaked(address indexed user, uint256 amount, address indexed lpToken, uint256 indexed tierId, uint256 positionId);

    /**
     * @notice Emitted when a user unstakes LP tokens.
     * @param user The address of the staker.
     * @param amount The amount of LP tokens unstaked (after penalty).
     * @param lpToken The address of the unstaked LP token.
     * @param positionId The ID of the unstaked position.
     * @param penaltyAmount The amount of LP tokens deducted as a penalty.
     */
    event LPUnstaked(address indexed user, uint256 amount, address indexed lpToken, uint256 indexed positionId, uint256 penaltyAmount);

    /**
     * @notice Emitted when a user claims rewards from a staking position.
     * @param user The address of the claimant.
     * @param amount The amount of reward tokens claimed.
     * @param lpToken The address of the LP token corresponding to the position.
     * @param positionId The ID of the position from which rewards were claimed.
     */
    event LPRewardsClaimed(address indexed user, uint256 amount, address indexed lpToken, uint256 indexed positionId);

    /**
     * @notice Emitted when a new LP token pool is added.
     * @param lpToken The address of the LP token for the new pool.
     * @param baseAPRBps The base Annual Percentage Rate for the pool, in basis points.
     * @param correspondingScaledRate The internal scaled rate representation of the APR.
     * @param creator The address that added the pool.
     */
    event PoolAdded(address indexed lpToken, uint256 baseAPRBps, uint256 correspondingScaledRate, address indexed creator);

    /**
     * @notice Emitted when an existing LP token pool is updated.
     * @param lpToken The address of the updated LP token pool.
     * @param newBaseAPRBps The new base APR for the pool, in basis points.
     * @param correspondingScaledRate The new internal scaled rate.
     * @param active The new active status of the pool.
     * @param updater The address that updated the pool.
     */
    event PoolUpdated(address indexed lpToken, uint256 newBaseAPRBps, uint256 correspondingScaledRate, bool active, address indexed updater);

    /**
     * @notice Emitted when a new staking tier is added.
     * @param tierId The ID of the new tier.
     * @param duration The staking duration of the tier, in seconds.
     * @param rewardMultiplier The reward multiplier of the tier, in basis points.
     * @param earlyWithdrawalPenalty The penalty for early withdrawal from the tier, in basis points.
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
     * @notice Emitted when the emergency withdrawal settings are changed.
     * @param enabled True if emergency withdrawal is enabled, false otherwise.
     * @param penalty The penalty applied during emergency withdrawal, in basis points.
     * @param updater The address that updated the settings.
     */
    event LPStakingEmergencyWithdrawalSet(bool enabled, uint256 penalty, address indexed updater);

    /**
     * @notice Emitted when the EmergencyController address is changed.
     * @param oldController The address of the old EmergencyController.
     * @param newController The address of the new EmergencyController.
     * @param setter The address that performed the update.
     */
    event LPStakingEmergencyControllerSet(address indexed oldController, address indexed newController, address indexed setter);

    /**
     * @notice Emitted when a discrepancy is detected between a pool's total staked amount and an unstake amount.
     * @dev This event is critical for off-chain monitoring to detect potential state inconsistencies.
     * @param lpToken The address of the LP token pool with the inconsistency.
     * @param poolTotal The recorded total staked amount for the pool before the unstake operation.
     * @param unstakeAmount The amount being unstaked that caused the inconsistency.
     */
    event PoolTotalStakedInconsistency(address indexed lpToken, uint256 poolTotal, uint256 unstakeAmount);

    /**
     * @notice Initializes the LPStaking contract.
     * @param pREWATokenAddress_ The address of the pREWA reward token.
     * @param liquidityManagerAddr_ The address of the LiquidityManager contract.
     * @param initialOwner_ The address of the initial owner of the contract.
     * @param minStakeDuration_ The minimum duration for any staking tier.
     * @param accessControlAddr_ The address of the AccessControl contract.
     * @param emergencyControllerAddr_ The address of the EmergencyController contract.
     */
    function initialize(
        address pREWATokenAddress_,
        address liquidityManagerAddr_,
        address initialOwner_,
        uint256 minStakeDuration_,
        address accessControlAddr_,
        address emergencyControllerAddr_
    ) external;

    /**
     * @notice Stakes a specified amount of an LP token into a chosen tier.
     * @param lpToken The address of the LP token to stake.
     * @param amount The amount of the LP token to stake.
     * @param tierId The ID of the staking tier to use.
     * @return positionId The ID of the newly created staking position for the user.
     */
    function stakeLPTokens(address lpToken, uint256 amount, uint256 tierId) external returns (uint256 positionId);

    /**
     * @notice Unstakes a position, claims any pending rewards, and returns the principal LP tokens.
     * @param positionId The ID of the user's staking position to unstake.
     * @return amountUnstaked The amount of LP tokens returned to the user after any penalties.
     */
    function unstakeLPTokens(uint256 positionId) external returns (uint256 amountUnstaked);

    /**
     * @notice Claims pending rewards for a specific staking position without unstaking.
     * @param positionId The ID of the user's staking position.
     * @return amountClaimed The amount of reward tokens claimed.
     */
    function claimLPRewards(uint256 positionId) external returns (uint256 amountClaimed);

    /**
     * @notice Allows a user to withdraw their staked LP tokens during an emergency.
     * @param positionId The ID of the user's staking position to withdraw.
     * @return amountWithdrawn The amount of LP tokens returned to the user after the emergency penalty.
     */
    function emergencyWithdrawLP(uint256 positionId) external returns (uint256 amountWithdrawn);

    /**
     * @notice Adds a new LP token pool for staking.
     * @param lpToken The address of the LP token for the new pool.
     * @param baseAPRBpsIn The base Annual Percentage Rate for rewards, in basis points.
     * @return success A boolean indicating if the operation was successful.
     */
    function addPool(address lpToken, uint256 baseAPRBpsIn) external returns (bool success);

    /**
     * @notice Updates an existing LP token pool's parameters.
     * @param lpToken The address of the LP token for the pool to update.
     * @param newBaseAPRBpsIn The new base APR for the pool, in basis points.
     * @param active The new active status for the pool.
     * @return success A boolean indicating if the operation was successful.
     */
    function updatePool(address lpToken, uint256 newBaseAPRBpsIn, bool active) external returns (bool success);

    /**
     * @notice Adds a new staking tier.
     * @param duration The staking duration for this tier, in seconds.
     * @param rewardMultiplier The reward multiplier for this tier, in basis points.
     * @param earlyWithdrawalPenalty The penalty for early unstaking, in basis points.
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
     * @return success A boolean indicating if the operation was successful.
     */
    function updateTier(uint256 tierId, uint256 duration, uint256 rewardMultiplier, uint256 earlyWithdrawalPenalty, bool active) external returns (bool success);

    /**
     * @notice Configures the emergency withdrawal settings.
     * @param enabled Whether to enable or disable emergency withdrawals.
     * @param penalty The penalty to apply on emergency withdrawals, in basis points.
     * @return success A boolean indicating if the operation was successful.
     */
    function setLPEmergencyWithdrawal(bool enabled, uint256 penalty) external returns (bool success);

    /**
     * @notice Retrieves the details of a specific LP staking position.
     * @param user The address of the staker.
     * @param positionId The ID of the staking position.
     * @return amount The staked amount.
     * @return startTime The timestamp when the stake was created.
     * @return endTime The timestamp when the stake matures.
     * @return lastClaimTime The timestamp of the last reward claim.
     * @return tierId The ID of the staking tier.
     * @return lpToken The address of the staked LP token.
     * @return active True if the position is active, false otherwise.
     */
    function getLPStakingPosition(address user, uint256 positionId) external view returns (
        uint256 amount, uint256 startTime, uint256 endTime,
        uint256 lastClaimTime, uint256 tierId, address lpToken, bool active
    );

    /**
     * @notice Calculates the pending rewards for a specific staking position.
     * @param user The address of the staker.
     * @param positionId The ID of the staking position.
     * @return rewardsAmount The amount of pending rewards.
     */
    function calculateLPRewards(address user, uint256 positionId) external view returns (uint256 rewardsAmount);

    /**
     * @notice Retrieves information about a specific LP token pool.
     * @param lpToken The address of the LP token pool.
     * @return baseAPRBpsOut The base APR of the pool, in basis points.
     * @return totalStakedInPoolOut The total amount of the LP token staked in this pool.
     * @return isActiveOut True if the pool is active, false otherwise.
     */
    function getPoolInfo(address lpToken) external view returns (
        uint256 baseAPRBpsOut,
        uint256 totalStakedInPoolOut,
        bool isActiveOut
    );

    /**
     * @notice Retrieves information about a specific staking tier.
     * @param tierId The ID of the tier.
     * @return duration The staking duration of the tier.
     * @return rewardMultiplier The reward multiplier of the tier.
     * @return earlyWithdrawalPenalty The early withdrawal penalty of the tier.
     * @return active True if the tier is active, false otherwise.
     */
    function getTierInfo(uint256 tierId) external view returns (
        uint256 duration, uint256 rewardMultiplier, uint256 earlyWithdrawalPenalty, bool active
    );

    /**
     * @notice Gets the total number of staking positions for a user.
     * @param user The address of the user.
     * @return count The number of positions.
     */
    function getLPPositionCount(address user) external view returns (uint256 count);

    /**
     * @notice Gets the current emergency withdrawal settings.
     * @return enabled True if emergency withdrawal is enabled.
     * @return penaltyBps The penalty in basis points.
     */
    function getLPEmergencyWithdrawalSettings() external view returns (bool enabled, uint256 penaltyBps);
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IVesting Interface
 * @notice Defines the external interface for a single vesting contract.
 */
interface IVesting {
    /**
     * @notice Emitted when a beneficiary releases vested tokens.
     * @param beneficiary The address of the beneficiary receiving the tokens.
     * @param amount The amount of tokens released.
     */
    event TokensReleased(address indexed beneficiary, uint256 amount);

    /**
     * @notice Emitted when a vesting schedule is revoked by its owner.
     * @param revoker The address of the owner who revoked the vesting.
     * @param amount The amount of unvested tokens refunded to the owner.
     */
    event VestingRevoked(address indexed revoker, uint256 amount);

    /**
     * @notice Initializes the vesting contract with full emergency and oracle integration.
     * @param tokenAddress The address of the ERC20 token to be vested.
     * @param beneficiary The address that will receive the vested tokens.
     * @param startTime The timestamp when the vesting period begins.
     * @param cliffDuration The duration in seconds during which no tokens are vested.
     * @param duration The total duration of the vesting period.
     * @param revocable A flag indicating if the vesting can be revoked.
     * @param totalAmount The total amount of tokens to be vested.
     * @param initialOwner The address that owns and can revoke the vesting schedule.
     * @param emergencyControllerAddress The address of the system's EmergencyController.
     * @param oracleIntegrationAddress The address of the system's OracleIntegration contract.
     */
    function initialize(
        address tokenAddress,
        address beneficiary,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 duration,
        bool revocable,
        uint256 totalAmount,
        address initialOwner,
        address emergencyControllerAddress,
        address oracleIntegrationAddress
    ) external;

    /**
     * @notice Initializes the vesting contract without emergency or oracle integration.
     * @param tokenAddress The address of the ERC20 token to be vested.
     * @param beneficiary The address that will receive the vested tokens.
     * @param startTime The timestamp when the vesting period begins.
     * @param cliffDuration The duration in seconds during which no tokens are vested.
     * @param duration The total duration of the vesting period.
     * @param revocable A flag indicating if the vesting can be revoked.
     * @param totalAmount The total amount of tokens to be vested.
     * @param initialOwner The address that owns and can revoke the vesting schedule.
     */
    function initialize(
        address tokenAddress,
        address beneficiary,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 duration,
        bool revocable,
        uint256 totalAmount,
        address initialOwner
    ) external;

    /**
     * @notice Allows the beneficiary to release their currently vested and unreleased tokens.
     * @return amount The amount of tokens successfully released.
     */
    function release() external returns (uint256 amount);

    /**
     * @notice Allows the owner to revoke the vesting schedule.
     * @dev Any unvested tokens are returned to the owner. Any vested but unreleased tokens are sent to the beneficiary.
     * @return amount The amount of unvested tokens refunded to the owner.
     */
    function revoke() external returns (uint256 amount);

    /**
     * @notice Retrieves all details of the vesting schedule.
     * @return beneficiary The beneficiary's address.
     * @return totalAmount The total amount in the schedule.
     * @return startTime The start timestamp.
     * @return cliffDuration The cliff duration in seconds.
     * @return duration The total duration in seconds.
     * @return releasedAmount The amount already released.
     * @return revocable True if the schedule is revocable.
     * @return revoked True if the schedule has been revoked.
     */
    function getVestingSchedule() external view returns (
        address beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 duration,
        uint256 releasedAmount,
        bool revocable,
        bool revoked
    );

    /**
     * @notice Calculates the amount of tokens that are currently vested but not yet released.
     * @return The amount of tokens available for release.
     */
    function releasableAmount() external view returns (uint256);

    /**
     * @notice Calculates the total amount of tokens that should have vested at a specific point in time.
     * @param timestamp The timestamp to check against.
     * @return The total vested amount at the given timestamp.
     */
    function vestedAmount(uint256 timestamp) external view returns (uint256);

    /**
     * @notice Returns the owner of the vesting schedule.
     * @return The owner's address.
     */
    function owner() external view returns (address);
}
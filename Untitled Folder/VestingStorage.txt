// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title VestingStorage
 * @author Rewa
 * @notice Defines the storage layout for the VestingImplementation contract.
 * @dev This contract is not meant to be deployed. It is inherited by VestingImplementation to separate
 * storage variables from logic, which can help in managing upgrades.
 */
contract VestingStorage {
    /**
     * @notice Represents the complete vesting schedule for a single beneficiary.
     * @param beneficiary The address that will receive the vested tokens.
     * @param totalAmount The total amount of tokens to be vested over the entire duration.
     * @param startTime The timestamp when the vesting period begins.
     * @param cliffDuration The duration in seconds from the start time during which no tokens are vested.
     * @param duration The total duration of the vesting period in seconds, starting from `startTime`.
     * @param releasedAmount The amount of tokens that have already been released to the beneficiary.
     * @param revocable A flag indicating whether the vesting can be revoked by the owner.
     * @param revoked A flag indicating whether the vesting has been revoked.
     */
    struct VestingSchedule {
        address beneficiary;
        uint256 totalAmount;
        uint256 startTime;
        uint256 cliffDuration;
        uint256 duration;
        uint256 releasedAmount;
        bool revocable;
        bool revoked;
    }

    /// @dev The address of the ERC20 token being vested.
    address internal _tokenAddress;             
    /// @dev The address of the factory contract that created this vesting contract.
    address internal _factoryAddress;           
    /// @dev The struct containing all details of the vesting schedule.
    VestingSchedule internal _vestingSchedule;  
    /// @dev The owner of the vesting schedule, with the ability to revoke (if revocable).
    address internal _owner;
}
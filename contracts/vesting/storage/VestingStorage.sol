// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title VestingStorage
 * @author drt-pREWA
 * @notice Defines the storage layout for the VestingImplementation contract.
 * @dev This contract is not meant to be deployed directly. It is inherited by VestingImplementation
 * to separate storage variables from logic, following the unstructured storage pattern for upgradeability.
 */
contract VestingStorage {
    /**
     * @notice Represents the complete vesting schedule for a single beneficiary.
     * @param beneficiary The address that will receive the vested tokens.
     * @param totalAmount The total amount of tokens to be vested over the entire duration.
     * @param startTime The Unix timestamp when the vesting period begins.
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

    /// @notice The address of the ERC20 token being vested (pREWA).
    address internal _tokenAddress;             

    /// @notice The address of the VestingFactory contract that created this vesting contract.
    address internal _factoryAddress;           

    /// @notice The struct containing all details of this specific vesting schedule.
    VestingSchedule internal _vestingSchedule;  

    /// @notice The owner of the vesting schedule, who has the ability to revoke it (if revocable).
    address internal _owner;

    /// @notice Reserved storage space to allow for future upgrades without storage collisions.
    uint256[50] private __gap;
}
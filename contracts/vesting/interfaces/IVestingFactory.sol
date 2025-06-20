// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IVestingFactory Interface
 * @notice Defines the external interface for the VestingFactory contract.
 */
interface IVestingFactory {
    /**
     * @notice Emitted when a new vesting contract is created.
     * @param vestingContract The address of the newly deployed vesting proxy contract.
     * @param beneficiary The address of the beneficiary of the vesting schedule.
     * @param amount The total amount of tokens being vested.
     * @param owner The address that created and owns the vesting schedule.
     */
    event VestingCreated(address indexed vestingContract, address indexed beneficiary, uint256 amount, address indexed owner);

    /**
     * @notice Creates and initializes a new vesting contract (proxy) for a beneficiary.
     * @param beneficiary The address that will receive the vested tokens.
     * @param startTime The timestamp when the vesting period begins. Use 0 for current block timestamp.
     * @param cliffDuration The duration in seconds during which no tokens are vested.
     * @param duration The total duration of the vesting period in seconds.
     * @param revocable A flag indicating whether the vesting can be revoked by the owner.
     * @param amount The total amount of tokens to be vested.
     * @return vestingAddress The address of the newly created vesting contract.
     */
    function createVesting(
        address beneficiary,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 duration,
        bool revocable,
        uint256 amount
    ) external returns (address vestingAddress);

    /**
     * @notice Retrieves all vesting contracts created for a specific beneficiary.
     * @param beneficiary The address of the beneficiary.
     * @return An array of vesting contract addresses.
     */
    function getVestingsByBeneficiary(address beneficiary) external view returns (address[] memory);

    /**
     * @notice Retrieves all vesting contracts created by a specific owner.
     * @param owner The address of the owner.
     * @return An array of vesting contract addresses.
     */
    function getVestingsByOwner(address owner) external view returns (address[] memory);

    /**
     * @notice Gets the address of the current vesting implementation contract.
     * @return The implementation address.
     */
    function getImplementation() external view returns (address);

    /**
     * @notice Sets a new implementation address for future vesting contract creations.
     * @param newImplementation The address of the new implementation contract.
     * @return success A boolean indicating if the operation was successful.
     */
    function setImplementation(address newImplementation) external returns (bool success);

    /**
     * @notice Gets the address of the token used for vesting.
     * @return The token address.
     */
    function getTokenAddress() external view returns (address);
}
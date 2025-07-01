// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IEmergencyAware Interface
 * @notice Defines a standard interface for contracts that can be managed by an EmergencyController.
 * @dev Contracts implementing this interface can have their state checked and modified by a central
 * emergency management system, allowing for coordinated responses to threats.
 */
interface IEmergencyAware {
    /**
     * @notice Emitted when an emergency status check is performed.
     * @param emergencyLevel The current system-wide emergency level at the time of the check.
     * @param operation The function selector of the operation being checked.
     * @param allowed A boolean indicating whether the operation was allowed to proceed.
     */
    event EmergencyStatusChecked(uint8 emergencyLevel, bytes4 operation, bool allowed);

    /**
     * @notice Emitted when a contract has processed an `emergencyShutdown` signal from the controller.
     * @param emergencyLevel The emergency level that was handled.
     * @param caller The address of the controller that initiated the shutdown signal.
     */
    event EmergencyShutdownHandled(uint8 emergencyLevel, address indexed caller);

    /**
     * @notice Checks if a specific operation is allowed based on the current emergency status.
     * @dev This function is typically called by modifiers within the implementing contract to guard functions.
     * @param operation The 4-byte function selector of the operation being attempted.
     * @return allowed A boolean indicating if the operation is permitted.
     */
    function checkEmergencyStatus(bytes4 operation) external view returns (bool allowed);

    /**
     * @notice A function to be called by the EmergencyController to trigger a state change in the contract.
     * @dev The implementing contract defines how it should react to different emergency levels.
     * For example, it might pause itself or enable emergency withdrawals.
     * @param emergencyLevel The system-wide emergency level being broadcast by the controller.
     * @return success A boolean indicating if the shutdown was handled successfully.
     */
    function emergencyShutdown(uint8 emergencyLevel) external returns (bool success);

    /**
     * @notice Returns the address of the EmergencyController managing this contract.
     * @return controller The address of the EmergencyController.
     */
    function getEmergencyController() external view returns (address controller);

    /**
     * @notice Sets or updates the address of the EmergencyController.
     * @dev This function should be access-controlled within the implementing contract (e.g., `onlyOwner`).
     * @param controller The address of the new EmergencyController.
     * @return success A boolean indicating if the operation was successful.
     */
    function setEmergencyController(address controller) external returns (bool success);

    /**
     * @notice Checks if the contract is effectively paused, either locally or by the global EmergencyController.
     * @return isPaused A boolean indicating if the contract is considered to be in a paused state.
     */
    function isEmergencyPaused() external view returns (bool isPaused);
}
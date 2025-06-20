// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../interfaces/IEmergencyAware.sol";
import "../controllers/EmergencyController.sol";
import "../libraries/Constants.sol";

/**
 * @title EmergencyAwareBase
 * @author Rewa
 * @notice An abstract base contract that provides a standardized, robust, and reusable
 * implementation for checking the global emergency status from the EmergencyController.
 * @dev It centralizes the logic to prevent code duplication and ensure consistent behavior across all
 * emergency-aware contracts in the system.
 */
abstract contract EmergencyAwareBase is IEmergencyAware {
    /**
     * @notice The central controller for system-wide emergency states.
     * @dev This contract must be compatible with the IEmergencyController interface.
     */
    EmergencyController public emergencyController;

    /**
     * @notice Centralized logic to determine if the system is effectively paused.
     * @dev A system is considered paused if the EmergencyController has directly paused it,
     * or if the emergency level has been escalated to `EMERGENCY_LEVEL_CRITICAL`.
     * This function uses try/catch blocks for maximum resilience against external call failures.
     * @return isPaused True if the system is effectively paused, false otherwise.
     */
    function _isEffectivelyPaused() internal view returns (bool isPaused) {
        if (address(emergencyController) == address(0)) {
            return false;
        }

        bool ecSystemPaused = false;
        uint8 ecLevel = Constants.EMERGENCY_LEVEL_NORMAL;

        try emergencyController.isSystemPaused() returns (bool p) {
            ecSystemPaused = p;
        } catch {}
        
        try emergencyController.getEmergencyLevel() returns (uint8 l) {
            ecLevel = l;
        } catch {}
        
        isPaused = ecSystemPaused || (ecLevel >= Constants.EMERGENCY_LEVEL_CRITICAL);
        return isPaused;
    }
}
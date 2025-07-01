// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./storage/LPStakingStorage.sol";
import "../libraries/Errors.sol";
import "../libraries/Constants.sol";
import "../utils/EmergencyAwareBase.sol";
import "../interfaces/IEmergencyAware.sol";
import "../access/AccessControl.sol";

/**
 * @title LPStakingUtils
 * @author Rewa
 * @notice An abstract contract providing shared utilities, modifiers, and storage for the LPStaking contract.
 * @dev This contract is not meant to be deployed directly but is inherited by `LPStaking`. It includes
 * ownership, role-based access control, and pause-related modifiers and initializes the underlying
 * OpenZeppelin modules.
 */
abstract contract LPStakingUtils is
    LPStakingStorage,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    EmergencyAwareBase
{
    /// @notice The AccessControl contract instance.
    AccessControl public accessControl; 

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        if (msg.sender != _owner) revert NotOwner();
        _;
    }

    /**
     * @dev Throws if called by any account that does not have the `PARAMETER_ROLE`.
     */
    modifier onlyParameterRole() {
        if (address(accessControl) == address(0)) revert NotInitialized(); 
        if (!accessControl.hasRole(accessControl.PARAMETER_ROLE(), msg.sender)) {
            revert NotAuthorized(accessControl.PARAMETER_ROLE());
        }
        _;
    }

    /**
     * @dev Initializes the Pausable and ReentrancyGuard modules.
     * This function is internal and can only be called during initialization.
     */
    function __LPStakingUtils_init() internal virtual onlyInitializing { 
        __Pausable_init();
        __ReentrancyGuard_init();
    }
}
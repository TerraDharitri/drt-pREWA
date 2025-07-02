// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../access/AccessControl.sol"; 
import "../libraries/Errors.sol"; 

/**
 * @title EmergencyTimelockController
 * @author Rewa
 * @notice A timelock controller specifically for proposing, executing, and cancelling privileged emergency actions.
 * @dev This contract allows accounts with the `EMERGENCY_ROLE` to propose actions on allowlisted target
 * contracts. These actions can only be executed after a specified timelock period has passed,
 * providing a window for review and response. It is upgradeable.
 */
contract EmergencyTimelockController is 
    Initializable, 
    ReentrancyGuardUpgradeable 
{
    /// @notice The contract that controls roles and permissions.
    AccessControl public accessControl;
    
    /// @notice The duration in seconds that must pass after a proposal before it can be executed.
    uint256 public timelockDuration;
    
    /// @notice The minimum allowed duration for the timelock.
    uint256 public constant MIN_TIMELOCK_DURATION = 1 hours;
    
    /// @notice The maximum allowed duration for the timelock.
    uint256 public constant MAX_TIMELOCK_DURATION = 7 days;
    
    /// @notice A mapping of contract addresses that are approved targets for timelocked actions.
    mapping(address => bool) public allowedTargets;
    
    /// @notice A mapping of function selectors that are approved to be called via timelocked actions.
    mapping(bytes4 => bool) public allowedFunctionSelectors;
    
    /**
     * @notice Struct representing a proposed emergency action.
     * @param emergencyLevel The emergency level associated with the action.
     * @param proposalTime The timestamp when the action was proposed.
     * @param proposer The address that proposed the action.
     * @param target The address of the contract to be called.
     * @param data The calldata for the function to be executed.
     * @param executed A flag indicating if the action has been executed.
     * @param cancelled A flag indicating if the action has been cancelled.
     */
    struct EmergencyAction {
        uint8 emergencyLevel;
        uint256 proposalTime;
        address proposer;
        address target;       
        bytes data;           
        bool executed;
        bool cancelled;
    }
    
    /// @notice A mapping from a unique action ID to its corresponding EmergencyAction struct.
    mapping(bytes32 => EmergencyAction) public emergencyActions;
    
    /// @notice An array of all proposed action IDs for enumeration.
    bytes32[] public allActionIds;
    
    /**
     * @notice Emitted when a new emergency action is proposed.
     * @param actionId The unique ID of the proposed action.
     * @param emergencyLevel The emergency level associated with the action.
     * @param proposer The address that proposed the action.
     * @param proposalTime The timestamp of the proposal.
     * @param target The address of the contract to be called.
     * @param functionSelector The selector of the function to be called.
     * @param data The full calldata for the proposed action.
     */
    event EmergencyActionProposed(
        bytes32 indexed actionId,
        uint8 emergencyLevel,
        address indexed proposer,
        uint256 proposalTime,
        address indexed target,
        bytes4 functionSelector,
        bytes data
    );
    
    /**
     * @notice Emitted when a proposed emergency action is executed.
     * @param actionId The unique ID of the executed action.
     * @param emergencyLevel The emergency level of the action.
     * @param executor The address that executed the action.
     * @param target The address of the contract that was called.
     * @param functionSelector The selector of the function that was called.
     * @param executionTime The timestamp of the execution.
     */
    event EmergencyActionExecuted(
        bytes32 indexed actionId,
        uint8 emergencyLevel,
        address indexed executor,
        address indexed target,
        bytes4 functionSelector,
        uint256 executionTime
    );
    
    /**
     * @notice Emitted when a proposed emergency action is cancelled.
     * @param actionId The unique ID of the cancelled action.
     * @param canceller The address that cancelled the action.
     * @param cancellationTime The timestamp of the cancellation.
     */
    event EmergencyActionCancelled(
        bytes32 indexed actionId,
        address indexed canceller,
        uint256 cancellationTime
    );
    
    /**
     * @notice Emitted when the timelock duration is updated.
     * @param oldDuration The previous timelock duration.
     * @param newDuration The new timelock duration.
     * @param updater The address that performed the update.
     */
    event TimelockDurationUpdated(
        uint256 oldDuration,
        uint256 newDuration,
        address indexed updater
    );
    
    /**
     * @notice Emitted when a target contract's status on the allowlist is changed.
     * @param target The address of the target contract.
     * @param allowed True if the target is now allowed, false otherwise.
     * @param updater The address that performed the update.
     */
    event TargetAllowlistUpdated(
        address indexed target, 
        bool allowed,
        address indexed updater
    );
    
    /**
     * @notice Emitted when a function selector's status on the allowlist is changed.
     * @param selector The 4-byte function selector.
     * @param allowed True if the selector is now allowed, false otherwise.
     * @param updater The address that performed the update.
     */
    event FunctionSelectorAllowlistUpdated(
        bytes4 indexed selector, 
        bool allowed,
        address indexed updater
    );
    
    /**
     * @dev Reserved storage space to allow for future upgrades without storage collisions.
     * This is a best practice for upgradeable contracts.
     */
    uint256[50] private __gap; 
    
    /**
     * @dev Disables the regular constructor to make the contract upgradeable.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the EmergencyTimelockController.
     * @dev Sets the AccessControl contract and the initial timelock duration. Can only be called once.
     * @param accessControlAddress The address of the AccessControl contract.
     * @param initialTimelockDuration The initial timelock duration in seconds.
     */
    function initialize(
        address accessControlAddress,
        uint256 initialTimelockDuration
    ) external initializer {
        __ReentrancyGuard_init();
        
        if(accessControlAddress == address(0)) revert ZeroAddress("accessControlAddress");
        if (initialTimelockDuration < MIN_TIMELOCK_DURATION || initialTimelockDuration > MAX_TIMELOCK_DURATION) {
            revert InvalidDuration();
        }
        
        accessControl = AccessControl(accessControlAddress);
        timelockDuration = initialTimelockDuration;
    }
    
    /**
     * @dev Modifier to restrict access to functions to addresses with the EMERGENCY_ROLE.
     */
    modifier onlyEmergencyRole() {
        if (!accessControl.hasRole(accessControl.EMERGENCY_ROLE(), msg.sender)) {
            revert NotAuthorized(accessControl.EMERGENCY_ROLE());
        }
        _;
    }
    
    /**
     * @notice Adds or removes a contract address from the list of allowed targets for emergency actions.
     * @param target The address of the target contract.
     * @param allowed True to allow, false to disallow.
     * @return success A boolean indicating if the operation was successful.
     */
    function setAllowedTarget(address target, bool allowed) external onlyEmergencyRole returns (bool success) {
        if (target == address(0)) revert ZeroAddress("target");
        
        allowedTargets[target] = allowed;
        
        emit TargetAllowlistUpdated(target, allowed, msg.sender);
        return true;
    }
    
    /**
     * @notice Adds or removes a function selector from the list of allowed functions for emergency actions.
     * @param selector The 4-byte function selector.
     * @param allowed True to allow, false to disallow.
     * @return success A boolean indicating if the operation was successful.
     */
    function setAllowedFunctionSelector(bytes4 selector, bool allowed) external onlyEmergencyRole returns (bool success) {
        if (selector == bytes4(0)) revert InvalidAmount();
        
        allowedFunctionSelectors[selector] = allowed;
        
        emit FunctionSelectorAllowlistUpdated(selector, allowed, msg.sender);
        return true;
    }
    
    /**
     * @notice Proposes a new emergency action to be executed after a timelock.
     * @dev The target contract and function selector must both be on the allowlist.
     * @param emergencyLevel The emergency level associated with this action.
     * @param target The address of the contract to call.
     * @param data The calldata for the function to be executed on the target.
     * @return actionId A unique ID for the proposed action.
     */
    function proposeEmergencyAction(
        uint8 emergencyLevel,
        address target,
        bytes calldata data
    ) external onlyEmergencyRole nonReentrant returns (bytes32 actionId) {
        if (emergencyLevel > 3) revert EC_InvalidEmergencyLevel(emergencyLevel);
        if (target == address(0)) revert ZeroAddress("target");
        if (data.length < 4) revert ETC_DataTooShortForSelector(); 
        if (!allowedTargets[target]) revert NotAuthorized(bytes32(0));
        
        // Securely extract the function selector by first copying calldata to memory.
        // This prevents vulnerabilities related to unaligned calldata reads.
        bytes memory dataMemory = data;
        bytes4 functionSelector;
        assembly {
            functionSelector := mload(add(dataMemory, 32))
        }
        
        if (!allowedFunctionSelectors[functionSelector]) revert NotAuthorized(bytes32(0));
        
        actionId = keccak256(abi.encodePacked(block.timestamp, emergencyLevel, msg.sender, target, data));
        
        EmergencyAction storage existingAction = emergencyActions[actionId];
        if (existingAction.proposalTime != 0) revert InvalidAmount();
        
        emergencyActions[actionId] = EmergencyAction({
            emergencyLevel: emergencyLevel,
            proposalTime: block.timestamp,
            proposer: msg.sender,
            target: target,
            data: data,
            executed: false,
            cancelled: false
        });
        
        allActionIds.push(actionId);
        
        emit EmergencyActionProposed(
            actionId,
            emergencyLevel,
            msg.sender,
            block.timestamp,
            target,
            functionSelector,
            data
        );
        
        return actionId;
    }
    
    /**
     * @notice Executes a proposed emergency action after the timelock period has passed.
     * @dev Performs checks to ensure the action is valid, executable, and still allowed.
     * It then performs a low-level call to the target contract.
     * @param actionId The ID of the action to execute.
     * @return success A boolean indicating if the execution was successful.
     */
    function executeEmergencyAction(
        bytes32 actionId
    ) external onlyEmergencyRole nonReentrant returns (bool success) {
        EmergencyAction storage action = emergencyActions[actionId];
        
        if (action.proposalTime == 0) revert InvalidAmount();
        if (action.executed) revert InvalidAmount();
        if (action.cancelled) revert InvalidAmount();
        
        uint256 safeUnlockTime = action.proposalTime + timelockDuration; 
        if (block.timestamp < safeUnlockTime) revert PA_TimelockNotYetExpired();
        
        bytes memory dataBytes = action.data; 
        if (dataBytes.length < 4) revert ETC_DataTooShortForSelector(); 
        
        // Securely extract the function selector from the in-memory copy of the data.
        bytes4 functionSelector;
        assembly {
            functionSelector := mload(add(dataBytes, 32))
        }
        
        if(!allowedFunctionSelectors[functionSelector]) revert NotAuthorized(bytes32(0));
        if(!allowedTargets[action.target]) revert NotAuthorized(bytes32(0));
        
        address targetAddress = action.target;
        uint8 emergencyLevel = action.emergencyLevel;
        
        action.executed = true;
        
        emit EmergencyActionExecuted(
            actionId,
            emergencyLevel,
            msg.sender,
            targetAddress,
            functionSelector,
            block.timestamp
        );
        
        // Low-level call to the target contract. This is a privileged operation, but access to this
        // function is heavily restricted by the `onlyEmergencyRole` modifier, timelock, and allowlists.
        // The return data is bubbled up to provide detailed error information on failure.
        (bool callSuccess, bytes memory returnData) = targetAddress.call(dataBytes); 
        
        if (!callSuccess) {
            if (returnData.length > 0) {
                assembly {
                    let returnDataSize := mload(returnData)
                    revert(add(32, returnData), returnDataSize)
                }
            } else {
                revert("EmergencyTimelock: execution failed with no error data");
            }
        }
        
        return true;
    }
    
    /**
     * @notice Cancels a previously proposed emergency action.
     * @param actionId The ID of the action to cancel.
     * @return success A boolean indicating if the cancellation was successful.
     */
    function cancelEmergencyAction(
        bytes32 actionId
    ) external onlyEmergencyRole nonReentrant returns (bool success) {
        EmergencyAction storage action = emergencyActions[actionId];
        
        if (action.proposalTime == 0) revert InvalidAmount();
        if (action.executed) revert InvalidAmount();
        if (action.cancelled) revert InvalidAmount();
        
        action.cancelled = true;
        
        emit EmergencyActionCancelled(
            actionId,
            msg.sender,
            block.timestamp
        );
        
        return true;
    }
    
    /**
     * @notice Updates the timelock duration for all future proposals.
     * @param newDuration The new timelock duration in seconds.
     * @return success A boolean indicating if the update was successful.
     */
    function updateTimelockDuration(
        uint256 newDuration
    ) external onlyEmergencyRole returns (bool success) {
        if (newDuration < MIN_TIMELOCK_DURATION || newDuration > MAX_TIMELOCK_DURATION) {
            revert InvalidDuration();
        }
        
        uint256 oldDuration = timelockDuration;
        timelockDuration = newDuration;
        
        emit TimelockDurationUpdated(
            oldDuration,
            newDuration,
            msg.sender
        );
        
        return true;
    }
    
    /**
     * @notice Retrieves the current status of a proposed action.
     * @param actionId The ID of the action.
     * @return exists True if the action exists.
     * @return executed True if the action has been executed.
     * @return cancelled True if the action has been cancelled.
     * @return timeRemaining The time in seconds remaining until the action can be executed.
     */
    function getActionStatus(
        bytes32 actionId
    ) external view returns (
        bool exists,
        bool executed,
        bool cancelled,
        uint256 timeRemaining
    ) {
        EmergencyAction storage action = emergencyActions[actionId];
        
        exists = action.proposalTime > 0;
        
        if (!exists) {
            return (false, false, false, 0);
        }
        
        executed = action.executed;
        cancelled = action.cancelled;
        
        if (executed || cancelled) {
            return (exists, executed, cancelled, 0);
        }
        
        uint256 unlockTime = action.proposalTime + timelockDuration;
        uint256 currentTime = block.timestamp;
        
        if (currentTime >= unlockTime) {
            timeRemaining = 0;
        } else {
            timeRemaining = unlockTime - currentTime;
        }
        
        return (exists, executed, cancelled, timeRemaining);
    }
    
    /**
     * @notice Returns an array of all proposed action IDs.
     * @return actionIds An array of all action IDs.
     */
    function getAllActionIds() external view returns (bytes32[] memory actionIds) {
        return allActionIds;
    }
    
    /**
     * @notice Retrieves the full details of a proposed action.
     * @param actionId The ID of the action.
     * @return emergencyLevel The action's emergency level.
     * @return proposalTime The action's proposal timestamp.
     * @return proposer The address of the proposer.
     * @return target The address of the target contract.
     * @return data The calldata of the proposed call.
     * @return executed True if executed.
     * @return cancelled True if cancelled.
     */
    function getActionDetails(
        bytes32 actionId
    ) external view returns (
        uint8 emergencyLevel,
        uint256 proposalTime,
        address proposer,
        address target,
        bytes memory data,
        bool executed,
        bool cancelled
    ) {
        EmergencyAction storage action = emergencyActions[actionId];
        
        if(action.proposalTime == 0) revert InvalidAmount();
        
        return (
            action.emergencyLevel,
            action.proposalTime,
            action.proposer,
            action.target,
            action.data,
            action.executed,
            action.cancelled
        );
    }
    
    /**
     * @notice Checks if a function selector is on the allowlist.
     * @param selector The function selector to check.
     * @return allowed True if the selector is allowed.
     */
    function isFunctionSelectorAllowed(bytes4 selector) external view returns (bool allowed) {
        return allowedFunctionSelectors[selector];
    }
    
    /**
     * @notice Checks if a target contract address is on the allowlist.
     * @param target The address to check.
     * @return allowed True if the target is allowed.
     */
    function isTargetAllowed(address target) external view returns (bool allowed) {
        return allowedTargets[target];
    }
}
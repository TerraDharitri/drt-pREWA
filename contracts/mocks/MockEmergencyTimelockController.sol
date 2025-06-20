// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../access/AccessControl.sol";

contract MockEmergencyTimelockController {
    struct MockEmergencyAction {
        uint8 emergencyLevel;
        uint256 proposalTime;
        address proposer;
        address target;
        bytes data;
        bool executed;
        bool cancelled;
        bool exists;
        uint256 unlockTime;
    }
    mapping(bytes32 => MockEmergencyAction) public mockActions;
    mapping(address => bool) public mockAllowedTargets;
    mapping(bytes4 => bool) public mockAllowedFunctionSelectors;
    uint256 public mockTimelockDuration = 1 hours;

    AccessControl public mockAccessControl;

    event MockProposeEmergencyActionCalled(bytes32 actionId, uint8 level, address target, bytes data);
    event MockExecuteEmergencyActionCalled(bytes32 actionId, bool expectedSuccess);
    event MockCancelEmergencyActionCalled(bytes32 actionId);
    event MockSetAllowedTargetCalled(address target, bool allowed);
    event MockSetAllowedFunctionSelectorCalled(bytes4 selector, bool allowed);

    constructor(address accessControlAddress) {
        if (accessControlAddress != address(0)) {
            mockAccessControl = AccessControl(accessControlAddress);
        }
    }

    function setMockAction(bytes32 actionId, MockEmergencyAction memory actionData) external {
        mockActions[actionId] = actionData;
    }

    function setMockTimelockDuration(uint256 duration) external {
        mockTimelockDuration = duration;
    }

    function setMockAccessControl(address acAddress) external {
        mockAccessControl = AccessControl(acAddress);
    }

    function setAllowedTarget(address target, bool allowed) external returns (bool success) {
        mockAllowedTargets[target] = allowed;
        emit MockSetAllowedTargetCalled(target, allowed);
        return true;
    }

    function setAllowedFunctionSelector(bytes4 selector, bool allowed) external returns (bool success) {
        mockAllowedFunctionSelectors[selector] = allowed;
        emit MockSetAllowedFunctionSelectorCalled(selector, allowed);
        return true;
    }

    function proposeEmergencyAction(
        uint8 emergencyLevel,
        address target,
        bytes calldata data
    ) external returns (bytes32 actionId) {
        require(mockAllowedTargets[target], "MockETC: Target not allowed");
        bytes4 selector;
        if (data.length >= 4) {
            selector = bytes4(data[0:4]);
        }
        require(mockAllowedFunctionSelectors[selector], "MockETC: Selector not allowed");

        actionId = keccak256(abi.encodePacked(block.timestamp, emergencyLevel, msg.sender, target, data));
        mockActions[actionId] = MockEmergencyAction({
            emergencyLevel: emergencyLevel,
            proposalTime: block.timestamp,
            proposer: msg.sender,
            target: target,
            data: data,
            executed: false,
            cancelled: false,
            exists: true,
            unlockTime: block.timestamp + mockTimelockDuration
        });
        emit MockProposeEmergencyActionCalled(actionId, emergencyLevel, target, data);
        return actionId;
    }

    function executeEmergencyAction(bytes32 actionId) external returns (bool success) {
        MockEmergencyAction storage action = mockActions[actionId];
        require(action.exists, "MockETC: Action does not exist");
        require(!action.executed, "MockETC: Action already executed");
        require(!action.cancelled, "MockETC: Action cancelled");
        require(block.timestamp >= action.unlockTime, "MockETC: Timelock not expired");
        
        action.executed = true;
        emit MockExecuteEmergencyActionCalled(actionId, true);
        return true;
    }

    function cancelEmergencyAction(bytes32 actionId) external returns (bool success) {
        MockEmergencyAction storage action = mockActions[actionId];
        require(action.exists, "MockETC: Action does not exist");
        require(!action.executed, "MockETC: Action already executed");
        require(!action.cancelled, "MockETC: Action already cancelled");

        action.cancelled = true;
        emit MockCancelEmergencyActionCalled(actionId);
        return true;
    }

    function getActionStatus(
        bytes32 actionId
    ) external view returns (
        bool exists,
        bool executed,
        bool cancelled,
        uint256 timeRemaining
    ) {
        MockEmergencyAction storage action = mockActions[actionId];
        exists = action.exists;
        if (!exists) return (false, false, false, 0);

        executed = action.executed;
        cancelled = action.cancelled;

        if (executed || cancelled) return (exists, executed, cancelled, 0);

        if (block.timestamp >= action.unlockTime) {
            timeRemaining = 0;
        } else {
            timeRemaining = action.unlockTime - block.timestamp;
        }
        return (exists, executed, cancelled, timeRemaining);
    }
}
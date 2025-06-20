pragma solidity ^0.8.28;

import "../interfaces/IEmergencyAware.sol";

contract MockIEmergencyAware is IEmergencyAware {
    bool public mockIsPaused;
    bool public mockCheckStatusAllowed = true;
    address public mockEcAddress;
    address public mockOwner;
    bool public shouldRevertOnShutdown;

    uint8 public lastEmergencyLevelReceived;
    address public lastEmergencyCaller;

    constructor(address _owner) {
        mockOwner = _owner;
    }

    function setMockIsPaused(bool _isPaused) external {
        mockIsPaused = _isPaused;
    }
    function setMockCheckStatusAllowed(bool _allowed) external {
        mockCheckStatusAllowed = _allowed;
    }
    function setMockEcAddress(address _ec) external {
        mockEcAddress = _ec;
    }
    function setShouldRevertOnShutdown(bool _revert) external {
        shouldRevertOnShutdown = _revert;
    }

    function checkEmergencyStatus(bytes4) external view override returns (bool allowed) {
        return mockCheckStatusAllowed;
    }

    function emergencyShutdown(uint8 emergencyLevel) external override returns (bool success) {
        if (shouldRevertOnShutdown) {
            revert("MockIEA: Shutdown reverted by mock setting");
        }
        lastEmergencyLevelReceived = emergencyLevel;
        lastEmergencyCaller = msg.sender;
        emit EmergencyShutdownHandled(emergencyLevel, msg.sender);
        return true;
    }

    function getEmergencyController() external view override returns (address controller) {
        return mockEcAddress;
    }

    function setEmergencyController(address controller) external override returns (bool success) {
        require(msg.sender == mockOwner, "MockIEA: Not owner");
        mockEcAddress = controller;
        return true;
    }

    function isEmergencyPaused() external view override returns (bool isPaused) {
        return mockIsPaused;
    }
}
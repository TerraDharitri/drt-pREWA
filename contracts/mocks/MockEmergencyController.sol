// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../interfaces/IEmergencyController.sol";
import "../interfaces/IEmergencyAware.sol"; 

contract MockEmergencyController is IEmergencyController {

    uint8 public mockEmergencyLevel;
    bool public mockSystemPaused;
    bool public mockEmergencyWithdrawalEnabled;
    uint256 public mockEmergencyWithdrawalPenalty;
    address public mockRecoveryAdminAddress;

    mapping(bytes4 => uint8) public mockRestrictedFunctionsThreshold;
    mapping(address => bool) public mockIsEmergencyAwareContract;
    address[] public mockEmergencyAwareContractsArray;
    mapping(address => bool) public mockApprovals;
    address[] public mockApproversArray;

    uint256 public mockRequiredApprovals = 1;
    uint256 public mockCurrentApprovalCount;
    bool public mockLevel3TimelockInProgress;
    uint256 public mockLevel3ApprovalTime;
    uint256 public mockLevel3TimelockDuration = 1 hours;
    
    bool public shouldRevert; // General revert flag for testing EC failure scenarios
    bool public revertIsFunctionRestricted;
    bool public revertIsSystemPaused;
    bool public revertGetEmergencyLevel;

    event MockSetEmergencyLevelCalled(uint8 level);
    event MockEnableEmergencyWithdrawalCalled(bool enabled, uint256 penalty);
    event MockPauseSystemCalled();
    event MockUnpauseSystemCalled();
    event MockRecoverTokensCalled(address tokenAddress, uint256 amount);
    event MockProcessEmergencyForContractCalled(address contractAddr, uint8 level, bool callSuccess);
    event MockApproveLevel3EmergencyCalled(address approver);
    event MockCancelLevel3EmergencyCalled(address canceller);
    event MockExecuteLevel3EmergencyCalled(address executor);

    function setShouldRevert(bool _revert) external {
        shouldRevert = _revert;
    }

    function setRevertFlags(bool Pfer, bool Psys, bool Plevel) external {
        revertIsFunctionRestricted = Pfer;
        revertIsSystemPaused = Psys;
        revertGetEmergencyLevel = Plevel;
    }

    function setMockEmergencyLevel(uint8 level) external {
        if (shouldRevert) revert("MockEC Reverted");
        mockEmergencyLevel = level;
        emit EmergencyLevelSet(level, msg.sender);
    }

    function setMockSystemPaused(bool paused) external {
        if (shouldRevert) revert("MockEC Reverted");
        mockSystemPaused = paused;
        if (paused) emit SystemPaused(msg.sender);
        else emit SystemUnpaused(msg.sender);
    }

    function setMockEmergencyWithdrawal(bool enabled, uint256 penalty) external {
        if (shouldRevert) revert("MockEC Reverted");
        mockEmergencyWithdrawalEnabled = enabled;
        mockEmergencyWithdrawalPenalty = penalty;
        emit EmergencyWithdrawalSet(enabled, penalty);
    }
    
    function setMockRecoveryAdminAddress(address newAdmin) external {
        mockRecoveryAdminAddress = newAdmin;
    }

    function setMockFunctionRestriction(bytes4 selector, uint8 threshold) external {
        mockRestrictedFunctionsThreshold[selector] = threshold;
    }

    function addMockEmergencyAwareContract(address contractAddr) external {
        if (!mockIsEmergencyAwareContract[contractAddr]) {
            mockIsEmergencyAwareContract[contractAddr] = true;
            mockEmergencyAwareContractsArray.push(contractAddr);
        }
    }
    function removeMockEmergencyAwareContract(address contractAddr) external {
        if (mockIsEmergencyAwareContract[contractAddr]) {
            mockIsEmergencyAwareContract[contractAddr] = false;
            for (uint i = 0; i < mockEmergencyAwareContractsArray.length; i++) {
                if (mockEmergencyAwareContractsArray[i] == contractAddr) {
                    if (mockEmergencyAwareContractsArray.length > 1 && i != mockEmergencyAwareContractsArray.length -1) {
                         mockEmergencyAwareContractsArray[i] = mockEmergencyAwareContractsArray[mockEmergencyAwareContractsArray.length - 1];
                    }
                    mockEmergencyAwareContractsArray.pop();
                    break;
                }
            }
        }
    }

    function setMockRequiredApprovals(uint256 count) external {
        mockRequiredApprovals = count;
    }
    function setMockLevel3TimelockDuration(uint256 duration) external {
        mockLevel3TimelockDuration = duration;
    }

    function setEmergencyLevel(uint8 level) external override returns (bool success) {
        if (shouldRevert) revert("MockEC Reverted");
        mockEmergencyLevel = level;
        emit MockSetEmergencyLevelCalled(level);
        emit EmergencyLevelSet(level, msg.sender); 
        return true;
    }

    function enableEmergencyWithdrawal(bool enabled, uint256 penalty) external override returns (bool success) {
        if (shouldRevert) revert("MockEC Reverted");
        mockEmergencyWithdrawalEnabled = enabled;
        mockEmergencyWithdrawalPenalty = penalty;
        emit MockEnableEmergencyWithdrawalCalled(enabled, penalty); 
        emit EmergencyWithdrawalSet(enabled, penalty); 
        return true;
    }

    function pauseSystem() external override returns (bool success) {
        if (shouldRevert) revert("MockEC Reverted");
        mockSystemPaused = true;
        emit MockPauseSystemCalled(); 
        emit SystemPaused(msg.sender); 
        return true;
    }

    function unpauseSystem() external override returns (bool success) {
        if (shouldRevert) revert("MockEC Reverted");
        mockSystemPaused = false;
        emit MockUnpauseSystemCalled(); 
        emit SystemUnpaused(msg.sender);
        return true;
    }

    function recoverTokens(address tokenAddress, uint256 amount) external override returns (bool success) {
        if (shouldRevert) revert("MockEC Reverted");
        emit MockRecoverTokensCalled(tokenAddress, amount); 
        emit TokensRecovered(tokenAddress, amount, mockRecoveryAdminAddress); 
        return true;
    }

    function getEmergencyLevel() external view override returns (uint8 level) {
        if (shouldRevert || revertGetEmergencyLevel) revert("MockEC: getEmergencyLevel Reverted");
        return mockEmergencyLevel;
    }

    function getEmergencyWithdrawalSettings() external view override returns (bool enabled, uint256 penalty) {
        if (shouldRevert) revert("MockEC Reverted");
        return (mockEmergencyWithdrawalEnabled, mockEmergencyWithdrawalPenalty);
    }

    function isSystemPaused() external view override returns (bool isPaused) {
        if (shouldRevert || revertIsSystemPaused) revert("MockEC: isSystemPaused Reverted");
        return mockSystemPaused;
    }

    function getEmergencyAwareContractsPaginated(uint256 offset, uint256 limit) external view override returns (address[] memory page, uint256 totalContracts) {
        if (shouldRevert) revert("MockEC: Reverted");
        totalContracts = mockEmergencyAwareContractsArray.length;
        if (limit == 0) {
            revert("MockEC: Limit cannot be zero");
        }
        if (offset >= totalContracts) {
            return (new address[](0), totalContracts);
        }
        uint256 count = totalContracts - offset < limit ? totalContracts - offset : limit;
        page = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            page[i] = mockEmergencyAwareContractsArray[offset + i];
        }
        return (page, totalContracts);
    }
    
    // NOTE: The following functions are not part of the IEmergencyController interface, but are required
    // by the EmergencyController contract's own logic and tests. We provide mock implementations here.
    function approveLevel3Emergency() external returns (bool success) {
        if (!mockApprovals[msg.sender]) {
            mockApprovals[msg.sender] = true;
            mockApproversArray.push(msg.sender);
            mockCurrentApprovalCount++;
        }
        emit MockApproveLevel3EmergencyCalled(msg.sender);
        return true;
    }

    function cancelLevel3Emergency() external returns (bool success) {
        emit MockCancelLevel3EmergencyCalled(msg.sender);
        return true;
    }

    function executeLevel3Emergency() external returns (bool success) {
        emit MockExecuteLevel3EmergencyCalled(msg.sender);
        return true;
    }
    
    function getApprovalStatus(uint256 approversOffset, uint256 approversLimit) external view returns (
        uint256 currentCount,
        uint256 required,
        address[] memory approversPage,
        uint256 nextApproverOffset,
        uint256 totalApprovers,
        bool timelockActive,
        uint256 executeAfter
    ) {
        currentCount = mockCurrentApprovalCount;
        required = mockRequiredApprovals;
        timelockActive = mockLevel3TimelockInProgress;
        executeAfter = mockLevel3ApprovalTime + mockLevel3TimelockDuration;

        address[] storage approvers = mockApproversArray;
        totalApprovers = approvers.length;

        if (approversLimit == 0 || approversOffset >= totalApprovers) {
            approversPage = new address[](0);
            nextApproverOffset = totalApprovers;
        } else {
            uint256 count = totalApprovers - approversOffset < approversLimit ? totalApprovers - approversOffset : approversLimit;
            approversPage = new address[](count);
            for (uint256 i = 0; i < count; i++) {
                approversPage[i] = approvers[approversOffset + i];
            }
            nextApproverOffset = approversOffset + count;
        }
    }

    function isFunctionRestricted(bytes4 functionSelector) external view returns (bool isRestricted) {
        if (shouldRevert || revertIsFunctionRestricted) revert("MockEC: isFunctionRestricted Reverted");
        uint8 threshold = mockRestrictedFunctionsThreshold[functionSelector];
        return (threshold > 0 && mockEmergencyLevel >= threshold);
    }
}
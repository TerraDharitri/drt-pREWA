// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/controllers/EmergencyTimelockController.sol";
import "../contracts/access/AccessControl.sol";
import "../contracts/mocks/MockAccessControl.sol";
import "../contracts/libraries/Errors.sol";
import "../contracts/proxy/TransparentProxy.sol";

contract TargetContract {
    uint256 public value;
    address public lastCaller;
    uint8 public lastLevel;
    bytes public lastData;

    event ActionCalled(address caller, uint8 level, bytes data);
    event ValueSet(uint256 newValue);

    function performAction(uint8 level, bytes calldata data) external {
        lastCaller = msg.sender; 
        lastLevel = level; 
        lastData = data;
        emit ActionCalled(msg.sender, level, data);
    }

    function setValue(uint256 _value) external {
        value = _value;
        emit ValueSet(_value);
    }
    
    function actionThatReverts() external pure {
        revert("TargetReverted");
    }
    
    function actionThatRevertsWithReason(string memory reason) external pure {
        revert(reason);
    }
}

contract EmergencyTimelockControllerTest is Test {
    EmergencyTimelockController etc;
    MockAccessControl mockAC;
    TargetContract target;

    address owner; 
    address emergencyRoleHolder;
    address nonEmergencyRoleHolder;
    address proxyAdmin;
    
    uint256 constant MIN_DURATION_ETC = 1 hours; 
    uint256 constant MAX_DURATION_ETC = 7 days;  
    uint256 defaultTimelockDuration;
    
    bytes32[] private proposedActionIds;

    function setUp() public {
        owner = makeAddr("owner");
        emergencyRoleHolder = makeAddr("emergencyRoleHolder");
        nonEmergencyRoleHolder = makeAddr("nonEmergencyRoleHolder");
        proxyAdmin = makeAddr("proxyAdmin");

        mockAC = new MockAccessControl();
        vm.prank(owner);
        mockAC.grantRole(mockAC.DEFAULT_ADMIN_ROLE(), owner);
        vm.prank(owner);
        mockAC.setRoleAdmin(mockAC.EMERGENCY_ROLE(), mockAC.DEFAULT_ADMIN_ROLE());
        vm.prank(owner);
        mockAC.grantRole(mockAC.EMERGENCY_ROLE(), emergencyRoleHolder);

        target = new TargetContract();
        defaultTimelockDuration = 1 days;

        EmergencyTimelockController logic = new EmergencyTimelockController();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        etc = EmergencyTimelockController(address(proxy));
        
        etc.initialize(address(mockAC), defaultTimelockDuration);
        
        vm.prank(owner);
        mockAC.grantRole(mockAC.EMERGENCY_ROLE(), address(etc));

        vm.startPrank(emergencyRoleHolder);
        etc.setAllowedTarget(address(target), true);
        etc.setAllowedFunctionSelector(target.setValue.selector, true);
        etc.setAllowedFunctionSelector(target.performAction.selector, true);
        etc.setAllowedFunctionSelector(target.actionThatReverts.selector, true);
        etc.setAllowedFunctionSelector(target.actionThatRevertsWithReason.selector, true);
        vm.stopPrank();
    }
    
    function tearDown() public {
        uint256 actionCount = proposedActionIds.length;
        if (actionCount > 0) {
            vm.startPrank(emergencyRoleHolder);
            for (uint i = 0; i < actionCount; i++) {
                bytes32 actionId = proposedActionIds[i];
                (bool exists, bool executed, bool cancelled,) = etc.getActionStatus(actionId);
                if (exists && !executed && !cancelled) {
                    try etc.cancelEmergencyAction(actionId) {} catch {}
                }
            }
            vm.stopPrank();
        }
        delete proposedActionIds;
    }
    
    function proposeAction(
        uint8 level,
        address targetAddress,
        bytes memory data
    ) internal returns (bytes32) {
        vm.prank(emergencyRoleHolder);
        bytes32 actionId = etc.proposeEmergencyAction(level, targetAddress, data);
        proposedActionIds.push(actionId);
        return actionId;
    }

    function test_Initialize_Success() public {
        EmergencyTimelockController logic = new EmergencyTimelockController();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        EmergencyTimelockController newEtc = EmergencyTimelockController(address(proxy));
        
        newEtc.initialize(address(mockAC), MIN_DURATION_ETC);
        
        assertEq(address(newEtc.accessControl()), address(mockAC));
        assertEq(newEtc.timelockDuration(), MIN_DURATION_ETC);
    }

    function test_Initialize_Revert_ZeroAccessControl() public {
        EmergencyTimelockController logic = new EmergencyTimelockController();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        EmergencyTimelockController newEtc = EmergencyTimelockController(address(proxy));
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "accessControlAddress"));
        newEtc.initialize(address(0), MIN_DURATION_ETC);
    }
    
    function test_Initialize_Revert_InvalidTimelockDuration() public {
        EmergencyTimelockController logic = new EmergencyTimelockController();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        EmergencyTimelockController newEtc = EmergencyTimelockController(address(proxy));
        
        vm.expectRevert(InvalidDuration.selector);
        newEtc.initialize(address(mockAC), MIN_DURATION_ETC - 1);
        
        vm.expectRevert(InvalidDuration.selector);
        newEtc.initialize(address(mockAC), MAX_DURATION_ETC + 1);
    }
    
    function test_Initialize_Revert_AlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        etc.initialize(address(mockAC), defaultTimelockDuration);
    }

    function test_Constructor_Runs() public {
        new EmergencyTimelockController();
        assertTrue(true, "Constructor ran");
    }

    function test_Modifier_OnlyEmergencyRole_Fail() public {
        vm.prank(nonEmergencyRoleHolder);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, mockAC.EMERGENCY_ROLE()));
        etc.setAllowedTarget(address(target), true);
    }
    
    function test_Modifier_OnlyEmergencyRole_Success() public {
        vm.prank(emergencyRoleHolder);
        etc.setAllowedTarget(address(target), false); 
        assertTrue(true);
        // cleanup
        vm.prank(emergencyRoleHolder);
        etc.setAllowedTarget(address(target), true);
    }

    function test_SetAllowedTarget_Success() public {
        address newTarget = makeAddr("newTarget");
        vm.prank(emergencyRoleHolder);
        vm.expectEmit(true, true, false, true);
        emit EmergencyTimelockController.TargetAllowlistUpdated(newTarget, true, emergencyRoleHolder);
        assertTrue(etc.setAllowedTarget(newTarget, true));
        assertTrue(etc.isTargetAllowed(newTarget));

        vm.prank(emergencyRoleHolder);
        vm.expectEmit(true, true, false, true);
        emit EmergencyTimelockController.TargetAllowlistUpdated(newTarget, false, emergencyRoleHolder);
        assertTrue(etc.setAllowedTarget(newTarget, false));
        assertFalse(etc.isTargetAllowed(newTarget));
    }
    
    function test_SetAllowedTarget_Revert_InvalidTarget() public {
        vm.prank(emergencyRoleHolder);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "target"));
        etc.setAllowedTarget(address(0), true);
    }

    function test_SetAllowedFunctionSelector_Success() public {
        bytes4 newSelector = bytes4(keccak256("newAction()"));
        vm.prank(emergencyRoleHolder);
        vm.expectEmit(true, true, false, true);
        emit EmergencyTimelockController.FunctionSelectorAllowlistUpdated(newSelector, true, emergencyRoleHolder);
        assertTrue(etc.setAllowedFunctionSelector(newSelector, true));
        assertTrue(etc.isFunctionSelectorAllowed(newSelector));
    }
    
    function test_SetAllowedFunctionSelector_Revert_InvalidSelector() public {
        vm.prank(emergencyRoleHolder);
        vm.expectRevert(InvalidAmount.selector);
        etc.setAllowedFunctionSelector(bytes4(0), true);
    }

    function test_ProposeEmergencyAction_Success() public {
        uint8 level = 1;
        bytes memory callData = abi.encodeWithSelector(target.setValue.selector, uint256(123));
        
        bytes32 actionId = proposeAction(level, address(target), callData);

        // FIX: Correctly check for proposal existence by reading its proposalTime
        (, uint256 proposalTime, , , , , ) = etc.getActionDetails(actionId);
        assertTrue(proposalTime > 0, "Proposal should have a valid timestamp");
    }
    
    function test_ProposeEmergencyAction_Reverts() public {
        bytes memory validData = abi.encodeWithSelector(target.setValue.selector, uint256(1));
        
        vm.prank(emergencyRoleHolder);
        vm.expectRevert(abi.encodeWithSelector(EC_InvalidEmergencyLevel.selector, 4));
        etc.proposeEmergencyAction(4, address(target), validData);

        vm.prank(emergencyRoleHolder);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "target"));
        etc.proposeEmergencyAction(1, address(0), validData);
        
        vm.prank(emergencyRoleHolder);
        vm.expectRevert(ETC_DataTooShortForSelector.selector);
        etc.proposeEmergencyAction(1, address(target), bytes("abc")); 

        address unallowedTarget = makeAddr("unallowedTarget");
        vm.prank(emergencyRoleHolder);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, bytes32(0)));
        etc.proposeEmergencyAction(1, unallowedTarget, validData);
        
        bytes4 unallowedSelector = bytes4(keccak256("unallowed()"));
        bytes memory dataWithUnallowedSelector = abi.encodeWithSelector(unallowedSelector);
        vm.prank(emergencyRoleHolder);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, bytes32(0)));
        etc.proposeEmergencyAction(1, address(target), dataWithUnallowedSelector);
    }

    function test_ExecuteEmergencyAction_Success() public {
        bytes memory callData = abi.encodeWithSelector(target.setValue.selector, uint256(456));
        bytes32 actionId = proposeAction(1, address(target), callData);
        
        skip(defaultTimelockDuration + 1); 

        vm.prank(emergencyRoleHolder);
        assertTrue(etc.executeEmergencyAction(actionId));
        assertEq(target.value(), 456);
    }
    
    function test_ExecuteEmergencyAction_TargetReverts_WithReason() public {
        bytes memory callData = abi.encodeWithSelector(target.actionThatRevertsWithReason.selector, "Custom Revert Msg");
        bytes32 actionId = proposeAction(1, address(target), callData);
        skip(defaultTimelockDuration + 1);

        vm.prank(emergencyRoleHolder);
        vm.expectRevert(bytes("Custom Revert Msg")); 
        etc.executeEmergencyAction(actionId);
    }
    
    function test_ExecuteEmergencyAction_TargetReverts_NoReason() public {
        bytes memory callData = abi.encodeWithSelector(target.actionThatReverts.selector);
        bytes32 actionId = proposeAction(1, address(target), callData);
        skip(defaultTimelockDuration + 1);

        vm.prank(emergencyRoleHolder);
        vm.expectRevert(bytes("TargetReverted")); 
        etc.executeEmergencyAction(actionId);
    }
    
    function test_ExecuteEmergencyAction_TargetReverts_NoReturnData() public {
        TargetContract revertingTarget = new TargetContract();
        bytes memory callData = abi.encodeWithSelector(revertingTarget.setValue.selector, 1);
        
        address targetAddress = address(revertingTarget);
        vm.prank(emergencyRoleHolder);
        etc.setAllowedTarget(targetAddress, true); 
        
        bytes32 actionId = proposeAction(1, targetAddress, callData);

        bytes memory revertingBytecode = hex"60006000fe";
        vm.etch(targetAddress, revertingBytecode);

        skip(defaultTimelockDuration + 1);
        vm.prank(emergencyRoleHolder);
        vm.expectRevert("EmergencyTimelock: execution failed with no error data");
        etc.executeEmergencyAction(actionId);
    }

    function test_ExecuteEmergencyAction_Revert_ActionDoesNotExist() public {
        vm.prank(emergencyRoleHolder);
        bytes32 nonExistentActionId = keccak256("fake");
        vm.expectRevert(InvalidAmount.selector);
        etc.executeEmergencyAction(nonExistentActionId);
    }
    
    function test_ExecuteEmergencyAction_Revert_TimelockNotExpired() public {
        bytes memory callData = abi.encodeWithSelector(target.setValue.selector, 1);
        bytes32 actionId = proposeAction(1, address(target), callData);
        
        vm.prank(emergencyRoleHolder);
        vm.expectRevert(PA_TimelockNotYetExpired.selector);
        etc.executeEmergencyAction(actionId);
    }
    
    function test_ExecuteEmergencyAction_Revert_FunctionNoLongerAllowed() public {
        bytes memory callData = abi.encodeWithSelector(target.setValue.selector, 1);
        bytes32 actionId = proposeAction(1, address(target), callData);
        
        vm.prank(emergencyRoleHolder);
        etc.setAllowedFunctionSelector(target.setValue.selector, false);
        
        skip(defaultTimelockDuration + 1);
        vm.prank(emergencyRoleHolder);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, bytes32(0)));
        etc.executeEmergencyAction(actionId);
    }
    
    function test_ExecuteEmergencyAction_Revert_TargetNoLongerAllowed() public {
        bytes memory callData = abi.encodeWithSelector(target.performAction.selector, uint8(1), bytes("test"));
        bytes32 actionId = proposeAction(1, address(target), callData);
        
        vm.prank(emergencyRoleHolder);
        etc.setAllowedTarget(address(target), false);
        
        skip(defaultTimelockDuration + 1);
        vm.prank(emergencyRoleHolder);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, bytes32(0)));
        etc.executeEmergencyAction(actionId);
    }
    
    function test_ExecuteEmergencyAction_Revert_ActionAlreadyExecuted() public {
        bytes memory callData = abi.encodeWithSelector(target.setValue.selector, 1);
        bytes32 actionId = proposeAction(1, address(target), callData);
        
        skip(defaultTimelockDuration + 1);
        vm.prank(emergencyRoleHolder);
        etc.executeEmergencyAction(actionId);
        
        vm.prank(emergencyRoleHolder);
        vm.expectRevert(InvalidAmount.selector);
        etc.executeEmergencyAction(actionId);
    }
    
    function test_ExecuteEmergencyAction_Revert_ActionCancelled() public {
        bytes memory callData = abi.encodeWithSelector(target.setValue.selector, 1);
        bytes32 actionId = proposeAction(1, address(target), callData);
        
        vm.prank(emergencyRoleHolder);
        etc.cancelEmergencyAction(actionId);
        
        skip(defaultTimelockDuration + 1);
        vm.prank(emergencyRoleHolder);
        vm.expectRevert(InvalidAmount.selector);
        etc.executeEmergencyAction(actionId);
    }

    function test_CancelEmergencyAction_Success() public {
        bytes memory callData = abi.encodeWithSignature("setValue(uint256)", 789);
        bytes32 actionId = proposeAction(1, address(target), callData);
        
        vm.prank(emergencyRoleHolder);
        assertTrue(etc.cancelEmergencyAction(actionId));
    }
    
    function test_CancelEmergencyAction_Revert_ActionDoesNotExist() public {
        vm.prank(emergencyRoleHolder);
        vm.expectRevert(InvalidAmount.selector);
        etc.cancelEmergencyAction(keccak256("fake"));
    }
    
    function test_CancelEmergencyAction_Revert_ActionAlreadyExecuted() public {
        bytes memory callData = abi.encodeWithSelector(target.setValue.selector, uint256(1));
        bytes32 actionId = proposeAction(1, address(target), callData);
        
        skip(defaultTimelockDuration + 1);
        
        vm.prank(emergencyRoleHolder);
        etc.executeEmergencyAction(actionId);
        
        vm.prank(emergencyRoleHolder);
        vm.expectRevert(InvalidAmount.selector);
        etc.cancelEmergencyAction(actionId);
    }
    
    function test_CancelEmergencyAction_Revert_ActionAlreadyCancelled() public {
        bytes memory callData = abi.encodeWithSignature("setValue(uint256)", 2);
        bytes32 actionId = proposeAction(1, address(target), callData);
        
        vm.prank(emergencyRoleHolder);
        etc.cancelEmergencyAction(actionId);
        
        vm.prank(emergencyRoleHolder);
        vm.expectRevert(InvalidAmount.selector);
        etc.cancelEmergencyAction(actionId);
    }

    function test_UpdateTimelockDuration_Success() public {
        uint256 newDuration = MIN_DURATION_ETC + 2 hours;
        vm.prank(emergencyRoleHolder);
        assertTrue(etc.updateTimelockDuration(newDuration));
        assertEq(etc.timelockDuration(), newDuration);
    }
    
    function test_UpdateTimelockDuration_Revert_InvalidDuration() public {
        vm.prank(emergencyRoleHolder);
        vm.expectRevert(InvalidDuration.selector);
        etc.updateTimelockDuration(MIN_DURATION_ETC - 1);

        vm.prank(emergencyRoleHolder);
        vm.expectRevert(InvalidDuration.selector);
        etc.updateTimelockDuration(MAX_DURATION_ETC + 1);
    }

    function test_GetActionStatus_AllStates() public {
        (bool exists, , , ) = etc.getActionStatus(keccak256("fake")); 
        assertFalse(exists);

        bytes memory callData = abi.encodeWithSignature("setValue(uint256)", 10);
        bytes32 actionIdPending = proposeAction(1, address(target), callData);
        
        uint256 timeRem;
        (exists, , , timeRem) = etc.getActionStatus(actionIdPending); 
        assertTrue(exists);
        assertTrue(timeRem > 0 && timeRem <= defaultTimelockDuration);
    }

    function test_GetAllActionIds_EmptyAndPopulated() public {
        assertEq(etc.getAllActionIds().length, 0);
        bytes memory callData = abi.encodeWithSignature("setValue(uint256)", 1);
        proposeAction(1, address(target), callData);
        assertEq(etc.getAllActionIds().length, 1);
    }
    
    function test_Debug_FunctionSelectorIssue() public {
        bytes4 setValueSelector = target.setValue.selector;
        bytes memory callData = abi.encodeWithSelector(setValueSelector, uint256(1));
        
        vm.prank(emergencyRoleHolder);
        bytes32 actionId = etc.proposeEmergencyAction(1, address(target), callData);
        
        skip(defaultTimelockDuration + 1);
        
        vm.prank(emergencyRoleHolder);
        etc.executeEmergencyAction(actionId);
        
        assertTrue(true, "Execution should succeed");
    }

    function test_Debug_FunctionSelectorExtraction() public pure {
        bytes memory testData = abi.encodeWithSelector(TargetContract.setValue.selector, 1);
        bytes4 proposalMethod;
        assembly {
            proposalMethod := mload(add(testData, 32))
        }
        assertEq(proposalMethod, TargetContract.setValue.selector, "Proposal method should match");
    }
}
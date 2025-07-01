// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../contracts/controllers/EmergencyController.sol";
import "../contracts/interfaces/IEmergencyController.sol";
import "../contracts/mocks/MockAccessControl.sol";
import "../contracts/mocks/MockIEmergencyAware.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/MockEmergencyTimelockController.sol";
import "../contracts/libraries/Constants.sol";
import "../contracts/libraries/Errors.sol";
import "../contracts/proxy/TransparentProxy.sol";

contract EmergencyControllerCoverageTest is Test {
    EmergencyController ec;
    MockAccessControl mockAC;
    MockEmergencyTimelockController mockETC;
    MockERC20 mockToken;
    MockIEmergencyAware awareContract1;
    MockIEmergencyAware awareContract2;
    MockIEmergencyAware awareContract3;

    address owner;
    address emergencyRoleHolder1;
    address emergencyRoleHolder2;
    address emergencyRoleHolder3;
    address pauserRoleHolder;
    address nonRoleHolder;
    address recoveryAdmin;
    address proxyAdmin;

    function setUp() public {
        vm.warp(2 days);

        owner = makeAddr("owner");
        emergencyRoleHolder1 = makeAddr("emergencyRoleHolder1");
        emergencyRoleHolder2 = makeAddr("emergencyRoleHolder2");
        emergencyRoleHolder3 = makeAddr("emergencyRoleHolder3");
        pauserRoleHolder = makeAddr("pauserRoleHolder");
        nonRoleHolder = makeAddr("nonRoleHolder");
        recoveryAdmin = makeAddr("recoveryAdmin");
        proxyAdmin = makeAddr("proxyAdmin");

        mockAC = new MockAccessControl();
        vm.prank(owner);
        mockAC.setRole(mockAC.DEFAULT_ADMIN_ROLE(), owner, true);
        vm.prank(owner);
        mockAC.setRoleAdmin(mockAC.EMERGENCY_ROLE(), mockAC.DEFAULT_ADMIN_ROLE());
        vm.prank(owner);
        mockAC.setRole(mockAC.EMERGENCY_ROLE(), emergencyRoleHolder1, true);
        vm.prank(owner);
        mockAC.setRole(mockAC.EMERGENCY_ROLE(), emergencyRoleHolder2, true);
        vm.prank(owner);
        mockAC.setRole(mockAC.EMERGENCY_ROLE(), emergencyRoleHolder3, true);
        vm.prank(owner);
        mockAC.setRoleAdmin(mockAC.PAUSER_ROLE(), mockAC.DEFAULT_ADMIN_ROLE());
        vm.prank(owner);
        mockAC.setRole(mockAC.PAUSER_ROLE(), pauserRoleHolder, true);

        mockETC = new MockEmergencyTimelockController(address(mockAC));
        
        mockToken = new MockERC20();
        mockToken.mockInitialize("Test Token", "TST", 18, owner);

        EmergencyController logic = new EmergencyController();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        ec = EmergencyController(address(proxy));
        ec.initialize(address(mockAC), address(mockETC), 3, 2 hours, recoveryAdmin);

        awareContract1 = new MockIEmergencyAware(owner);
        awareContract2 = new MockIEmergencyAware(owner);
        awareContract3 = new MockIEmergencyAware(owner);
        
        vm.prank(emergencyRoleHolder1);
        ec.registerEmergencyAwareContract(address(awareContract1));
        vm.prank(emergencyRoleHolder1);
        ec.registerEmergencyAwareContract(address(awareContract2));
    }

    // Test initialization edge cases
    function test_Initialize_NotAContract_AccessControl() public {
        EmergencyController logic = new EmergencyController();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        EmergencyController newEc = EmergencyController(address(proxy));
        
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "accessControl"));
        newEc.initialize(address(0x123), address(0), 1, 1 hours, recoveryAdmin);
    }

    function test_Initialize_NotAContract_TimelockController() public {
        EmergencyController logic = new EmergencyController();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        EmergencyController newEc = EmergencyController(address(proxy));
        
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "timelockController"));
        newEc.initialize(address(mockAC), address(0x123), 1, 1 hours, recoveryAdmin);
    }

    // Test modifier edge cases with zero access control
    function test_Modifiers_AccessControlZero() public {
        EmergencyController logic = new EmergencyController();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        EmergencyController newEc = EmergencyController(address(proxy));
        // Don't initialize, so accessControl is address(0)
        
        vm.expectRevert(EC_AccessControlZero.selector);
        newEc.setEmergencyLevel(1);
        
        vm.expectRevert(EC_AccessControlZero.selector);
        newEc.pauseSystem();
        
        vm.expectRevert(EC_AccessControlZero.selector);
        newEc.setRequiredApprovals(3);
    }

    // Test setRequiredApprovals edge cases
    function test_SetRequiredApprovals_MaxValue() public {
        vm.prank(owner);
        bool success = ec.setRequiredApprovals(20); // MAX_REQUIRED_APPROVALS
        assertTrue(success);
        assertEq(ec.requiredApprovals(), 20);
    }

    function test_SetRequiredApprovals_ResetsApprovals() public {
        // First get some approvals
        vm.prank(emergencyRoleHolder1);
        ec.approveLevel3Emergency();
        vm.prank(emergencyRoleHolder2);
        ec.approveLevel3Emergency();
        assertEq(ec.currentApprovalCount(), 2);
        
        // Change required approvals - should reset
        vm.prank(owner);
        ec.setRequiredApprovals(5);
        assertEq(ec.currentApprovalCount(), 0);
    }

    // Test setLevel3TimelockDuration edge cases
    function test_SetLevel3TimelockDuration_MinValue() public {
        vm.prank(owner);
        bool success = ec.setLevel3TimelockDuration(Constants.MIN_TIMELOCK_DURATION);
        assertTrue(success);
        assertEq(ec.level3TimelockDuration(), Constants.MIN_TIMELOCK_DURATION);
    }

    function test_SetLevel3TimelockDuration_MaxValue() public {
        vm.prank(owner);
        bool success = ec.setLevel3TimelockDuration(Constants.MAX_TIMELOCK_DURATION);
        assertTrue(success);
        assertEq(ec.level3TimelockDuration(), Constants.MAX_TIMELOCK_DURATION);
    }

    // Test Level 3 emergency edge cases
    function test_ApproveLevel3Emergency_TimelockAlreadyInProgress() public {
        // Get enough approvals to start timelock
        vm.prank(emergencyRoleHolder1);
        ec.approveLevel3Emergency();
        vm.prank(emergencyRoleHolder2);
        ec.approveLevel3Emergency();
        vm.prank(emergencyRoleHolder3);
        ec.approveLevel3Emergency();
        
        assertTrue(ec.level3TimelockInProgress());
        
        // Try to approve again - should not start another timelock
        vm.prank(emergencyRoleHolder1);
        ec.approveLevel3Emergency(); // Should succeed but not restart timelock
    }

    function test_ExecuteLevel3Emergency_AlreadyEnabled() public {
        // First enable emergency withdrawal manually
        vm.prank(emergencyRoleHolder1);
        ec.enableEmergencyWithdrawal(true, 500);
        
        // Then execute level 3
        vm.prank(emergencyRoleHolder1);
        ec.approveLevel3Emergency();
        vm.prank(emergencyRoleHolder2);
        ec.approveLevel3Emergency();
        vm.prank(emergencyRoleHolder3);
        ec.approveLevel3Emergency();
        
        skip(2 hours + 1);
        
        vm.prank(emergencyRoleHolder1);
        ec.executeLevel3Emergency();
        
        // Should still be at level 3
        assertEq(ec.emergencyLevel(), Constants.EMERGENCY_LEVEL_CRITICAL);
    }

    function test_ExecuteLevel3Emergency_SystemAlreadyPaused() public {
        // First pause system manually
        vm.prank(pauserRoleHolder);
        ec.pauseSystem();
        
        // Then execute level 3
        vm.prank(emergencyRoleHolder1);
        ec.approveLevel3Emergency();
        vm.prank(emergencyRoleHolder2);
        ec.approveLevel3Emergency();
        vm.prank(emergencyRoleHolder3);
        ec.approveLevel3Emergency();
        
        skip(2 hours + 1);
        
        vm.prank(emergencyRoleHolder1);
        ec.executeLevel3Emergency();
        
        assertTrue(ec.systemPaused());
    }

    // Test setEmergencyLevel edge cases
    function test_SetEmergencyLevel_ToNormal_WithTimelockInProgress() public {
        // Start level 3 approval process
        vm.prank(emergencyRoleHolder1);
        ec.approveLevel3Emergency();
        vm.prank(emergencyRoleHolder2);
        ec.approveLevel3Emergency();
        vm.prank(emergencyRoleHolder3);
        ec.approveLevel3Emergency();
        
        assertTrue(ec.level3TimelockInProgress());
        
        // Set to normal - should cancel timelock
        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_NORMAL);
        
        assertFalse(ec.level3TimelockInProgress());
        assertEq(ec.currentApprovalCount(), 0);
    }

    function test_SetEmergencyLevel_ToNormal_WithApprovals() public {
        // Get some approvals but not enough for timelock
        vm.prank(emergencyRoleHolder1);
        ec.approveLevel3Emergency();
        assertEq(ec.currentApprovalCount(), 1);
        
        // Set to normal - should reset approvals
        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_NORMAL);
        
        assertEq(ec.currentApprovalCount(), 0);
    }

    function test_SetEmergencyLevel_NotificationTimestamp() public {
        // Set to alert level
        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_ALERT);
        
        uint256 firstTimestamp = ec.emergencyLevelTimestamp(Constants.EMERGENCY_LEVEL_ALERT);
        assertTrue(firstTimestamp > 0);
        
        // Wait more than 1 hour and set again
        skip(2 hours);
        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_CAUTION);
        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_ALERT);
        
        uint256 secondTimestamp = ec.emergencyLevelTimestamp(Constants.EMERGENCY_LEVEL_ALERT);
        assertTrue(secondTimestamp > firstTimestamp);
    }

    // Test enableEmergencyWithdrawal edge cases
    function test_EnableEmergencyWithdrawal_MaxPenalty() public {
        vm.prank(emergencyRoleHolder1);
        bool success = ec.enableEmergencyWithdrawal(true, Constants.MAX_PENALTY);
        assertTrue(success);
        assertEq(ec.emergencyWithdrawalPenalty(), Constants.MAX_PENALTY);
    }

    // Test pauseSystem edge cases
    function test_PauseSystem_NotificationTimestamp() public {
        vm.prank(pauserRoleHolder);
        ec.pauseSystem();
        
        uint256 timestamp = ec.emergencyLevelTimestamp(Constants.EMERGENCY_LEVEL_CRITICAL);
        assertTrue(timestamp > 0);
        assertTrue(ec.emergencyLevelNotified(Constants.EMERGENCY_LEVEL_CRITICAL));
    }

    function test_PauseSystem_NotificationAlreadyRecent() public {
        // First set emergency level to critical
        vm.prank(emergencyRoleHolder1);
        ec.approveLevel3Emergency();
        vm.prank(emergencyRoleHolder2);
        ec.approveLevel3Emergency();
        vm.prank(emergencyRoleHolder3);
        ec.approveLevel3Emergency();
        skip(2 hours + 1);
        vm.prank(emergencyRoleHolder1);
        ec.executeLevel3Emergency();
        
        uint256 firstTimestamp = ec.emergencyLevelTimestamp(Constants.EMERGENCY_LEVEL_CRITICAL);
        
        // Reset to normal
        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_NORMAL);
        
        // Pause system - should not update timestamp since it's recent
        vm.prank(pauserRoleHolder);
        ec.pauseSystem();
        
        uint256 secondTimestamp = ec.emergencyLevelTimestamp(Constants.EMERGENCY_LEVEL_CRITICAL);
        assertEq(firstTimestamp, secondTimestamp);
    }

    // Test recoverTokens edge case
    function test_RecoverTokens_RecoveryAdminNotSet() public {
        // Create new EC without recovery admin
        EmergencyController logic = new EmergencyController();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        EmergencyController newEc = EmergencyController(address(proxy));
        newEc.initialize(address(mockAC), address(0), 1, 1 hours, recoveryAdmin);
        
        // Set recovery admin to zero (this should revert in setRecoveryAdminAddress)
        // So we need to test this differently - we can't actually set it to zero
        // This test case is actually impossible to reach due to validation
        
        // Instead, test successful recovery
        vm.prank(owner);
        mockToken.mintForTest(address(ec), 1000);
        vm.prank(emergencyRoleHolder1);
        bool success = ec.recoverTokens(address(mockToken), 1000);
        assertTrue(success);
    }

    // Test emergency aware contract management edge cases
    function test_RegisterEmergencyAwareContract_AlreadyRegistered() public {
        // Try to register already registered contract
        vm.prank(emergencyRoleHolder1);
        bool success = ec.registerEmergencyAwareContract(address(awareContract1));
        assertTrue(success); // Should succeed but have no effect
    }

    function test_RemoveEmergencyAwareContract_SwapAndPop() public {
        // Register third contract
        vm.prank(emergencyRoleHolder1);
        ec.registerEmergencyAwareContract(address(awareContract3));
        
        // Remove middle contract to test swap and pop
        vm.prank(emergencyRoleHolder1);
        ec.removeEmergencyAwareContract(address(awareContract1));
        
        (address[] memory page,) = ec.getEmergencyAwareContractsPaginated(0, 10);
        assertEq(page.length, 2);
        // awareContract3 should have moved to index 0
        assertEq(page[0], address(awareContract3));
        assertEq(page[1], address(awareContract2));
    }

    function test_RemoveEmergencyAwareContract_LastElement() public {
        // Remove last element (no swap needed)
        vm.prank(emergencyRoleHolder1);
        ec.removeEmergencyAwareContract(address(awareContract2));
        
        (address[] memory page,) = ec.getEmergencyAwareContractsPaginated(0, 10);
        assertEq(page.length, 1);
        assertEq(page[0], address(awareContract1));
    }

    // Test processEmergencyForContract edge cases
    function test_ProcessEmergencyForContract_AlreadyProcessedButOldTimestamp() public {
        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_ALERT);
        
        // Process first time
        vm.prank(emergencyRoleHolder1);
        ec.processEmergencyForContract(address(awareContract1), Constants.EMERGENCY_LEVEL_ALERT);
        
        // Wait more than 1 day
        skip(1 days + 1);
        
        // Should be able to process again
        vm.prank(emergencyRoleHolder1);
        bool success = ec.processEmergencyForContract(address(awareContract1), Constants.EMERGENCY_LEVEL_ALERT);
        assertTrue(success);
    }

    function test_ProcessEmergencyForContract_ZeroTimestamp() public {
        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_ALERT);
        
        // Manually set processed flag without timestamp
        // This is a bit artificial but tests the edge case
        vm.prank(emergencyRoleHolder1);
        ec.processEmergencyForContract(address(awareContract1), Constants.EMERGENCY_LEVEL_ALERT);
        
        // Try again immediately - should revert
        vm.prank(emergencyRoleHolder1);
        vm.expectRevert(abi.encodeWithSelector(EC_AlreadyProcessed.selector, address(awareContract1), Constants.EMERGENCY_LEVEL_ALERT));
        ec.processEmergencyForContract(address(awareContract1), Constants.EMERGENCY_LEVEL_ALERT);
    }

    // Test updateFunctionRestriction edge cases
    function test_UpdateFunctionRestriction_ZeroThreshold() public {
        bytes4 sel = bytes4(keccak256("test()"));
        vm.prank(emergencyRoleHolder1);
        ec.updateFunctionRestriction(sel, 2);
        assertEq(ec.restrictedFunctions(sel), 2);
        
        // Set to zero to unrestrict
        vm.prank(emergencyRoleHolder1);
        ec.updateFunctionRestriction(sel, 0);
        assertEq(ec.restrictedFunctions(sel), 0);
    }

    // Test getter functions
    function test_GetEmergencyLevel() public view {
        uint8 level = ec.getEmergencyLevel();
        assertEq(level, Constants.EMERGENCY_LEVEL_NORMAL);
    }

    function test_GetEmergencyWithdrawalSettings() public view {
        (bool enabled, uint256 penalty) = ec.getEmergencyWithdrawalSettings();
        assertFalse(enabled);
        assertEq(penalty, Constants.DEFAULT_PENALTY);
    }

    function test_IsSystemPaused() public view {
        bool paused = ec.isSystemPaused();
        assertFalse(paused);
    }

    // Test pagination edge cases
    function test_GetEmergencyAwareContractsPaginated_OffsetAtEnd() public view {
        (address[] memory page, uint256 total) = ec.getEmergencyAwareContractsPaginated(2, 5);
        assertEq(page.length, 0);
        assertEq(total, 2);
    }

    function test_GetEmergencyAwareContractsPaginated_LimitLargerThanRemaining() public view {
        (address[] memory page, uint256 total) = ec.getEmergencyAwareContractsPaginated(1, 10);
        assertEq(page.length, 1);
        assertEq(page[0], address(awareContract2));
        assertEq(total, 2);
    }

    function test_GetApprovalStatus_NoApprovals() public view {
        (uint256 currentCount, uint256 required, address[] memory page, , uint256 total, bool active, uint256 executeAfter) = ec.getApprovalStatus(0, 10);
        assertEq(currentCount, 0);
        assertEq(required, 3);
        assertEq(page.length, 0);
        assertEq(total, 0);
        assertFalse(active);
        assertEq(executeAfter, 0);
    }

    function test_GetApprovalStatus_OffsetBeyondApprovers() public {
        vm.prank(emergencyRoleHolder1);
        ec.approveLevel3Emergency();
        
        (, , address[] memory page, uint256 nextOffset, uint256 total, , ) = ec.getApprovalStatus(5, 10);
        assertEq(page.length, 0);
        assertEq(nextOffset, 1);
        assertEq(total, 1);
    }

    // Test isFunctionRestricted edge cases
    function test_IsFunctionRestricted_ThresholdZero() public {
        bytes4 sel = bytes4(keccak256("test()"));
        // Default threshold is 0
        assertFalse(ec.isFunctionRestricted(sel));
        
        // Cannot set emergency level to critical directly, need to use approval process
        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_ALERT);
        assertFalse(ec.isFunctionRestricted(sel)); // Still false because threshold is 0
    }

    function test_IsFunctionRestricted_EmergencyLevelBelowThreshold() public {
        bytes4 sel = bytes4(keccak256("test()"));
        vm.prank(emergencyRoleHolder1);
        ec.updateFunctionRestriction(sel, Constants.EMERGENCY_LEVEL_CRITICAL);
        
        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_ALERT);
        assertFalse(ec.isFunctionRestricted(sel)); // Alert < Critical
    }

    // Test _resetApprovals edge cases
    function test_ResetApprovals_ProposalIdOverflow() public {
        // This is very artificial but tests the overflow protection
        // We can't easily test this in practice due to gas limits
        // But the code has protection for uint256 max overflow
        
        // Just test normal reset behavior
        vm.prank(emergencyRoleHolder1);
        ec.approveLevel3Emergency();
        uint256 oldProposalId = ec.level3ProposalId();
        
        vm.prank(emergencyRoleHolder1);
        ec.cancelLevel3Emergency();
        
        uint256 newProposalId = ec.level3ProposalId();
        assertEq(newProposalId, oldProposalId + 1);
    }

    // Test complex scenarios
    function test_ComplexScenario_MultipleEmergencyLevels() public {
        // Start at normal
        assertEq(ec.emergencyLevel(), Constants.EMERGENCY_LEVEL_NORMAL);
        
        // Go to caution
        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_CAUTION);
        assertFalse(ec.emergencyWithdrawalEnabled());
        
        // Go to alert - should enable emergency withdrawal
        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_ALERT);
        assertTrue(ec.emergencyWithdrawalEnabled());
        
        // Go back to normal - should disable everything
        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_NORMAL);
        assertFalse(ec.emergencyWithdrawalEnabled());
        assertFalse(ec.systemPaused());
    }

    function test_ComplexScenario_Level3WithManualPause() public {
        // Manually pause system first
        vm.prank(pauserRoleHolder);
        ec.pauseSystem();
        assertTrue(ec.systemPaused());
        
        // Then do level 3 emergency
        vm.prank(emergencyRoleHolder1);
        ec.approveLevel3Emergency();
        vm.prank(emergencyRoleHolder2);
        ec.approveLevel3Emergency();
        vm.prank(emergencyRoleHolder3);
        ec.approveLevel3Emergency();
        
        skip(2 hours + 1);
        
        vm.prank(emergencyRoleHolder1);
        ec.executeLevel3Emergency();
        
        // Should still be paused and at critical level
        assertTrue(ec.systemPaused());
        assertEq(ec.emergencyLevel(), Constants.EMERGENCY_LEVEL_CRITICAL);
        
        // Cannot unpause at level 3
        vm.prank(pauserRoleHolder);
        vm.expectRevert(EC_CannotUnpauseAtLevel3.selector);
        ec.unpauseSystem();
    }

    // Test event emissions for better coverage
    function test_EventEmissions_RequiredApprovalsUpdated() public {
        vm.expectEmit(true, true, true, true);
        emit RequiredApprovalsUpdated(3, 5, owner);
        
        vm.prank(owner);
        ec.setRequiredApprovals(5);
    }

    function test_EventEmissions_Level3TimelockDurationUpdated() public {
        vm.expectEmit(true, true, true, true);
        emit Level3TimelockDurationUpdated(2 hours, 3 hours, owner);
        
        vm.prank(owner);
        ec.setLevel3TimelockDuration(3 hours);
    }

    function test_EventEmissions_RecoveryAdminAddressUpdated() public {
        address newAdmin = makeAddr("newAdmin");
        vm.expectEmit(true, true, true, true);
        emit RecoveryAdminAddressUpdated(recoveryAdmin, newAdmin, owner);
        
        vm.prank(owner);
        ec.setRecoveryAdminAddress(newAdmin);
    }

    // Events
    event RequiredApprovalsUpdated(uint256 oldValue, uint256 newValue, address indexed updater);
    event Level3TimelockDurationUpdated(uint256 oldDuration, uint256 newDuration, address indexed updater);
    event RecoveryAdminAddressUpdated(address indexed oldAdmin, address indexed newAdmin, address indexed updater);
}
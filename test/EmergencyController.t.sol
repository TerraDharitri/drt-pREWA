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

contract EmergencyControllerTest is Test {
    event Level3TimelockStarted(uint256 unlockTime, address indexed starter);
    event EmergencyLevelSet(uint8 level, address indexed setter);
    event EmergencyWithdrawalSet(bool enabled, uint256 penalty);
    event SystemPaused(address indexed pauser);
    event SystemUnpaused(address indexed unpauser);

    EmergencyController ec;
    MockAccessControl mockAC;
    MockEmergencyTimelockController mockETC;
    MockERC20 mockToken;
    MockIEmergencyAware awareContract1;
    MockIEmergencyAware awareContract2;

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
        ec.initialize(address(mockAC), address(mockETC), 2, 1 hours, recoveryAdmin);

        awareContract1 = new MockIEmergencyAware(owner);
        awareContract2 = new MockIEmergencyAware(owner);
        vm.prank(emergencyRoleHolder1);
        ec.registerEmergencyAwareContract(address(awareContract1));
    }

    // --- INITIALIZATION ---
    function test_Initialize_Success() public view {
        assertEq(address(ec.accessControl()), address(mockAC));
        assertEq(address(ec.timelockController()), address(mockETC));
        assertEq(ec.requiredApprovals(), 2);
        assertEq(ec.level3TimelockDuration(), 1 hours);
        assertEq(ec.recoveryAdminAddress(), recoveryAdmin);
        assertEq(ec.emergencyLevel(), Constants.EMERGENCY_LEVEL_NORMAL);
    }
    
    function test_Initialize_Reverts() public {
        EmergencyController logic = new EmergencyController();
        TransparentProxy proxy;
        EmergencyController newEc;

        proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        newEc = EmergencyController(address(proxy));
        vm.expectRevert(EC_AccessControlZero.selector);
        newEc.initialize(address(0), address(0), 1, 1 hours, recoveryAdmin);
        
        proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        newEc = EmergencyController(address(proxy));
        vm.expectRevert(EC_RequiredApprovalsZero.selector);
        newEc.initialize(address(mockAC), address(0), 0, 1 hours, recoveryAdmin);

        proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        newEc = EmergencyController(address(proxy));
        vm.expectRevert(abi.encodeWithSelector(EC_RequiredApprovalsTooHigh.selector, 21, 20));
        newEc.initialize(address(mockAC), address(0), 21, 1 hours, recoveryAdmin);

        proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        newEc = EmergencyController(address(proxy));
        vm.expectRevert(EC_TimelockTooShort.selector);
        newEc.initialize(address(mockAC), address(0), 1, 3599, recoveryAdmin);

        proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        newEc = EmergencyController(address(proxy));
        vm.expectRevert(EC_TimelockTooLong.selector);
        newEc.initialize(address(mockAC), address(0), 1, 7 days + 1, recoveryAdmin);

        proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        newEc = EmergencyController(address(proxy));
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "initialRecoveryAdminAddress_"));
        newEc.initialize(address(mockAC), address(0), 1, 1 hours, address(0));
    }

    function test_Initialize_NoTimelockController_Success() public {
        EmergencyController logic = new EmergencyController();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        EmergencyController newEc = EmergencyController(address(proxy));
        newEc.initialize(address(mockAC), address(0), 2, 1 hours, recoveryAdmin);
        assertEq(address(newEc.timelockController()), address(0));
    }

    // --- ROLE-BASED ACCESS ---
    function test_Modifiers_Fail_NoRole() public {
        vm.prank(nonRoleHolder);
        vm.expectRevert(EC_MustHaveEmergencyRole.selector);
        ec.setEmergencyLevel(1);
        
        vm.prank(nonRoleHolder);
        vm.expectRevert(EC_MustHavePauserRole.selector);
        ec.pauseSystem();
        
        vm.prank(nonRoleHolder);
        vm.expectRevert(EC_MustHaveAdminRole.selector);
        ec.setRequiredApprovals(3);
    }

    // --- LEVEL 3 EMERGENCY FLOW ---
    function test_Level3_FullFlow_Success() public {
        vm.prank(emergencyRoleHolder1);
        ec.approveLevel3Emergency();
        assertEq(ec.currentApprovalCount(), 1);

        vm.prank(emergencyRoleHolder2);
        vm.expectEmit(true, true, false, false);
        emit Level3TimelockStarted(block.timestamp + 1 hours, emergencyRoleHolder2);
        ec.approveLevel3Emergency();
        assertEq(ec.currentApprovalCount(), 2);
        assertTrue(ec.level3TimelockInProgress());
        
        vm.prank(emergencyRoleHolder1);
        vm.expectRevert(EC_Level3TimelockNotExpired.selector);
        ec.executeLevel3Emergency();
        
        skip(1 hours + 1);

        vm.prank(emergencyRoleHolder1);
        vm.expectEmit(false, false, false, false);
        emit EmergencyWithdrawalSet(true, Constants.DEFAULT_PENALTY);
        vm.expectEmit(false, false, false, true);
        emit SystemPaused(emergencyRoleHolder1);
        vm.expectEmit(false, false, false, true);
        emit EmergencyLevelSet(Constants.EMERGENCY_LEVEL_CRITICAL, emergencyRoleHolder1);
        ec.executeLevel3Emergency();

        assertEq(ec.emergencyLevel(), Constants.EMERGENCY_LEVEL_CRITICAL);
        assertTrue(ec.systemPaused());
        assertTrue(ec.emergencyWithdrawalEnabled());
        assertFalse(ec.level3TimelockInProgress());
        assertEq(ec.currentApprovalCount(), 0);
    }

    function test_Level3_Cancel_And_ReApprove_Success() public {
        vm.prank(emergencyRoleHolder1);
        ec.approveLevel3Emergency();
        
        vm.prank(emergencyRoleHolder2);
        ec.cancelLevel3Emergency();
        assertEq(ec.currentApprovalCount(), 0);
        assertFalse(ec.level3TimelockInProgress());
        
        vm.prank(emergencyRoleHolder3);
        ec.approveLevel3Emergency();
        assertEq(ec.currentApprovalCount(), 1);
    }
    
    function test_Level3_Approval_NoEffectIfAlreadyApproved() public {
        vm.prank(emergencyRoleHolder1);
        ec.approveLevel3Emergency();
        assertEq(ec.currentApprovalCount(), 1);

        vm.prank(emergencyRoleHolder1);
        ec.approveLevel3Emergency(); // No event, no count change
        assertEq(ec.currentApprovalCount(), 1);
    }
    
    function test_Level3_Reverts() public {
        vm.prank(emergencyRoleHolder1);
        vm.expectRevert(EC_NoLevel3EscalationInProgress.selector);
        ec.cancelLevel3Emergency();

        vm.prank(emergencyRoleHolder1);
        vm.expectRevert(EC_UseApproveForLevel3.selector);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_CRITICAL);
        
        vm.prank(emergencyRoleHolder1);
        ec.approveLevel3Emergency();
        vm.prank(emergencyRoleHolder2);
        ec.approveLevel3Emergency();
        skip(1 hours + 1);
        vm.prank(emergencyRoleHolder1);
        ec.executeLevel3Emergency();
        
        vm.prank(emergencyRoleHolder1);
        vm.expectRevert(EC_AlreadyAtLevel3.selector);
        ec.approveLevel3Emergency();
    }
    
    // --- GENERAL EMERGENCY MANAGEMENT ---
    function test_SetEmergencyLevel_Success_ToAlert_And_ToNormal() public {
        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_ALERT);
        assertEq(ec.emergencyLevel(), Constants.EMERGENCY_LEVEL_ALERT);
        assertTrue(ec.emergencyWithdrawalEnabled());

        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_NORMAL);
        assertEq(ec.emergencyLevel(), Constants.EMERGENCY_LEVEL_NORMAL);
        assertFalse(ec.emergencyWithdrawalEnabled());
    }
    
    function test_SetEmergencyLevel_ToNormal_ResetsApprovals() public {
        vm.prank(emergencyRoleHolder1);
        ec.approveLevel3Emergency();
        assertTrue(ec.emergencyApprovalProposalIds(emergencyRoleHolder1) == ec.level3ProposalId());

        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_NORMAL);
        assertFalse(ec.emergencyApprovalProposalIds(emergencyRoleHolder1) == ec.level3ProposalId());
    }
    
    function test_SetEmergencyLevel_Reverts() public {
        vm.prank(emergencyRoleHolder1);
        vm.expectRevert(abi.encodeWithSelector(EC_InvalidEmergencyLevel.selector, 4));
        ec.setEmergencyLevel(4);

        vm.prank(emergencyRoleHolder1);
        vm.expectRevert(EC_UseApproveForLevel3.selector);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_CRITICAL);
    }
    
    function test_SetEmergencyLevel_Notifications() public {
        vm.prank(emergencyRoleHolder1);
        vm.expectEmit(true, false, false, true);
        emit EmergencyLevelSet(Constants.EMERGENCY_LEVEL_ALERT, emergencyRoleHolder1);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_ALERT);
        assertTrue(ec.emergencyLevelNotified(Constants.EMERGENCY_LEVEL_ALERT));
    }
    
    function test_PauseUnpauseSystem_Success() public {
        vm.prank(pauserRoleHolder);
        ec.pauseSystem();
        assertTrue(ec.systemPaused());

        vm.prank(pauserRoleHolder);
        ec.unpauseSystem();
        assertFalse(ec.systemPaused());
    }

    function test_PauseUnpauseSystem_Reverts() public {
        vm.prank(pauserRoleHolder);
        vm.expectRevert(EC_SystemNotPaused.selector);
        ec.unpauseSystem();

        vm.prank(pauserRoleHolder);
        ec.pauseSystem();
        vm.prank(pauserRoleHolder);
        vm.expectRevert(EC_SystemAlreadyPaused.selector);
        ec.pauseSystem();
        
        setUp(); // Reset state
        vm.prank(emergencyRoleHolder1);
        ec.approveLevel3Emergency();
        vm.prank(emergencyRoleHolder2);
        ec.approveLevel3Emergency();
        skip(ec.level3TimelockDuration() + 1);
        vm.prank(emergencyRoleHolder1);
        ec.executeLevel3Emergency();

        vm.prank(pauserRoleHolder);
        vm.expectRevert(EC_CannotUnpauseAtLevel3.selector);
        ec.unpauseSystem();
    }

    // --- CONTRACT INTEGRATION ---
    function test_RegisterAndRemoveAwareContract_Success() public {
        vm.prank(emergencyRoleHolder1);
        ec.registerEmergencyAwareContract(address(awareContract2));
        
        (address[] memory page,) = ec.getEmergencyAwareContractsPaginated(0, 5);
        assertEq(page.length, 2);
        assertEq(page[0], address(awareContract1));
        assertEq(page[1], address(awareContract2));
        
        vm.prank(emergencyRoleHolder1);
        ec.removeEmergencyAwareContract(address(awareContract1));
        (page,) = ec.getEmergencyAwareContractsPaginated(0, 5);
        assertEq(page.length, 1);
        assertEq(page[0], address(awareContract2));
    }
    
    function test_RegisterAndRemove_Reverts() public {
        vm.startPrank(emergencyRoleHolder1);
        vm.expectRevert(EC_ContractAddressZero.selector);
        ec.registerEmergencyAwareContract(address(0));
        
        // This should not revert, just has no effect as it's already registered
        ec.registerEmergencyAwareContract(address(awareContract1));

        vm.expectRevert(EC_ContractAddressZero.selector);
        ec.removeEmergencyAwareContract(address(0));
        
        vm.expectRevert(abi.encodeWithSelector(EC_ContractNotRegistered.selector, address(awareContract2)));
        ec.removeEmergencyAwareContract(address(awareContract2));
        vm.stopPrank();
    }
    
    function test_GetEmergencyAwareContractsPaginated_EdgeCases() public {
        (address[] memory page, uint256 total) = ec.getEmergencyAwareContractsPaginated(1, 1);
        assertEq(page.length, 0);
        assertEq(total, 1);
        
        vm.expectRevert(EC_LimitIsZero.selector);
        ec.getEmergencyAwareContractsPaginated(0, 0);
    }
    
    function test_ProcessEmergencyForContract_Success() public {
        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_ALERT);

        vm.prank(emergencyRoleHolder1);
        ec.processEmergencyForContract(address(awareContract1), Constants.EMERGENCY_LEVEL_ALERT);
        assertEq(awareContract1.lastEmergencyLevelReceived(), Constants.EMERGENCY_LEVEL_ALERT);
    }
    
    function test_ProcessEmergencyForContract_Reverts_AllPaths() public {
        // Path 1: Contract address is zero
        vm.prank(emergencyRoleHolder1);
        vm.expectRevert(EC_ContractAddressZero.selector);
        ec.processEmergencyForContract(address(0), 1);
        
        // Path 2: Invalid emergency level
        vm.prank(emergencyRoleHolder1);
        vm.expectRevert(abi.encodeWithSelector(EC_InvalidEmergencyLevel.selector, 4));
        ec.processEmergencyForContract(address(awareContract1), 4);
        
        // Path 3: Level not in emergency
        vm.prank(emergencyRoleHolder1);
        vm.expectRevert(abi.encodeWithSelector(EC_LevelNotInEmergency.selector, 1));
        ec.processEmergencyForContract(address(awareContract1), 1);
        
        // Path 4: Contract not registered
        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(1);
        vm.expectRevert(abi.encodeWithSelector(EC_ContractNotRegistered.selector, address(awareContract2)));
        ec.processEmergencyForContract(address(awareContract2), 1);
        
        // Path 5: Already processed
        vm.prank(emergencyRoleHolder1);
        ec.processEmergencyForContract(address(awareContract1), 1); // First time is ok
        vm.expectRevert(abi.encodeWithSelector(EC_AlreadyProcessed.selector, address(awareContract1), 1));
        ec.processEmergencyForContract(address(awareContract1), 1); // Second time reverts
        
        // Path 6: Shutdown call fails - FIXED: Use different emergency level (2)
        awareContract1.setShouldRevertOnShutdown(true);
        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(Constants.EMERGENCY_LEVEL_ALERT); // level 2
        vm.prank(emergencyRoleHolder1);
        vm.expectRevert(EC_EmergencyShutdownCallFailed.selector);
        ec.processEmergencyForContract(address(awareContract1), Constants.EMERGENCY_LEVEL_ALERT);
    }

    // --- RECOVERY & ADMIN ---
    function test_RecoverTokens_SuccessAndReverts() public {
        // Success case
        vm.prank(owner);
        mockToken.mintForTest(address(ec), 1000);
        vm.prank(emergencyRoleHolder1);
        ec.recoverTokens(address(mockToken), 500);
        assertEq(mockToken.balanceOf(address(ec)), 500);
        assertEq(mockToken.balanceOf(recoveryAdmin), 500);
        
        // Revert Paths
        vm.startPrank(emergencyRoleHolder1);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "tokenAddress for recovery"));
        ec.recoverTokens(address(0), 100);
        vm.expectRevert(AmountIsZero.selector);
        ec.recoverTokens(address(mockToken), 0);
        vm.expectRevert(EC_InsufficientBalanceToRecover.selector);
        ec.recoverTokens(address(mockToken), 1000); // Only 500 left
        vm.stopPrank();

        // This path is impossible as setRecoveryAdminAddress prevents setting to address(0)
        // vm.prank(owner);
        // ec.setRecoveryAdminAddress(address(0)); // This would revert
        // vm.prank(emergencyRoleHolder1);
        // vm.expectRevert(EC_RecoveryAdminNotSet.selector);
        // ec.recoverTokens(address(mockToken), 1);
    }
    
    function test_SetRecoveryAdminAddress_SuccessAndRevert() public {
        address newAdmin = makeAddr("newAdmin");
        vm.prank(owner);
        ec.setRecoveryAdminAddress(newAdmin);
        assertEq(ec.recoveryAdminAddress(), newAdmin);
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "newRecoveryAdminAddress"));
        ec.setRecoveryAdminAddress(address(0));
    }
    
    function test_GetApprovalStatus_Pagination() public {
        vm.prank(emergencyRoleHolder1);
        ec.approveLevel3Emergency();
        vm.prank(emergencyRoleHolder2);
        ec.approveLevel3Emergency();

        (uint256 currentCount, uint256 required, address[] memory page, uint256 nextOffset, uint256 total, bool active, uint256 executeAfter) = ec.getApprovalStatus(0, 1);
        assertEq(page.length, 1);
        assertEq(page[0], emergencyRoleHolder1);
        
        (currentCount, required, page, nextOffset, total, active, executeAfter) = ec.getApprovalStatus(1, 5);
        assertEq(page.length, 1);
        assertEq(page[0], emergencyRoleHolder2);
        
        (currentCount, required, page, nextOffset, total, active, executeAfter) = ec.getApprovalStatus(2, 1);
        assertEq(page.length, 0);

        // Test with zero limit
        (currentCount, required, page, nextOffset, total, active, executeAfter) = ec.getApprovalStatus(0, 0);
        assertEq(page.length, 0);
    }
    
    function test_UpdateFunctionRestriction_SuccessAndRevert() public {
        bytes4 sel = bytes4(keccak256("test()"));
        vm.prank(emergencyRoleHolder1);
        ec.updateFunctionRestriction(sel, 2);
        assertEq(ec.restrictedFunctions(sel), 2);
        
        vm.prank(emergencyRoleHolder1);
        vm.expectRevert(abi.encodeWithSelector(EC_ThresholdInvalid.selector, 4));
        ec.updateFunctionRestriction(sel, 4);
    }

    function test_isFunctionRestricted() public {
        bytes4 sel = bytes4(keccak256("test()"));
        assertFalse(ec.isFunctionRestricted(sel));
        
        vm.prank(emergencyRoleHolder1);
        ec.updateFunctionRestriction(sel, 2);
        
        assertFalse(ec.isFunctionRestricted(sel));

        vm.prank(emergencyRoleHolder1);
        ec.setEmergencyLevel(2);
        assertTrue(ec.isFunctionRestricted(sel));
    }
}
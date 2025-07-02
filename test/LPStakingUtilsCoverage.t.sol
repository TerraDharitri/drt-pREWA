// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/liquidity/LPStakingUtils.sol";
import "../contracts/mocks/MockAccessControl.sol";
import "../contracts/mocks/MockEmergencyController.sol";

// Concrete implementation for testing the abstract LPStakingUtils
contract TestLPStakingUtils is LPStakingUtils {
    function initialize(
        address owner_,
        address accessControl_,
        address emergencyController_
    ) external initializer {
        if (owner_ == address(0)) revert ZeroAddress("owner");
        if (accessControl_ == address(0)) revert ZeroAddress("accessControl");
        if (emergencyController_ == address(0)) revert ZeroAddress("emergencyController");
        
        _owner = owner_;
        accessControl = AccessControl(accessControl_);
        emergencyController = EmergencyController(emergencyController_);
        
        __LPStakingUtils_init();
    }
    
    // Implement required IEmergencyAware functions
    function checkEmergencyStatus(bytes4) external view returns (bool allowed) {
        return !_isEffectivelyPaused();
    }
    
    function emergencyShutdown(uint8) external returns (bool success) {
        _pause();
        return true;
    }
    
    function getEmergencyController() external view returns (address controller) {
        return address(emergencyController);
    }
    
    function isEmergencyPaused() external view returns (bool isPaused) {
        return _isEffectivelyPaused();
    }
    
    function setEmergencyController(address controller) external returns (bool success) {
        emergencyController = EmergencyController(controller);
        return true;
    }
    
    // Helper functions to exercise modifiers and functionality
    function checkOnlyOwner() external view onlyOwner returns (bool) {
        return true;
    }
    
    function checkOnlyParameterRole() external view onlyParameterRole returns (bool) {
        return true;
    }
    
    function checkNonReentrant() external nonReentrant returns (bool) {
        return true;
    }
    
    function checkWhenNotPaused() external view whenNotPaused returns (bool) {
        return true;
    }
    
    function pauseContract() external onlyOwner {
        _pause();
    }
    
    function unpauseContract() external onlyOwner {
        _unpause();
    }
    
    function getOwner() external view returns (address) {
        return _owner;
    }
    
    function getAccessControl() external view returns (address) {
        return address(accessControl);
    }
}

contract LPStakingUtilsCoverageTest is Test {
    TestLPStakingUtils stakingUtils;
    MockAccessControl mockAC;
    MockEmergencyController mockEC;
    
    address owner;
    address admin;
    address user;
    
    function setUp() public {
        owner = address(0x1001);
        admin = address(0x1002);
        user = address(0x1003);
        
        // Deploy mocks
        mockAC = new MockAccessControl();
        mockEC = new MockEmergencyController();
        
        // Set up access control roles
        vm.prank(owner);
        mockAC.setRole(mockAC.DEFAULT_ADMIN_ROLE(), owner, true);
        vm.prank(owner);
        mockAC.setRole(mockAC.PARAMETER_ROLE(), admin, true);
        
        // Deploy test contract
        stakingUtils = new TestLPStakingUtils();
        stakingUtils.initialize(owner, address(mockAC), address(mockEC));
    }
    
    // Test initialization
    function test_Initialize_Success() public {
        TestLPStakingUtils newUtils = new TestLPStakingUtils();
        
        newUtils.initialize(owner, address(mockAC), address(mockEC));
        
        assertEq(newUtils.getOwner(), owner);
        assertEq(newUtils.getAccessControl(), address(mockAC));
        assertEq(address(newUtils.getEmergencyController()), address(mockEC));
        assertFalse(newUtils.paused());
    }
    
    function test_Initialize_Revert_ZeroOwner() public {
        TestLPStakingUtils newUtils = new TestLPStakingUtils();
        
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "owner"));
        newUtils.initialize(address(0), address(mockAC), address(mockEC));
    }
    
    function test_Initialize_Revert_ZeroAccessControl() public {
        TestLPStakingUtils newUtils = new TestLPStakingUtils();
        
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "accessControl"));
        newUtils.initialize(owner, address(0), address(mockEC));
    }
    
    function test_Initialize_Revert_ZeroEmergencyController() public {
        TestLPStakingUtils newUtils = new TestLPStakingUtils();
        
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "emergencyController"));
        newUtils.initialize(owner, address(mockAC), address(0));
    }
    
    function test_Initialize_Revert_AlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        stakingUtils.initialize(owner, address(mockAC), address(mockEC));
    }
    
    // Test onlyOwner modifier
    function test_OnlyOwner_Success() public {
        vm.prank(owner);
        assertTrue(stakingUtils.checkOnlyOwner());
    }
    
    function test_OnlyOwner_Revert_NotOwner() public {
        vm.prank(user);
        vm.expectRevert(NotOwner.selector);
        stakingUtils.checkOnlyOwner();
    }
    
    // Test onlyParameterRole modifier
    function test_OnlyParameterRole_Success() public {
        vm.prank(admin);
        assertTrue(stakingUtils.checkOnlyParameterRole());
    }
    
    function test_OnlyParameterRole_Revert_NotAuthorized() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, mockAC.PARAMETER_ROLE()));
        stakingUtils.checkOnlyParameterRole();
    }
    
    function test_OnlyParameterRole_Revert_AccessControlZero() public {
        // Create new utils with zero access control to test the branch
        TestLPStakingUtils newUtils = new TestLPStakingUtils();
        
        // Manually set state to bypass initialization checks
        vm.store(address(newUtils), bytes32(uint256(0)), bytes32(uint256(1))); // Set initialized flag
        
        vm.expectRevert(NotInitialized.selector);
        newUtils.checkOnlyParameterRole();
    }
    
    // Test nonReentrant modifier
    function test_NonReentrant_Success() public {
        vm.prank(user);
        assertTrue(stakingUtils.checkNonReentrant());
    }
    
    // Test whenNotPaused modifier
    function test_WhenNotPaused_Success() public {
        vm.prank(user);
        assertTrue(stakingUtils.checkWhenNotPaused());
    }
    
    function test_WhenNotPaused_Revert_Paused() public {
        // Pause the contract
        vm.prank(owner);
        stakingUtils.pauseContract();
        
        vm.prank(user);
        vm.expectRevert("Pausable: paused");
        stakingUtils.checkWhenNotPaused();
    }
    
    // Test pause/unpause functionality
    function test_PauseContract_Success() public {
        assertFalse(stakingUtils.paused());
        
        vm.prank(owner);
        stakingUtils.pauseContract();
        
        assertTrue(stakingUtils.paused());
    }
    
    function test_PauseContract_Revert_NotOwner() public {
        vm.prank(user);
        vm.expectRevert(NotOwner.selector);
        stakingUtils.pauseContract();
    }
    
    function test_UnpauseContract_Success() public {
        // First pause
        vm.prank(owner);
        stakingUtils.pauseContract();
        assertTrue(stakingUtils.paused());
        
        // Then unpause
        vm.prank(owner);
        stakingUtils.unpauseContract();
        assertFalse(stakingUtils.paused());
    }
    
    function test_UnpauseContract_Revert_NotOwner() public {
        // First pause
        vm.prank(owner);
        stakingUtils.pauseContract();
        
        vm.prank(user);
        vm.expectRevert(NotOwner.selector);
        stakingUtils.unpauseContract();
    }
    
    // Test getter functions
    function test_GetOwner_Success() public view {
        assertEq(stakingUtils.getOwner(), owner);
    }
    
    function test_GetAccessControl_Success() public view {
        assertEq(stakingUtils.getAccessControl(), address(mockAC));
    }
    
    function test_GetEmergencyController_Success() public view {
        assertEq(address(stakingUtils.getEmergencyController()), address(mockEC));
    }
    
    // Test combined modifier scenarios
    function test_CombinedModifiers_OwnerWhenNotPaused() public {
        vm.prank(owner);
        assertTrue(stakingUtils.checkOnlyOwner());
        assertTrue(stakingUtils.checkWhenNotPaused());
    }
    
    function test_CombinedModifiers_ParameterRoleNonReentrant() public {
        vm.prank(admin);
        assertTrue(stakingUtils.checkOnlyParameterRole());
        assertTrue(stakingUtils.checkNonReentrant());
    }
    
    // Test edge cases
    function test_MultipleOperations_Success() public {
        // Test multiple operations in sequence
        vm.startPrank(owner);
        assertTrue(stakingUtils.checkOnlyOwner());
        stakingUtils.pauseContract();
        stakingUtils.unpauseContract();
        assertTrue(stakingUtils.checkOnlyOwner());
        vm.stopPrank();
        
        vm.prank(admin);
        assertTrue(stakingUtils.checkOnlyParameterRole());
    }
}
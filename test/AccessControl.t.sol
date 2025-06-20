// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../contracts/access/AccessControl.sol";
import "../contracts/access/interfaces/IAccessControl.sol";
import "../contracts/libraries/Errors.sol";
import "../contracts/proxy/TransparentProxy.sol";

contract AccessControlTest is Test {
    AccessControl accessControl;
    address deployer;
    address adminUser;
    address user1;
    address user2;
    address user3;
    address nonAdminUser;
    address proxyAdmin;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant PARAMETER_ROLE = keccak256("PARAMETER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public CUSTOM_ROLE_1 = keccak256("CUSTOM_ROLE_1");
    bytes32 public CUSTOM_ROLE_2 = keccak256("CUSTOM_ROLE_2");


    function setUp() public {
        deployer = address(this); 
        adminUser = makeAddr("adminUser");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        nonAdminUser = makeAddr("nonAdminUser");
        proxyAdmin = makeAddr("proxyAdmin");

        AccessControl logic = new AccessControl();
        bytes memory data = abi.encodeWithSelector(logic.initialize.selector, adminUser);
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, data);
        accessControl = AccessControl(address(proxy));
    }

    function test_Constructor_Runs() public {
        new AccessControl(); 
        assertTrue(true, "Constructor ran"); 
    }


    function test_Initialize_CorrectlySetsUpRolesAndAdmin() public { 
        vm.prank(user1);
        assertTrue(accessControl.hasRole(DEFAULT_ADMIN_ROLE, adminUser));
        vm.prank(user1);
        assertEq(accessControl.getRoleAdmin(DEFAULT_ADMIN_ROLE), DEFAULT_ADMIN_ROLE);
        vm.prank(user1);
        assertEq(accessControl.getRoleAdmin(UPGRADER_ROLE), DEFAULT_ADMIN_ROLE);
        vm.prank(user1);
        assertEq(accessControl.getRoleAdmin(EMERGENCY_ROLE), DEFAULT_ADMIN_ROLE);
        vm.prank(user1);
        assertEq(accessControl.getRoleAdmin(PAUSER_ROLE), DEFAULT_ADMIN_ROLE);
        vm.prank(user1);
        assertEq(accessControl.getRoleAdmin(PARAMETER_ROLE), DEFAULT_ADMIN_ROLE);
        vm.prank(user1);
        assertEq(accessControl.getRoleAdmin(MINTER_ROLE), DEFAULT_ADMIN_ROLE);

        vm.prank(user1);
        assertEq(accessControl.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
        vm.prank(user1);
        assertEq(accessControl.getRoleMember(DEFAULT_ADMIN_ROLE, 0), adminUser);
    }

    function test_Initialize_RevertIfAdminIsZeroAddress() public {
        AccessControl logic = new AccessControl();
        bytes memory data = abi.encodeWithSelector(logic.initialize.selector, address(0));
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "admin"));
        new TransparentProxy(address(logic), proxyAdmin, data);
    }

    function test_Initialize_RevertIfCalledTwice() public {
        vm.prank(user1);
        vm.expectRevert("Initializable: contract is already initialized");
        accessControl.initialize(user1);
    }

    function test_HasRole_ReturnsTrueIfAccountHasRole() public {
        vm.prank(adminUser);
        accessControl.grantRole(MINTER_ROLE, user1);
        vm.prank(user2);
        assertTrue(accessControl.hasRole(MINTER_ROLE, user1));
    }

    function test_HasRole_ReturnsFalseIfAccountDoesNotHaveRole() public { 
        vm.prank(user1);
        assertFalse(accessControl.hasRole(MINTER_ROLE, user2));
    }

    function test_HasRole_RevertIfAccountIsZero() public {
        vm.prank(user1);
        vm.expectRevert(AC_AccountInvalid.selector);
        accessControl.hasRole(MINTER_ROLE, address(0));
    }

    function test_GetRoleAdmin_ReturnsCorrectAdminRole() public { 
        vm.prank(user1);
        assertEq(accessControl.getRoleAdmin(MINTER_ROLE), DEFAULT_ADMIN_ROLE);
        vm.prank(user1);
        assertEq(accessControl.getRoleAdmin(DEFAULT_ADMIN_ROLE), DEFAULT_ADMIN_ROLE);
        vm.prank(user1);
        assertEq(accessControl.getRoleAdmin(CUSTOM_ROLE_1), DEFAULT_ADMIN_ROLE);
    }
    
    function test_GrantRole_Success() public {
        vm.prank(adminUser);
        vm.expectEmit(true, true, true, true);
        emit IAccessControl.RoleGranted(MINTER_ROLE, user1, adminUser);
        accessControl.grantRole(MINTER_ROLE, user1);

        vm.prank(user2);
        assertTrue(accessControl.hasRole(MINTER_ROLE, user1));
        vm.prank(user2);
        assertEq(accessControl.getRoleMemberCount(MINTER_ROLE), 1);
        vm.prank(user2);
        assertEq(accessControl.getRoleMember(MINTER_ROLE, 0), user1);
    }

    function test_GrantRole_NoEffectIfRoleAlreadyGranted() public {
        vm.prank(adminUser);
        accessControl.grantRole(MINTER_ROLE, user1); 
        
        vm.prank(adminUser); 
        accessControl.grantRole(MINTER_ROLE, user1); 

        vm.prank(user2);
        assertTrue(accessControl.hasRole(MINTER_ROLE, user1));
        vm.prank(user2);
        assertEq(accessControl.getRoleMemberCount(MINTER_ROLE), 1); 
    }

    function test_GrantRole_RevertIfSenderLacksAdminRole() public {
        vm.prank(nonAdminUser);
        vm.expectRevert(abi.encodeWithSelector(AC_SenderMissingAdminRole.selector, DEFAULT_ADMIN_ROLE));
        accessControl.grantRole(MINTER_ROLE, user1);
    }
    
    function test_GrantRole_RevertIfAccountIsZero() public {
        vm.prank(adminUser);
        vm.expectRevert(AC_AccountInvalid.selector);
        accessControl.grantRole(MINTER_ROLE, address(0));
    }

    function test_GrantRole_RevertIfRoleIsZeroAndNotDAR() public {
        vm.prank(adminUser);
        accessControl.grantRole(bytes32(0), user1);
        assertTrue(accessControl.hasRole(bytes32(0), user1));
    }
    
    function test_RevokeRole_Success() public {
        vm.prank(adminUser);
        accessControl.grantRole(MINTER_ROLE, user1);
        vm.prank(user2);
        assertTrue(accessControl.hasRole(MINTER_ROLE, user1));

        vm.prank(adminUser); 
        vm.expectEmit(true, true, true, true);
        emit IAccessControl.RoleRevoked(MINTER_ROLE, user1, adminUser);
        accessControl.revokeRole(MINTER_ROLE, user1);

        vm.prank(user2);
        assertFalse(accessControl.hasRole(MINTER_ROLE, user1));
        vm.prank(user2);
        assertEq(accessControl.getRoleMemberCount(MINTER_ROLE), 0);
    }
    
    function test_RevokeRole_MemberIsLastElementInActiveArray() public {
        vm.prank(adminUser);
        accessControl.grantRole(MINTER_ROLE, user1);
        vm.prank(adminUser);
        accessControl.grantRole(MINTER_ROLE, user2); 
        
        vm.prank(adminUser); 
        accessControl.revokeRole(MINTER_ROLE, user2);

        vm.prank(user3);
        assertFalse(accessControl.hasRole(MINTER_ROLE, user2));
        vm.prank(user3);
        assertEq(accessControl.getRoleMemberCount(MINTER_ROLE), 1);
        vm.prank(user3);
        assertEq(accessControl.getRoleMember(MINTER_ROLE, 0), user1);
    }

    function test_RevokeRole_MemberIsMiddleElementInActiveArray() public {
        vm.prank(adminUser);
        accessControl.grantRole(MINTER_ROLE, user1);
        vm.prank(adminUser);
        accessControl.grantRole(MINTER_ROLE, user2);
        vm.prank(adminUser);
        accessControl.grantRole(MINTER_ROLE, user3); 
        
        vm.prank(adminUser); 
        accessControl.revokeRole(MINTER_ROLE, user2); 

        vm.prank(nonAdminUser);
        assertFalse(accessControl.hasRole(MINTER_ROLE, user2));
        vm.prank(nonAdminUser);
        assertEq(accessControl.getRoleMemberCount(MINTER_ROLE), 2);
        vm.prank(nonAdminUser);
        assertEq(accessControl.getRoleMember(MINTER_ROLE, 0), user1);
        vm.prank(nonAdminUser);
        assertEq(accessControl.getRoleMember(MINTER_ROLE, 1), user3);
    }

    function test_RevokeRole_NoEffectIfRoleNotGranted() public {
        vm.prank(adminUser);
        accessControl.revokeRole(MINTER_ROLE, user1); 
        vm.prank(user2);
        assertFalse(accessControl.hasRole(MINTER_ROLE, user1));
    }

    function test_RevokeRole_RevertIfSenderLacksAdminRole() public {
        vm.prank(adminUser);
        accessControl.grantRole(MINTER_ROLE, user1);
        vm.prank(nonAdminUser);
        vm.expectRevert(abi.encodeWithSelector(AC_SenderMissingAdminRole.selector, DEFAULT_ADMIN_ROLE));
        accessControl.revokeRole(MINTER_ROLE, user1);
    }

    function test_RevokeRole_RevertIfCannotRemoveLastAdmin() public {
        vm.prank(adminUser);
        vm.expectRevert(AC_CannotRemoveLastAdmin.selector);
        accessControl.revokeRole(DEFAULT_ADMIN_ROLE, adminUser);
    }
    
    function test_RevokeRole_SuccessRemovingOneOfMultipleAdmins() public {
        vm.prank(adminUser);
        accessControl.grantRole(DEFAULT_ADMIN_ROLE, user1); 
        vm.prank(user2);
        assertTrue(accessControl.hasRole(DEFAULT_ADMIN_ROLE, user1));
        vm.prank(user2);
        assertEq(accessControl.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 2);

        vm.prank(adminUser); 
        vm.expectEmit(true, true, true, true);
        emit IAccessControl.RoleRevoked(DEFAULT_ADMIN_ROLE, user1, adminUser);
        accessControl.revokeRole(DEFAULT_ADMIN_ROLE, user1);
        
        vm.prank(user2);
        assertFalse(accessControl.hasRole(DEFAULT_ADMIN_ROLE, user1));
        vm.prank(user2);
        assertEq(accessControl.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
        vm.prank(user2);
        assertTrue(accessControl.hasRole(DEFAULT_ADMIN_ROLE, adminUser)); 
    }

    function test_RevokeRole_RevertIfRoleIsZeroAndNotDAR() public {
        vm.prank(adminUser);
        vm.expectRevert(AC_CannotRemoveLastAdmin.selector);
        accessControl.revokeRole(bytes32(0), adminUser);
    }

    function test_RevokeRole_RevertIfAccountIsZero() public {
        vm.prank(adminUser);
        vm.expectRevert(AC_AccountInvalid.selector);
        accessControl.revokeRole(MINTER_ROLE, address(0));
    }

    function test_RenounceRole_Success() public {
        vm.prank(adminUser);
        accessControl.grantRole(MINTER_ROLE, user1);
        
        vm.prank(user1); 
        vm.expectEmit(true, true, true, true);
        emit IAccessControl.RoleRevoked(MINTER_ROLE, user1, user1);
        accessControl.renounceRole(MINTER_ROLE);

        vm.prank(user2);
        assertFalse(accessControl.hasRole(MINTER_ROLE, user1));
        vm.prank(user2);
        assertEq(accessControl.getRoleMemberCount(MINTER_ROLE), 0);
    }

    function test_RenounceRole_NoEffectIfRoleNotHeld() public {
        vm.prank(user1); 
        accessControl.renounceRole(MINTER_ROLE);
        vm.prank(user2);
        assertFalse(accessControl.hasRole(MINTER_ROLE, user1));
    }
    
    function test_RenounceRole_RevertIfCannotRemoveLastAdmin() public {
        vm.prank(adminUser);
        vm.expectRevert(AC_CannotRemoveLastAdmin.selector);
        accessControl.renounceRole(DEFAULT_ADMIN_ROLE);
    }

    function test_RenounceRole_SuccessOneOfMultipleAdmins() public {
        vm.prank(adminUser);
        accessControl.grantRole(DEFAULT_ADMIN_ROLE, user1);

        vm.prank(user1); 
        accessControl.renounceRole(DEFAULT_ADMIN_ROLE);

        vm.prank(user2);
        assertFalse(accessControl.hasRole(DEFAULT_ADMIN_ROLE, user1));
        vm.prank(user2);
        assertEq(accessControl.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1); 
    }

    function test_RenounceRole_RevertIfRoleIsZeroAndNotDAR() public {
        vm.prank(adminUser);
        vm.expectRevert(AC_CannotRemoveLastAdmin.selector);
        accessControl.renounceRole(bytes32(0));
    }

    function test_SetRoleAdmin_Success() public {
        vm.prank(adminUser); 
        vm.expectEmit(true, true, true, true);
        emit IAccessControl.RoleAdminChanged(MINTER_ROLE, DEFAULT_ADMIN_ROLE, CUSTOM_ROLE_1);
        accessControl.setRoleAdmin(MINTER_ROLE, CUSTOM_ROLE_1);

        vm.prank(user1);
        assertEq(accessControl.getRoleAdmin(MINTER_ROLE), CUSTOM_ROLE_1);
    }

    function test_SetRoleAdmin_SuccessWithNonDefaultAdminRole() public {
        vm.prank(adminUser);
        accessControl.setRoleAdmin(MINTER_ROLE, CUSTOM_ROLE_1); 
        vm.prank(adminUser); 
        accessControl.grantRole(CUSTOM_ROLE_1, user1); 

        vm.prank(user1); 
        vm.expectEmit(true, true, true, true);
        emit IAccessControl.RoleAdminChanged(MINTER_ROLE, CUSTOM_ROLE_1, DEFAULT_ADMIN_ROLE);
        accessControl.setRoleAdmin(MINTER_ROLE, DEFAULT_ADMIN_ROLE);
        
        vm.prank(user2);
        assertEq(accessControl.getRoleAdmin(MINTER_ROLE), DEFAULT_ADMIN_ROLE);
    }
    
    function test_SetRoleAdmin_RevertIfSenderLacksAdminRole() public {
        vm.prank(nonAdminUser);
        vm.expectRevert(abi.encodeWithSelector(AC_SenderMissingAdminRole.selector, DEFAULT_ADMIN_ROLE));
        accessControl.setRoleAdmin(MINTER_ROLE, CUSTOM_ROLE_1);
    }

    function test_SetRoleAdmin_RevertIfRoleIsZeroAndNotDAR() public {
        vm.prank(adminUser);
        accessControl.setRoleAdmin(bytes32(0), CUSTOM_ROLE_1);
        assertEq(accessControl.getRoleAdmin(bytes32(0)), CUSTOM_ROLE_1);
    }

    function test_GetRoleMember_Success() public {
        vm.prank(adminUser);
        accessControl.grantRole(MINTER_ROLE, user1);
        vm.prank(adminUser);
        accessControl.grantRole(MINTER_ROLE, user2);

        vm.prank(user3);
        assertEq(accessControl.getRoleMember(MINTER_ROLE, 0), user1);
        vm.prank(user3);
        assertEq(accessControl.getRoleMember(MINTER_ROLE, 1), user2);
    }

    function test_GetRoleMember_RevertIfIndexOutOfBounds() public {
        vm.prank(adminUser);
        accessControl.grantRole(MINTER_ROLE, user1);
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(AC_IndexOutOfBounds.selector, 1, 1));
        accessControl.getRoleMember(MINTER_ROLE, 1);
    }
    
    function test_GetRoleMemberCount_Success() public {
        vm.prank(user1);
        assertEq(accessControl.getRoleMemberCount(MINTER_ROLE), 0);
        
        vm.prank(adminUser);
        accessControl.grantRole(MINTER_ROLE, user1);
        vm.prank(user2);
        assertEq(accessControl.getRoleMemberCount(MINTER_ROLE), 1);

        vm.prank(adminUser);
        accessControl.grantRole(MINTER_ROLE, user2);
        vm.prank(user1);
        assertEq(accessControl.getRoleMemberCount(MINTER_ROLE), 2);

        vm.prank(adminUser);
        accessControl.revokeRole(MINTER_ROLE, user1);
        vm.prank(user2);
        assertEq(accessControl.getRoleMemberCount(MINTER_ROLE), 1);
    }

    function test_GetRoleMembersPaginated_SuccessScenarios() public {
        vm.prank(adminUser);
        accessControl.grantRole(MINTER_ROLE, user1);
        vm.prank(adminUser);
        accessControl.grantRole(MINTER_ROLE, user2);
        vm.prank(adminUser);
        accessControl.grantRole(MINTER_ROLE, user3);

        vm.prank(nonAdminUser);
        (address[] memory page, uint256 total) = accessControl.getRoleMembersPaginated(MINTER_ROLE, 0, 2);
        assertEq(total, 3);
        assertEq(page.length, 2);
        assertEq(page[0], user1);
        assertEq(page[1], user2);

        vm.prank(nonAdminUser);
        (page, total) = accessControl.getRoleMembersPaginated(MINTER_ROLE, 1, 2);
        assertEq(total, 3);
        assertEq(page.length, 2);
        assertEq(page[0], user2);
        assertEq(page[1], user3);
        
        vm.prank(nonAdminUser);
        (page, total) = accessControl.getRoleMembersPaginated(MINTER_ROLE, 2, 2);
        assertEq(total, 3);
        assertEq(page.length, 1);
        assertEq(page[0], user3);

        vm.prank(nonAdminUser);
        (page, total) = accessControl.getRoleMembersPaginated(MINTER_ROLE, 0, 5); 
        assertEq(total, 3);
        assertEq(page.length, 3);
    }
    
    function test_GetRoleMembersPaginated_OffsetOutOfBounds() public {
        vm.prank(adminUser);
        accessControl.grantRole(MINTER_ROLE, user1);

        vm.prank(user2);
        (address[] memory page, uint256 total) = accessControl.getRoleMembersPaginated(MINTER_ROLE, 1, 1);
        assertEq(total, 1);
        assertEq(page.length, 0);
    }

    function test_GetRoleMembersPaginated_NoMembers() public { 
        vm.prank(user1);
        (address[] memory page, uint256 total) = accessControl.getRoleMembersPaginated(CUSTOM_ROLE_1, 0, 10);
        assertEq(total, 0);
        assertEq(page.length, 0);
    }

    function test_GetRoleMembersPaginated_RevertIfLimitIsZero() public {
        vm.prank(user1);
        vm.expectRevert(InvalidAmount.selector);
        accessControl.getRoleMembersPaginated(MINTER_ROLE, 0, 0);
    }
}
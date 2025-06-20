// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./storage/AccessControlStorage.sol";
import "./interfaces/IAccessControl.sol";
import "../libraries/Errors.sol";

/**
 * @title AccessControl
 * @author Rewa
 * @notice A robust role-based access control contract with member enumeration.
 * @dev This contract extends the standard OpenZeppelin AccessControl model by adding the ability
 * to enumerate members of a role. It defines several system-wide roles and is designed to be
 * a central authority for permissions across the entire protocol. It is upgradeable.
 */
contract AccessControl is Initializable, AccessControlStorage, IAccessControl {
    /// @notice The default admin role, which can manage other roles.
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    /// @notice The role for managing contract upgrades via the ProxyAdmin.
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    /// @notice The role for managing the ProxyAdmin contract itself.
    bytes32 public constant PROXY_ADMIN_ROLE = keccak256("PROXY_ADMIN_ROLE");
    /// @notice The role for managing emergency states and actions.
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    /// @notice The role for pausing and unpausing system components.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice The role for managing critical system parameters.
    bytes32 public constant PARAMETER_ROLE = keccak256("PARAMETER_ROLE");
    /// @notice The role for minting new tokens.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    /**
     * @dev Disables the regular constructor to make the contract upgradeable.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the AccessControl contract.
     * @dev Sets up the role hierarchy and grants the `DEFAULT_ADMIN_ROLE` to the provided admin address.
     * This function can only be called once.
     * @param admin The address of the initial default admin.
     */
    function initialize(address admin) external initializer {
        if (admin == address(0)) revert ZeroAddress("admin");
        
        _setRoleAdmin(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        
        _setRoleAdmin(UPGRADER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(PROXY_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(EMERGENCY_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(PARAMETER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(MINTER_ROLE, DEFAULT_ADMIN_ROLE);
    }

    /**
     * @inheritdoc IAccessControl
     */
    function hasRole(bytes32 role, address account) external view override returns (bool) {
        if (account == address(0)) revert AC_AccountInvalid();
        return _roles[role][account];
    }

    /**
     * @inheritdoc IAccessControl
     */
    function getRoleAdmin(bytes32 role) external view override returns (bytes32) {
        return _roleAdmins[role];
    }

    /**
     * @inheritdoc IAccessControl
     */
    function grantRole(bytes32 role, address account) external override {
        if (account == address(0)) revert AC_AccountInvalid();
        
        // Determine the admin role required to grant the target role.
        bytes32 adminRoleToCheck = _roleAdmins[role];
        if (adminRoleToCheck == bytes32(0) && role != DEFAULT_ADMIN_ROLE) {
            adminRoleToCheck = DEFAULT_ADMIN_ROLE;
        } else if (role == DEFAULT_ADMIN_ROLE && adminRoleToCheck == bytes32(0)){
            adminRoleToCheck = DEFAULT_ADMIN_ROLE;
        }

        if (!_roles[adminRoleToCheck][msg.sender]) {
            revert AC_SenderMissingAdminRole(adminRoleToCheck);
        }
        if (role == bytes32(0) && role != DEFAULT_ADMIN_ROLE) revert AC_RoleCannotBeZero();

        _grantRole(role, account);
    }

    /**
     * @inheritdoc IAccessControl
     */
    function revokeRole(bytes32 role, address account) external override {
        if (account == address(0)) revert AC_AccountInvalid();
        
        // Determine the admin role required to revoke the target role.
        bytes32 adminRoleToCheck = _roleAdmins[role];
        if (adminRoleToCheck == bytes32(0) && role != DEFAULT_ADMIN_ROLE) {
            adminRoleToCheck = DEFAULT_ADMIN_ROLE;
        } else if (role == DEFAULT_ADMIN_ROLE && adminRoleToCheck == bytes32(0)){
            adminRoleToCheck = DEFAULT_ADMIN_ROLE;
        }

        if (!_roles[adminRoleToCheck][msg.sender]) {
            revert AC_SenderMissingAdminRole(adminRoleToCheck);
        }
        
        // A safety check to prevent the contract from being left without any admin.
        if (role == DEFAULT_ADMIN_ROLE) {
            if (_activeRoleMembers[DEFAULT_ADMIN_ROLE].length <= 1) {
                 revert AC_CannotRemoveLastAdmin();
            }
        } else if (role == bytes32(0)) {
             revert AC_RoleCannotBeZero();
        }
        
        _revokeRole(role, account);
    }

    /**
     * @inheritdoc IAccessControl
     */
    function renounceRole(bytes32 role) external override {
        // A safety check to prevent the contract from being left without any admin.
        if (role == DEFAULT_ADMIN_ROLE) {
             if (_activeRoleMembers[DEFAULT_ADMIN_ROLE].length <= 1) {
                 revert AC_CannotRemoveLastAdmin();
            }
        } else if (role == bytes32(0)) {
             revert AC_RoleCannotBeZero();
        }
        
        _revokeRole(role, msg.sender);
    }

    /**
     * @notice Sets the admin role for a given role.
     * @dev The caller must have the current admin role for the target role.
     * @param role The role to be administered.
     * @param adminRole The new admin role.
     */
    function setRoleAdmin(bytes32 role, bytes32 adminRole) external {
        bytes32 currentAdminRole = _roleAdmins[role];
        bytes32 effectiveCurrentAdmin = (currentAdminRole == bytes32(0) && role != DEFAULT_ADMIN_ROLE) ? DEFAULT_ADMIN_ROLE : currentAdminRole;
        if (role == DEFAULT_ADMIN_ROLE && currentAdminRole == bytes32(0)) {
            effectiveCurrentAdmin = DEFAULT_ADMIN_ROLE;
        }

        if (!_roles[effectiveCurrentAdmin][msg.sender]) {
            revert AC_SenderMissingAdminRole(effectiveCurrentAdmin);
        }
        if (role == bytes32(0) && role != DEFAULT_ADMIN_ROLE) revert AC_RoleCannotBeZero();

        _setRoleAdmin(role, adminRole);
    }
    
    /**
     * @inheritdoc IAccessControl
     */
    function getRoleMember(bytes32 role, uint256 index) external view override returns (address) {
        if (index >= _activeRoleMembers[role].length) revert AC_IndexOutOfBounds(index, _activeRoleMembers[role].length);
        return _activeRoleMembers[role][index];
    }
    
    /**
     * @inheritdoc IAccessControl
     */
    function getRoleMemberCount(bytes32 role) external view override returns (uint256) {
        return _activeRoleMembers[role].length;
    }

    /**
     * @inheritdoc IAccessControl
     */
    function getRoleMembersPaginated(bytes32 role, uint256 offset, uint256 limit) external view override returns (address[] memory page, uint256 totalMembers) {
        if (limit == 0) revert InvalidAmount(); 

        address[] storage members = _activeRoleMembers[role];
        totalMembers = members.length;

        if (offset >= totalMembers) {
            return (new address[](0), totalMembers);
        }

        uint256 count = totalMembers - offset < limit ? totalMembers - offset : limit;
        page = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            page[i] = members[offset + i];
        }
        return (page, totalMembers);
    }

    /**
     * @dev Internal function to grant a role and update member enumeration lists.
     * It adds the account to the role's member array for O(1) access by index.
     */
    function _grantRole(bytes32 role, address account) internal {
        if (!_roles[role][account]) {
            _roles[role][account] = true;
            
            _memberIndices[role][account] = _activeRoleMembers[role].length;
            _activeRoleMembers[role].push(account);
            
            emit RoleGranted(role, account, msg.sender);
        }
    }

    /**
     * @dev Internal function to revoke a role and update member enumeration lists.
     * It uses the "swap and pop" technique for O(1) removal from the member array.
     */
    function _revokeRole(bytes32 role, address account) internal {
        if (_roles[role][account]) {
            _roles[role][account] = false;
            
            if (_activeRoleMembers[role].length > 0) {
                uint256 index = _memberIndices[role][account];
                if (index < _activeRoleMembers[role].length) { 
                    uint256 lastIndex = _activeRoleMembers[role].length - 1;
                    
                    if (index != lastIndex) {
                        address lastMember = _activeRoleMembers[role][lastIndex];
                        _activeRoleMembers[role][index] = lastMember;
                        _memberIndices[role][lastMember] = index;
                    }
                    
                    _activeRoleMembers[role].pop();
                }
            }
            delete _memberIndices[role][account]; 
            
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    /**
     * @dev Internal function to set the admin role for another role.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal {
        bytes32 previousAdminRole = _roleAdmins[role];
        _roleAdmins[role] = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }
}
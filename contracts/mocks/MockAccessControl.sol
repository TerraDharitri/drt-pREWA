// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../access/interfaces/IAccessControl.sol";
import "../access/storage/AccessControlStorage.sol";

contract MockAccessControl is IAccessControl, AccessControlStorage {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant PARAMETER_ROLE = keccak256("PARAMETER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PROXY_ADMIN_ROLE = keccak256("PROXY_ADMIN_ROLE");

    function setRole(bytes32 role, address account, bool has) external {
        if (has) {
            _grantRoleInternal(role, account, msg.sender);
        } else {
            // Prevent removing the last admin
            if (role == DEFAULT_ADMIN_ROLE && this.getRoleMemberCount(DEFAULT_ADMIN_ROLE) <= 1 && _roles[role][account]) {
                return;
            }
            _revokeRoleInternal(role, account, msg.sender);
        }
    }
    
    function _setRoleAdminInternal(bytes32 role, bytes32 adminRole) internal {
        bytes32 previousAdminRole = _roleAdmins[role];
        _roleAdmins[role] = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }

    function setRoleAdmin(bytes32 role, bytes32 adminRole) external {
        _setRoleAdminInternal(role, adminRole);
    }

    function hasRole(bytes32 role, address account) external view override returns (bool) {
        return _roles[role][account];
    }

    function getRoleAdmin(bytes32 role) external view override returns (bytes32) {
        return _roleAdmins[role];
    }

    function grantRole(bytes32 role, address account) external override {
        _grantRoleInternal(role, account, msg.sender);
    }

    function revokeRole(bytes32 role, address account) external override {
        // Prevent removing the last admin
        if (role == DEFAULT_ADMIN_ROLE && this.getRoleMemberCount(DEFAULT_ADMIN_ROLE) <= 1 && _roles[role][account]) {
            revert("MockAC: Cannot remove last admin");
        }
        _revokeRoleInternal(role, account, msg.sender);
    }

    function renounceRole(bytes32 role) external override {
         // Prevent removing the last admin
        if (role == DEFAULT_ADMIN_ROLE && this.getRoleMemberCount(DEFAULT_ADMIN_ROLE) <= 1) {
            revert("MockAC: Cannot remove last admin");
        }
        _revokeRoleInternal(role, msg.sender, msg.sender);
    }

    function _grantRoleInternal(bytes32 role, address account, address sender) internal {
        if (!_roles[role][account]) {
            _roles[role][account] = true;
            if (account != address(0)) {
                _memberIndices[role][account] = _activeRoleMembers[role].length;
                _activeRoleMembers[role].push(account);
            }
            emit RoleGranted(role, account, sender);
        }
    }

    function _revokeRoleInternal(bytes32 role, address account, address sender) internal {
        if (_roles[role][account]) {
            _roles[role][account] = false;
            if (account != address(0) && _activeRoleMembers[role].length > 0) {
                uint256 index = _memberIndices[role][account];
                if (index < _activeRoleMembers[role].length) { 
                    uint256 lastIndex = _activeRoleMembers[role].length - 1;
                    if (index != lastIndex) {
                        address lastMember = _activeRoleMembers[role][lastIndex];
                        _activeRoleMembers[role][index] = lastMember;
                        _memberIndices[role][lastMember] = index;
                    }
                    _activeRoleMembers[role].pop();
                    delete _memberIndices[role][account];
                }
            }
            emit RoleRevoked(role, account, sender);
        }
    }
    
    function getRoleMember(bytes32 role, uint256 index) external view override returns (address) {
        require(index < _activeRoleMembers[role].length, "MockAC: Index out of bounds");
        return _activeRoleMembers[role][index];
    }
    
    function getRoleMemberCount(bytes32 role) external view override returns (uint256) {
        return _activeRoleMembers[role].length;
    }

    function getRoleMembersPaginated(bytes32 role, uint256 offset, uint256 limit) external view override returns (address[] memory page, uint256 totalMembers) {
        address[] storage members = _activeRoleMembers[role];
        totalMembers = members.length;

        if (limit == 0) {
            revert("MockAC: Limit cannot be zero");
        }

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
    
    // Helper function for tests to reset state more reliably
    function resetRoleState() external {
        uint256 count = this.getRoleMemberCount(EMERGENCY_ROLE);
        // Create a copy of members to iterate over, as _revokeRoleInternal modifies the array
        address[] memory membersToRevoke = new address[](count);
        for(uint i = 0; i < count; i++) {
            membersToRevoke[i] = _activeRoleMembers[EMERGENCY_ROLE][i];
        }

        for (uint i = 0; i < membersToRevoke.length; i++) {
            address account = membersToRevoke[i];
            if (_roles[EMERGENCY_ROLE][account]) {
                _revokeRoleInternal(EMERGENCY_ROLE, account, address(this));
            }
        }
    }
}
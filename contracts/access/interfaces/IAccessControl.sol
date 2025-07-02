// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IAccessControl Interface
 * @notice Defines the external interface for an access control contract, inspired by OpenZeppelin's standard.
 * @dev This interface includes standard role management functions as well as extensions for enumerating role members.
 */
interface IAccessControl {
    /**
     * @notice Emitted when a `role` is granted to an `account`.
     * @param role The `bytes32` identifier of the role.
     * @param account The address that was granted the role.
     * @param sender The address that granted the role.
     */
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @notice Emitted when a `role` is revoked from an `account`.
     * @param role The `bytes32` identifier of the role.
     * @param account The address whose role was revoked.
     * @param sender The address that revoked the role.
     */
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @notice Emitted when the admin role for a `role` is changed.
     * @param role The `bytes32` identifier of the role whose admin was changed.
     * @param previousAdminRole The `bytes32` identifier of the previous admin role.
     * @param newAdminRole The `bytes32` identifier of the new admin role.
     */
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /**
     * @notice Checks if an `account` has been granted a `role`.
     * @param role The `bytes32` identifier of the role.
     * @param account The address to check.
     * @return A boolean indicating whether the account has the role.
     */
    function hasRole(bytes32 role, address account) external view returns (bool);

    /**
     * @notice Returns the admin role that controls a given `role`.
     * @param role The `bytes32` identifier of the role to query.
     * @return The `bytes32` identifier of the admin role.
     */
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    /**
     * @notice Grants a `role` to an `account`.
     * @dev The caller must have the admin role for the specified `role`.
     * @param role The `bytes32` identifier of the role to grant.
     * @param account The address to grant the role to.
     */
    function grantRole(bytes32 role, address account) external;

    /**
     * @notice Revokes a `role` from an `account`.
     * @dev The caller must have the admin role for the specified `role`.
     * @param role The `bytes32` identifier of the role to revoke.
     * @param account The address to revoke the role from.
     */
    function revokeRole(bytes32 role, address account) external;

    /**
     * @notice Allows the caller to renounce a `role` they hold.
     * @param role The `bytes32` identifier of the role to renounce.
     */
    function renounceRole(bytes32 role) external;

    /**
     * @notice Returns the address of a member of a role by their index.
     * @param role The `bytes32` identifier of the role.
     * @param index The index of the member in the role's member list.
     * @return The address of the member.
     */
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);

    /**
     * @notice Returns the number of accounts that have been granted a `role`.
     * @param role The `bytes32` identifier of the role.
     * @return The number of members in the role.
     */
    function getRoleMemberCount(bytes32 role) external view returns (uint256);

    /**
     * @notice Returns a paginated list of members for a given role.
     * @param role The `bytes32` identifier of the role.
     * @param offset The starting index for pagination.
     * @param limit The maximum number of members to return.
     * @return page A memory array of member addresses.
     * @return totalMembers The total number of members in the role.
     */
    function getRoleMembersPaginated(bytes32 role, uint256 offset, uint256 limit) external view returns (address[] memory page, uint256 totalMembers);
}
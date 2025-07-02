// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title AccessControlStorage
 * @author Rewa
 * @notice Defines the storage layout for the AccessControl contract.
 * @dev This contract is not meant to be deployed. It is inherited by AccessControl to separate
 * storage variables from logic, which can help in managing upgrades. This pattern follows
 * OpenZeppelin's recommendations for upgradeable contracts.
 */
contract AccessControlStorage {
    /**
     * @dev A mapping from a role's `bytes32` identifier to another mapping that tracks
     * whether an account address has that role. Returns `true` if the account has the role.
     *
     * `_roles[role][account]`
     */
    mapping(bytes32 => mapping(address => bool)) internal _roles;

    /**
     * @dev A mapping from a role's `bytes32` identifier to the `bytes32` identifier of its
     * admin role. This defines the hierarchy for role management.
     *
     * `_roleAdmins[role]`
     */
    mapping(bytes32 => bytes32) internal _roleAdmins;

    /**
     * @dev A mapping from a role's `bytes32` identifier to an array of addresses that
     * currently hold that role. This allows for enumeration of role members.
     *
     * `_activeRoleMembers[role]`
     */
    mapping(bytes32 => address[]) internal _activeRoleMembers;

    /**
     * @dev A mapping from a role's `bytes32` identifier to another mapping that tracks
     * an account's index within the `_activeRoleMembers` array for that role.
     * This enables O(1) removal of a member from the array.
     *
     * `_memberIndices[role][account]`
     */
    mapping(bytes32 => mapping(address => uint256)) internal _memberIndices;
    
    /**
     * @dev Reserved storage space to allow for future upgrades without storage collisions.
     * This is a best practice for upgradeable contracts.
     */
    uint256[49] internal __gap;
}
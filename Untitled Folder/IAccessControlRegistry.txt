// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IAccessControlRegistry Interface
 * @notice Defines a combined interface for access control and a simple contract registry.
 * @dev This interface is a conceptual combination and is not used directly by the provided contracts,
 * which separate these concerns into AccessControl.sol and ContractRegistry.sol for better modularity.
 */
interface IAccessControlRegistry {
    /**
     * @notice Emitted when a role is granted to an account.
     * @param role The `bytes32` identifier of the role.
     * @param account The address of the account being granted the role.
     * @param sender The address that granted the role.
     */
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @notice Emitted when a role is revoked from an account.
     * @param role The `bytes32` identifier of the role.
     * @param account The address of the account whose role is being revoked.
     * @param sender The address that revoked the role.
     */
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @notice Emitted when the admin role for a given role is changed.
     * @param role The `bytes32` identifier of the role whose admin is being changed.
     * @param previousAdminRole The `bytes32` identifier of the previous admin role.
     * @param newAdminRole The `bytes32` identifier of the new admin role.
     */
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /**
     * @notice Emitted when a new contract is registered.
     * @param contractAddress The address of the registered contract.
     * @param registrar The address that performed the registration.
     */
    event ContractRegistered(address indexed contractAddress, address indexed registrar);

    /**
     * @notice Emitted when a contract is unregistered.
     * @param contractAddress The address of the unregistered contract.
     * @param registrar The address that performed the unregistration.
     */
    event ContractUnregistered(address indexed contractAddress, address indexed registrar);

    /**
     * @notice Checks if an account has a specific role.
     * @param role The role to check for.
     * @param account The account to check.
     * @return True if the account has the role, false otherwise.
     */
    function hasRole(bytes32 role, address account) external view returns (bool);

    /**
     * @notice Gets the admin role for a specific role.
     * @param role The role to query.
     * @return The `bytes32` identifier of the admin role.
     */
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    /**
     * @notice Grants a role to an account.
     * @param role The role to grant.
     * @param account The account to receive the role.
     */
    function grantRole(bytes32 role, address account) external;

    /**
     * @notice Revokes a role from an account.
     * @param role The role to revoke.
     * @param account The account to revoke the role from.
     */
    function revokeRole(bytes32 role, address account) external;

    /**
     * @notice Allows an account to renounce a role it holds.
     * @param role The role to renounce.
     */
    function renounceRole(bytes32 role) external;

    /**
     * @notice Gets the address of a member of a role by its index.
     * @param role The role to query.
     * @param index The index of the member.
     * @return The address of the role member.
     */
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);

    /**
     * @notice Gets the number of members in a role.
     * @param role The role to query.
     * @return The count of members.
     */
    function getRoleMemberCount(bytes32 role) external view returns (uint256);

    /**
     * @notice Registers a contract address.
     * @param contractAddress The address to register.
     * @return success True if the operation was successful.
     */
    function registerContract(address contractAddress) external returns (bool success);

    /**
     * @notice Unregisters a contract address.
     * @param contractAddress The address to unregister.
     * @return success True if the operation was successful.
     */
    function unregisterContract(address contractAddress) external returns (bool success);

    /**
     * @notice Checks if a contract address is registered.
     * @param contractAddress The address to check.
     * @return True if the contract is registered.
     */
    function isContractRegistered(address contractAddress) external view returns (bool);

    /**
     * @notice Gets a list of all registered contract addresses.
     * @return An array of addresses.
     */
    function getRegisteredContracts() external view returns (address[] memory);

    /**
     * @notice Sets the admin role for a given role.
     * @param role The role to be administered.
     * @param adminRole The new admin role.
     */
    function setRoleAdmin(bytes32 role, bytes32 adminRole) external;
}
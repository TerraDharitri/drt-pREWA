// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IProxy Interface
 * @notice Defines a standard interface for a Transparent Upgradeable Proxy.
 * @dev This interface provides functions to manage the proxy's implementation and admin,
 * consistent with the EIP-1967 standard. It is used internally for type-safe interactions
 * with proxy contracts managed by the `ProxyAdmin`.
 */
interface IProxy {
    /**
     * @notice Returns the address of the current implementation contract.
     * @dev This function should be restricted to the proxy's admin.
     * @return The logic contract address.
     */
    function implementation() external view returns (address);

    /**
     * @notice Returns the address of the current admin of the proxy.
     * @dev This function should be restricted to the proxy's admin.
     * @return The admin address.
     */
    function admin() external view returns (address);

    /**
     * @notice Changes the admin of the proxy.
     * @dev This function should be restricted to the current admin.
     * @param newAdmin The address of the new admin.
     */
    function changeAdmin(address newAdmin) external;

    /**
     * @notice Upgrades the proxy to a new implementation contract.
     * @dev This function should be restricted to the proxy's admin.
     * @param newImplementation The address of the new implementation contract.
     */
    function upgradeTo(address newImplementation) external;

    /**
     * @notice Upgrades the proxy to a new implementation contract and calls a function on it.
     * @dev This is used to run an initializer function on the new implementation.
     * This function should be restricted to the proxy's admin.
     * @param newImplementation The address of the new implementation contract.
     * @param data The calldata to be executed in the context of the new implementation.
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}
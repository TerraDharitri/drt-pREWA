// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "./interfaces/IProxy.sol";

/**
 * @title TransparentProxy
 * @author Rewa
 * @notice A custom Transparent Upgradeable Proxy that also implements the local `IProxy` interface.
 * @dev This contract inherits from OpenZeppelin's `TransparentUpgradeableProxy` and adds view functions
 * to query the implementation and admin addresses, gated by an `onlyAdmin` modifier for consistency
 * with the upgrade functions. It is intended to be deployed by factories like `VestingFactory`.
 */
contract TransparentProxy is TransparentUpgradeableProxy, IProxy {
    /**
     * @notice Initializes the proxy with a logic contract, an admin, and optional initialization data.
     * @dev The constructor ensures that the provided logic address is a contract to prevent
     * deploying a proxy that points to a non-executable address.
     * @param _logic The address of the initial implementation contract.
     * @param adminAddress The address of the admin (e.g., a ProxyAdmin contract).
     * @param _data The data to be passed to the implementation's initializer, if any.
     */
    constructor(
        address _logic,
        address adminAddress,
        bytes memory _data
    ) TransparentUpgradeableProxy(_logic, adminAddress, _data) {
        require(_logic != address(0), "TransparentProxy: logic cannot be zero address");
        require(adminAddress != address(0), "TransparentProxy: admin cannot be zero address");
        
        uint256 size;
        assembly {
            size := extcodesize(_logic)
        }
        require(size > 0, "TransparentProxy: logic is not a contract");
    }

    /**
     * @dev Modifier to restrict functions to be called only by the proxy's admin.
     */
    modifier onlyAdmin() {
        require(msg.sender == _getAdmin(), "TransparentProxy: caller is not admin");
        _;
    }

    /**
     * @inheritdoc IProxy
     */
    function implementation() external view override onlyAdmin returns (address) {
        return _implementation();
    }

    /**
     * @inheritdoc IProxy
     */
    function admin() external view override onlyAdmin returns (address) {
        return _getAdmin();
    }

    /**
     * @inheritdoc IProxy
     */
    function changeAdmin(address newAdmin) external override onlyAdmin {
        require(newAdmin != address(0), "TransparentProxy: new admin cannot be zero address");
        _changeAdmin(newAdmin);
    }

    /**
     * @inheritdoc IProxy
     */
    function upgradeTo(address newImplementation) external override onlyAdmin {
        require(newImplementation != address(0), "TransparentProxy: new implementation cannot be zero address");
        
        uint256 size;
        assembly {
            size := extcodesize(newImplementation)
        }
        require(size > 0, "TransparentProxy: implementation is not a contract");
        
        _upgradeToAndCall(newImplementation, bytes(""), false);
    }

    /**
     * @inheritdoc IProxy
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable override onlyAdmin {
        require(newImplementation != address(0), "TransparentProxy: new implementation cannot be zero address");
        require(data.length > 0, "TransparentProxy: call data cannot be empty");
        
        uint256 size;
        assembly {
            size := extcodesize(newImplementation)
        }
        require(size > 0, "TransparentProxy: implementation is not a contract");
        
        _upgradeToAndCall(newImplementation, data, true);
    }

    /**
     * @notice Returns the EIP-1967 storage slot for the admin address.
     * @return The bytes32 storage slot identifier.
     */
    function getAdminSlot() external pure returns (bytes32) {
        return 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    }

    /**
     * @notice Returns the EIP-1967 storage slot for the implementation address.
     * @return The bytes32 storage slot identifier.
     */
    function getImplementationSlot() external pure returns (bytes32) {
        return 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    }
}
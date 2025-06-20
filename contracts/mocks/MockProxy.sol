// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../proxy/interfaces/IProxy.sol";

contract MockProxy is IProxy {
    address private _mockImplementation;
    address private _mockAdmin;

    event Upgraded(address indexed implementation);
    event AdminChanged(address previousAdmin, address newAdmin);
    event MockUpgradeToAndCallCalled(address newImplementation, bytes data, uint256 value);

    constructor(address initialImplementation, address initialAdmin) {
        _mockImplementation = initialImplementation;
        _mockAdmin = initialAdmin;
        emit AdminChanged(address(0), initialAdmin);
        emit Upgraded(initialImplementation);
    }

    function implementation() external view override returns (address) {
        return _mockImplementation;
    }

    function admin() external view override returns (address) {
        return _mockAdmin;
    }

    function changeAdmin(address newAdmin) external override {
        require(msg.sender == _mockAdmin, "MockProxy: Caller is not admin");
        require(newAdmin != address(0), "MockProxy: New admin cannot be zero");
        address oldAdmin = _mockAdmin;
        _mockAdmin = newAdmin;
        emit AdminChanged(oldAdmin, newAdmin);
    }

    function upgradeTo(address newImplementation) external override {
        require(msg.sender == _mockAdmin, "MockProxy: Caller is not admin");
        require(newImplementation != address(0), "MockProxy: New implementation cannot be zero");
        _mockImplementation = newImplementation;
        emit Upgraded(newImplementation);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) external payable override {
        require(msg.sender == _mockAdmin, "MockProxy: Caller is not admin");
        require(newImplementation != address(0), "MockProxy: New implementation cannot be zero");
        _mockImplementation = newImplementation;
        emit Upgraded(newImplementation);
        emit MockUpgradeToAndCallCalled(newImplementation, data, msg.value);
        (bool success, ) = newImplementation.delegatecall(data);
        require(success, "MockProxy: delegatecall failed");
    }

    fallback() external payable {
        address impl = _mockImplementation;
        require(impl != address(0), "MockProxy: No implementation set");
        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())
            let result := delegatecall(gas(), impl, ptr, calldatasize(), 0, 0)
            let size := returndatasize()
            returndatacopy(ptr, 0, size)
            switch result
            case 0 {
                revert(ptr, size)
            }
            default {
                return(ptr, size)
            }
        }
    }

    receive() external payable {}
}
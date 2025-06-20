// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../contracts/proxy/TransparentProxy.sol";
import "../contracts/mocks/MockERC20.sol";

// Mock implementation contract for testing
contract MockImplementationV1 {
    uint256 public value;
    bool public initialized;
    
    function initialize(uint256 _value) external {
        require(!initialized, "Already initialized");
        value = _value;
        initialized = true;
    }
    
    function setValue(uint256 _value) external {
        value = _value;
    }
    
    function getValue() external view returns (uint256) {
        return value;
    }
    
    function version() external pure returns (string memory) {
        return "v1";
    }
}

// Second implementation for upgrade testing
contract MockImplementationV2 {
    uint256 public value;
    bool public initialized;
    uint256 public newValue;
    
    function initialize(uint256 _value) external {
        require(!initialized, "Already initialized");
        value = _value;
        initialized = true;
    }
    
    function setValue(uint256 _value) external {
        value = _value;
    }
    
    function getValue() external view returns (uint256) {
        return value;
    }
    
    function setNewValue(uint256 _newValue) external {
        newValue = _newValue;
    }
    
    function version() external pure returns (string memory) {
        return "v2";
    }
    
    function initializeV2(uint256 _newValue) external {
        newValue = _newValue;
    }
}

contract TransparentProxyCoverageTest is Test {
    TransparentProxy proxy;
    MockImplementationV1 implementationV1;
    MockImplementationV2 implementationV2;
    
    address admin;
    address user;
    address newAdmin;
    
    function setUp() public {
        admin = address(0x1001);
        user = address(0x1002);
        newAdmin = address(0x1003);
        
        // Deploy implementations
        implementationV1 = new MockImplementationV1();
        implementationV2 = new MockImplementationV2();
        
        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(
            MockImplementationV1.initialize.selector,
            42
        );
        
        proxy = new TransparentProxy(
            address(implementationV1),
            admin,
            initData
        );
    }
    
    // Test constructor success
    function test_Constructor_Success() public {
        bytes memory initData = abi.encodeWithSelector(
            MockImplementationV1.initialize.selector,
            100
        );
        
        TransparentProxy newProxy = new TransparentProxy(
            address(implementationV1),
            admin,
            initData
        );
        
        // Verify proxy was created successfully
        assertNotEq(address(newProxy), address(0));
    }
    
    function test_Constructor_Success_EmptyData() public {
        TransparentProxy newProxy = new TransparentProxy(
            address(implementationV1),
            admin,
            ""
        );
        
        assertNotEq(address(newProxy), address(0));
    }
    
    // Test constructor reverts
    function test_Constructor_Revert_ZeroLogic() public {
        vm.expectRevert("ERC1967: new implementation is not a contract");
        new TransparentProxy(address(0), admin, "");
    }
    
    function test_Constructor_Revert_ZeroAdmin() public {
        vm.expectRevert("ERC1967: new admin is the zero address");
        new TransparentProxy(address(implementationV1), address(0), "");
    }
    
    function test_Constructor_Revert_LogicNotContract() public {
        vm.expectRevert("ERC1967: new implementation is not a contract");
        new TransparentProxy(address(0x1234), admin, ""); // EOA address
    }
    
    // Test onlyAdmin modifier
    function test_OnlyAdmin_Implementation_Success() public {
        vm.prank(admin);
        address impl = proxy.implementation();
        assertEq(impl, address(implementationV1));
    }
    
    function test_OnlyAdmin_Implementation_Revert_NotAdmin() public {
        vm.prank(user);
        vm.expectRevert("TransparentProxy: caller is not admin");
        proxy.implementation();
    }
    
    function test_OnlyAdmin_Admin_Success() public {
        vm.prank(admin);
        address proxyAdmin = proxy.admin();
        assertEq(proxyAdmin, admin);
    }
    
    function test_OnlyAdmin_Admin_Revert_NotAdmin() public {
        vm.prank(user);
        vm.expectRevert("TransparentProxy: caller is not admin");
        proxy.admin();
    }
    
    // Test changeAdmin function
    function test_ChangeAdmin_Success() public {
        vm.prank(admin);
        proxy.changeAdmin(newAdmin);
        
        // Verify admin changed
        vm.prank(newAdmin);
        address currentAdmin = proxy.admin();
        assertEq(currentAdmin, newAdmin);
    }
    
    function test_ChangeAdmin_Revert_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("TransparentProxy: new admin cannot be zero address");
        proxy.changeAdmin(address(0));
    }
    
    function test_ChangeAdmin_Revert_NotAdmin() public {
        vm.prank(user);
        vm.expectRevert("TransparentProxy: caller is not admin");
        proxy.changeAdmin(newAdmin);
    }
    
    // Test upgradeTo function
    function test_UpgradeTo_Success() public {
        vm.prank(admin);
        proxy.upgradeTo(address(implementationV2));
        
        // Verify implementation changed
        vm.prank(admin);
        address currentImpl = proxy.implementation();
        assertEq(currentImpl, address(implementationV2));
    }
    
    function test_UpgradeTo_Revert_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("TransparentProxy: new implementation cannot be zero address");
        proxy.upgradeTo(address(0));
    }
    
    function test_UpgradeTo_Revert_NotContract() public {
        vm.prank(admin);
        vm.expectRevert("TransparentProxy: implementation is not a contract");
        proxy.upgradeTo(address(0x1234)); // EOA address
    }
    
    function test_UpgradeTo_Revert_NotAdmin() public {
        vm.prank(user);
        vm.expectRevert("TransparentProxy: caller is not admin");
        proxy.upgradeTo(address(implementationV2));
    }
    
    // Test upgradeToAndCall function
    function test_UpgradeToAndCall_Success() public {
        bytes memory callData = abi.encodeWithSelector(
            MockImplementationV2.initializeV2.selector,
            999
        );
        
        vm.prank(admin);
        proxy.upgradeToAndCall(address(implementationV2), callData);
        
        // Verify implementation changed
        vm.prank(admin);
        address currentImpl = proxy.implementation();
        assertEq(currentImpl, address(implementationV2));
        
        // Verify the call was executed by checking the proxy's state
        // We need to call through the proxy to check the state
        (bool success, bytes memory result) = address(proxy).call(
            abi.encodeWithSignature("newValue()")
        );
        assertTrue(success);
        uint256 newValue = abi.decode(result, (uint256));
        assertEq(newValue, 999);
    }
    
    function test_UpgradeToAndCall_Revert_ZeroAddress() public {
        bytes memory callData = abi.encodeWithSelector(
            MockImplementationV2.initializeV2.selector,
            999
        );
        
        vm.prank(admin);
        vm.expectRevert("TransparentProxy: new implementation cannot be zero address");
        proxy.upgradeToAndCall(address(0), callData);
    }
    
    function test_UpgradeToAndCall_Revert_EmptyData() public {
        vm.prank(admin);
        vm.expectRevert("TransparentProxy: call data cannot be empty");
        proxy.upgradeToAndCall(address(implementationV2), "");
    }
    
    function test_UpgradeToAndCall_Revert_NotContract() public {
        bytes memory callData = abi.encodeWithSelector(
            MockImplementationV2.initializeV2.selector,
            999
        );
        
        vm.prank(admin);
        vm.expectRevert("TransparentProxy: implementation is not a contract");
        proxy.upgradeToAndCall(address(0x1234), callData); // EOA address
    }
    
    function test_UpgradeToAndCall_Revert_NotAdmin() public {
        bytes memory callData = abi.encodeWithSelector(
            MockImplementationV2.initializeV2.selector,
            999
        );
        
        vm.prank(user);
        vm.expectRevert("TransparentProxy: caller is not admin");
        proxy.upgradeToAndCall(address(implementationV2), callData);
    }
    
    // Test storage slot functions
    function test_GetAdminSlot_Success() public {
        bytes32 expectedSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        bytes32 actualSlot = proxy.getAdminSlot();
        assertEq(actualSlot, expectedSlot);
    }
    
    function test_GetImplementationSlot_Success() public {
        bytes32 expectedSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 actualSlot = proxy.getImplementationSlot();
        assertEq(actualSlot, expectedSlot);
    }
    
    // Test proxy functionality (delegatecall behavior)
    function test_ProxyDelegatecall_Success() public {
        // Call through proxy to set value
        (bool success,) = address(proxy).call(
            abi.encodeWithSelector(MockImplementationV1.setValue.selector, 123)
        );
        assertTrue(success);
        
        // Verify value was set
        (bool success2, bytes memory result) = address(proxy).call(
            abi.encodeWithSelector(MockImplementationV1.getValue.selector)
        );
        assertTrue(success2);
        uint256 value = abi.decode(result, (uint256));
        assertEq(value, 123);
    }
    
    function test_ProxyDelegatecall_AfterUpgrade() public {
        // Upgrade to V2
        vm.prank(admin);
        proxy.upgradeTo(address(implementationV2));
        
        // Call new function from V2
        (bool success,) = address(proxy).call(
            abi.encodeWithSelector(MockImplementationV2.setNewValue.selector, 456)
        );
        assertTrue(success);
        
        // Verify new value was set
        (bool success2, bytes memory result) = address(proxy).call(
            abi.encodeWithSignature("newValue()")
        );
        assertTrue(success2);
        uint256 newValue = abi.decode(result, (uint256));
        assertEq(newValue, 456);
        
        // Verify old state is preserved
        (bool success3, bytes memory result2) = address(proxy).call(
            abi.encodeWithSelector(MockImplementationV2.getValue.selector)
        );
        assertTrue(success3);
        uint256 oldValue = abi.decode(result2, (uint256));
        assertEq(oldValue, 42); // From initialization
    }
    
    // Test edge cases
    function test_MultipleAdminChanges() public {
        address admin2 = address(0x2001);
        address admin3 = address(0x2002);
        
        // Change admin multiple times
        vm.prank(admin);
        proxy.changeAdmin(admin2);
        
        vm.prank(admin2);
        proxy.changeAdmin(admin3);
        
        // Verify final admin
        vm.prank(admin3);
        address currentAdmin = proxy.admin();
        assertEq(currentAdmin, admin3);
        
        // Verify old admins can't access
        vm.prank(admin);
        vm.expectRevert("TransparentProxy: caller is not admin");
        proxy.admin();
        
        vm.prank(admin2);
        vm.expectRevert("TransparentProxy: caller is not admin");
        proxy.admin();
    }
    
    function test_MultipleUpgrades() public {
        // First upgrade
        vm.prank(admin);
        proxy.upgradeTo(address(implementationV2));
        
        // Deploy another implementation
        MockImplementationV1 implementationV3 = new MockImplementationV1();
        
        // Second upgrade
        vm.prank(admin);
        proxy.upgradeTo(address(implementationV3));
        
        // Verify final implementation
        vm.prank(admin);
        address currentImpl = proxy.implementation();
        assertEq(currentImpl, address(implementationV3));
    }
    
    function test_UpgradeToAndCall_WithValue() public {
        // Deploy a payable implementation
        MockImplementationV2 payableImpl = new MockImplementationV2();
        
        bytes memory callData = abi.encodeWithSelector(
            MockImplementationV2.initializeV2.selector,
            777
        );
        
        vm.prank(admin);
        proxy.upgradeToAndCall{value: 0}(address(payableImpl), callData);
        
        // Verify upgrade succeeded
        vm.prank(admin);
        address currentImpl = proxy.implementation();
        assertEq(currentImpl, address(payableImpl));
    }
    
    // Test assembly code coverage
    function test_AssemblyCodeCoverage() public {
        // Test constructor assembly code by deploying with different logic addresses
        MockImplementationV1 impl1 = new MockImplementationV1();
        MockImplementationV1 impl2 = new MockImplementationV1();
        
        // These should succeed (contracts with code)
        new TransparentProxy(address(impl1), admin, "");
        new TransparentProxy(address(impl2), admin, "");
        
        // Test upgradeTo assembly code
        vm.startPrank(admin);
        proxy.upgradeTo(address(impl1));
        proxy.upgradeTo(address(impl2));
        vm.stopPrank();
        
        // Test upgradeToAndCall assembly code
        bytes memory callData = abi.encodeWithSelector(
            MockImplementationV2.initializeV2.selector,
            888
        );
        
        vm.prank(admin);
        proxy.upgradeToAndCall(address(implementationV2), callData);
    }
}
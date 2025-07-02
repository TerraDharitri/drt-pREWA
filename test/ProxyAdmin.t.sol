// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/proxy/ProxyAdmin.sol";
import "../contracts/mocks/MockProxy.sol";
import "../contracts/mocks/MockAccessControl.sol";
import "../contracts/mocks/MockEmergencyController.sol";
import "../contracts/mocks/MockVestingImplementation.sol";
import "../contracts/libraries/Constants.sol";
import "../contracts/libraries/Errors.sol";
import "../contracts/proxy/TransparentProxy.sol";

// A non-payable version of the mock for testing reverts
contract MockVestingImplementationNonPayable is MockVestingImplementation {
    // Override payable functions with non-payable versions
    function initialize(
        address t, address b, uint256 s, uint256 c, uint256 d, bool r, uint256 ta, address o
    ) public override {
        super.initialize(t,b,s,c,d,r,ta,o);
    }
    function initialize(
        address t, address b, uint256 s, uint256 c, uint256 d, bool r, uint256 ta, address o, address ec, address oi
    ) public override {
        super.initialize(t,b,s,c,d,r,ta,o,ec,oi);
    }
}


contract ProxyAdminTest is Test {
    ProxyAdmin proxyAdmin;
    MockAccessControl mockAC;
    MockEmergencyController mockEC;

    address owner;
    address upgrader;
    address nonUpgrader;
    address emergencyControllerAdmin;
    address proxyAdminForAdmin;

    MockVestingImplementation logicV1;
    MockVestingImplementation logicV2;
    MockVestingImplementation logicV3;
    TransparentProxy proxy; 
    
    uint256 constant TIMELOCK = 1 days;

    function setUp() public {
        owner = makeAddr("owner");
        upgrader = makeAddr("upgrader");
        nonUpgrader = makeAddr("nonUpgrader");
        emergencyControllerAdmin = makeAddr("ecAdminPA");
        proxyAdminForAdmin = makeAddr("proxyAdminForAdmin");

        mockAC = new MockAccessControl();
        mockEC = new MockEmergencyController();
        
        vm.prank(owner);
        mockAC.setRole(mockAC.DEFAULT_ADMIN_ROLE(), owner, true);
        vm.prank(owner);
        mockAC.setRoleAdmin(mockAC.UPGRADER_ROLE(), mockAC.DEFAULT_ADMIN_ROLE());
        vm.prank(owner);
        mockAC.setRole(mockAC.UPGRADER_ROLE(), upgrader, true);

        ProxyAdmin logic = new ProxyAdmin();
        TransparentProxy proxyForAdmin = new TransparentProxy(address(logic), proxyAdminForAdmin, "");
        proxyAdmin = ProxyAdmin(address(proxyForAdmin));
        proxyAdmin.initialize(address(mockAC), address(mockEC), TIMELOCK, owner);

        logicV1 = new MockVestingImplementation();
        logicV2 = new MockVestingImplementation();
        logicV3 = new MockVestingImplementation();
        proxy = new TransparentProxy(address(logicV1), address(proxyAdmin), "");
    }

    function test_Initialize_Success() public {
        ProxyAdmin logic = new ProxyAdmin();
        TransparentProxy proxyForAdmin = new TransparentProxy(address(logic), proxyAdminForAdmin, "");
        ProxyAdmin newPA = ProxyAdmin(address(proxyForAdmin));
        newPA.initialize(address(mockAC), address(mockEC), TIMELOCK, owner);
        assertEq(address(newPA.accessControl()), address(mockAC));
        assertEq(address(newPA.emergencyController()), address(mockEC));
        assertEq(newPA.upgradeTimelock(), TIMELOCK);
        assertTrue(newPA.accessControl().hasRole(newPA.accessControl().PROXY_ADMIN_ROLE(), owner));
    }

    function test_Initialize_Reverts() public {
        ProxyAdmin logic = new ProxyAdmin();
        TransparentProxy proxyForAdmin;
        ProxyAdmin newPA;

        proxyForAdmin = new TransparentProxy(address(logic), proxyAdminForAdmin, "");
        newPA = ProxyAdmin(address(proxyForAdmin));
        vm.expectRevert(PA_AccessControlZero.selector);
        newPA.initialize(address(0), address(mockEC), TIMELOCK, owner);
        
        proxyForAdmin = new TransparentProxy(address(logic), proxyAdminForAdmin, "");
        newPA = ProxyAdmin(address(proxyForAdmin));
        vm.expectRevert(PA_EmergencyControllerZero.selector);
        newPA.initialize(address(mockAC), address(0), TIMELOCK, owner);

        proxyForAdmin = new TransparentProxy(address(logic), proxyAdminForAdmin, "");
        newPA = ProxyAdmin(address(proxyForAdmin));
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "initialAdmin_"));
        newPA.initialize(address(mockAC), address(mockEC), TIMELOCK, address(0));

        proxyForAdmin = new TransparentProxy(address(logic), proxyAdminForAdmin, "");
        newPA = ProxyAdmin(address(proxyForAdmin));
        vm.expectRevert(PA_InvalidTimelockDuration.selector);
        newPA.initialize(address(mockAC), address(mockEC), Constants.MIN_TIMELOCK_DURATION - 1, owner);
    }
    
    function test_Constructor_Runs() public {
        new ProxyAdmin();
        assertTrue(true);
    }
    
    function test_GetProxyImplementationAndAdmin_Success() public view {
        assertEq(proxyAdmin.getProxyImplementation(address(proxy)), address(logicV1));
        assertEq(proxyAdmin.getProxyAdmin(address(proxy)), address(proxyAdmin));
    }

    function test_GetProxyImplementationAndAdmin_Revert_ZeroAddress() public {
        vm.expectRevert(PA_ProxyZero.selector);
        proxyAdmin.getProxyImplementation(address(0));
        vm.expectRevert(PA_ProxyZero.selector);
        proxyAdmin.getProxyAdmin(address(0));
    }
    
    function test_GetProxyImplementationAndAdmin_Revert_CallFails() public {
        address nonProxy = makeAddr("nonProxyWithNoCode");
        vm.expectRevert();
        proxyAdmin.getProxyImplementation(nonProxy);
        vm.expectRevert();
        proxyAdmin.getProxyAdmin(nonProxy);
    }

    function test_AddAndRemoveValidImplementation_Success() public {
        vm.startPrank(upgrader);
        assertTrue(proxyAdmin.addValidImplementation(address(logicV2)));
        assertTrue(proxyAdmin.validImplementations(address(logicV2)));
        assertEq(proxyAdmin.getImplementationCount(), 1);

        assertTrue(proxyAdmin.removeValidImplementation(address(logicV2)));
        assertFalse(proxyAdmin.validImplementations(address(logicV2)));
        assertEq(proxyAdmin.getImplementationCount(), 0);
        vm.stopPrank();
    }

    function test_AddValidImplementation_Reverts() public {
        vm.startPrank(upgrader);
        vm.expectRevert(PA_ImplZero.selector);
        proxyAdmin.addValidImplementation(address(0));

        proxyAdmin.addValidImplementation(address(logicV2));
        vm.expectRevert(PA_ImplAlreadyAdded.selector);
        proxyAdmin.addValidImplementation(address(logicV2));
        
        vm.expectRevert(PA_ImplNotAContract.selector);
        proxyAdmin.addValidImplementation(makeAddr("notAContract"));
        vm.stopPrank();
    }

    function test_ProposeUpgrade_Success_NoVerification() public {
        vm.prank(upgrader);
        proxyAdmin.proposeUpgrade(address(proxy), address(logicV2));
        (address impl, uint256 propTime, , , bool verified, ) = proxyAdmin.getUpgradeProposal(address(proxy));
        assertEq(impl, address(logicV2));
        assertTrue(propTime > 0);
        assertFalse(verified);
    }

    function test_ProposeUpgradeAndCall_Success_WithVerification() public {
        vm.startPrank(upgrader);
        proxyAdmin.addValidImplementation(address(logicV2));
        
        bytes memory data = abi.encodeWithSignature("setMockAdmin(address)", address(0x123));
        proxyAdmin.proposeUpgradeAndCall(address(proxy), address(logicV2), data);
        vm.stopPrank();

        (address impl, , , , bool verified, ) = proxyAdmin.getUpgradeProposal(address(proxy));
        assertEq(impl, address(logicV2));
        assertTrue(verified);
        
        (,,bytes memory returnedData,,,) = proxyAdmin.upgradeProposals(address(proxy));
        assertEq(returnedData, data);
    }

    function test_ProposeUpgrade_Reverts() public {
        vm.startPrank(upgrader);
        vm.expectRevert(PA_ProxyZero.selector);
        proxyAdmin.proposeUpgrade(address(0), address(logicV2));
        
        vm.expectRevert(PA_ImplZero.selector);
        proxyAdmin.proposeUpgrade(address(proxy), address(0));

        proxyAdmin.proposeUpgrade(address(proxy), address(logicV2));
        vm.expectRevert(PA_UpgradePropExists.selector);
        proxyAdmin.proposeUpgrade(address(proxy), address(logicV3));
        vm.stopPrank();
    }
    
    function test_ExecuteUpgrade_Success_NoCall() public {
        vm.prank(upgrader);
        proxyAdmin.proposeUpgrade(address(proxy), address(logicV2));
        skip(TIMELOCK + 1);
        
        vm.prank(upgrader);
        vm.expectEmit(true, true, true, true);
        emit ProxyAdmin.UpgradeExecuted(address(proxy), address(logicV2), upgrader);
        proxyAdmin.executeUpgrade(address(proxy));
        assertEq(proxyAdmin.getProxyImplementation(address(proxy)), address(logicV2));
    }
    
    function test_ExecuteUpgrade_Success_WithCall_Payable() public {
        vm.prank(upgrader);
        bytes memory data = abi.encodeWithSignature("setMockAdmin(address)", makeAddr("newMockAdmin"));
        proxyAdmin.proposeUpgradeAndCall(address(proxy), address(logicV2), data);
        skip(TIMELOCK + 1);
        
        vm.prank(upgrader);
        proxyAdmin.executeUpgrade(address(proxy));
        
        MockVestingImplementation proxyAsLogicV2 = MockVestingImplementation(payable(address(proxy)));
        assertEq(proxyAsLogicV2.mockAdmin(), makeAddr("newMockAdmin"));
    }

    function test_ExecuteUpgrade_Revert_ValueToNonPayable() public { 
        MockVestingImplementationNonPayable logicNonPayable = new MockVestingImplementationNonPayable();

        vm.startPrank(upgrader);
        proxyAdmin.addValidImplementation(address(logicNonPayable));
        bytes memory data = abi.encodeWithSignature("setMockAdmin(address)", makeAddr("newMockAdmin"));
        proxyAdmin.proposeUpgradeAndCall(address(proxy), address(logicNonPayable), data);
        skip(TIMELOCK + 1);

        vm.deal(upgrader, 1 ether);
        
        vm.expectRevert();
        proxyAdmin.executeUpgrade{value: 1 ether}(address(proxy)); 
        vm.stopPrank();
    }

    function test_CancelUpgrade_Success() public {
        vm.prank(upgrader);
        proxyAdmin.proposeUpgrade(address(proxy), address(logicV2));
        (address implBefore,,,,,) = proxyAdmin.upgradeProposals(address(proxy));
        assertEq(implBefore, address(logicV2));

        vm.prank(upgrader);
        proxyAdmin.cancelUpgrade(address(proxy));
        (address implAfter,,,,,) = proxyAdmin.upgradeProposals(address(proxy));
        assertEq(implAfter, address(0));
    }
    
    function test_CancelUpgrade_ByOwner_NotProposer_Success() public {
        vm.prank(upgrader);
        proxyAdmin.proposeUpgrade(address(proxy), address(logicV2));

        vm.prank(owner);
        assertTrue(proxyAdmin.cancelUpgrade(address(proxy)));
    }

    function test_CancelUpgrade_Revert_NotAuthorized() public {
        vm.prank(upgrader);
        proxyAdmin.proposeUpgrade(address(proxy), address(logicV2));
        vm.prank(nonUpgrader);
        vm.expectRevert(PA_NotAuthorizedToCancel.selector);
        proxyAdmin.cancelUpgrade(address(proxy));
    }
    
    function test_UpdateTimelock_Success() public {
        vm.prank(owner);
        proxyAdmin.updateTimelock(TIMELOCK + 1 hours);
        assertEq(proxyAdmin.upgradeTimelock(), TIMELOCK + 1 hours);
    }
    
    function test_EmergencyAwareness_Success() public {
        bytes4 op = proxyAdmin.proposeUpgrade.selector;
        assertTrue(proxyAdmin.checkEmergencyStatus(op));
        
        mockEC.setMockSystemPaused(true);
        assertTrue(proxyAdmin.isEmergencyPaused());
        assertFalse(proxyAdmin.checkEmergencyStatus(op));
        
        mockEC.setMockSystemPaused(false);
        mockEC.setMockFunctionRestriction(op, 2);
        mockEC.setMockEmergencyLevel(2);
        assertFalse(proxyAdmin.checkEmergencyStatus(op));
    }
    
    function test_EmergencyShutdown_Success() public {
        vm.prank(address(mockEC));
        assertTrue(proxyAdmin.emergencyShutdown(1));
    }
    
    function test_GetAndSetEC_Success() public {
        assertEq(proxyAdmin.getEmergencyController(), address(mockEC));
        MockEmergencyController newEc = new MockEmergencyController();
        vm.prank(owner);
        proxyAdmin.setEmergencyController(address(newEc));
        assertEq(proxyAdmin.getEmergencyController(), address(newEc));
    }
}
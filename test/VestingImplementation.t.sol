// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/vesting/VestingImplementation.sol";
import "../contracts/vesting/interfaces/IVesting.sol";
import "../contracts/interfaces/IEmergencyAware.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/MockEmergencyController.sol";
import "../contracts/mocks/MockOracleIntegration.sol";
import "../contracts/libraries/Constants.sol";
import "../contracts/libraries/Errors.sol";
import "../contracts/proxy/TransparentProxy.sol";

contract VestingImplementationTest is Test {
    VestingImplementation vestingImpl;
    MockERC20 pREWAToken;
    MockEmergencyController mockEC;
    MockOracleIntegration mockOracle;

    address deployer;       
    address beneficiary;
    address vestingOwner;   
    address user1;
    address user2;
    address owner;
    address proxyAdmin;

    uint256 defaultStartTime;
    uint256 defaultCliffDuration;
    uint256 defaultDuration;
    uint256 defaultTotalAmount;
    bool defaultRevocable;

    function setUp() public {
        deployer = address(this);
        beneficiary = makeAddr("beneficiary");
        vestingOwner = makeAddr("vestingOwner"); 
        user1 = makeAddr("user1"); 
        user2 = makeAddr("user2");
        owner = makeAddr("owner");
        proxyAdmin = makeAddr("proxyAdmin");

        pREWAToken = new MockERC20();
        pREWAToken.mockInitialize("pREWA Token", "PREWA", 18, deployer);

        mockEC = new MockEmergencyController();
        mockOracle = new MockOracleIntegration();

        VestingImplementation logic = new VestingImplementation(); 

        defaultStartTime = block.timestamp + 1 days;
        defaultCliffDuration = 30 days;
        defaultDuration = 365 days;
        defaultTotalAmount = 1000 * 1e18;
        defaultRevocable = true;

        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        vestingImpl = VestingImplementation(payable(address(proxy)));
        vestingImpl.initialize(
            address(pREWAToken),
            beneficiary,
            defaultStartTime,
            defaultCliffDuration,
            defaultDuration,
            defaultRevocable,
            defaultTotalAmount,
            vestingOwner,
            address(mockEC),
            address(mockOracle)
        );

        vm.prank(deployer);
        pREWAToken.mintForTest(address(vestingImpl), defaultTotalAmount);
    }

    function test_Initialize_Success() public {
        VestingImplementation logic = new VestingImplementation();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        VestingImplementation newImpl = VestingImplementation(payable(address(proxy)));
        newImpl.initialize(
            address(pREWAToken), beneficiary, block.timestamp + 1 hours, 0, 30 days, false, 100e18, vestingOwner, address(mockEC), address(mockOracle)
        );
        
        vm.prank(deployer);
        pREWAToken.mintForTest(address(newImpl), 100e18);

        (address ben, uint256 totalAmt,,,,,,) = newImpl.getVestingSchedule();
        assertEq(ben, beneficiary);
        assertEq(totalAmt, 100e18);
        assertEq(newImpl.owner(), vestingOwner);
        assertEq(address(newImpl.emergencyController()), address(mockEC));
        assertEq(address(newImpl.oracleIntegration()), address(mockOracle));
    }

    function test_Initialize_StartTimeZero_UsesBlockTimestamp() public {
        VestingImplementation logic = new VestingImplementation();
        uint256 expectedStartTime = block.timestamp; 

        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        VestingImplementation newImpl = VestingImplementation(payable(address(proxy)));
        newImpl.initialize(
            address(pREWAToken), beneficiary, 0, 0, 30 days, false, 100e18, vestingOwner
        );

        vm.prank(deployer);
        pREWAToken.mintForTest(address(newImpl), 100e18);
        
        (,,uint256 actualStartTime,,,,,) = newImpl.getVestingSchedule(); 
        assertEq(actualStartTime, expectedStartTime);
    }

    function test_Initialize_Revert_TokenZero() public {
        VestingImplementation logic = new VestingImplementation();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        VestingImplementation newImpl = VestingImplementation(payable(address(proxy)));
        vm.expectRevert(Vesting_TokenZero.selector);
        newImpl.initialize(address(0), beneficiary, 0,0,30 days,false,100e18,vestingOwner);
    }

    function test_Initialize_Revert_BeneficiaryZero() public {
        VestingImplementation logic = new VestingImplementation();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        VestingImplementation newImpl = VestingImplementation(payable(address(proxy)));
        vm.expectRevert(Vesting_BeneficiaryZero.selector);
        newImpl.initialize(address(pREWAToken), address(0), 0,0,30 days,false,100e18,vestingOwner);
    }
    
    function test_Initialize_Revert_OwnerZero() public {
        VestingImplementation logic = new VestingImplementation();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        VestingImplementation newImpl = VestingImplementation(payable(address(proxy)));
        vm.expectRevert(Vesting_OwnerZeroV.selector);
        newImpl.initialize(address(pREWAToken), beneficiary, 0,0,30 days,false,100e18,address(0));
    }

    function test_Initialize_Revert_DurationZero() public {
        VestingImplementation logic = new VestingImplementation();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        VestingImplementation newImpl = VestingImplementation(payable(address(proxy)));
        vm.expectRevert(Vesting_DurationZero.selector);
        newImpl.initialize(address(pREWAToken), beneficiary, 0,0,0,false,100e18,vestingOwner);
    }
    
    function test_Initialize_Revert_AmountZero() public {
        VestingImplementation logic = new VestingImplementation();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        VestingImplementation newImpl = VestingImplementation(payable(address(proxy)));
        vm.expectRevert(Vesting_AmountZeroV.selector);
        newImpl.initialize(address(pREWAToken), beneficiary, 0,0,30 days,false,0,vestingOwner);
    }

    function test_Initialize_Revert_CliffTooLong() public {
        VestingImplementation logic = new VestingImplementation();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        VestingImplementation newImpl = VestingImplementation(payable(address(proxy)));
        vm.expectRevert(Vesting_CliffLongerThanDuration.selector);
        newImpl.initialize(address(pREWAToken), beneficiary, 0,31 days,30 days,false,100e18,vestingOwner);
    }

    function test_Initialize_Revert_StartTimeInvalid() public {
        VestingImplementation logic = new VestingImplementation();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        VestingImplementation newImpl = VestingImplementation(payable(address(proxy)));
        
        vm.warp(2 days);
        
        vm.expectRevert(Vesting_StartTimeInvalid.selector);
        uint256 pastTimestamp = block.timestamp - 1 days;
        newImpl.initialize(address(pREWAToken), beneficiary, pastTimestamp, 0, 30 days, false, 100e18, vestingOwner);
    }
    
    function test_Constructor_Runs() public {
        new VestingImplementation();
        assertTrue(true, "Constructor ran");
    }

    function test_Release_Success_AfterCliff_BeforeEnd() public {
        skip(defaultStartTime + defaultCliffDuration + 1 days - block.timestamp); 

        uint256 expectedReleasable = vestingImpl.releasableAmount();
        assertTrue(expectedReleasable > 0, "Expected releasable to be > 0");

        vm.expectEmit(true, false, false, false);
        emit IVesting.TokensReleased(beneficiary, expectedReleasable);

        uint256 released = vestingImpl.release();
        assertEq(released, expectedReleasable);
        assertEq(pREWAToken.balanceOf(beneficiary), expectedReleasable);
        (,,,,,uint256 releasedAmtInternal,,) = vestingImpl.getVestingSchedule(); 
        assertEq(releasedAmtInternal, expectedReleasable);
    }

    function test_Release_Success_AfterFullDuration() public {
        skip(defaultStartTime + defaultDuration + 1 days - block.timestamp); 

        uint256 expectedReleasable = defaultTotalAmount; 

        vm.expectEmit(true, false, false, false);
        emit IVesting.TokensReleased(beneficiary, expectedReleasable);

        uint256 released = vestingImpl.release();
        assertEq(released, expectedReleasable);
        assertEq(pREWAToken.balanceOf(beneficiary), expectedReleasable);
        (,,,,,uint256 releasedAmtInternal,,) = vestingImpl.getVestingSchedule(); 
        assertEq(releasedAmtInternal, expectedReleasable);
    }
    
    function test_Release_Revert_BeforeCliff() public {
        skip(defaultStartTime + (defaultCliffDuration / 2) - block.timestamp); 
        vm.expectRevert(Vesting_NoTokensDue.selector);
        vestingImpl.release();
    }

    function test_Release_Revert_AlreadyRevoked() public {
        vm.prank(vestingOwner);
        vestingImpl.revoke();
        vm.expectRevert(Vesting_AlreadyRevoked.selector);
        vestingImpl.release();
    }

    function test_Release_Revert_WhenEmergencyPaused() public {
        mockEC.setMockSystemPaused(true);
        
        skip(defaultStartTime + defaultCliffDuration + 1 days - block.timestamp);
        vm.expectRevert(SystemInEmergencyMode.selector);
        vestingImpl.release();
        
        mockEC.setMockSystemPaused(false); 
    }

    function test_Revoke_Success() public {
        skip(defaultStartTime + (defaultDuration / 2) - block.timestamp); 

        uint256 vestedAtRevoke = vestingImpl.vestedAmount(block.timestamp);
        uint256 expectedRefund = defaultTotalAmount - vestedAtRevoke;
        
        (,,,,,uint256 releasedBefore,,) = vestingImpl.getVestingSchedule(); 
        uint256 unreleasedButVested = vestedAtRevoke - releasedBefore;

        vm.prank(vestingOwner);
        if (unreleasedButVested > 0) {
            vm.expectEmit(true, false, false, false);
            emit IVesting.TokensReleased(beneficiary, unreleasedButVested);
        }
        vm.expectEmit(true, false, false, false);
        emit IVesting.VestingRevoked(vestingOwner, expectedRefund);

        uint256 refunded = vestingImpl.revoke();
        assertEq(refunded, expectedRefund);

        assertEq(pREWAToken.balanceOf(vestingOwner), expectedRefund);
        assertEq(pREWAToken.balanceOf(beneficiary), unreleasedButVested); 

        (,,,,,uint256 releasedAfter,,bool revokedAfter) = vestingImpl.getVestingSchedule(); 
        assertTrue(revokedAfter);
        assertEq(releasedAfter, defaultTotalAmount, "Released amount should be total amount after revoke");
    }
    
    function test_Revoke_Revert_NotRevocable() public {
        VestingImplementation logic = new VestingImplementation();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        VestingImplementation nonRevocableImpl = VestingImplementation(payable(address(proxy)));
        nonRevocableImpl.initialize(
            address(pREWAToken), beneficiary, block.timestamp + 1, 0, 30 days, false, 100e18, vestingOwner
        );

        vm.prank(deployer);
        pREWAToken.mintForTest(address(nonRevocableImpl), 100e18);

        vm.prank(vestingOwner);
        vm.expectRevert(Vesting_NotRevocable.selector);
        nonRevocableImpl.revoke();
    }
    
    function test_Revoke_Revert_NotOwner() public {
        vm.prank(user1); 
        vm.expectRevert(NotOwner.selector);
        vestingImpl.revoke();
    }

    function test_GetVestingSchedule_ReturnsCorrectData() public view {
        (address ben, uint256 totalAmt, uint256 sTime, uint256 cDur, uint256 dur, uint256 relAmt, bool rev, bool rvkd) =
            vestingImpl.getVestingSchedule();
        assertEq(ben, beneficiary);
        assertEq(totalAmt, defaultTotalAmount);
        assertEq(sTime, defaultStartTime);
        assertEq(cDur, defaultCliffDuration);
        assertEq(dur, defaultDuration);
        assertEq(relAmt, 0);
        assertEq(rev, defaultRevocable);
        assertFalse(rvkd);
    }

    function test_ReleasableAmount_Correctness() public {
        skip(defaultStartTime + (defaultCliffDuration / 2) - block.timestamp);
        assertEq(vestingImpl.releasableAmount(), 0);

        skip(defaultCliffDuration / 2 + 1 days); 
        uint256 expectedVestedMid = vestingImpl.vestedAmount(block.timestamp);
        assertEq(vestingImpl.releasableAmount(), expectedVestedMid);
        
        vestingImpl.release();
        assertEq(vestingImpl.releasableAmount(), 0);

        skip(defaultDuration + 1 days); 
        assertEq(vestingImpl.releasableAmount(), defaultTotalAmount - expectedVestedMid); 
    }

    function test_VestedAmount_Correctness() public view {
        assertEq(vestingImpl.vestedAmount(defaultStartTime), 0);
        assertEq(vestingImpl.vestedAmount(defaultStartTime + defaultCliffDuration - 1), 0);
        
        uint256 midTime = defaultStartTime + defaultDuration / 2;
        uint256 expectedMidVested = (defaultTotalAmount * (midTime - defaultStartTime)) / defaultDuration;
        assertEq(vestingImpl.vestedAmount(midTime), expectedMidVested);

        assertEq(vestingImpl.vestedAmount(defaultStartTime + defaultDuration), defaultTotalAmount);
        assertEq(vestingImpl.vestedAmount(defaultStartTime + defaultDuration + 365 days), defaultTotalAmount);
    }
    
    function test_VestedAmount_ZeroDuration() public {
        VestingImplementation logic = new VestingImplementation();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        VestingImplementation newImpl = VestingImplementation(payable(address(proxy)));

        vm.expectRevert(Vesting_DurationZero.selector);
        newImpl.initialize(
            address(pREWAToken), beneficiary, 0, 0, 0, true, 100e18, vestingOwner
        );
    }

    function test_Getters_ReturnCorrectAddresses() public view {
        assertEq(vestingImpl.owner(), vestingOwner);
        assertEq(vestingImpl.getTokenAddress(), address(pREWAToken));
        assertEq(vestingImpl.getFactoryAddress(), address(this));
    }

    function test_TransferOwnership_Success() public {
        vm.prank(vestingOwner);
        vm.expectEmit(true, true, false, false);
        emit VestingImplementation.OwnershipTransferred(vestingOwner, user1);
        assertTrue(vestingImpl.transferOwnership(user1));
        assertEq(vestingImpl.owner(), user1);
    }
    
    function test_TransferOwnership_Revert_NotOwnerOrZeroAddress() public {
        vm.prank(user1);
        vm.expectRevert(NotOwner.selector);
        vestingImpl.transferOwnership(user2);
        
        vm.prank(vestingOwner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "newOwner"));
        vestingImpl.transferOwnership(address(0));
    }

    function test_EmergencyAware_InterfaceFunctions() public {
        MockEmergencyController newEC = new MockEmergencyController();
        vm.prank(vestingOwner);
        vm.expectEmit(true, true, true, false);
        emit VestingImplementation.EmergencyControllerSet(address(mockEC), address(newEC), vestingOwner);
        assertTrue(vestingImpl.setEmergencyController(address(newEC)));
        assertEq(address(vestingImpl.emergencyController()), address(newEC));
        
        assertEq(vestingImpl.getEmergencyController(), address(newEC));

        vm.prank(address(newEC));
        vm.expectEmit(true, true, false, false);
        emit IEmergencyAware.EmergencyShutdownHandled(Constants.EMERGENCY_LEVEL_CRITICAL, address(newEC));
        assertTrue(vestingImpl.emergencyShutdown(Constants.EMERGENCY_LEVEL_CRITICAL));

        newEC.setMockSystemPaused(true);
        assertTrue(vestingImpl.isEmergencyPaused());
        assertFalse(vestingImpl.checkEmergencyStatus(bytes4(0)));
        newEC.setMockSystemPaused(false);
        assertFalse(vestingImpl.isEmergencyPaused());
        assertTrue(vestingImpl.checkEmergencyStatus(bytes4(0)));
    }
    
    function test_EmergencyShutdown_Revert_NotEC() public {
        vm.prank(owner);
        vm.expectRevert(Vesting_CallerNotEmergencyController.selector);
        vestingImpl.emergencyShutdown(1);
    }
    
    function test_EmergencyShutdown_FromFactory_Success() public {
        VestingImplementation logic = new VestingImplementation();
        address factory = address(this); 
        // FIX: The proxy admin must NOT be the same as the factory/caller to avoid the
        // transparent proxy's admin protection feature.
        address separateAdmin = makeAddr("separateAdminForProxy");
        TransparentProxy proxy = new TransparentProxy(address(logic), separateAdmin, "");
        VestingImplementation newImpl = VestingImplementation(payable(address(proxy)));
        newImpl.initialize(
             address(pREWAToken), beneficiary, block.timestamp, 0, 30 days, true, 1e18, vestingOwner, address(0), address(0)
        );

        vm.prank(factory);
        vm.expectEmit(true, true, false, false);
        emit IEmergencyAware.EmergencyShutdownHandled(1, factory);
        newImpl.emergencyShutdown(1);
    }

    function test_SetOracleIntegration_Success() public {
        MockOracleIntegration newOracle = new MockOracleIntegration();
        vm.prank(vestingOwner);
        vm.expectEmit(true, true, true, false);
        emit VestingImplementation.OracleIntegrationSet(address(mockOracle), address(newOracle), vestingOwner);
        assertTrue(vestingImpl.setOracleIntegration(address(newOracle)));
        assertEq(address(vestingImpl.oracleIntegration()), address(newOracle));
    }

    function test_SetOracleIntegration_ToZero_Success() public {
        vm.prank(vestingOwner);
        vm.expectEmit(true, true, true, false);
        emit VestingImplementation.OracleIntegrationSet(address(mockOracle), address(0), vestingOwner);
        assertTrue(vestingImpl.setOracleIntegration(address(0)));
        assertEq(address(vestingImpl.oracleIntegration()), address(0));
    }
     function test_SetOracleIntegration_Revert_NotOwner() public {
        MockOracleIntegration newOracle = new MockOracleIntegration();
        vm.prank(user1); 
        vm.expectRevert(NotOwner.selector);
        vestingImpl.setOracleIntegration(address(newOracle));
    }
    function test_SetOracleIntegration_Revert_NotAContract() public {
        address nonContract = makeAddr("nonContractOracle");
        vm.prank(vestingOwner);
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "oracleIntegration"));
        vestingImpl.setOracleIntegration(nonContract);
    }
}
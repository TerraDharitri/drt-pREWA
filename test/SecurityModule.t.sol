// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../contracts/security/SecurityModule.sol";
import "../contracts/interfaces/IEmergencyAware.sol";
import "../contracts/controllers/EmergencyController.sol";
import "../contracts/oracle/OracleIntegration.sol";
import "../contracts/mocks/MockEmergencyController.sol";
import "../contracts/mocks/MockOracleIntegration.sol";
import "../contracts/mocks/MockAccessControl.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/libraries/Constants.sol";
import "../contracts/libraries/Errors.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../contracts/proxy/TransparentProxy.sol";

contract SecurityModuleTest is Test {
    SecurityModule sm;
    MockAccessControl mockAC;
    MockEmergencyController mockEC;
    MockOracleIntegration mockOracle;
    MockERC20 mockToken;

    address owner;
    address pauser;
    address parameterAdmin;
    address user1;
    address user2;
    address emergencyControllerAdmin;
    address proxyAdmin;

    function setUp() public {
        vm.warp(10 days); 

        owner = makeAddr("owner");
        pauser = makeAddr("pauser");
        parameterAdmin = makeAddr("parameterAdmin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        emergencyControllerAdmin = makeAddr("ecAdmin");
        proxyAdmin = makeAddr("proxyAdmin");

        mockAC = new MockAccessControl();
        vm.prank(owner);
        mockAC.setRole(mockAC.DEFAULT_ADMIN_ROLE(), owner, true);
        vm.prank(owner);
        mockAC.setRole(mockAC.PAUSER_ROLE(), pauser, true);
        vm.prank(owner);
        mockAC.setRole(mockAC.PARAMETER_ROLE(), parameterAdmin, true);
        
        mockEC = new MockEmergencyController();
        mockOracle = new MockOracleIntegration();

        mockToken = new MockERC20();
        mockToken.mockInitialize("Test Token", "TST", 18, owner);

        SecurityModule logic = new SecurityModule();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        sm = SecurityModule(address(proxy));
        sm.initialize(address(mockAC), address(mockEC), address(mockOracle));
        
        vm.prank(owner);
        mockAC.setRole(mockAC.DEFAULT_ADMIN_ROLE(), address(sm), true);
        vm.prank(owner);
        mockAC.setRole(mockAC.PAUSER_ROLE(), address(sm), true);
        vm.prank(owner);
        mockAC.setRole(mockAC.PARAMETER_ROLE(), address(sm), true);


        vm.prank(owner);
        mockToken.mintForTest(user1, 1_000_000 * 1e18);

        vm.prank(owner);
        mockOracle.setMockTokenPrice(address(mockToken), 1 * 1e18, false, block.timestamp, true, 18);
        vm.prank(owner);
        mockOracle.setStalenessThreshold(1 hours);

        sm.validateTransactionSequence(user1, address(mockToken), 0);
        sm.monitorVolatility(address(mockToken), 0);
    }

    function test_Initialize_Success() public view {
        assertEq(address(sm.accessControl()), address(mockAC));
        assertEq(address(sm.emergencyController()), address(mockEC));
        assertEq(address(sm.oracleIntegration()), address(mockOracle));
        assertEq(sm.flashLoanDetectionThresholdBps(), 1000);
        assertEq(sm.priceDeviationThresholdBps(), 500);
        assertEq(sm.volumeAnomalyThresholdBps(), 3000);
        assertEq(sm.transactionCooldownBlocks(), 1);
        assertFalse(sm.securityPaused());
        assertEq(sm.maxGasForExternalCalls(), 100_000);
    }
    function test_Initialize_Revert_ZeroAddresses() public {
        SecurityModule logic = new SecurityModule();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        SecurityModule newSm = SecurityModule(address(proxy));

        vm.expectRevert(EC_AccessControlZero.selector);
        newSm.initialize(address(0), address(mockEC), address(mockOracle));

        vm.expectRevert(SM_ControllerZero.selector); 
        newSm.initialize(address(mockAC), address(0), address(mockOracle));

        vm.expectRevert(SM_OracleZero.selector); 
        newSm.initialize(address(mockAC), address(mockEC), address(0));
    }
     function test_Initialize_Revert_AlreadyInitialized() public {
        vm.prank(owner);
        vm.expectRevert("Initializable: contract is already initialized");
        sm.initialize(address(mockAC), address(mockEC), address(mockOracle));
    }
    function test_Constructor_Runs() public {
        new SecurityModule();
        assertTrue(true, "Constructor ran");
    }

    function test_SetTokenFlashLoanThreshold_Success() public {
        vm.prank(parameterAdmin);
        vm.expectEmit(true, true, false, true);
        emit SecurityModule.TokenFlashLoanThresholdSet(address(mockToken), 0, 500, parameterAdmin);
        assertTrue(sm.setTokenFlashLoanThreshold(address(mockToken), 500));
        assertEq(sm.tokenFlashLoanThresholdsBps(address(mockToken)), 500);
    }
    function test_SetTokenFlashLoanThreshold_Reverts() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(SM_TokenZero.selector);
        sm.setTokenFlashLoanThreshold(address(0), 500);
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(SM_ThresholdTooHigh.selector, "token flash loan BPS"));
        sm.setTokenFlashLoanThreshold(address(mockToken), Constants.BPS_MAX + 1);
    }

    function test_SetMaxGasForExternalCalls_Success() public {
        vm.prank(owner);
        assertTrue(sm.setMaxGasForExternalCalls(200_000));
        assertEq(sm.maxGasForExternalCalls(), 200_000);
    }
    function test_SetMaxGasForExternalCalls_Revert_InvalidLimit() public {
        vm.prank(owner);
        vm.expectRevert(SM_GasLimitInvalid.selector);
        sm.setMaxGasForExternalCalls(19_999);
        vm.prank(owner);
        vm.expectRevert(SM_GasLimitInvalid.selector);
        sm.setMaxGasForExternalCalls(1_000_001);
    }

    function test_SetTransactionCooldownBlocks_Success() public {
        vm.prank(parameterAdmin);
        assertTrue(sm.setTransactionCooldownBlocks(5));
        assertEq(sm.transactionCooldownBlocks(), 5);
    }
    function test_SetTransactionCooldownBlocks_Revert_TooHigh() public {
        vm.prank(parameterAdmin);
        uint256 tooHighCooldown = 601;
        vm.expectRevert(SM_CooldownTooHigh.selector);
        sm.setTransactionCooldownBlocks(tooHighCooldown);
    }
    function test_SetTransactionCooldownBlocks_SetToZero() public {
        vm.prank(parameterAdmin);
        assertTrue(sm.setTransactionCooldownBlocks(0));
        assertEq(sm.transactionCooldownBlocks(), 0);
    }

    function test_SetSecurityParameters_Success() public {
        vm.prank(parameterAdmin);
        assertTrue(sm.setSecurityParameters(200, 300, 4000));
        assertEq(sm.flashLoanDetectionThresholdBps(), 200);
        assertEq(sm.priceDeviationThresholdBps(), 300);
        assertEq(sm.volumeAnomalyThresholdBps(), 4000);
    }
    function test_SetSecurityParameters_Reverts() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(SM_ThresholdNotPositive.selector, "flash loan BPS"));
        sm.setSecurityParameters(0, 300, 4000);
        
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(SM_ThresholdTooHigh.selector, "flash loan BPS"));
        sm.setSecurityParameters(Constants.BPS_MAX + 1, 300, 4000);
    }

    function test_PauseResumeSecurity_Success() public {
        assertFalse(sm.securityPaused());
        
        vm.prank(pauser);
        vm.expectEmit(true, false, false, true);
        emit SecurityModule.SecurityPaused(pauser, block.timestamp);
        assertTrue(sm.pauseSecurity());
        assertTrue(sm.securityPaused());

        vm.prank(pauser);
        vm.expectEmit(true, false, false, true);
        emit SecurityModule.SecurityResumed(pauser, block.timestamp);
        assertTrue(sm.resumeSecurity());
        assertFalse(sm.securityPaused());
    }
    function test_PauseResumeSecurity_Reverts() public {
        vm.prank(pauser);
        vm.expectRevert(SM_SecurityNotPaused.selector);
        sm.resumeSecurity();

        vm.prank(pauser);
        sm.pauseSecurity();
        vm.prank(pauser);
        vm.expectRevert(SM_SecurityPaused.selector);
        sm.pauseSecurity();
    }

    function test_ValidatePrice_Success() public {
        vm.prank(owner);
        mockOracle.setMockTokenPrice(address(mockToken), 2000e18, false, block.timestamp - 10 minutes, true, 18);
        assertTrue(sm.validatePrice(address(mockToken), 2000e18));
        uint256 validPrice = 2000e18 + (2000e18 * sm.priceDeviationThresholdBps() / Constants.BPS_MAX);
        assertTrue(sm.validatePrice(address(mockToken), validPrice));
    }

    function test_ValidatePrice_Fail_DeviationExceeded() public {
        vm.prank(owner);
        mockOracle.setMockTokenPrice(address(mockToken), 2000e18, false, block.timestamp - 10 minutes, true, 18);
        uint256 priceTooHigh = 2000e18 + (2000e18 * (sm.priceDeviationThresholdBps() + 1) / Constants.BPS_MAX);
        vm.expectEmit(true, true, false, false);
        emit SecurityModule.PriceAnomalyDetected(address(mockToken), 2000e18, priceTooHigh, block.timestamp);
        assertFalse(sm.validatePrice(address(mockToken), priceTooHigh));
    }

    function test_ValidatePrice_Fail_OracleStale() public {
        vm.prank(owner);
        uint256 staleness = mockOracle.getStalenessThreshold();
        uint256 oldTimestamp = block.timestamp - (staleness + 1 seconds);
        mockOracle.setMockTokenPrice(address(mockToken), 2000e18, false, oldTimestamp, true, 18);
        vm.expectEmit(true, true, false, true);
        emit SecurityModule.OracleFailure(address(mockToken), "OracleIntegration.getTokenPrice reverted with unknown error or custom error");
        assertFalse(sm.validatePrice(address(mockToken), 2000e18));
    }

    function test_ValidatePrice_Success_FallbackPrice_HalvedDeviation() public {
        uint256 flashBps = sm.flashLoanDetectionThresholdBps();
        uint256 volBps = sm.volumeAnomalyThresholdBps();
        vm.prank(parameterAdmin); 
        sm.setSecurityParameters(flashBps, 1000, volBps);

        vm.prank(owner);
        mockOracle.setMockTokenPrice(address(mockToken), 2000e18, true, block.timestamp - 10 minutes, true, 18);

        uint256 validDeviation = 2000e18 * (sm.priceDeviationThresholdBps() / 2) / Constants.BPS_MAX;
        assertTrue(sm.validatePrice(address(mockToken), 2000e18 + validDeviation));

        uint256 invalidDeviation = 2000e18 * (sm.priceDeviationThresholdBps() / 2 + 1) / Constants.BPS_MAX;
        vm.expectEmit(true, true, false, false);
        emit SecurityModule.PriceAnomalyDetected(address(mockToken), 2000e18, 2000e18 + invalidDeviation, block.timestamp);
        assertFalse(sm.validatePrice(address(mockToken), 2000e18 + invalidDeviation));
    }

     function test_ValidatePrice_FallbackPrice_OddDeviationBps() public {
        uint256 flashBps = sm.flashLoanDetectionThresholdBps();
        uint256 volBps = sm.volumeAnomalyThresholdBps();
        vm.prank(parameterAdmin); 
        sm.setSecurityParameters(flashBps, 5, volBps);

        vm.prank(owner);
        mockOracle.setMockTokenPrice(address(mockToken), 2000e18, true, block.timestamp - 10 minutes, true, 18);
        
        uint256 validDeviation = 2000e18 * 2 / Constants.BPS_MAX; // 5/2 = 2
        assertTrue(sm.validatePrice(address(mockToken), 2000e18 + validDeviation));
        
        uint256 invalidDeviation = 2000e18 * 3 / Constants.BPS_MAX;
        assertFalse(sm.validatePrice(address(mockToken), 2000e18 + invalidDeviation));
    }

    function test_ValidatePrice_Fail_OracleCallFails_ReturnsFalse() public {
        vm.prank(owner);
        mockOracle.setMockTokenPrice(address(mockToken), 0, false, 0, false, 18);
        vm.expectEmit(true, true, false, true);
        emit SecurityModule.OracleFailure(address(mockToken), "OracleIntegration.getTokenPrice reverted with unknown error or custom error");
        assertFalse(sm.validatePrice(address(mockToken), 2000e18));
    }

    function test_ValidatePrice_Paused_ReturnsTrue() public {
        vm.prank(pauser); sm.pauseSecurity();
        assertTrue(sm.validatePrice(address(mockToken), 100e18));
    }
    function test_ValidatePrice_Reverts() public {
        vm.expectRevert(SM_TokenZero.selector);
        sm.validatePrice(address(0), 1e18);
        vm.expectRevert(SM_PriceNotPositive.selector);
        sm.validatePrice(address(mockToken), 0);
    }
    
    function test_MonitorVolatility_Normal_WithinDay() public {
        uint256 initialUpdateTime = sm.lastVolumeUpdateTime();
        sm.monitorVolatility(address(mockToken), 1000e18);
        assertEq(sm.currentDailyVolume(), 1000e18);
        assertEq(sm.lastVolumeUpdateTime(), initialUpdateTime);

        skip(12 hours);
        sm.monitorVolatility(address(mockToken), 500e18);
        assertEq(sm.currentDailyVolume(), 1500e18);
        assertEq(sm.lastVolumeUpdateTime(), initialUpdateTime);
    }

    function test_MonitorVolatility_Anomaly_ExceedsThreshold() public {
        sm.monitorVolatility(address(mockToken), 1000e18);
        skip(1 days + 1 hours);
        sm.monitorVolatility(address(mockToken), 10e18);

        uint256 prevDayVol = sm.lastDailyVolume();
        uint256 threshold = sm.volumeAnomalyThresholdBps();
        uint256 largeSpike = (prevDayVol * threshold / Constants.BPS_MAX) + prevDayVol + 1;

        assertTrue(sm.monitorVolatility(address(mockToken), largeSpike));
    }

    function test_MonitorVolatility_ResetsDaily() public {
        sm.monitorVolatility(address(mockToken), 1000e18);
        uint256 day1EndVolume = sm.currentDailyVolume();
        uint256 day1UpdateTime = sm.lastVolumeUpdateTime();

        skip(1 days + 1 hours);

        sm.monitorVolatility(address(mockToken), 50e18);
        assertEq(sm.lastDailyVolume(), day1EndVolume);
        assertEq(sm.currentDailyVolume(), 50e18);
        assertTrue(sm.lastVolumeUpdateTime() > day1UpdateTime);
    }

    function test_MonitorVolatility_NoLastDayVolume_NoAnomaly() public {
        sm.monitorVolatility(address(mockToken), 0);
        skip(1 days);
        sm.monitorVolatility(address(mockToken), 0);

        assertTrue(sm.monitorVolatility(address(mockToken), 1_000_000_000e18));
        assertEq(sm.lastDailyVolume(), 0);
    }

    function test_MonitorVolatility_Paused_ReturnsTrue() public {
        vm.prank(pauser); sm.pauseSecurity();
        assertTrue(sm.monitorVolatility(address(mockToken), 1000e18));
    }
    function test_MonitorVolatility_AmountZero_ReturnsTrue() public {
        assertTrue(sm.monitorVolatility(address(mockToken), 0));
    }

    function test_ValidateTransactionSequence_Success_NoFlashLoan() public {
        uint256 prevBlock = sm.lastTransactionBlock(user1);
        uint256 prevCount = sm.transactionCount(user1);
        uint256 prevTs = sm.lastTransactionTimestamp(user1);

        skip(sm.transactionCooldownBlocks() + 1);

        assertTrue(sm.validateTransactionSequence(user1, address(mockToken), 10e18));

        assertTrue(sm.lastTransactionBlock(user1) >= prevBlock);
        assertEq(sm.transactionCount(user1), prevCount + 1);
        assertTrue(sm.lastTransactionTimestamp(user1) > prevTs);
    }

    function test_ValidateTransactionSequence_Fail_IfFlashLoanDetected() public {
        vm.prank(parameterAdmin);
        sm.setTokenFlashLoanThreshold(address(mockToken), 100);
        vm.prank(parameterAdmin);
        sm.setTransactionCooldownBlocks(2);

        sm.validateTransactionSequence(user1, address(mockToken), 0);
        uint256 initialBalance = mockToken.balanceOf(user1);

        skip(1);
        uint256 flashLoanAmountSim = (initialBalance * 500 / 10000) + 1; // 5% increase
        vm.prank(owner);
        mockToken.mintForTest(user1, flashLoanAmountSim);

        vm.expectRevert("Anomalous balance change detected");
        sm.validateTransactionSequence(user1, address(mockToken), 0);
    }

    function test_ValidateTransactionSequence_Paused_ReturnsTrue() public {
        vm.prank(pauser); sm.pauseSecurity();
        assertTrue(sm.validateTransactionSequence(user1, address(mockToken), 1e18));
    }
    function test_ValidateTransactionSequence_Reverts() public {
        vm.expectRevert(SM_AccountZero.selector);
        sm.validateTransactionSequence(address(0), address(mockToken), 1e18);
        vm.expectRevert(SM_TokenZero.selector);
        sm.validateTransactionSequence(user1, address(0), 1e18);
    }

    function test_CheckEmergencyStatus_Logic() public {
        bytes4 op = sm.validatePrice.selector;
        assertTrue(sm.checkEmergencyStatus(op));

        mockEC.setMockSystemPaused(true);
        assertFalse(sm.checkEmergencyStatus(op));
        
        mockEC.setMockSystemPaused(false);
        mockEC.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_CRITICAL);
        assertFalse(sm.checkEmergencyStatus(op));

        mockEC.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_ALERT);
        mockEC.setMockFunctionRestriction(op, Constants.EMERGENCY_LEVEL_ALERT);
        assertFalse(sm.checkEmergencyStatus(op));
    }
    
    function test_CheckEmergencyStatus_ECFails() public {
        bytes4 op = sm.validatePrice.selector;
        mockEC.setShouldRevert(true);
        assertTrue(sm.checkEmergencyStatus(op));
    }

    function test_EmergencyShutdown_Success_SetsLocalPause() public {
        assertFalse(sm.securityPaused());
        vm.prank(address(mockEC));
        vm.expectEmit(true, false, false, true);
        emit SecurityModule.SecurityPaused(address(mockEC), block.timestamp);
        vm.expectEmit(true, true, false, false);
        emit IEmergencyAware.EmergencyShutdownHandled(Constants.EMERGENCY_LEVEL_CRITICAL, address(mockEC));

        assertTrue(sm.emergencyShutdown(Constants.EMERGENCY_LEVEL_CRITICAL));
        assertTrue(sm.securityPaused());
    }
    
    function test_EmergencyShutdown_NoLocalPause_IfNotCritical() public {
        assertFalse(sm.securityPaused());
        vm.prank(address(mockEC));
        assertTrue(sm.emergencyShutdown(Constants.EMERGENCY_LEVEL_ALERT));
        assertFalse(sm.securityPaused());
    }
    
    function test_EmergencyShutdown_Revert_NotEC() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, bytes32(uint256(uint160(address(mockEC))))));
        sm.emergencyShutdown(1);
    }
    
    function test_GetAndSetEmergencyController_Success() public {
        assertEq(sm.getEmergencyController(), address(mockEC));
        MockEmergencyController newEc = new MockEmergencyController();
        vm.prank(owner);
        assertTrue(sm.setEmergencyController(address(newEc)));
        assertEq(sm.getEmergencyController(), address(newEc));
    }
    
    function test_GetAndSetEmergencyController_RevertNotContract() public {
        address nonContract = makeAddr("nonContract");
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "EmergencyController"));
        sm.setEmergencyController(nonContract);
    }

    function test_PreventFrontRunning_Valid() public {
        bytes32 salt = keccak256(abi.encodePacked("mysecret"));
        uint8 opType = 1;
        bytes memory params = abi.encode(uint256(100), address(user2));
        bytes32 commitHash = keccak256(abi.encodePacked(user1, opType, params, salt, block.chainid));
        vm.prank(user1);
        assertTrue(sm.preventFrontRunning(commitHash, opType, params, salt));
    }
    function test_PreventFrontRunning_Invalid_WrongHash() public {
        vm.prank(user1);
        assertFalse(sm.preventFrontRunning(keccak256(abi.encodePacked("wrong")), 1, abi.encode(123), keccak256(abi.encodePacked("s"))));
    }
    function test_PreventFrontRunning_Reverts() public {
        vm.prank(user1);
        vm.expectRevert(SM_CommitHashZero.selector);
        sm.preventFrontRunning(bytes32(0), 1, abi.encode(1), keccak256(abi.encodePacked("s")));

        bytes32 validHash = keccak256(abi.encodePacked("valid"));
        vm.prank(user1);
        vm.expectRevert(SM_ParamsEmpty.selector);
        sm.preventFrontRunning(validHash, 1, bytes(""), keccak256(abi.encodePacked("s")));

        vm.prank(user1);
        assertTrue(sm.preventFrontRunning(keccak256(abi.encodePacked(user1, uint8(0), bytes(""), keccak256(abi.encodePacked("s")), block.chainid)), 0, bytes(""), keccak256(abi.encodePacked("s"))));

        vm.prank(user1);
        vm.expectRevert(SM_SaltZero.selector);
        sm.preventFrontRunning(validHash, 1, abi.encode(1), bytes32(0));
    }
}
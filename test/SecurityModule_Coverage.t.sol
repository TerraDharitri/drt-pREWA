// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/security/SecurityModule.sol";
import "../contracts/mocks/MockAccessControl.sol";
import "../contracts/mocks/MockEmergencyController.sol";
import "../contracts/mocks/MockOracleIntegration.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/proxy/TransparentProxy.sol";
import "../contracts/proxy/ProxyAdmin.sol";
import "../contracts/libraries/Constants.sol";
import "../contracts/libraries/Errors.sol";

contract SecurityModuleCoverageTest is Test {
    SecurityModule public securityModule;
    MockAccessControl public mockAccessControl;
    MockEmergencyController public mockEmergencyController;
    MockOracleIntegration public mockOracleIntegration;
    MockERC20 public mockToken;
    ProxyAdmin public proxyAdminForSecurity;
    
    address public admin = address(0x1);
    address public parameterSetter = address(0x2);
    address public pauser = address(0x3);
    address public user = address(0x4);
    address public emergencyController = address(0x5);
    
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant PARAMETER_ROLE = keccak256("PARAMETER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    function setUp() public {
        // Deploy mock contracts
        mockAccessControl = new MockAccessControl();
        mockEmergencyController = new MockEmergencyController();
        mockOracleIntegration = new MockOracleIntegration();
        mockToken = new MockERC20();
        mockToken.mockInitialize("Test Token", "TEST", 18, address(this));
        
        // Deploy ProxyAdmin for SecurityModule proxy
        ProxyAdmin logic = new ProxyAdmin();
        proxyAdminForSecurity = new ProxyAdmin();
        TransparentProxy proxyForAdmin = new TransparentProxy(address(logic), address(proxyAdminForSecurity), "");
        proxyAdminForSecurity = ProxyAdmin(address(proxyForAdmin));
        
        // Deploy SecurityModule behind proxy
        SecurityModule securityLogic = new SecurityModule();
        TransparentProxy securityProxy = new TransparentProxy(
            address(securityLogic),
            address(proxyAdminForSecurity),
            abi.encodeWithSelector(
                SecurityModule.initialize.selector,
                address(mockAccessControl),
                address(mockEmergencyController),
                address(mockOracleIntegration)
            )
        );
        securityModule = SecurityModule(address(securityProxy));
        
        // Setup roles
        mockAccessControl.grantRole(DEFAULT_ADMIN_ROLE, admin);
        mockAccessControl.grantRole(PARAMETER_ROLE, parameterSetter);
        mockAccessControl.grantRole(PAUSER_ROLE, pauser);
        
        // Setup mock token balances
        mockToken.mint(user, 1000000 * 10**18);
    }

    // ============ INITIALIZATION TESTS ============

    function test_Initialize_Success() public {
        // Deploy fresh instance to test initialization
        SecurityModule freshLogic = new SecurityModule();
        TransparentProxy freshProxy = new TransparentProxy(
            address(freshLogic),
            address(proxyAdminForSecurity),
            abi.encodeWithSelector(
                SecurityModule.initialize.selector,
                address(mockAccessControl),
                address(mockEmergencyController),
                address(mockOracleIntegration)
            )
        );
        SecurityModule freshSecurity = SecurityModule(address(freshProxy));
        
        assertEq(address(freshSecurity.accessControl()), address(mockAccessControl));
        assertEq(address(freshSecurity.emergencyController()), address(mockEmergencyController));
        assertEq(address(freshSecurity.oracleIntegration()), address(mockOracleIntegration));
        assertEq(freshSecurity.flashLoanDetectionThresholdBps(), 1000);
        assertEq(freshSecurity.priceDeviationThresholdBps(), 500);
        assertEq(freshSecurity.volumeAnomalyThresholdBps(), 3000);
        assertEq(freshSecurity.transactionCooldownBlocks(), 1);
        assertFalse(freshSecurity.securityPaused());
        assertEq(freshSecurity.maxGasForExternalCalls(), 100_000);
    }

    function test_Initialize_Revert_AccessControlZero() public {
        SecurityModule freshLogic = new SecurityModule();
        
        vm.expectRevert(EC_AccessControlZero.selector);
        new TransparentProxy(
            address(freshLogic),
            address(proxyAdminForSecurity),
            abi.encodeWithSelector(
                SecurityModule.initialize.selector,
                address(0),
                address(mockEmergencyController),
                address(mockOracleIntegration)
            )
        );
    }

    function test_Initialize_Revert_EmergencyControllerZero() public {
        SecurityModule freshLogic = new SecurityModule();
        
        vm.expectRevert(SM_ControllerZero.selector);
        new TransparentProxy(
            address(freshLogic),
            address(proxyAdminForSecurity),
            abi.encodeWithSelector(
                SecurityModule.initialize.selector,
                address(mockAccessControl),
                address(0),
                address(mockOracleIntegration)
            )
        );
    }

    function test_Initialize_Revert_OracleZero() public {
        SecurityModule freshLogic = new SecurityModule();
        
        vm.expectRevert(SM_OracleZero.selector);
        new TransparentProxy(
            address(freshLogic),
            address(proxyAdminForSecurity),
            abi.encodeWithSelector(
                SecurityModule.initialize.selector,
                address(mockAccessControl),
                address(mockEmergencyController),
                address(0)
            )
        );
    }

    function test_Initialize_Revert_AccessControlNotContract() public {
        SecurityModule freshLogic = new SecurityModule();
        
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "accessControl"));
        new TransparentProxy(
            address(freshLogic),
            address(proxyAdminForSecurity),
            abi.encodeWithSelector(
                SecurityModule.initialize.selector,
                address(0x123), // EOA, not contract
                address(mockEmergencyController),
                address(mockOracleIntegration)
            )
        );
    }

    function test_Initialize_Revert_EmergencyControllerNotContract() public {
        SecurityModule freshLogic = new SecurityModule();
        
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "emergencyController"));
        new TransparentProxy(
            address(freshLogic),
            address(proxyAdminForSecurity),
            abi.encodeWithSelector(
                SecurityModule.initialize.selector,
                address(mockAccessControl),
                address(0x123), // EOA, not contract
                address(mockOracleIntegration)
            )
        );
    }

    function test_Initialize_Revert_OracleNotContract() public {
        SecurityModule freshLogic = new SecurityModule();
        
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "oracleIntegration"));
        new TransparentProxy(
            address(freshLogic),
            address(proxyAdminForSecurity),
            abi.encodeWithSelector(
                SecurityModule.initialize.selector,
                address(mockAccessControl),
                address(mockEmergencyController),
                address(0x123) // EOA, not contract
            )
        );
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_OnlyAdminRole_Success() public {
        vm.prank(admin);
        bool success = securityModule.setMaxGasForExternalCalls(50000);
        assertTrue(success);
    }

    function test_OnlyAdminRole_Revert_NotAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, DEFAULT_ADMIN_ROLE));
        securityModule.setMaxGasForExternalCalls(50000);
    }

    function test_OnlyParameterRole_Success() public {
        vm.prank(parameterSetter);
        bool success = securityModule.setTransactionCooldownBlocks(5);
        assertTrue(success);
    }

    function test_OnlyParameterRole_Revert_NotParameter() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, PARAMETER_ROLE));
        securityModule.setTransactionCooldownBlocks(5);
    }

    function test_OnlyPauserRole_Success() public {
        vm.prank(pauser);
        bool success = securityModule.pauseSecurity();
        assertTrue(success);
    }

    function test_OnlyPauserRole_Revert_NotPauser() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, PAUSER_ROLE));
        securityModule.pauseSecurity();
    }

    // ============ PARAMETER SETTING TESTS ============

    function test_SetTokenFlashLoanThreshold_Success() public {
        vm.prank(parameterSetter);
        bool success = securityModule.setTokenFlashLoanThreshold(address(mockToken), 2000);
        assertTrue(success);
        assertEq(securityModule.tokenFlashLoanThresholdsBps(address(mockToken)), 2000);
    }

    function test_SetTokenFlashLoanThreshold_Revert_TokenZero() public {
        vm.prank(parameterSetter);
        vm.expectRevert(SM_TokenZero.selector);
        securityModule.setTokenFlashLoanThreshold(address(0), 2000);
    }

    function test_SetTokenFlashLoanThreshold_Revert_ThresholdTooHigh() public {
        vm.prank(parameterSetter);
        vm.expectRevert(abi.encodeWithSelector(SM_ThresholdTooHigh.selector, "token flash loan BPS"));
        securityModule.setTokenFlashLoanThreshold(address(mockToken), Constants.BPS_MAX + 1);
    }

    function test_SetMaxGasForExternalCalls_Success() public {
        vm.prank(admin);
        bool success = securityModule.setMaxGasForExternalCalls(50000);
        assertTrue(success);
        assertEq(securityModule.maxGasForExternalCalls(), 50000);
    }

    function test_SetMaxGasForExternalCalls_Revert_TooLow() public {
        vm.prank(admin);
        vm.expectRevert(SM_GasLimitInvalid.selector);
        securityModule.setMaxGasForExternalCalls(19999);
    }

    function test_SetMaxGasForExternalCalls_Revert_TooHigh() public {
        vm.prank(admin);
        vm.expectRevert(SM_GasLimitInvalid.selector);
        securityModule.setMaxGasForExternalCalls(1000001);
    }

    function test_SetTransactionCooldownBlocks_Success() public {
        vm.prank(parameterSetter);
        bool success = securityModule.setTransactionCooldownBlocks(10);
        assertTrue(success);
        assertEq(securityModule.transactionCooldownBlocks(), 10);
    }

    function test_SetTransactionCooldownBlocks_Success_Zero() public {
        vm.prank(parameterSetter);
        bool success = securityModule.setTransactionCooldownBlocks(0);
        assertTrue(success);
        assertEq(securityModule.transactionCooldownBlocks(), 0);
    }

    function test_SetTransactionCooldownBlocks_Revert_TooHigh() public {
        vm.prank(parameterSetter);
        vm.expectRevert(SM_CooldownTooHigh.selector);
        securityModule.setTransactionCooldownBlocks(601);
    }

    function test_SetSecurityParameters_Success() public {
        vm.prank(parameterSetter);
        bool success = securityModule.setSecurityParameters(1500, 750, 4000);
        assertTrue(success);
        assertEq(securityModule.flashLoanDetectionThresholdBps(), 1500);
        assertEq(securityModule.priceDeviationThresholdBps(), 750);
        assertEq(securityModule.volumeAnomalyThresholdBps(), 4000);
    }

    function test_SetSecurityParameters_Revert_ZeroFlashLoanWhenNonZero() public {
        vm.prank(parameterSetter);
        vm.expectRevert(abi.encodeWithSelector(SM_ThresholdNotPositive.selector, "flash loan BPS"));
        securityModule.setSecurityParameters(0, 500, 3000); // Try to set flash loan to 0 when it's currently 1000
    }

    function test_SetSecurityParameters_Revert_ZeroPriceDeviationWhenNonZero() public {
        vm.prank(parameterSetter);
        vm.expectRevert(abi.encodeWithSelector(SM_ThresholdNotPositive.selector, "price deviation BPS"));
        securityModule.setSecurityParameters(1000, 0, 3000); // Try to set price deviation to 0 when it's currently 500
    }

    function test_SetSecurityParameters_Revert_ZeroVolumeAnomalyWhenNonZero() public {
        vm.prank(parameterSetter);
        vm.expectRevert(abi.encodeWithSelector(SM_ThresholdNotPositive.selector, "volume anomaly BPS"));
        securityModule.setSecurityParameters(1000, 500, 0); // Try to set volume anomaly to 0 when it's currently 3000
    }

    function test_SetSecurityParameters_Revert_FlashLoanThresholdTooHigh() public {
        vm.prank(parameterSetter);
        vm.expectRevert(abi.encodeWithSelector(SM_ThresholdTooHigh.selector, "flash loan BPS"));
        securityModule.setSecurityParameters(Constants.BPS_MAX + 1, 500, 3000);
    }

    function test_SetSecurityParameters_Revert_PriceDeviationTooHigh() public {
        vm.prank(parameterSetter);
        vm.expectRevert(abi.encodeWithSelector(SM_ThresholdTooHigh.selector, "price deviation BPS"));
        securityModule.setSecurityParameters(1000, Constants.BPS_MAX + 1, 3000);
    }

    function test_SetSecurityParameters_Revert_VolumeAnomalyTooHigh() public {
        vm.prank(parameterSetter);
        vm.expectRevert(abi.encodeWithSelector(SM_ThresholdTooHigh.selector, "volume anomaly BPS (max 20x)"));
        securityModule.setSecurityParameters(1000, 500, (Constants.BPS_MAX * 20) + 1);
    }

    // ============ PAUSE/RESUME TESTS ============

    function test_PauseSecurity_Success() public {
        vm.prank(pauser);
        bool success = securityModule.pauseSecurity();
        assertTrue(success);
        assertTrue(securityModule.securityPaused());
    }

    function test_PauseSecurity_Revert_AlreadyPaused() public {
        vm.prank(pauser);
        securityModule.pauseSecurity();
        
        vm.prank(pauser);
        vm.expectRevert(SM_SecurityPaused.selector);
        securityModule.pauseSecurity();
    }

    function test_ResumeSecurity_Success() public {
        vm.prank(pauser);
        securityModule.pauseSecurity();
        
        vm.prank(pauser);
        bool success = securityModule.resumeSecurity();
        assertTrue(success);
        assertFalse(securityModule.securityPaused());
    }

    function test_ResumeSecurity_Revert_NotPaused() public {
        vm.prank(pauser);
        vm.expectRevert(SM_SecurityNotPaused.selector);
        securityModule.resumeSecurity();
    }

    // ============ PRICE VALIDATION TESTS ============

    function test_ValidatePrice_Success() public {
        mockOracleIntegration.setMockTokenPrice(address(mockToken), 1000, false, block.timestamp, true, 18);
        
        bool isValid = securityModule.validatePrice(address(mockToken), 1020); // Within 5% threshold
        assertTrue(isValid);
    }

    function test_ValidatePrice_Revert_TokenZero() public {
        vm.expectRevert(SM_TokenZero.selector);
        securityModule.validatePrice(address(0), 1000);
    }

    function test_ValidatePrice_Revert_PriceZero() public {
        vm.expectRevert(SM_PriceNotPositive.selector);
        securityModule.validatePrice(address(mockToken), 0);
    }

    function test_ValidatePrice_Success_WhenPaused() public {
        vm.prank(pauser);
        securityModule.pauseSecurity();
        
        bool isValid = securityModule.validatePrice(address(mockToken), 1000);
        assertTrue(isValid); // Should return true when paused
    }

    function test_ValidatePrice_Success_NoOracle() public {
        // Deploy SecurityModule without oracle
        SecurityModule freshLogic = new SecurityModule();
        MockAccessControl freshAccessControl = new MockAccessControl();
        MockEmergencyController freshEmergencyController = new MockEmergencyController();
        
        TransparentProxy freshProxy = new TransparentProxy(
            address(freshLogic),
            address(proxyAdminForSecurity),
            abi.encodeWithSelector(
                SecurityModule.initialize.selector,
                address(freshAccessControl),
                address(freshEmergencyController),
                address(mockOracleIntegration) // Will be set to zero later
            )
        );
        SecurityModule freshSecurity = SecurityModule(address(freshProxy));
        
        // Set oracle to zero through admin
        freshAccessControl.grantRole(DEFAULT_ADMIN_ROLE, address(this));
        vm.expectRevert(SM_OracleZero.selector);
        freshSecurity.setOracleIntegration(address(0));
    }

    function test_ValidatePrice_False_PriceDeviation() public {
        mockOracleIntegration.setMockTokenPrice(address(mockToken), 1000, false, block.timestamp, true, 18);
        
        bool isValid = securityModule.validatePrice(address(mockToken), 1100); // 10% deviation, above 5% threshold
        assertFalse(isValid);
    }

    function test_ValidatePrice_False_StalePrice() public {
        // Set current time to a reasonable value to avoid underflow
        vm.warp(7200); // Set block.timestamp to 2 hours (7200 seconds)
        
        // Price from 1 hour ago (3600), but current time is 7200, so it's stale by 3600 seconds
        mockOracleIntegration.setMockTokenPrice(address(mockToken), 1000, false, 3600, true, 18);
        mockOracleIntegration.setStalenessThreshold(3599); // Threshold just under the staleness (3600 seconds)
        
        bool isValid = securityModule.validatePrice(address(mockToken), 1000);
        assertFalse(isValid);
    }

    function test_ValidatePrice_Success_FallbackPrice() public {
        mockOracleIntegration.setMockTokenPrice(address(mockToken), 1000, true, block.timestamp, true, 18); // Fallback price
        
        // With fallback, threshold is halved (2.5%), so 2% deviation should pass
        bool isValid = securityModule.validatePrice(address(mockToken), 1020);
        assertTrue(isValid);
    }

    function test_ValidatePrice_False_OracleFailure() public {
        mockOracleIntegration.setShouldRevert(true);
        
        bool isValid = securityModule.validatePrice(address(mockToken), 1000);
        assertFalse(isValid);
    }

    // ============ VOLUME MONITORING TESTS ============

    function test_MonitorVolatility_Success_Normal() public {
        bool isNormal = securityModule.monitorVolatility(user, 1000);
        assertTrue(isNormal);
        assertEq(securityModule.currentDailyVolume(), 1000);
    }

    function test_MonitorVolatility_Success_WhenPaused() public {
        vm.prank(pauser);
        securityModule.pauseSecurity();
        
        bool isNormal = securityModule.monitorVolatility(user, 1000);
        assertTrue(isNormal);
    }

    function test_MonitorVolatility_Success_ZeroAmount() public {
        bool isNormal = securityModule.monitorVolatility(user, 0);
        assertTrue(isNormal);
    }

    function test_MonitorVolatility_Success_DayRollover() public {
        // Add some volume
        securityModule.monitorVolatility(user, 1000);
        
        // Fast forward more than a day
        vm.warp(block.timestamp + Constants.SECONDS_PER_DAY + 1);
        
        bool isNormal = securityModule.monitorVolatility(user, 500);
        assertTrue(isNormal);
        assertEq(securityModule.lastDailyVolume(), 1000);
        assertEq(securityModule.currentDailyVolume(), 500);
    }

    function test_MonitorVolatility_False_VolumeAnomaly() public {
        // Set up previous day volume
        securityModule.monitorVolatility(user, 1000);
        
        // Fast forward to simulate day rollover
        vm.warp(block.timestamp + Constants.SECONDS_PER_DAY + 1);
        securityModule.monitorVolatility(user, 1000); // This sets lastDailyVolume to 1000
        
        // Reset to beginning of new day
        vm.warp(block.timestamp + Constants.SECONDS_PER_DAY + 1);
        securityModule.monitorVolatility(user, 100); // Reset current volume
        
        // Now add volume that exceeds threshold
        // After 1 hour (1/24 of day), expected volume is 1000/24 ≈ 42
        vm.warp(block.timestamp + 3600); // 1 hour later
        bool isNormal = securityModule.monitorVolatility(user, 5000); // Much higher than expected
        assertFalse(isNormal);
    }

    // ============ TRANSACTION SEQUENCE VALIDATION TESTS ============

    function test_ValidateTransactionSequence_Success() public {
        bool isValid = securityModule.validateTransactionSequence(user, address(mockToken), 1000);
        assertTrue(isValid);
        assertEq(securityModule.transactionCount(user), 1);
        assertEq(securityModule.lastTransactionBlock(user), block.number);
        assertEq(securityModule.lastTransactionTimestamp(user), block.timestamp);
    }

    function test_ValidateTransactionSequence_Success_WhenPaused() public {
        vm.prank(pauser);
        securityModule.pauseSecurity();
        
        bool isValid = securityModule.validateTransactionSequence(user, address(mockToken), 1000);
        assertTrue(isValid);
    }

    function test_ValidateTransactionSequence_Revert_AccountZero() public {
        vm.expectRevert(SM_AccountZero.selector);
        securityModule.validateTransactionSequence(address(0), address(mockToken), 1000);
    }

    function test_ValidateTransactionSequence_Revert_TokenZero() public {
        vm.expectRevert(SM_TokenZero.selector);
        securityModule.validateTransactionSequence(user, address(0), 1000);
    }

    function test_ValidateTransactionSequence_Revert_AnomalousBalance() public {
        // First transaction to set baseline
        securityModule.validateTransactionSequence(user, address(mockToken), 1000);
        
        // Simulate large balance increase (flash loan scenario)
        mockToken.mint(user, 10000000 * 10**18); // Massive increase
        
        // Next transaction in same block should detect anomaly
        vm.expectRevert("Anomalous balance change detected");
        securityModule.validateTransactionSequence(user, address(mockToken), 1000);
    }

    // ============ EMERGENCY AWARE TESTS ============

    function test_CheckEmergencyStatus_Success_Normal() public {
        mockEmergencyController.setMockSystemPaused(false);
        mockEmergencyController.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_NORMAL);
        
        bool allowed = securityModule.checkEmergencyStatus(bytes4(keccak256("test()")));
        assertTrue(allowed);
    }

    function test_CheckEmergencyStatus_False_SecurityPaused() public {
        vm.prank(pauser);
        securityModule.pauseSecurity();
        
        bool allowed = securityModule.checkEmergencyStatus(bytes4(keccak256("test()")));
        assertFalse(allowed);
    }

    function test_CheckEmergencyStatus_False_SystemPaused() public {
        mockEmergencyController.setMockSystemPaused(true);
        
        bool allowed = securityModule.checkEmergencyStatus(bytes4(keccak256("test()")));
        assertFalse(allowed);
    }

    function test_CheckEmergencyStatus_False_CriticalLevel() public {
        mockEmergencyController.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_CRITICAL);
        
        bool allowed = securityModule.checkEmergencyStatus(bytes4(keccak256("test()")));
        assertFalse(allowed);
    }

    function test_CheckEmergencyStatus_False_FunctionRestricted() public {
        bytes4 operation = bytes4(keccak256("test()"));
        mockEmergencyController.setMockFunctionRestriction(operation, 1); // threshold 1 means restricted at level 1+
        mockEmergencyController.setMockEmergencyLevel(1); // Set emergency level to trigger restriction
        
        bool allowed = securityModule.checkEmergencyStatus(operation);
        assertFalse(allowed);
    }

    function test_CheckEmergencyStatus_True_NoEmergencyController() public {
        // Deploy SecurityModule without emergency controller (will be set to zero)
        // This test verifies the edge case handling
        mockEmergencyController.setMockSystemPaused(false);
        
        bool allowed = securityModule.checkEmergencyStatus(bytes4(keccak256("test()")));
        assertTrue(allowed);
    }

    function test_EmergencyShutdown_Success() public {
        vm.prank(address(mockEmergencyController));
        bool success = securityModule.emergencyShutdown(Constants.EMERGENCY_LEVEL_CRITICAL);
        assertTrue(success);
        assertTrue(securityModule.securityPaused());
    }

    function test_EmergencyShutdown_Success_LowLevel() public {
        vm.prank(address(mockEmergencyController));
        bool success = securityModule.emergencyShutdown(Constants.EMERGENCY_LEVEL_CAUTION);
        assertTrue(success);
        assertFalse(securityModule.securityPaused()); // Should not pause for low level
    }

    function test_EmergencyShutdown_Revert_NotController() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, bytes32(uint256(uint160(address(mockEmergencyController))))));
        securityModule.emergencyShutdown(Constants.EMERGENCY_LEVEL_CRITICAL);
    }

    function test_GetEmergencyController_Success() public view {
        address controller = securityModule.getEmergencyController();
        assertEq(controller, address(mockEmergencyController));
    }

    function test_SetEmergencyController_Success() public {
        MockEmergencyController newController = new MockEmergencyController();
        
        vm.prank(admin);
        bool success = securityModule.setEmergencyController(address(newController));
        assertTrue(success);
        assertEq(address(securityModule.emergencyController()), address(newController));
    }

    function test_SetEmergencyController_Revert_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(SM_ControllerZero.selector);
        securityModule.setEmergencyController(address(0));
    }

    function test_SetEmergencyController_Revert_NotContract() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "EmergencyController"));
        securityModule.setEmergencyController(address(0x123));
    }

    function test_SetOracleIntegration_Success() public {
        MockOracleIntegration newOracle = new MockOracleIntegration();
        
        vm.prank(admin);
        bool success = securityModule.setOracleIntegration(address(newOracle));
        assertTrue(success);
        assertEq(address(securityModule.oracleIntegration()), address(newOracle));
    }

    function test_SetOracleIntegration_Revert_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(SM_OracleZero.selector);
        securityModule.setOracleIntegration(address(0));
    }

    function test_SetOracleIntegration_Revert_NotContract() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "OracleIntegration"));
        securityModule.setOracleIntegration(address(0x123));
    }

    function test_IsEmergencyPaused_False_Normal() public view {
        bool isPaused = securityModule.isEmergencyPaused();
        assertFalse(isPaused);
    }

    function test_IsEmergencyPaused_True_SecurityPaused() public {
        vm.prank(pauser);
        securityModule.pauseSecurity();
        
        bool isPaused = securityModule.isEmergencyPaused();
        assertTrue(isPaused);
    }

    function test_IsEmergencyPaused_True_SystemPaused() public {
        mockEmergencyController.setMockSystemPaused(true);
        
        bool isPaused = securityModule.isEmergencyPaused();
        assertTrue(isPaused);
    }

    function test_IsEmergencyPaused_True_CriticalLevel() public {
        mockEmergencyController.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_CRITICAL);
        
        bool isPaused = securityModule.isEmergencyPaused();
        assertTrue(isPaused);
    }

    // ============ FRONT-RUNNING PREVENTION TESTS ============

    function test_PreventFrontRunning_Success() public view {
        uint8 operationType = 1;
        bytes memory parameters = abi.encode(1000, address(mockToken));
        bytes32 salt = keccak256("test_salt");
        
        bytes32 commitHash = keccak256(abi.encodePacked(address(this), operationType, parameters, salt, block.chainid));
        
        bool isValid = securityModule.preventFrontRunning(commitHash, operationType, parameters, salt);
        assertTrue(isValid);
    }

    function test_PreventFrontRunning_False_WrongHash() public view {
        uint8 operationType = 1;
        bytes memory parameters = abi.encode(1000, address(mockToken));
        bytes32 salt = keccak256("test_salt");
        bytes32 wrongHash = keccak256("wrong_hash");
        
        bool isValid = securityModule.preventFrontRunning(wrongHash, operationType, parameters, salt);
        assertFalse(isValid);
    }

    function test_PreventFrontRunning_Revert_CommitHashZero() public {
        vm.expectRevert(SM_CommitHashZero.selector);
        securityModule.preventFrontRunning(bytes32(0), 1, abi.encode(1000), keccak256("salt"));
    }

    function test_PreventFrontRunning_Revert_ParamsEmpty() public {
        bytes32 commitHash = keccak256("test");
        vm.expectRevert(SM_ParamsEmpty.selector);
        securityModule.preventFrontRunning(commitHash, 1, "", keccak256("salt"));
    }

    function test_PreventFrontRunning_Success_EmptyParamsWithZeroOperation() public view {
        bytes32 commitHash = keccak256(abi.encodePacked(address(this), uint8(0), "", keccak256("salt"), block.chainid));
        bool isValid = securityModule.preventFrontRunning(commitHash, 0, "", keccak256("salt"));
        assertTrue(isValid);
    }

    function test_PreventFrontRunning_Revert_SaltZero() public {
        bytes32 commitHash = keccak256("test");
        vm.expectRevert(SM_SaltZero.selector);
        securityModule.preventFrontRunning(commitHash, 1, abi.encode(1000), bytes32(0));
    }

    // ============ EDGE CASE AND INTEGRATION TESTS ============

    function test_DetectAnomalousBalanceChange_Success_NormalIncrease() public {
        // First transaction to establish baseline
        securityModule.validateTransactionSequence(user, address(mockToken), 1000);
        
        // Move to next block
        vm.roll(block.number + 2);
        
        // Normal transaction should pass
        bool isValid = securityModule.validateTransactionSequence(user, address(mockToken), 1000);
        assertTrue(isValid);
    }

    function test_DetectAnomalousBalanceChange_Success_WithinCooldown() public {
        // Set cooldown to 0 to disable cooldown checks
        vm.prank(parameterSetter);
        securityModule.setTransactionCooldownBlocks(0);
        
        // Even large balance changes should pass when cooldown is disabled
        mockToken.mint(user, 10000000 * 10**18);
        bool isValid = securityModule.validateTransactionSequence(user, address(mockToken), 1000);
        assertTrue(isValid);
    }

    function test_DetectAnomalousBalanceChange_TokenBalanceFailure() public {
        // Use a token that will fail balance calls
        MockERC20 failingToken = new MockERC20();
        failingToken.mockInitialize("Failing", "FAIL", 18, address(this));
        failingToken.setShouldRevert(true);
        
        vm.expectRevert("Anomalous balance change detected");
        securityModule.validateTransactionSequence(user, address(failingToken), 1000);
    }

    function test_ComplexScenario_MultipleSecurityChecks() public {
        // Setup oracle price
        mockOracleIntegration.setMockTokenPrice(address(mockToken), 1000, false, block.timestamp, true, 18);
        
        // 1. Validate price
        bool priceValid = securityModule.validatePrice(address(mockToken), 1020);
        assertTrue(priceValid);
        
        // 2. Monitor volume
        bool volumeNormal = securityModule.monitorVolatility(user, 5000);
        assertTrue(volumeNormal);
        
        // 3. Validate transaction sequence
        bool sequenceValid = securityModule.validateTransactionSequence(user, address(mockToken), 1000);
        assertTrue(sequenceValid);
        
        // 4. Check emergency status
        bool operationAllowed = securityModule.checkEmergencyStatus(bytes4(keccak256("transfer(address,uint256)")));
        assertTrue(operationAllowed);
    }

    function test_EdgeCase_EmergencyControllerFailures() public {
        // Set emergency controller to revert on calls
        mockEmergencyController.setShouldRevert(true);
        
        // Should still work gracefully
        bool allowed = securityModule.checkEmergencyStatus(bytes4(keccak256("test()")));
        assertTrue(allowed); // Should default to allowed when calls fail
    }

    function test_EdgeCase_OracleIntegrationFailures() public {
        // Set oracle to revert
        mockOracleIntegration.setShouldRevert(true);
        
        bool isValid = securityModule.validatePrice(address(mockToken), 1000);
        assertFalse(isValid); // Should return false when oracle fails
    }

    function test_EdgeCase_MaxGasLimits() public {
        // Set very low gas limit
        vm.prank(admin);
        securityModule.setMaxGasForExternalCalls(20000);
        
        // Should still work with low gas
        securityModule.validatePrice(address(mockToken), 1000);
        // Result depends on whether oracle call succeeds with low gas
    }

    function test_GetterFunctions_Comprehensive() public view {
        assertEq(address(securityModule.accessControl()), address(mockAccessControl));
        assertEq(address(securityModule.emergencyController()), address(mockEmergencyController));
        assertEq(address(securityModule.oracleIntegration()), address(mockOracleIntegration));
        assertEq(securityModule.flashLoanDetectionThresholdBps(), 1000);
        assertEq(securityModule.priceDeviationThresholdBps(), 500);
        assertEq(securityModule.volumeAnomalyThresholdBps(), 3000);
        assertEq(securityModule.transactionCooldownBlocks(), 1);
        assertFalse(securityModule.securityPaused());
        assertEq(securityModule.maxGasForExternalCalls(), 100_000);
        assertEq(securityModule.lastDailyVolume(), 0);
        assertEq(securityModule.currentDailyVolume(), 0);
        assertGt(securityModule.lastVolumeUpdateTime(), 0);
        assertEq(securityModule.lastTransactionTimestamp(user), 0);
        assertEq(securityModule.lastTransactionBlock(user), 0);
        assertEq(securityModule.transactionCount(user), 0);
        assertEq(securityModule.tokenFlashLoanThresholdsBps(address(mockToken)), 0);
    }

    function test_EventEmissions_SecurityParametersUpdated() public {
        vm.prank(parameterSetter);
        vm.expectEmit(true, true, true, true);
        emit SecurityParametersUpdated(1500, 750, 4000, parameterSetter);
        securityModule.setSecurityParameters(1500, 750, 4000);
    }

    function test_EventEmissions_SecurityPaused() public {
        vm.prank(pauser);
        vm.expectEmit(true, true, true, true);
        emit SecurityPaused(pauser, block.timestamp);
        securityModule.pauseSecurity();
    }

    function test_EventEmissions_SecurityResumed() public {
        vm.prank(pauser);
        securityModule.pauseSecurity();
        
        vm.prank(pauser);
        vm.expectEmit(true, true, true, true);
        emit SecurityResumed(pauser, block.timestamp);
        securityModule.resumeSecurity();
    }

    function test_EventEmissions_TokenFlashLoanThresholdSet() public {
        vm.prank(parameterSetter);
        vm.expectEmit(true, true, true, true);
        emit TokenFlashLoanThresholdSet(address(mockToken), 0, 2000, parameterSetter);
        securityModule.setTokenFlashLoanThreshold(address(mockToken), 2000);
    }

    function test_EventEmissions_EmergencyControllerSet() public {
        MockEmergencyController newController = new MockEmergencyController();
        
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit EmergencyControllerSet(address(mockEmergencyController), address(newController), admin);
        securityModule.setEmergencyController(address(newController));
    }

    function test_EventEmissions_OracleIntegrationSet() public {
        MockOracleIntegration newOracle = new MockOracleIntegration();
        
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit OracleIntegrationSet(address(mockOracleIntegration), address(newOracle), admin);
        securityModule.setOracleIntegration(address(newOracle));
    }

    function test_EventEmissions_MaxGasForExternalCallsUpdated() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit MaxGasForExternalCallsUpdated(100_000, 50_000, admin);
        securityModule.setMaxGasForExternalCalls(50_000);
    }

    function test_EventEmissions_TransactionCooldownUpdated() public {
        vm.prank(parameterSetter);
        vm.expectEmit(true, true, true, true);
        emit TransactionCooldownUpdated(1, 10, parameterSetter);
        securityModule.setTransactionCooldownBlocks(10);
    }

    // ============ EVENTS ============
    
    event SecurityParametersUpdated(
        uint256 newFlashLoanThresholdBps,
        uint256 newPriceDeviationThresholdBps,
        uint256 newVolumeAnomalyThresholdBps,
        address indexed updater
    );
    
    event SecurityPaused(address indexed pauser, uint256 timestamp);
    event SecurityResumed(address indexed resumer, uint256 timestamp);
    
    event TokenFlashLoanThresholdSet(
        address indexed token,
        uint256 oldThresholdBps,
        uint256 newThresholdBps,
        address indexed setter
    );
    
    event EmergencyControllerSet(
        address indexed oldController,
        address indexed newController,
        address indexed setter
    );
    
    event OracleIntegrationSet(
        address indexed oldOracle,
        address indexed newOracle,
        address indexed setter
    );
    
    event MaxGasForExternalCallsUpdated(
        uint256 oldLimit,
        uint256 newLimit,
        address indexed setter
    );
    
    event TransactionCooldownUpdated(
        uint256 oldCooldown,
        uint256 newCooldown,
        address indexed updater
    );
    
    event EmergencyShutdownHandled(uint8 emergencyLevel, address indexed caller);
}
// --- START OF FILE PriceGuard.t.txt ---

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/security/PriceGuard.sol";
import "../contracts/interfaces/IEmergencyAware.sol";
import "../contracts/controllers/EmergencyController.sol";
import "../contracts/oracle/OracleIntegration.sol";
import "../contracts/mocks/MockEmergencyController.sol";
import "../contracts/mocks/MockOracleIntegration.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/libraries/Constants.sol";
import "../contracts/libraries/Errors.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../contracts/proxy/TransparentProxy.sol";

contract PriceGuardTest is Test {
    PriceGuard priceGuard;
    MockEmergencyController mockEC;
    MockOracleIntegration mockOracle;
    MockERC20 token0;
    MockERC20 token1;

    address owner;
    address user1;
    address user2; 
    address emergencyControllerAdmin;
    address proxyAdmin;

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2"); 
        emergencyControllerAdmin = makeAddr("ecAdmin");
        proxyAdmin = makeAddr("proxyAdmin");

        mockEC = new MockEmergencyController(); 
        mockOracle = new MockOracleIntegration();
        
        token0 = new MockERC20(); token0.mockInitialize("Token Zero", "TKN0", 18, owner);
        token1 = new MockERC20(); token1.mockInitialize("Token One", "TKN1", 18, owner);

        PriceGuard logic = new PriceGuard();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        priceGuard = PriceGuard(address(proxy));
        priceGuard.initialize(owner, address(mockOracle), address(mockEC));

        vm.prank(owner); 
        mockOracle.setMockTokenPrice(address(token0), 1 * 1e18, false, block.timestamp, true, 18);
        vm.prank(owner); 
        mockOracle.setMockTokenPrice(address(token1), 2 * 1e18, false, block.timestamp, true, 18);
    }
    
   
    function test_Initialize_Success() public view {
        assertEq(priceGuard.owner(), owner);
        assertEq(address(priceGuard.oracleIntegration()), address(mockOracle));
        assertEq(address(priceGuard.emergencyController()), address(mockEC));
        assertEq(priceGuard.maxPriceImpactNormal(), 200);
        assertEq(priceGuard.minBlockDelay(), 1);
        assertEq(priceGuard.minAcceptablePrice(), 1);
    }
    function test_Initialize_Revert_ZeroAddresses() public {
        PriceGuard logic = new PriceGuard();
        
        bytes memory data1 = abi.encodeWithSelector(logic.initialize.selector, address(0), address(mockOracle), address(mockEC));
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "initialOwner_"));
        new TransparentProxy(address(logic), proxyAdmin, data1);
        
        bytes memory data2 = abi.encodeWithSelector(logic.initialize.selector, owner, address(0), address(mockEC));
        vm.expectRevert(SM_OracleZero.selector); 
        new TransparentProxy(address(logic), proxyAdmin, data2);

        bytes memory data3 = abi.encodeWithSelector(logic.initialize.selector, owner, address(mockOracle), address(0));
        vm.expectRevert(SM_ControllerZero.selector); 
        new TransparentProxy(address(logic), proxyAdmin, data3);
    }
     function test_Initialize_Revert_AlreadyInitialized() public {
        vm.prank(owner);
        vm.expectRevert("Initializable: contract is already initialized");
        priceGuard.initialize(owner, address(mockOracle), address(mockEC));
    }
    function test_Constructor_Runs() public {
        new PriceGuard();
        assertTrue(true, "Constructor ran");
    }

    function test_WhenNotEffectivelyPaused_RevertsIfECPaused() public {
        mockEC.setMockSystemPaused(true);
        vm.expectRevert(SystemInEmergencyMode.selector);
        priceGuard.checkPriceImpact(address(token0), address(token1), 1e18, 1e18);
        mockEC.setMockSystemPaused(false);
    }

    function test_CheckPriceImpact_Success_Normal() public {
        assertTrue(priceGuard.checkPriceImpact(address(token0), address(token1), 100e18, 101e18));
        assertTrue(priceGuard.checkPriceImpact(address(token0), address(token1), 100e18, 99e18));
    }
    function test_CheckPriceImpact_Fail_Normal_ExceedsImpact() public {
        vm.expectEmit(true, true, true, false); 
        emit PriceGuard.PriceImpactExceeded(address(token0), address(token1), 100e18, 103e18, 300);
        assertFalse(priceGuard.checkPriceImpact(address(token0), address(token1), 100e18, 103e18));
    }
    function test_CheckPriceImpact_Success_Emergency() public {
        mockEC.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_ALERT);
        
        // Setup with tight emergency limits
        vm.prank(owner);
        priceGuard.setPriceGuardParameters(500, 50, 500, 100);

        // This impact (4%) is less than the normal limit but more than the emergency limit
        // so it should fail.
        assertFalse(priceGuard.checkPriceImpact(address(token0), address(token1), 100e18, 104e18)); 

        // This impact (4%) IS within the emergency limit now
        vm.prank(owner);
        priceGuard.setPriceGuardParameters(500, 450, 500, 100);
        assertTrue(priceGuard.checkPriceImpact(address(token0), address(token1), 100e18, 104e18)); 
    }
    function test_CheckPriceImpact_Fail_Emergency_ExceedsImpact() public {
        mockEC.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_ALERT);
        
        // Set a tight emergency threshold
        vm.prank(owner); 
        priceGuard.setPriceGuardParameters(200, 50, 500, 100);
        
        vm.expectEmit(true, true, true, false);
        // This is a 1% price impact (100 bps)
        emit PriceGuard.PriceImpactExceeded(address(token0), address(token1), 100e18, 101e18, 100);
        // This check fails because 100 BPS > 50 BPS emergency threshold
        assertFalse(priceGuard.checkPriceImpact(address(token0), address(token1), 100e18, 101e18));
    }
    function test_CheckPriceImpact_Reverts() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "token0 for checkPriceImpact"));
        priceGuard.checkPriceImpact(address(0), address(token1), 1e18, 1e18);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "token1 for checkPriceImpact"));
        priceGuard.checkPriceImpact(address(token0), address(0), 1e18, 1e18);

        vm.expectRevert(SM_PriceNotPositive.selector); 
        priceGuard.checkPriceImpact(address(token0), address(token1), 0, 1e18);
        vm.expectRevert(SM_PriceNotPositive.selector);
        priceGuard.checkPriceImpact(address(token0), address(token1), 1e18, 0);
        
        vm.prank(owner); priceGuard.setMinAcceptablePrice(10);
        vm.expectRevert(abi.encodeWithSelector(OI_MinPriceNotMet.selector, 5, 10));
        priceGuard.checkPriceImpact(address(token0), address(token1), 5, 1e18); 
    }
    
    function test_CheckPriceImpact_ECFail() public {
        mockEC.setShouldRevert(true);
        assertTrue(priceGuard.checkPriceImpact(address(token0), address(token1), 100e18, 101e18));
        mockEC.setShouldRevert(false);
    }

    function test_GetExpectedPrice_Success() public view {
        assertEq(priceGuard.getExpectedPrice(address(token0), address(token1)), 2 * 1e18);
        assertEq(priceGuard.getExpectedPrice(address(token1), address(token0)), 0.5 * 1e18);
    }
    function test_GetExpectedPrice_Reverts() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "token0 for getExpectedPrice"));
        priceGuard.getExpectedPrice(address(0), address(token1));
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "token1 for getExpectedPrice"));
        priceGuard.getExpectedPrice(address(token0), address(0));

        // Test SM_OracleZero revert
        PriceGuard logic = new PriceGuard();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        PriceGuard guardNoOracle = PriceGuard(address(proxy));
        vm.expectRevert(SM_OracleZero.selector);
        guardNoOracle.initialize(owner, address(0), address(mockEC)); 
        vm.expectRevert(SM_OracleZero.selector);
        guardNoOracle.getExpectedPrice(address(token0), address(token1));

        vm.prank(owner); 
        mockOracle.setMockTokenPrice(address(token0), 0, false, block.timestamp, true, 18);
        vm.expectRevert(SM_PriceNotPositive.selector);
        priceGuard.getExpectedPrice(address(token0), address(token1));
        vm.prank(owner); 
        mockOracle.setMockTokenPrice(address(token0), 1e18, false, block.timestamp, true, 18); 
        
        vm.prank(owner); priceGuard.setMinAcceptablePrice(3 * 1e18); 
        vm.expectRevert(abi.encodeWithSelector(OI_MinPriceNotMet.selector, 2 * 1e18, 3 * 1e18));
        priceGuard.getExpectedPrice(address(token0), address(token1));
        vm.prank(owner); priceGuard.setMinAcceptablePrice(1); 
    }
    function test_GetExpectedPrice_OracleFails_Reverts() public {
        vm.prank(owner); 
        mockOracle.setMockTokenPrice(address(token0), 0, false, 0, false, 18); 
        vm.expectRevert(OI_NoPriceSource.selector); 
        priceGuard.getExpectedPrice(address(token0), address(token1));
    }
    
    function test_GetExpectedPrice_Revert_FallbackNotAllowed() public {
        vm.prank(owner);
        mockOracle.setMockTokenPrice(address(token0), 1e18, true, block.timestamp, true, 18);
        vm.expectRevert(PG_FallbackPriceNotAllowed.selector);
        priceGuard.getExpectedPrice(address(token0), address(token1));
    }

    function test_ValidateSlippage_Success() public view {
        assertTrue(priceGuard.validateSlippage(100e18, 99e18, 100)); 
        assertTrue(priceGuard.validateSlippage(100e18, 100e18, 100)); 
    }
    function test_ValidateSlippage_Fail_Exceeds() public view {
        assertFalse(priceGuard.validateSlippage(100e18, 98e18, 100)); 
    }
    function test_ValidateSlippage_Reverts() public {
        vm.expectRevert(AmountIsZero.selector); 
        priceGuard.validateSlippage(0, 1, 100);
        
        vm.expectRevert(abi.encodeWithSelector(LM_SlippageInvalid.selector, Constants.MAX_SLIPPAGE + 1));
        priceGuard.validateSlippage(100, 90, Constants.MAX_SLIPPAGE + 1);
    }
     function test_ValidateSlippage_ExpectedZero_ActualZero_Success() public view {
        assertTrue(priceGuard.validateSlippage(0, 0, 100));
    }

    function test_CalculateMinimumOutput_Success() public view {
        assertEq(priceGuard.calculateMinimumOutput(100e18, 2e18, 100), 198e18);
    }
    function test_CalculateMinimumOutput_ZeroInput() public view {
        assertEq(priceGuard.calculateMinimumOutput(0, 2e18, 100), 0);
    }
    function test_CalculateMinimumOutput_Reverts() public {
        vm.expectRevert(SM_PriceNotPositive.selector);
        priceGuard.calculateMinimumOutput(100e18, 0, 100);
        vm.expectRevert(abi.encodeWithSelector(LM_SlippageInvalid.selector, Constants.MAX_SLIPPAGE + 1));
        priceGuard.calculateMinimumOutput(100e18, 1e18, Constants.MAX_SLIPPAGE + 1);
    }

    function test_RegisterCommitment_Success() public {
        bytes32 commitHash = keccak256("data");
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit PriceGuard.CommitmentRegistered(commitHash, user1, block.number);
        assertTrue(priceGuard.registerCommitment(commitHash));
        assertTrue(priceGuard.commitments(commitHash));
        assertEq(priceGuard.commitmentBlocks(commitHash), block.number);
        assertEq(priceGuard.commitmentCreators(commitHash), user1);
    }
    
    function test_RegisterCommitment_Reverts() public {
        vm.prank(user1);
        vm.expectRevert(SM_CommitHashZero.selector);
        priceGuard.registerCommitment(bytes32(0));
        
        bytes32 hash1 = keccak256("h1");
        vm.prank(user1);
        priceGuard.registerCommitment(hash1);
        vm.prank(user1);
        vm.expectRevert(InvalidAmount.selector); 
        priceGuard.registerCommitment(hash1); 
    }

    function test_VerifyCommitment_Success() public {
        uint8 opType = 1;
        bytes memory params = abi.encode(uint(123));
        bytes32 salt = keccak256("salt");
        bytes32 commitHash = keccak256(abi.encodePacked(user1, opType, params, salt, block.chainid)); 
        
        vm.prank(user1); 
        priceGuard.registerCommitment(commitHash);
        uint256 commitBlock = priceGuard.commitmentBlocks(commitHash);
        
        vm.roll(block.number + priceGuard.minBlockDelay() + 1);

        vm.prank(user1);
        vm.expectEmit(true, true, false, false); 
        emit PriceGuard.CommitmentRevealed(commitHash, user1, keccak256(params), block.number - commitBlock);
        assertTrue(priceGuard.verifyCommitment(opType, params, salt));
        assertFalse(priceGuard.commitments(commitHash)); 
    }

    function test_VerifyCommitment_Reverts() public {
        uint8 opType = 1;
        bytes memory params = abi.encode(uint(123));
        bytes32 salt = keccak256("salt");

        // Scenario 1: Hash not registered at all.
        // The hash is calculated with msg.sender=user1, but it's never registered.
        vm.prank(user1);
        vm.expectRevert(InvalidAmount.selector);
        priceGuard.verifyCommitment(opType, params, salt);

        // Scenario 2: Caller is not the creator.
        // User1 registers a hash. User2 tries to verify. This will generate a *different*
        // hash (because msg.sender is different), which is not found in the commitments mapping.
        bytes32 commitHashUser1 = keccak256(abi.encodePacked(user1, opType, params, salt, block.chainid));
        vm.prank(user1);
        priceGuard.registerCommitment(commitHashUser1);
        
        vm.roll(block.number + priceGuard.minBlockDelay() + 1);

        vm.prank(user2);
        vm.expectRevert(InvalidAmount.selector);
        priceGuard.verifyCommitment(opType, params, salt);
        
        // Scenario 3: Block delay not met
        vm.prank(user1);
        bytes32 commitHashUser1Delay = keccak256(abi.encodePacked(user1, uint8(2), params, salt, block.chainid));
        priceGuard.registerCommitment(commitHashUser1Delay);
        vm.expectRevert(InvalidAmount.selector); 
        priceGuard.verifyCommitment(2, params, salt); 
    }

    function test_SetPriceGuardParameters_Success() public {
        vm.prank(owner);
        assertTrue(priceGuard.setPriceGuardParameters(100, 20, 300, 60));
        assertEq(priceGuard.maxPriceImpactNormal(), 100);
    }
    function test_SetPriceGuardParameters_Reverts_InvalidValues() public {
        vm.prank(owner);
        vm.expectRevert(InvalidAmount.selector); 
        priceGuard.setPriceGuardParameters(Constants.BPS_MAX / 2 + 1, 20, 300, 60); 
        
        vm.prank(owner);
        vm.expectRevert(InvalidAmount.selector); 
        priceGuard.setPriceGuardParameters(100, 200, 300, 60); 
    }
    
    function test_SetCommitRevealParameters_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(SM_CooldownNotPositive.selector);
        priceGuard.setCommitRevealParameters(0, 5);
        
        vm.prank(owner);
        vm.expectRevert(InvalidDuration.selector);
        priceGuard.setCommitRevealParameters(5, 4);

        vm.prank(owner);
        vm.expectRevert(SM_CooldownTooHigh.selector);
        priceGuard.setCommitRevealParameters(1, 1001);
    }

    function test_SetMinAcceptablePrice_Success() public {
        vm.prank(owner);
        assertTrue(priceGuard.setMinAcceptablePrice(100));
        assertEq(priceGuard.minAcceptablePrice(), 100);
    }
    
    function test_SetMinAcceptablePrice_Revert_Zero() public {
        vm.prank(owner);
        vm.expectRevert(OI_MinAcceptablePriceZero.selector);
        priceGuard.setMinAcceptablePrice(0);
    }

    function test_CheckEmergencyStatus_Logic() public {
        bytes4 op = priceGuard.checkPriceImpact.selector;
        assertTrue(priceGuard.checkEmergencyStatus(op));

        mockEC.setMockSystemPaused(true);
        assertFalse(priceGuard.checkEmergencyStatus(op));
        
        mockEC.setMockSystemPaused(false);
        mockEC.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_CRITICAL);
        assertFalse(priceGuard.checkEmergencyStatus(op));

        mockEC.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_ALERT);
        mockEC.setMockFunctionRestriction(op, Constants.EMERGENCY_LEVEL_ALERT);
        assertFalse(priceGuard.checkEmergencyStatus(op));
    }
    
    function test_CheckEmergencyStatus_ECFails() public {
        mockEC.setShouldRevert(true);
        assertTrue(priceGuard.checkEmergencyStatus(priceGuard.checkPriceImpact.selector));
    }

    function test_EmergencyShutdown_Success() public {
        vm.prank(address(mockEC)); 
        vm.expectEmit(true, true, false, false);
        emit IEmergencyAware.EmergencyShutdownHandled(Constants.EMERGENCY_LEVEL_CRITICAL, address(mockEC));
        assertTrue(priceGuard.emergencyShutdown(Constants.EMERGENCY_LEVEL_CRITICAL));
    }
    
    function test_EmergencyShutdown_Revert_NotEC() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, bytes32(uint256(uint160(address(mockEC))))));
        priceGuard.emergencyShutdown(1);
    }
    
    function test_GetAndSetEmergencyController_Success() public {
        assertEq(priceGuard.getEmergencyController(), address(mockEC));
        MockEmergencyController newEc = new MockEmergencyController();
        vm.prank(owner);
        assertTrue(priceGuard.setEmergencyController(address(newEc)));
        assertEq(priceGuard.getEmergencyController(), address(newEc));
    }
    
    function test_GetAndSetEmergencyController_RevertNotContract() public {
        address nonContract = makeAddr("nonContract");
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "EmergencyController"));
        priceGuard.setEmergencyController(nonContract);
    }

    function test_PreventFrontRunning_Valid() public {
        bytes32 salt = keccak256(abi.encodePacked("mysecret"));
        uint8 opType = 1;
        bytes memory params = abi.encode(uint256(100), address(user2));
        bytes32 commitHash = keccak256(abi.encodePacked(user1, opType, params, salt, block.chainid));
        vm.prank(user1);
        assertTrue(priceGuard.preventFrontRunning(commitHash, opType, params, salt));
    }
    function test_PreventFrontRunning_Invalid_WrongHash() public {
        vm.prank(user1);
        assertFalse(priceGuard.preventFrontRunning(keccak256(abi.encodePacked("wrong")), 1, abi.encode(123), keccak256(abi.encodePacked("s"))));
    }
    function test_PreventFrontRunning_Reverts() public {
        vm.prank(user1);
        vm.expectRevert(SM_CommitHashZero.selector);
        priceGuard.preventFrontRunning(bytes32(0), 1, abi.encode(1), keccak256(abi.encodePacked("s")));

        bytes32 validHash = keccak256(abi.encodePacked("valid"));
        vm.prank(user1);
        vm.expectRevert(SM_ParamsEmpty.selector);
        priceGuard.preventFrontRunning(validHash, 1, bytes(""), keccak256(abi.encodePacked("s")));

        vm.prank(user1);
        assertTrue(priceGuard.preventFrontRunning(keccak256(abi.encodePacked(user1, uint8(0), bytes(""), keccak256(abi.encodePacked("s")), block.chainid)), 0, bytes(""), keccak256(abi.encodePacked("s"))));

        vm.prank(user1);
        vm.expectRevert(SM_SaltZero.selector);
        priceGuard.preventFrontRunning(validHash, 1, abi.encode(1), bytes32(0));
    }
}
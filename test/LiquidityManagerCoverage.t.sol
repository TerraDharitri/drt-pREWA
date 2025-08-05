// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../contracts/liquidity/LiquidityManager.sol";
import "../contracts/liquidity/interfaces/ILiquidityManager.sol";
import "../contracts/interfaces/IEmergencyAware.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/MockAccessControl.sol";
import "../contracts/mocks/MockEmergencyController.sol";
import "../contracts/mocks/MockOracleIntegration.sol";
import "../contracts/mocks/MockPriceGuard.sol";
import "../contracts/mocks/MockPancakeRouter.sol";
import "../contracts/mocks/MockPancakeFactory.sol";
import "../contracts/mocks/MockPancakePair.sol";
import "../contracts/proxy/TransparentProxy.sol";

contract NonPayableContract {
    // Contract that cannot receive BNB
}

contract PayableContract {
    // Contract that can receive BNB
    receive() external payable {}
}

contract LiquidityManagerCoverageTest is Test {
    LiquidityManager lm;
    MockERC20 pREWAToken;
    MockERC20 otherToken;
    MockPancakeRouter mockRouter;
    MockPancakeFactory mockFactory;
    MockPancakePair mockPair;
    MockAccessControl mockAC;
    MockEmergencyController mockEC;
    MockOracleIntegration mockOracle;
    MockPriceGuard mockPriceGuard;

    address owner;
    address parameterAdmin;
    address user;
    address wbnbAddress;
    address proxyAdmin;

    function setUp() public virtual {
        owner = address(0x1001);
        parameterAdmin = address(0x1002);
        user = address(0x1003);
        proxyAdmin = address(0x1004);

        // Deploy mocks
        mockRouter = new MockPancakeRouter();
        wbnbAddress = mockRouter.WETH();
        mockFactory = new MockPancakeFactory();
        mockRouter.setFactoryReturn(address(mockFactory));

        pREWAToken = new MockERC20();
        pREWAToken.mockInitialize("pREWA Token", "PREWA", 18, owner);

        otherToken = new MockERC20();
        otherToken.mockInitialize("Other Token", "OTK", 18, owner);

        mockAC = new MockAccessControl();
        vm.prank(owner);
        mockAC.setRole(mockAC.DEFAULT_ADMIN_ROLE(), owner, true);
        vm.prank(owner);
        mockAC.setRoleAdmin(mockAC.PARAMETER_ROLE(), mockAC.DEFAULT_ADMIN_ROLE());
        vm.prank(owner);
        mockAC.setRole(mockAC.PARAMETER_ROLE(), parameterAdmin, true);

        mockEC = new MockEmergencyController();
        mockOracle = new MockOracleIntegration();
        mockPriceGuard = new MockPriceGuard(address(mockOracle), address(mockEC));

        // Deploy LiquidityManager via proxy
        LiquidityManager logic = new LiquidityManager();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        lm = LiquidityManager(payable(address(proxy)));
        lm.initialize(
            address(pREWAToken),
            address(mockRouter),
            address(mockAC),
            address(mockEC),
            address(mockOracle),
            address(mockPriceGuard)
        );

        // Setup tokens
        vm.prank(owner);
        pREWAToken.mintForTest(user, 1000000 ether);
        vm.prank(owner);
        otherToken.mintForTest(user, 1000000 ether);

        // Setup pair
        mockPair = new MockPancakePair("LP_TOKEN", "LP", address(pREWAToken), address(otherToken));
        mockFactory.setPair(address(pREWAToken), address(otherToken), address(mockPair));

        // Approve tokens
        vm.startPrank(user);
        pREWAToken.approve(address(lm), type(uint256).max);
        otherToken.approve(address(lm), type(uint256).max);
        vm.stopPrank();
    }

    // Test BNB liquidity operations
    function test_AddLiquidityBNB_Success() public {
        // Register BNB pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(0));

        mockRouter.setAddLiquidityETHReturn(100 ether, 1 ether, 50 ether);

        vm.deal(user, 2 ether);
        vm.prank(user);
        (uint256 amountToken, uint256 amountBNB, uint256 liquidity) = lm.addLiquidityBNB{value: 1.5 ether}(
            100 ether,
            90 ether,
            0.9 ether,
            block.timestamp + 1 hours
        );

        assertEq(amountToken, 100 ether);
        assertEq(amountBNB, 1 ether);
        assertEq(liquidity, 50 ether);
    }

    function test_AddLiquidityBNB_RouterReverts() public {
        // Register BNB pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(0));

        mockRouter.setShouldRevertAddLiquidityETH(true);

        vm.deal(user, 2 ether);
        vm.prank(user);
        vm.expectRevert("MockRouter: AddLiquidityETH reverted by mock setting");
        lm.addLiquidityBNB{value: 1 ether}(
            100 ether,
            90 ether,
            0.9 ether,
            block.timestamp + 1 hours
        );
    }

    function test_AddLiquidityBNB_BNBRefundFailure() public {
        // Register BNB pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(0));

        NonPayableContract nonPayable = new NonPayableContract();
        vm.deal(address(nonPayable), 2 ether);
        vm.prank(owner);
        pREWAToken.mintForTest(address(nonPayable), 200 ether);

        vm.prank(address(nonPayable));
        pREWAToken.approve(address(lm), 200 ether);

        mockRouter.setAddLiquidityETHReturn(100 ether, 0.5 ether, 50 ether);

        vm.prank(address(nonPayable));
        vm.expectEmit(true, true, true, true);
        emit ILiquidityManager.BNBRefundFailed(address(nonPayable), 0.5 ether);
        lm.addLiquidityBNB{value: 1 ether}(
            100 ether,
            90 ether,
            0.4 ether,
            block.timestamp + 1 hours
        );

        // Check pending refund was recorded
        assertEq(lm.pendingBNBRefunds(address(nonPayable)), 0.5 ether);
    }

    function test_RemoveLiquidityBNB_Success() public {
        // First create a BNB pair in the factory
        MockPancakePair bnbPair = new MockPancakePair("BNB_LP", "BNBLP", address(pREWAToken), wbnbAddress);
        mockFactory.setPair(address(pREWAToken), wbnbAddress, address(bnbPair));
        
        // Register BNB pair - this will use the existing pair from factory
        vm.prank(parameterAdmin);
        lm.registerPair(address(0));

        // Mint LP tokens to user
        bnbPair.mintTokensTo(user, 10 ether);

        mockRouter.setRemoveLiquidityETHReturn(50 ether, 0.5 ether);

        vm.prank(user);
        bnbPair.approve(address(lm), 10 ether);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit ILiquidityManager.LiquidityRemoved(wbnbAddress, 50 ether, 0.5 ether, 10 ether, user);
        (uint256 amountToken, uint256 amountBNB) = lm.removeLiquidityBNB(
            10 ether,
            40 ether,
            0.4 ether,
            block.timestamp + 1 hours
        );

        assertEq(amountToken, 50 ether);
        assertEq(amountBNB, 0.5 ether);
    }

    function test_RemoveLiquidityBNB_RouterReverts() public {
        // First create a BNB pair in the factory
        MockPancakePair bnbPair = new MockPancakePair("BNB_LP", "BNBLP", address(pREWAToken), wbnbAddress);
        mockFactory.setPair(address(pREWAToken), wbnbAddress, address(bnbPair));
        
        // Register BNB pair - this will use the existing pair from factory
        vm.prank(parameterAdmin);
        lm.registerPair(address(0));

        // Mint LP tokens to user
        bnbPair.mintTokensTo(user, 10 ether);

        mockRouter.setShouldRevertRemoveLiquidityETH(true);

        vm.prank(user);
        bnbPair.approve(address(lm), 10 ether);

        vm.prank(user);
        vm.expectRevert("MockRouter: RemoveLiquidityETH reverted by mock setting");
        lm.removeLiquidityBNB(
            10 ether,
            40 ether,
            0.4 ether,
            block.timestamp + 1 hours
        );
    }

    // Test pair management edge cases
    function test_RegisterPair_AlreadyRegistered() public {
        // Register pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        // Try to register again
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LM_PairAlreadyRegistered.selector, "Pair for this token is already registered."));
        lm.registerPair(address(otherToken));
    }

    function test_RegisterPair_FactoryGetPairReverts() public {
        mockFactory.setShouldRevertGetPair(true);

        MockERC20 newToken = new MockERC20();
        newToken.mockInitialize("New", "NEW", 18, owner);

        vm.prank(parameterAdmin);
        // Should still succeed as it catches the revert and proceeds to createPair
        assertTrue(lm.registerPair(address(newToken)));
    }

    function test_RegisterPair_FactoryReturnsZeroAddress() public {
        // Set the existing factory to revert on createPair
        mockFactory.setShouldRevertCreatePair(true);

        MockERC20 newToken = new MockERC20();
        newToken.mockInitialize("New", "NEW", 18, owner);

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LM_CreatePairReverted.selector, "Pair for this token could not be created.", address(newToken), "Factory createPair reverted"));
        lm.registerPair(address(newToken));
    }

    function test_SetPairStatus_Success() public {
        // Register pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        // Deactivate pair
        vm.prank(parameterAdmin);
        vm.expectEmit(true, true, true, true);
        emit ILiquidityManager.PairStatusUpdated(address(otherToken), false, parameterAdmin);
        assertTrue(lm.setPairStatus(address(otherToken), false));

        // Check status
        (, , bool active, , , , ) = lm.getPairInfo(address(otherToken));
        assertFalse(active);

        // Reactivate pair
        vm.prank(parameterAdmin);
        assertTrue(lm.setPairStatus(address(otherToken), true));
    }

    function test_SetPairStatus_PairNotRegistered() public {
        MockERC20 unregisteredToken = new MockERC20();
        unregisteredToken.mockInitialize("Unreg", "UNREG", 18, owner);

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LM_PairDoesNotExist.selector, "Pair not registered for the given token."));
        lm.setPairStatus(address(unregisteredToken), false);
    }

    // Test parameter management
    function test_SetSlippageTolerance_Success() public {
        vm.prank(parameterAdmin);
        vm.expectEmit(true, true, true, true);
        emit ILiquidityManager.SlippageToleranceUpdated(100, 1000, parameterAdmin);
        assertTrue(lm.setSlippageTolerance(1000));

        // Note: slippageTolerance is internal, so we can't directly test the value
    }

    function test_SetSlippageTolerance_InvalidValue() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LM_SlippageInvalid.selector, 10001));
        lm.setSlippageTolerance(10001); // > 10000 (100%)
    }

    function test_SetMaxDeadlineOffset_Success() public {
        vm.prank(parameterAdmin);
        vm.expectEmit(true, true, true, true);
        emit ILiquidityManager.MaxDeadlineOffsetUpdated(1 hours, 2 hours, parameterAdmin);
        assertTrue(lm.setMaxDeadlineOffset(2 hours));

        assertEq(lm.maxDeadlineOffset(), 2 hours);
    }

    function test_SetMaxDeadlineOffset_InvalidValue() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LM_DeadlineOffsetInvalid.selector, 0));
        lm.setMaxDeadlineOffset(0);
    }

    function test_SetRouterAddress_Success() public {
        MockPancakeRouter newRouter = new MockPancakeRouter();
        newRouter.setFactoryReturn(address(mockFactory));

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ILiquidityManager.RouterAddressUpdated(address(mockRouter), address(newRouter), owner);
        assertTrue(lm.setRouterAddress(address(newRouter)));

        // Note: router address is internal, so we can't directly test the value
    }

    function test_SetRouterAddress_FactoryCallFails() public {
        MockPancakeRouter badRouter = new MockPancakeRouter();
        badRouter.setShouldRevertFactory(true);

        vm.prank(owner);
        vm.expectRevert(LM_RouterUpdateFactoryFail.selector);
        lm.setRouterAddress(address(badRouter));
    }

    function test_SetRouterAddress_ZeroFactory() public {
        MockPancakeRouter badRouter = new MockPancakeRouter();
        badRouter.setFactoryReturn(address(0));

        vm.prank(owner);
        vm.expectRevert(LM_RouterUpdateInvalidFactory.selector);
        lm.setRouterAddress(address(badRouter));
    }

    // Test token recovery
    function test_RecoverTokens_ActiveLPToken() public {
        // Register pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        address lpToken = lm.getLPTokenAddress(address(otherToken));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LM_CannotRecoverActiveLP.selector));
        lm.recoverTokens(lpToken, 100 ether, owner);
    }

    function test_RecoverTokens_InactiveLPToken() public {
        // Register pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        address lpToken = lm.getLPTokenAddress(address(otherToken));

        // Deactivate pair
        vm.prank(parameterAdmin);
        lm.setPairStatus(address(otherToken), false);

        // Send some tokens to LM contract
        MockPancakePair(payable(lpToken)).mintTokensTo(address(lm), 100 ether);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit LiquidityManager.LiquidityManagerTokenRecovered(lpToken, 100 ether, owner);
        assertTrue(lm.recoverTokens(lpToken, 100 ether, owner));
    }

    function test_RecoverTokens_RegularToken() public {
        MockERC20 randomToken = new MockERC20();
        randomToken.mockInitialize("Random", "RND", 18, owner);

        vm.prank(owner);
        randomToken.mintForTest(address(lm), 100 ether);

        vm.prank(owner);
        assertTrue(lm.recoverTokens(address(randomToken), 100 ether, owner));
    }

    function test_RecoverTokens_InsufficientBalance() public {
        MockERC20 randomToken = new MockERC20();
        randomToken.mockInitialize("Random", "RND", 18, owner);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, 0, 100 ether));
        lm.recoverTokens(address(randomToken), 100 ether, owner);
    }

    // Test BNB refund recovery
    function test_RecoverFailedBNBRefund_Success() public {
        // First create a failed refund
        vm.prank(parameterAdmin);
        lm.registerPair(address(0));

        PayableContract payableUser = new PayableContract();
        vm.deal(address(payableUser), 2 ether);
        vm.prank(owner);
        pREWAToken.mintForTest(address(payableUser), 200 ether);

        vm.prank(address(payableUser));
        pREWAToken.approve(address(lm), 200 ether);

        mockRouter.setAddLiquidityETHReturn(100 ether, 0.5 ether, 50 ether);

        vm.prank(address(payableUser));
        lm.addLiquidityBNB{value: 1 ether}(100 ether, 90 ether, 0.4 ether, block.timestamp + 1 hours);

        // Manually set a pending refund (since PayableContract can receive BNB)
        vm.store(address(lm), keccak256(abi.encode(address(payableUser), 41)), bytes32(uint256(0.5 ether)));

        // Now recover the failed refund
        vm.deal(address(lm), 1 ether); // Ensure LM has BNB to refund

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ILiquidityManager.BNBRefundRecovered(address(payableUser), 0.5 ether, owner);
        assertTrue(lm.recoverFailedBNBRefund(address(payableUser)));

        assertEq(lm.pendingBNBRefunds(address(payableUser)), 0);
    }

    function test_RecoverFailedBNBRefund_NoPendingRefund() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LM_NoPendingRefund.selector));
        lm.recoverFailedBNBRefund(user);
    }

    // Test getter functions
    function test_GetPairInfo_NonExistentPair() public {
        MockERC20 nonExistentToken = new MockERC20();
        nonExistentToken.mockInitialize("NonExistent", "NE", 18, owner);

        (address pairAddr, address tokenAddr, bool active, uint256 r0, uint256 r1, bool isToken0, uint32 ts) = 
            lm.getPairInfo(address(nonExistentToken));

        assertEq(pairAddr, address(0));
        assertEq(tokenAddr, address(0));
        assertFalse(active);
        assertEq(r0, 0);
        assertEq(r1, 0);
        assertFalse(isToken0);
        assertEq(ts, 0);
    }

    function test_GetLPTokenAddress_RegisteredPair() public {
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        address lpToken = lm.getLPTokenAddress(address(otherToken));
        assertNotEq(lpToken, address(0));
    }

    function test_GetLPTokenAddress_UnregisteredPair() public {
        MockERC20 unregisteredToken = new MockERC20();
        unregisteredToken.mockInitialize("Unreg", "UNREG", 18, owner);

        address lpToken = lm.getLPTokenAddress(address(unregisteredToken));
        assertEq(lpToken, address(0));
    }

    // Test emergency functionality
    function test_EmergencyPause_BlocksOperations() public {
        // Register pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        // Trigger emergency pause
        mockEC.setMockSystemPaused(true);

        vm.prank(user);
        vm.expectRevert(SystemInEmergencyMode.selector);
        lm.addLiquidity(
            address(otherToken),
            100 ether,
            100 ether,
            90 ether,
            90 ether,
            block.timestamp + 1 hours
        );
    }

    // Test access control edge cases
    function test_OnlyParameterRole_AccessControlZero() public {
        LiquidityManager newLm = new LiquidityManager();
        
        vm.prank(parameterAdmin);
        vm.expectRevert(LM_AccessControlZero.selector);
        newLm.registerPair(address(otherToken));
    }

    function test_OnlyAdminRole_AccessControlZero() public {
        LiquidityManager newLm = new LiquidityManager();
        
        vm.prank(owner);
        vm.expectRevert(LM_AccessControlZero.selector);
        newLm.setRouterAddress(address(mockRouter));
    }
    // Additional comprehensive tests to improve branch coverage

    // Test initialization edge cases
    function test_Initialize_RouterNotContract() public {
        LiquidityManager logic = new LiquidityManager();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        LiquidityManager newLm = LiquidityManager(payable(address(proxy)));

        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "router"));
        newLm.initialize(
            address(pREWAToken),
            address(0x1234), // EOA address, not a contract
            address(mockAC),
            address(mockEC),
            address(mockOracle),
            address(mockPriceGuard)
        );
    }

    function test_Initialize_AccessControlNotContract() public {
        LiquidityManager logic = new LiquidityManager();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        LiquidityManager newLm = LiquidityManager(payable(address(proxy)));

        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "accessControl"));
        newLm.initialize(
            address(pREWAToken),
            address(mockRouter),
            address(0x1234), // EOA address, not a contract
            address(mockEC),
            address(mockOracle),
            address(mockPriceGuard)
        );
    }

    function test_Initialize_EmergencyControllerNotContract() public {
        LiquidityManager logic = new LiquidityManager();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        LiquidityManager newLm = LiquidityManager(payable(address(proxy)));

        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "emergencyController"));
        newLm.initialize(
            address(pREWAToken),
            address(mockRouter),
            address(mockAC),
            address(0x1234), // EOA address, not a contract
            address(mockOracle),
            address(mockPriceGuard)
        );
    }

    function test_Initialize_OracleIntegrationNotContract() public {
        LiquidityManager logic = new LiquidityManager();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        LiquidityManager newLm = LiquidityManager(payable(address(proxy)));

        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "oracleIntegration"));
        newLm.initialize(
            address(pREWAToken),
            address(mockRouter),
            address(mockAC),
            address(mockEC),
            address(0x1234), // EOA address, not a contract
            address(mockPriceGuard)
        );
    }

    function test_Initialize_PriceGuardNotContract() public {
        LiquidityManager logic = new LiquidityManager();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        LiquidityManager newLm = LiquidityManager(payable(address(proxy)));

        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "priceGuard"));
        newLm.initialize(
            address(pREWAToken),
            address(mockRouter),
            address(mockAC),
            address(mockEC),
            address(mockOracle),
            address(0x1234) // EOA address, not a contract
        );
    }

    // Test addLiquidity edge cases
    function test_AddLiquidity_PairNotRegistered() public {
        MockERC20 unregisteredToken = new MockERC20();
        unregisteredToken.mockInitialize("Unreg", "UNREG", 18, owner);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(LM_PairDoesNotExist.selector, "Pair not registered for the given token."));
        lm.addLiquidity(
            address(unregisteredToken),
            100 ether,
            100 ether,
            90 ether,
            90 ether,
            block.timestamp + 1 hours
        );
    }

    function test_AddLiquidity_PairNotActive() public {
        // Register pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        // Deactivate pair
        vm.prank(parameterAdmin);
        lm.setPairStatus(address(otherToken), false);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(LM_PairNotActive.selector, "Pair not active for the given token."));
        lm.addLiquidity(
            address(otherToken),
            100 ether,
            100 ether,
            90 ether,
            90 ether,
            block.timestamp + 1 hours
        );
    }

    function test_AddLiquidity_ZeroMinAmounts() public {
        // Register pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        vm.prank(user);
        vm.expectRevert(AmountIsZero.selector);
        lm.addLiquidity(
            address(otherToken),
            100 ether,
            100 ether,
            0, // Zero pREWAMin
            90 ether,
            block.timestamp + 1 hours
        );
    }

    function test_AddLiquidity_RouterReverts() public {
        // Register pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        mockRouter.setShouldRevertAddLiquidity(true);

        vm.prank(user);
        vm.expectRevert("MockRouter: AddLiquidity reverted by mock setting");
        lm.addLiquidity(
            address(otherToken),
            100 ether,
            100 ether,
            90 ether,
            90 ether,
            block.timestamp + 1 hours
        );
    }

    function test_AddLiquidity_PartialRefund() public {
        // Register pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        // Set router to return less than desired amounts
        mockRouter.setAddLiquidityReturn(80 ether, 70 ether, 50 ether);

        uint256 userPREWABefore = pREWAToken.balanceOf(user);
        uint256 userOtherBefore = otherToken.balanceOf(user);

        vm.prank(user);
        lm.addLiquidity(
            address(otherToken),
            100 ether,
            100 ether,
            70 ether,
            60 ether,
            block.timestamp + 1 hours
        );

        // Check refunds were made
        assertEq(pREWAToken.balanceOf(user), userPREWABefore - 80 ether);
        assertEq(otherToken.balanceOf(user), userOtherBefore - 70 ether);
    }

    // Test deadline validation
    function test_ValidateDeadline_Expired() public {
        // Register pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        vm.prank(user);
        vm.expectRevert(DeadlineExpired.selector);
        lm.addLiquidity(
            address(otherToken),
            100 ether,
            100 ether,
            90 ether,
            90 ether,
            block.timestamp - 1 // Expired deadline
        );
    }

    function test_ValidateDeadline_TooFar() public {
        // Register pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        vm.prank(user);
        vm.expectRevert(DeadlineTooFar.selector);
        lm.addLiquidity(
            address(otherToken),
            100 ether,
            100 ether,
            90 ether,
            90 ether,
            block.timestamp + 2 hours // Too far (maxDeadlineOffset is 1 hour)
        );
    }

    // Test emergency functionality
    function test_EmergencyShutdown_Success() public {
        vm.prank(address(mockEC));
        vm.expectEmit(true, true, false, false);
        emit IEmergencyAware.EmergencyShutdownHandled(2, address(mockEC));
        assertTrue(lm.emergencyShutdown(2));
    }

    function test_CheckEmergencyStatus_NotPaused() public {
        mockEC.setMockSystemPaused(false);
        assertTrue(lm.checkEmergencyStatus(bytes4(0)));
    }

    function test_CheckEmergencyStatus_Paused() public {
        mockEC.setMockSystemPaused(true);
        assertFalse(lm.checkEmergencyStatus(bytes4(0)));
    }

    function test_GetEmergencyController() public view {
        assertEq(lm.getEmergencyController(), address(mockEC));
    }

    // Test contract updates
    function test_SetEmergencyController_Success() public {
        MockEmergencyController newEC = new MockEmergencyController();

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit LiquidityManager.EmergencyControllerSet(address(mockEC), address(newEC), owner);
        assertTrue(lm.setEmergencyController(address(newEC)));

        assertEq(lm.getEmergencyController(), address(newEC));
    }

    function test_UpdateOracleIntegration_Success() public {
        MockOracleIntegration newOracle = new MockOracleIntegration();

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit LiquidityManager.OracleIntegrationSet(address(mockOracle), address(newOracle), owner);
        assertTrue(lm.updateOracleIntegration(address(newOracle)));
    }

    function test_UpdateOracleIntegration_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(LM_OracleIntegrationZero.selector);
        lm.updateOracleIntegration(address(0));
    }

    function test_UpdateOracleIntegration_NonContract() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "oracleIntegration"));
        lm.updateOracleIntegration(address(0x123));
    }

    function test_UpdatePriceGuard_Success() public {
        MockPriceGuard newPriceGuard = new MockPriceGuard(address(mockOracle), address(mockEC));

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit LiquidityManager.PriceGuardSet(address(mockPriceGuard), address(newPriceGuard), owner);
        assertTrue(lm.updatePriceGuard(address(newPriceGuard)));
    }

    function test_UpdatePriceGuard_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(LM_PriceGuardZero.selector);
        lm.updatePriceGuard(address(0));
    }

    function test_UpdatePriceGuard_NonContract() public {
        vm.prank(owner);
        vm.expectRevert(LM_PriceGuardNotContract.selector);
        lm.updatePriceGuard(address(0x123));
    }

    // Additional tests to improve branch coverage

    // Test exact BNB amount (no refund needed)
    function test_AddLiquidityBNB_ExactBNBAmount() public {
        // Register BNB pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(0));

        // Set router to use exact BNB amount
        mockRouter.setAddLiquidityETHReturn(100 ether, 1 ether, 50 ether);

        vm.deal(user, 2 ether);
        vm.prank(user);
        lm.addLiquidityBNB{value: 1 ether}(
            100 ether,
            90 ether,
            0.9 ether,
            block.timestamp + 1 hours
        );

        // Check that no refund was needed
        assertEq(lm.pendingBNBRefunds(user), 0);
    }

    // Test exact pREWA amount (no refund needed)
    function test_AddLiquidity_ExactPREWAAmount() public {
        // Register pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        // Set router to use exact amounts
        mockRouter.setAddLiquidityReturn(100 ether, 100 ether, 50 ether);

        uint256 userPREWABefore = pREWAToken.balanceOf(user);
        uint256 userOtherBefore = otherToken.balanceOf(user);

        vm.prank(user);
        lm.addLiquidity(
            address(otherToken),
            100 ether,
            100 ether,
            90 ether,
            90 ether,
            block.timestamp + 1 hours
        );

        // Check no refunds were made
        assertEq(pREWAToken.balanceOf(user), userPREWABefore - 100 ether);
        assertEq(otherToken.balanceOf(user), userOtherBefore - 100 ether);
    }

    // Test partial pREWA refund only
    function test_AddLiquidity_PartialPREWARefundOnly() public {
        // Register pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        // Set router to return less pREWA but exact other token
        mockRouter.setAddLiquidityReturn(80 ether, 100 ether, 50 ether);

        uint256 userPREWABefore = pREWAToken.balanceOf(user);
        uint256 userOtherBefore = otherToken.balanceOf(user);

        vm.prank(user);
        lm.addLiquidity(
            address(otherToken),
            100 ether,
            100 ether,
            70 ether,
            90 ether,
            block.timestamp + 1 hours
        );

        // Check only pREWA refund was made
        assertEq(pREWAToken.balanceOf(user), userPREWABefore - 80 ether);
        assertEq(otherToken.balanceOf(user), userOtherBefore - 100 ether);
    }

    // Test partial other token refund only
    function test_AddLiquidity_PartialOtherRefundOnly() public {
        // Register pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        // Set router to return exact pREWA but less other token
        mockRouter.setAddLiquidityReturn(100 ether, 80 ether, 50 ether);

        uint256 userPREWABefore = pREWAToken.balanceOf(user);
        uint256 userOtherBefore = otherToken.balanceOf(user);

        vm.prank(user);
        lm.addLiquidity(
            address(otherToken),
            100 ether,
            100 ether,
            90 ether,
            70 ether,
            block.timestamp + 1 hours
        );

        // Check only other token refund was made
        assertEq(pREWAToken.balanceOf(user), userPREWABefore - 100 ether);
        assertEq(otherToken.balanceOf(user), userOtherBefore - 80 ether);
    }


    // Test complex conditional in _getPairId
    function test_GetPairId_TokenOrdering() public {
        // This tests the ternary operator in _getPairId
        // We can't directly test _getPairId since it's private, but we can test through registerPair
        
        // Create two tokens with different addresses to test ordering
        MockERC20 tokenA = new MockERC20();
        tokenA.mockInitialize("TokenA", "TKA", 18, owner);
        
        MockERC20 tokenB = new MockERC20();
        tokenB.mockInitialize("TokenB", "TKB", 18, owner);

        // Ensure we test both branches of the ternary operator
        address lowerToken = address(tokenA) < address(tokenB) ? address(tokenA) : address(tokenB);
        address higherToken = address(tokenA) < address(tokenB) ? address(tokenB) : address(tokenA);

        // Test with lower address token
        vm.prank(parameterAdmin);
        assertTrue(lm.registerPair(lowerToken));

        // Test with higher address token
        vm.prank(parameterAdmin);
        assertTrue(lm.registerPair(higherToken));
    }

    // Test error conditions with zero amounts in different combinations
    function test_AddLiquidity_ZeroOtherMin() public {
        // Register pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        vm.prank(user);
        vm.expectRevert(AmountIsZero.selector);
        lm.addLiquidity(
            address(otherToken),
            100 ether,
            100 ether,
            90 ether,
            0, // Zero otherMin
            block.timestamp + 1 hours
        );
    }

    function test_AddLiquidityBNB_ZeroBNBMin() public {
        // Register BNB pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(0));

        vm.deal(user, 2 ether);
        vm.prank(user);
        vm.expectRevert(AmountIsZero.selector);
        lm.addLiquidityBNB{value: 1 ether}(
            100 ether,
            90 ether,
            0, // Zero bnbMin
            block.timestamp + 1 hours
        );
    }

    function test_RemoveLiquidity_ZeroPREWAMin() public virtual {
        // Register pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        vm.prank(user);
        vm.expectRevert(AmountIsZero.selector);
        lm.removeLiquidity(
            address(otherToken),
            10 ether,
            0, // Zero pREWAMin
            4 ether,
            block.timestamp + 1 hours
        );
    }

    function test_RemoveLiquidity_ZeroOtherMin() public {
        // Register pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        vm.prank(user);
        vm.expectRevert(AmountIsZero.selector);
        lm.removeLiquidity(
            address(otherToken),
            10 ether,
            40 ether,
            0, // Zero otherMin
            block.timestamp + 1 hours
        );
    }

    function test_RemoveLiquidityBNB_ZeroPREWAMin() public {
        // Register BNB pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(0));

        vm.prank(user);
        vm.expectRevert(AmountIsZero.selector);
        lm.removeLiquidityBNB(
            10 ether,
            0, // Zero pREWAMin
            0.4 ether,
            block.timestamp + 1 hours
        );
    }

    function test_RemoveLiquidityBNB_ZeroBNBMin() public {
        // Register BNB pair first
        vm.prank(parameterAdmin);
        lm.registerPair(address(0));

        vm.prank(user);
        vm.expectRevert(AmountIsZero.selector);
        lm.removeLiquidityBNB(
            10 ether,
            40 ether,
            0, // Zero bnbMin
            block.timestamp + 1 hours
        );
    }

    // Test slippage tolerance boundary conditions
    function test_SetSlippageTolerance_MaxValue() public {
        vm.prank(parameterAdmin);
        assertTrue(lm.setSlippageTolerance(5000)); // MAX_SLIPPAGE = 5000 (50%)
    }

    // Test deadline offset boundary conditions
    function test_SetMaxDeadlineOffset_MinValue() public {
        vm.prank(parameterAdmin);
        assertTrue(lm.setMaxDeadlineOffset(5 minutes)); // Minimum allowed
    }

    function test_SetMaxDeadlineOffset_MaxValue() public {
        vm.prank(parameterAdmin);
        assertTrue(lm.setMaxDeadlineOffset(1 days)); // Maximum allowed
    }
}
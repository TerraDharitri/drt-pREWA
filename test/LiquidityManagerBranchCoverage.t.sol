// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./LiquidityManagerCoverage.t.sol";

contract LiquidityManagerBranchCoverageTest is LiquidityManagerCoverageTest {
    function setUp() public override {
        super.setUp();
    }

    // Additional tests for branch coverage will be added here.
    function test_RegisterPair_CreatePairReverts_WithStringError() public {
        MockERC20 newToken = new MockERC20();
        newToken.mockInitialize("New Token", "NEW", 18, owner);

        mockFactory.setCreatePairRevertDetails("Error(string)", "Custom error message");

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LM_CreatePairReverted.selector, "Pair for this token could not be created.", address(newToken), "Factory createPair reverted"));
        lm.registerPair(address(newToken));
    }

    function test_RegisterPair_CreatePairReverts_WithPanicError() public {
        MockERC20 newToken = new MockERC20();
        newToken.mockInitialize("New Token", "NEW", 18, owner);

        mockFactory.setCreatePairRevertDetails("Panic(uint256)", "0x01");

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LM_CreatePairReverted.selector, "Pair for this token could not be created.", address(newToken), "Factory createPair reverted"));
        lm.registerPair(address(newToken));
    }

    function test_RegisterPair_OracleRegistrationFails() public {
        MockERC20 newToken = new MockERC20();
        newToken.mockInitialize("New Token", "NEW", 18, owner);

        mockOracle.setShouldRevertRegisterLP(true);

        vm.prank(parameterAdmin);
        (address token0, address token1) = address(pREWAToken) < address(newToken) ? (address(pREWAToken), address(newToken)) : (address(newToken), address(pREWAToken));
        address expectedLpTokenAddress = address(uint160(uint256(keccak256(abi.encodePacked(token0, token1)))));
        vm.expectEmit(true, true, true, true);
        emit ILiquidityManager.LPTokenOracleRegistrationFailed(expectedLpTokenAddress, address(pREWAToken), address(newToken));
        lm.registerPair(address(newToken));
    }

    function test_SetPairStatus_NoChange() public {
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        // Status is already active, so this should do nothing and return true
        vm.prank(parameterAdmin);
        assertTrue(lm.setPairStatus(address(otherToken), true));
    }

    function test_RecoverFailedBNBRefund_TransferFails() public {
        // 1. Setup: Create a scenario where a BNB refund fails
        vm.prank(parameterAdmin);
        lm.registerPair(address(0)); // Register BNB pair

        NonPayableContract nonPayableUser = new NonPayableContract();
        vm.deal(address(nonPayableUser), 2 ether);
        vm.prank(owner);
        pREWAToken.mintForTest(address(nonPayableUser), 200 ether);

        vm.prank(address(nonPayableUser));
        pREWAToken.approve(address(lm), 200 ether);

        mockRouter.setAddLiquidityETHReturn(100 ether, 0.5 ether, 50 ether);

        vm.prank(address(nonPayableUser));
        lm.addLiquidityBNB{value: 1 ether}(100 ether, 90 ether, 0.4 ether, block.timestamp + 1 hours);

        uint256 pendingRefund = lm.pendingBNBRefunds(address(nonPayableUser));
        assertTrue(pendingRefund > 0, "Pending refund should exist");

        // 2. Action: Attempt to recover the refund, expecting the transfer to fail
        vm.deal(address(lm), pendingRefund); // Ensure LM has enough BNB to attempt the refund
        vm.prank(owner);
        vm.expectRevert("BNB recovery transfer failed");
        lm.recoverFailedBNBRefund(address(nonPayableUser));

        // 3. Assertion: Verify the pending refund amount was not cleared
        assertEq(lm.pendingBNBRefunds(address(nonPayableUser)), pendingRefund, "Pending refund should not be cleared on failed recovery");
    }

    function test_GetPairInfo_GetReservesReverts() public {
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        address lpTokenAddress = lm.getLPTokenAddress(address(otherToken));
        MockPancakePair(payable(lpTokenAddress)).setShouldRevertGetReserves(true);

        (address pairAddr, address tokenAddr, bool active, uint256 r0, uint256 r1, bool isToken0, uint32 ts) =
            lm.getPairInfo(address(otherToken));

        assertEq(pairAddr, lpTokenAddress);
        assertEq(tokenAddr, address(otherToken));
        assertTrue(active);
        assertEq(r0, 0);
        assertEq(r1, 0);
        assertFalse(isToken0);
        assertEq(ts, 0);
    }

    function test_GetPairInfo_Token0Reverts() public {
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        address lpTokenAddress = lm.getLPTokenAddress(address(otherToken));
        MockPancakePair(payable(lpTokenAddress)).setShouldRevertToken0(true);

        (address pairAddr, address tokenAddr, bool active, , , bool isToken0, ) =
            lm.getPairInfo(address(otherToken));

        assertEq(pairAddr, lpTokenAddress);
        assertEq(tokenAddr, address(otherToken));
        assertTrue(active);
        assertFalse(isToken0); // Should be false due to revert
    }

    function test_RegisterPair_WethReverts() public {
        mockRouter.setShouldRevertWeth(true);
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LM_WETHFail.selector));
        lm.registerPair(address(0));
    }

    function test_RegisterPair_GetPairSucceeds() public {
        MockERC20 newToken = new MockERC20();
        newToken.mockInitialize("New Token", "NEW", 18, owner);
        
        MockPancakePair newPair = new MockPancakePair("New LP", "NLP", address(pREWAToken), address(newToken));
        address expectedPairAddress = address(newPair);

        mockFactory.setGetPairReturn(expectedPairAddress);

        vm.prank(parameterAdmin);
        vm.expectEmit(true, true, true, true);
        (address token0, address token1) = address(pREWAToken) < address(newToken) ? (address(pREWAToken), address(newToken)) : (address(newToken), address(pREWAToken));
        bytes32 pairId = keccak256(abi.encodePacked(token0, token1));
        emit ILiquidityManager.PairRegistered(pairId, expectedPairAddress, address(newToken), parameterAdmin);
        
        assertTrue(lm.registerPair(address(newToken)));
        
        (address pairAddr, , bool active, , , , ) = lm.getPairInfo(address(newToken));
        assertEq(pairAddr, expectedPairAddress);
        assertTrue(active);
    }

    function test_RegisterPair_CreatePairReverts_WithNoReason() public {
        MockERC20 newToken = new MockERC20();
        newToken.mockInitialize("New Token", "NEW", 18, owner);

        mockFactory.setCreatePairRevertDetails("None", "");

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LM_CreatePairReverted.selector, "Pair for this token could not be created.", address(newToken), "Factory createPair reverted"));
        lm.registerPair(address(newToken));
    }

    function test_AddLiquidity_PREWARefund() public {
        // 1. Setup
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));
        
        uint256 pREWAAmountDesired = 100 ether;
        uint256 otherAmountDesired = 100 ether;
        uint256 pREWAMin = 90 ether;
        uint256 otherMin = 90 ether;

        // Mock router to return less pREWA than desired
        mockRouter.setAddLiquidityReturn(pREWAAmountDesired - 10 ether, otherAmountDesired, 50 ether);

        vm.prank(owner);
        pREWAToken.mintForTest(user, pREWAAmountDesired);
        vm.prank(owner);
        otherToken.mintForTest(user, otherAmountDesired);
        vm.prank(user);
        pREWAToken.approve(address(lm), pREWAAmountDesired);
        vm.prank(user);
        otherToken.approve(address(lm), otherAmountDesired);

        uint256 balanceBefore = pREWAToken.balanceOf(user);

        // 2. Action
        vm.prank(user);
        lm.addLiquidity(address(otherToken), pREWAAmountDesired, otherAmountDesired, pREWAMin, otherMin, block.timestamp + 1 hours);

        // 3. Assertion
        uint256 balanceAfter = pREWAToken.balanceOf(user);
        assertEq(balanceAfter, balanceBefore - (pREWAAmountDesired - 10 ether), "Refunded pREWA amount is incorrect");
    }

    function test_AddLiquidityBNB_WethReverts() public {
        mockRouter.setShouldRevertWeth(true);
        vm.deal(owner, 1 ether);
        pREWAToken.mintForTest(owner, 100 ether);
        vm.prank(owner);
        pREWAToken.approve(address(lm), 100 ether);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LM_WETHFail.selector));
        lm.addLiquidityBNB{value: 1 ether}(100 ether, 90 ether, 0.9 ether, block.timestamp + 1 hours);
    }

    function test_RemoveLiquidity_ZeroPREWAMin() public override {
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        lm.removeLiquidity(address(otherToken), 1 ether, 0, 1, block.timestamp + 1 hours);
    }

    function test_SetRouterAddress_FactoryReverts() public {
        address newRouterAddress = address(new MockPancakeRouter());
        MockPancakeRouter(newRouterAddress).setShouldRevertFactory(true);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LM_RouterUpdateFactoryFail.selector));
        lm.setRouterAddress(newRouterAddress);
    }

    function test_GetPairInfo_WethReverts() public {
        mockRouter.setShouldRevertWeth(true);
        vm.expectRevert(bytes("MockRouter: WETH call reverted by mock setting"));
        lm.getPairInfo(address(0));
    }

    function test_GetLPTokenAddress_WethReverts() public {
        mockRouter.setShouldRevertWeth(true);
        vm.expectRevert(bytes("MockRouter: WETH call reverted by mock setting"));
        lm.getLPTokenAddress(address(0));
    }

    function test_UpdatePriceGuard_NotAContract() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LM_PriceGuardNotContract.selector));
        lm.updatePriceGuard(address(0xdeadbeef));
    }

    function test_RecoverTokens_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "tokenAddress for recovery"));
        lm.recoverTokens(address(0), 100, owner);
    }

    function test_RecoverTokens_ZeroRecipient() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "recipient for recovery"));
        lm.recoverTokens(address(otherToken), 100, address(0));
    }

    function test_RecoverTokens_ZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        lm.recoverTokens(address(otherToken), 0, owner);
    }

    function test_RecoverFailedBNBRefund_ZeroUser() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "user for BNB recovery"));
        lm.recoverFailedBNBRefund(address(0));
    }

    function test_EmergencyShutdown_ControllerNotSet() public {
        // Deploy a new instance without setting the controller
        LiquidityManager newLm = new LiquidityManager();
        // No initialize call, so controller is address(0)
        
        vm.prank(address(this)); // Any address
        vm.expectRevert(abi.encodeWithSelector(LM_ControllerNotSet.selector, "emergencyController"));
        newLm.emergencyShutdown(1);
    }

    function test_RegisterPair_WethReturnsZero() public {
        mockRouter.setWethReturn(address(0));
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LM_RouterReturnedZeroAddress.selector, "weth"));
        lm.registerPair(address(0));
    }
}
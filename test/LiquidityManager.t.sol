// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/liquidity/LiquidityManager.sol";
import "../contracts/liquidity/interfaces/ILiquidityManager.sol";
import "../contracts/liquidity/interfaces/IPancakeRouter.sol";
import "../contracts/liquidity/interfaces/IPancakeFactory.sol";
import "../contracts/liquidity/interfaces/IPancakePair.sol";
import "../contracts/access/AccessControl.sol";
import "../contracts/controllers/EmergencyController.sol";
import "../contracts/oracle/OracleIntegration.sol";
import "../contracts/security/PriceGuard.sol";
import "../contracts/libraries/Constants.sol";
import "../contracts/libraries/Errors.sol";

import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/MockAccessControl.sol";
import "../contracts/mocks/MockEmergencyController.sol";
import "../contracts/mocks/MockOracleIntegration.sol";
import "../contracts/mocks/MockPriceGuard.sol";
import "../contracts/mocks/MockPancakeRouter.sol";
import "../contracts/mocks/MockPancakeFactory.sol";
import "../contracts/mocks/MockPancakePair.sol";
import "../contracts/proxy/TransparentProxy.sol";

contract RevertingReceiverLMTestFull is Test {
    event Received(uint256 amount);
    receive() external payable {
        emit Received(msg.value);
        revert("BNB Refund Rejected by Test Contract");
    }
}

contract LiquidityManagerTest is Test {
    LiquidityManager lm;
    MockERC20 pREWAToken;
    MockERC20 otherToken;
    MockERC20 anotherToken;
    MockPancakeRouter mockRouter;
    MockPancakeFactory mockFactory;
    MockPancakePair mockPairPREWAOther;
    MockPancakePair mockPairPREWAWBNB;
    MockPancakePair mockPairPREWAAnother;

    MockAccessControl mockAC;
    MockEmergencyController mockEC;
    MockOracleIntegration mockOracle;
    MockPriceGuard mockPriceGuard;

    address owner;
    address parameterAdmin;
    address user;
    address wbnbAddress;
    address zeroAddress = address(0);
    address proxyAdmin;

    function setUp() public {
        owner = makeAddr("owner");
        parameterAdmin = makeAddr("parameterAdmin");
        user = makeAddr("userLMTF");
        proxyAdmin = makeAddr("proxyAdmin");

        mockRouter = new MockPancakeRouter();
        wbnbAddress = mockRouter.weth();
        mockFactory = new MockPancakeFactory();
        mockRouter.setFactoryReturn(address(mockFactory));

        pREWAToken = new MockERC20();
        pREWAToken.mockInitialize("pREWA Token", "PREWA", 18, owner);

        otherToken = new MockERC20();
        otherToken.mockInitialize("Other Token", "OTK", 18, owner);

        anotherToken = new MockERC20();
        anotherToken.mockInitialize("Another Token", "ANT", 18, owner);

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

        vm.prank(owner);
        pREWAToken.mintForTest(user, 2_000_000 * 1e18);
        vm.prank(owner);
        otherToken.mintForTest(user, 1_000_000 * 1e18);
        vm.prank(owner);
        anotherToken.mintForTest(user, 1_000_000 * 1e18);

        mockPairPREWAWBNB = new MockPancakePair("LP_BNB_PREWA", "LP-BP", address(pREWAToken), wbnbAddress);
        mockFactory.setPair(address(pREWAToken), wbnbAddress, address(mockPairPREWAWBNB));

        mockPairPREWAOther = new MockPancakePair("LP_OTHER_PREWA", "LP-OP", address(pREWAToken), address(otherToken));
        mockFactory.setPair(address(pREWAToken), address(otherToken), address(mockPairPREWAOther));

        mockPairPREWAAnother = new MockPancakePair("LP_ANOTHER_PREWA", "LP-AP", address(pREWAToken), address(anotherToken));
        mockFactory.setPair(address(pREWAToken), address(anotherToken), address(mockPairPREWAAnother));

        vm.prank(parameterAdmin);
        lm.registerPair(address(0)); // Registers WBNB pair
        vm.prank(parameterAdmin);
        lm.registerPair(address(otherToken));

        vm.startPrank(user);
        pREWAToken.approve(address(lm), type(uint256).max);
        otherToken.approve(address(lm), type(uint256).max);
        anotherToken.approve(address(lm), type(uint256).max);

        address actualLpOther = lm.getLPTokenAddress(address(otherToken));
        address actualLpBNB = lm.getLPTokenAddress(wbnbAddress);

        IERC20Upgradeable(actualLpOther).approve(address(lm), type(uint256).max);
        IERC20Upgradeable(actualLpBNB).approve(address(lm), type(uint256).max);
        vm.stopPrank();

        vm.prank(owner);
        mockOracle.setMockTokenPrice(address(pREWAToken), 1 * 1e18, false, block.timestamp, true, 18);
        vm.prank(owner);
        mockOracle.setMockTokenPrice(address(otherToken), 10 * 1e18, false, block.timestamp, true, 18);
        vm.prank(owner);
        mockOracle.setMockTokenPrice(wbnbAddress, 300 * 1e18, false, block.timestamp, true, 18);
        vm.prank(owner);
        mockOracle.setMockTokenPrice(address(anotherToken), 5 * 1e18, false, block.timestamp, true, 18);
    }

    function test_Initialize_Success() public view {
        assertEq(address(lm.accessControl()), address(mockAC));
        assertEq(address(lm.emergencyController()), address(mockEC));
        assertEq(address(lm.oracleIntegration()), address(mockOracle));
        assertEq(address(lm.priceGuard()), address(mockPriceGuard));
    }
    function test_Initialize_Revert_ZeroAddresses() public {
        LiquidityManager logic = new LiquidityManager();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        LiquidityManager newLm = LiquidityManager(payable(address(proxy)));
        
        vm.expectRevert(LM_PTokenZero.selector);
        newLm.initialize(address(0), address(mockRouter), address(mockAC), address(mockEC), address(mockOracle), address(mockPriceGuard));
    }
    function test_Initialize_Revert_RouterFactoryCallFails() public {
        MockPancakeRouter badRouter = new MockPancakeRouter();
        badRouter.setShouldRevertFactory(true);

        LiquidityManager logic = new LiquidityManager();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        LiquidityManager newLm = LiquidityManager(payable(address(proxy)));

        vm.expectRevert(LM_FactoryFail.selector);
        newLm.initialize(address(pREWAToken), address(badRouter), address(mockAC), address(mockEC), address(mockOracle), address(mockPriceGuard));
    }
     function test_Initialize_Revert_RouterReturnsZeroFactory() public {
        MockPancakeRouter routerWithZeroFactory = new MockPancakeRouter();
        routerWithZeroFactory.setFactoryReturn(address(0));

        LiquidityManager logic = new LiquidityManager();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        LiquidityManager newLm = LiquidityManager(payable(address(proxy)));
        
        vm.expectRevert(abi.encodeWithSelector(LM_RouterReturnedZeroAddress.selector, "factory"));
        newLm.initialize(address(pREWAToken), address(routerWithZeroFactory), address(mockAC), address(mockEC), address(mockOracle), address(mockPriceGuard));
    }

    function test_Constructor_Runs() public { new LiquidityManager(); assertTrue(true); }

    function test_Modifier_OnlyAdminRole_Fail() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, mockAC.DEFAULT_ADMIN_ROLE()));
        lm.setRouterAddress(address(mockRouter));
    }

    function test_Modifier_OnlyAdminRole_Success() public {
        vm.prank(owner);
        lm.setRouterAddress(address(mockRouter));
        assertTrue(true);
    }

    function test_Modifier_OnlyParameterRole_Fail() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, mockAC.PARAMETER_ROLE()));
        lm.registerPair(address(otherToken));
    }

    function test_Modifier_OnlyParameterRole_ACZero() public {
        LiquidityManager newLm = new LiquidityManager();
        vm.prank(parameterAdmin);
        vm.expectRevert(LM_AccessControlZero.selector);
        newLm.setSlippageTolerance(100);
    }

    function test_Modifier_OnlyParameterRole_Success() public {
        MockERC20 t = new MockERC20();
        t.mockInitialize("T","T",18,owner);
        vm.prank(parameterAdmin);
        lm.registerPair(address(t));
        assertTrue(true);
    }

    function test_Modifier_WhenNotEmergency_Reverts() public {
        mockEC.setMockSystemPaused(true);
        vm.prank(user);
        vm.expectRevert(SystemInEmergencyMode.selector);
        lm.addLiquidity(address(otherToken), 1 ether, 1 ether, 0.9 ether, 0.9 ether, block.timestamp + 1 hours);
        mockEC.setMockSystemPaused(false);
    }

    function test_Modifier_ValidateDeadline_Expired() public {
        vm.prank(user);
        vm.expectRevert(DeadlineExpired.selector);
        lm.addLiquidity(address(otherToken), 1 ether, 1 ether, 0.9 ether, 0.9 ether, block.timestamp - 1);
    }

    function test_Modifier_ValidateDeadline_TooFar() public {
        vm.prank(user);
        uint256 offset = lm.maxDeadlineOffset();
        uint256 deadline = block.timestamp + offset + 1;
        vm.expectRevert(DeadlineTooFar.selector);
        lm.addLiquidity(address(otherToken), 1 ether, 1 ether, 0.9 ether, 0.9 ether, deadline);
    }
 
    function test_AddLiquidity_Success_Refunds_And_Event() public {
        uint256 pREWAAmountDesired = 100e18;
        uint256 otherAmountDesired = 50e18;
        mockRouter.setAddLiquidityReturn(90e18, 40e18, 60e18);

        uint256 userPrewaBefore = pREWAToken.balanceOf(user);
        uint256 userOtherBefore = otherToken.balanceOf(user);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit ILiquidityManager.LiquidityAdded(address(otherToken), 90e18, 40e18, 60e18, user);
        lm.addLiquidity(address(otherToken), pREWAAmountDesired, otherAmountDesired, 80e18, 30e18, block.timestamp + 1 hours);
        
        assertEq(pREWAToken.balanceOf(user), userPrewaBefore - pREWAAmountDesired + (pREWAAmountDesired - 90e18));
        assertEq(otherToken.balanceOf(user), userOtherBefore - otherAmountDesired + (otherAmountDesired - 40e18));
    }

    function test_AddLiquidity_Revert_RouterReverts() public {
        mockRouter.setShouldRevertAddLiquidity(true);
        vm.prank(user);
        vm.expectRevert("MockRouter: AddLiquidity reverted by mock setting");
        lm.addLiquidity(address(otherToken), 1e18, 1e18, 1e18, 1e18, block.timestamp + 1 hours);
        mockRouter.setShouldRevertAddLiquidity(false);
    }
    
    function test_AddLiquidityBNB_BNBRefundFails() public {
        RevertingReceiverLMTestFull rrlmTest = new RevertingReceiverLMTestFull();
        vm.deal(address(rrlmTest), 10 ether);

        vm.prank(owner);
        pREWAToken.mintForTest(address(rrlmTest), 200e18);
        vm.prank(address(rrlmTest));
        pREWAToken.approve(address(lm), 200e18);

        mockRouter.setAddLiquidityETHReturn(100e18, 0.5 ether, 50e18);

        vm.startPrank(address(rrlmTest));
        vm.expectEmit(true, true, true, true);
        emit ILiquidityManager.BNBRefundFailed(address(rrlmTest), 0.5 ether);
        // The function should succeed even if BNB refund fails - it just emits an event
        (uint256 actualPREWA, uint256 actualBNB, uint256 lpReceived) = lm.addLiquidityBNB{value: 1 ether}(100e18, 90e18, 0.4 ether, block.timestamp + 1 hours);
        assertEq(actualPREWA, 100e18);
        assertEq(actualBNB, 0.5 ether);
        assertEq(lpReceived, 50e18);
        vm.stopPrank();
    }
    
    function test_RemoveLiquidity_Success_And_Event() public {
        address lpTokenAddress = lm.getLPTokenAddress(address(otherToken));
        MockPancakePair(payable(lpTokenAddress)).mintTokensTo(user, 10e18);

        mockRouter.setRemoveLiquidityReturn(50e18, 5e18);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit ILiquidityManager.LiquidityRemoved(address(otherToken), 50e18, 5e18, 10e18, user);
        lm.removeLiquidity(address(otherToken), 10e18, 40e18, 4e18, block.timestamp + 1 hours);
    }
    
    function test_RegisterPair_Success_NewPair() public {
        MockERC20 newTokenReg = new MockERC20();
        newTokenReg.mockInitialize("NewReg", "NREG", 18, owner);

        address pairAddress = mockFactory.getPair(address(pREWAToken), address(newTokenReg));
        if (pairAddress == address(0)) {
            pairAddress = mockFactory.createPair(address(pREWAToken), address(newTokenReg));
        }
        
        vm.etch(pairAddress, address(new MockPancakePair("a","b",address(pREWAToken),address(newTokenReg))).code);
        MockPancakePair(payable(pairAddress)).setReserves(0, 0, 0);

        vm.prank(parameterAdmin);
        assertTrue(lm.registerPair(address(newTokenReg)));

        (address pairAddr, address tokenAddrReg, bool active, , ,,) = lm.getPairInfo(address(newTokenReg));
        assertTrue(pairAddr != address(0));
        assertEq(tokenAddrReg, address(newTokenReg));
        assertTrue(active);
    }

    function test_RegisterPair_Revert_FactoryCreatePairReverts() public {
        mockFactory.setShouldRevertCreatePair(true);
        MockERC20 failToken = new MockERC20();
        failToken.mockInitialize("FAIL", "FAIL", 18, owner);

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LM_CreatePairReverted.selector, "Pair for this token could not be created.", address(failToken), "Factory createPair reverted"));
        lm.registerPair(address(failToken));
        mockFactory.setShouldRevertCreatePair(false);
    }

    function test_GetPairInfo_Correctness() public view {
        (address pairAddr, address tokenAddress, bool active, , , bool isToken0, ) = lm.getPairInfo(address(otherToken));
        assertEq(pairAddr, address(mockPairPREWAOther));
        assertEq(tokenAddress, address(otherToken));
        assertTrue(active);
        
        bool expectedIsToken0 = address(pREWAToken) < address(otherToken);
        assertEq(isToken0, expectedIsToken0);
    }
    
    function test_RecoverTokens_Success_InactiveLp() public {
        vm.prank(parameterAdmin);
        lm.setPairStatus(address(otherToken), false);
        
        address lpTokenAddress = lm.getLPTokenAddress(address(otherToken));
        vm.prank(owner);
        MockPancakePair(payable(lpTokenAddress)).mintTokensTo(address(lm), 10e18);
        
        vm.prank(owner);
        assertTrue(lm.recoverTokens(lpTokenAddress, 5e18, owner));
    }
    
    function test_ReceiveBNB_AcceptsBNB() public {
        uint256 initialBalance = address(lm).balance;
        vm.deal(user, 1 ether);
        vm.prank(user);
        (bool success, ) = address(lm).call{value: 1 ether}("");
        assertTrue(success, "LM should accept BNB");
        assertEq(address(lm).balance, initialBalance + 1 ether);
    }
}
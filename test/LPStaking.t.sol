// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/liquidity/LPStaking.sol";
import "../contracts/liquidity/interfaces/ILPStaking.sol";
import "../contracts/interfaces/IEmergencyAware.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/MockAccessControl.sol";
import "../contracts/mocks/MockEmergencyController.sol";
import "../contracts/mocks/MockLiquidityManager.sol";
import "../contracts/libraries/Constants.sol";
import "../contracts/libraries/Errors.sol";
import "../contracts/libraries/RewardMath.sol";
import "../contracts/proxy/TransparentProxy.sol";

// === Wrapper for Testing Private Owner === //
contract LPStakingTestWrapper is LPStaking {
    constructor() LPStaking() {}

    function getOwnerPublic() external view returns (address) {
        return _owner;
    }
}

contract LPStakingTest is Test {
    LPStakingTestWrapper lpStaking;
    MockERC20 pREWAToken;
    MockERC20 lpToken1;
    MockERC20 lpToken2;

    MockAccessControl mockAC;
    MockEmergencyController mockEC;
    MockLiquidityManager mockLM;

    address deployerAndTokenOwner; 
    address lpStakingActualOwner;  
    address parameterAdminLPS; 
    address user1;
    address user2;
    address emergencyControllerAdmin;
    address proxyAdmin; 
    
    uint256 constant MIN_STAKE_DURATION_LPS = Constants.MIN_STAKING_DURATION;

    function calculatePoolInputRate(uint256 aprBps) internal pure returns (uint256) {
        if (aprBps == 0) return 0;
        uint256 totalScaling = RewardMath.SCALE_RATE * RewardMath.SCALE_TIME; 
        uint256 numerator = aprBps * totalScaling;
        uint256 denominator = Constants.BPS_MAX * Constants.SECONDS_PER_YEAR;
        return numerator / denominator; 
    }

    function setUp() public {
        deployerAndTokenOwner = makeAddr("deployerAndTokenOwner"); 
        lpStakingActualOwner = makeAddr("lpStakingActualOwner");
        parameterAdminLPS = makeAddr("parameterAdminLPS");
        user1 = makeAddr("user1LPS");
        user2 = makeAddr("user2LPS");
        emergencyControllerAdmin = makeAddr("ecAdminLPS"); 
        proxyAdmin = makeAddr("proxyAdmin");

        pREWAToken = new MockERC20();
        pREWAToken.mockInitialize("pREWA Reward", "pREWAR", 18, deployerAndTokenOwner);

        lpToken1 = new MockERC20();
        lpToken1.mockInitialize("LP Token 1", "LP1", 18, deployerAndTokenOwner);
        lpToken2 = new MockERC20();
        lpToken2.mockInitialize("LP Token 2", "LP2", 18, deployerAndTokenOwner);

        mockAC = new MockAccessControl();
        vm.prank(deployerAndTokenOwner); 
        mockAC.setRole(mockAC.DEFAULT_ADMIN_ROLE(), deployerAndTokenOwner, true);
        vm.prank(deployerAndTokenOwner);
        mockAC.setRoleAdmin(mockAC.PARAMETER_ROLE(), mockAC.DEFAULT_ADMIN_ROLE());
        vm.prank(deployerAndTokenOwner);
        mockAC.setRole(mockAC.PARAMETER_ROLE(), parameterAdminLPS, true);
        vm.prank(deployerAndTokenOwner);
        mockAC.setRole(mockAC.DEFAULT_ADMIN_ROLE(), lpStakingActualOwner, true);

        mockEC = new MockEmergencyController(); 
        mockLM = new MockLiquidityManager(); 

        LPStakingTestWrapper logic = new LPStakingTestWrapper();

        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        lpStaking = LPStakingTestWrapper(payable(address(proxy)));
        lpStaking.initialize(
            address(pREWAToken),
            address(mockLM),
            lpStakingActualOwner,
            MIN_STAKE_DURATION_LPS,
            address(mockAC),
            address(mockEC)
        );
        
        vm.prank(deployerAndTokenOwner); 
        lpToken1.mintForTest(user1, 1_000_000 * 1e18); 
        vm.prank(deployerAndTokenOwner);
        lpToken1.mintForTest(user2, 1_000_000 * 1e18); 
        vm.prank(deployerAndTokenOwner);
        lpToken2.mintForTest(user1, 500_000 * 1e18);   
        
        vm.prank(deployerAndTokenOwner);
        pREWAToken.mintForTest(address(lpStaking), 10_000_000 * 1e18); 

        vm.startPrank(user1);
        lpToken1.approve(address(lpStaking), type(uint256).max);
        lpToken2.approve(address(lpStaking), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        lpToken1.approve(address(lpStaking), type(uint256).max);
        vm.stopPrank();

        vm.prank(parameterAdminLPS);
        lpStaking.addPool(address(lpToken1), 1000); 
        vm.prank(parameterAdminLPS);
        lpStaking.addTier(MIN_STAKE_DURATION_LPS, Constants.DEFAULT_REWARD_MULTIPLIER, Constants.DEFAULT_PENALTY); 
    }

    function test_Initialize_Success() public view {
        assertEq(lpStaking.getOwnerPublic(), lpStakingActualOwner);
        assertEq(address(lpStaking.accessControl()), address(mockAC));
        assertEq(address(lpStaking.emergencyController()), address(mockEC));
        assertEq(lpStaking.getRewardTokenAddress(), address(pREWAToken)); 
        assertEq(lpStaking.getLiquidityManagerAddress(), address(mockLM)); 
        
        (bool ewEnabled, uint256 ewPenalty) = lpStaking.getLPEmergencyWithdrawalSettings();
        assertEq(ewPenalty, Constants.DEFAULT_PENALTY);
        assertFalse(ewEnabled);
    }

    
    function test_Initialize_Revert_ZeroAddressesOrInvalidDuration() public {
        LPStaking logic = new LPStaking();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        LPStaking newLpStaking = LPStaking(payable(address(proxy)));

        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "initialOwner_"));
        newLpStaking.initialize(address(pREWAToken), address(mockLM), address(0), MIN_STAKE_DURATION_LPS, address(mockAC), address(mockEC));
        
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "AccessControl address for LPStaking init"));
        newLpStaking.initialize(address(pREWAToken), address(mockLM), lpStakingActualOwner, MIN_STAKE_DURATION_LPS, address(0), address(mockEC));
        
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "EmergencyController address for LPStaking init"));
        newLpStaking.initialize(address(pREWAToken), address(mockLM), lpStakingActualOwner, MIN_STAKE_DURATION_LPS, address(mockAC), address(0));

        vm.expectRevert(InvalidDuration.selector);
        newLpStaking.initialize(address(pREWAToken), address(mockLM), lpStakingActualOwner, Constants.MIN_STAKING_DURATION - 1, address(mockAC), address(mockEC));

        vm.expectRevert(InvalidDuration.selector);
        newLpStaking.initialize(address(pREWAToken), address(mockLM), lpStakingActualOwner, Constants.MAX_STAKING_DURATION + 1, address(mockAC), address(mockEC));
    }
    
    function test_Initialize_Revert_AlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        lpStaking.initialize(address(pREWAToken), address(mockLM), lpStakingActualOwner, MIN_STAKE_DURATION_LPS, address(mockAC), address(mockEC));
    }

    function test_Modifier_OnlyOwner_Fail() public {
        vm.prank(user1); 
        vm.expectRevert(NotOwner.selector);
        lpStaking.transferOwnership(user2);
    }

    function test_Modifier_OnlyParameterRole_Fail() public {
        vm.prank(user1); 
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, mockAC.PARAMETER_ROLE()));
        lpStaking.addPool(address(lpToken2), 1000);
    }
    
    function test_Modifier_WhenLpStakingNotEmergency_Reverts() public {
        vm.prank(address(mockEC));
        lpStaking.emergencyShutdown(Constants.EMERGENCY_LEVEL_CRITICAL);

        assertTrue(lpStaking.isEmergencyPaused());
        
        vm.prank(user1);
        vm.expectRevert(SystemInEmergencyMode.selector);
        lpStaking.stakeLPTokens(address(lpToken1), 10e18, 0);
    }

    function test_StakeLPTokens_Success() public {
        uint256 amount = 100e18;
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit ILPStaking.LPStaked(user1, amount, address(lpToken1), 0, 0); 
        uint256 posId = lpStaking.stakeLPTokens(address(lpToken1), amount, 0);
        assertEq(posId, 0);

        (uint256 stakedAmt, uint256 startTime, uint256 endTime,,,, bool active) = 
            lpStaking.getLPStakingPosition(user1, 0);
        assertEq(stakedAmt, amount);
        assertTrue(active);
        assertEq(startTime, block.timestamp);
        (uint256 tierDuration, , , ) = lpStaking.getTierInfo(0); 
        assertEq(endTime, block.timestamp + tierDuration);
        
        ( , uint256 poolStaked, ) = lpStaking.getPoolInfo(address(lpToken1)); 
        assertEq(poolStaked, amount);
        assertEq(lpToken1.balanceOf(address(lpStaking)), amount);
    }
    
    function test_StakeLPTokens_Revert_NotInitializedAC() public {
        LPStaking newLps = new LPStaking();
        vm.prank(user1);
        vm.expectRevert(NotInitialized.selector);
        newLps.stakeLPTokens(address(lpToken1), 100e18, 0);
    }

    function test_StakeLPTokens_Revert_ZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(LPS_StakeAmountZero.selector);
        lpStaking.stakeLPTokens(address(lpToken1), 0, 0);
    }
    function test_StakeLPTokens_Revert_TierDoesNotExist() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_TierDoesNotExist.selector, 1)); 
        lpStaking.stakeLPTokens(address(lpToken1), 100e18, 1);
    }
    function test_StakeLPTokens_Revert_MultiStakeInBlock() public {
        vm.startPrank(user1);
        lpStaking.stakeLPTokens(address(lpToken1), 10e18, 0);
        vm.expectRevert(LPS_MultiStakeInBlock.selector);
        lpStaking.stakeLPTokens(address(lpToken1), 10e18, 0);
        vm.stopPrank();
    }
    function test_StakeLPTokens_Revert_PoolNotActiveOrAdded() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_PoolNotActive.selector, address(lpToken2)));
        lpStaking.stakeLPTokens(address(lpToken2), 100e18, 0); 

        vm.prank(parameterAdminLPS);
        lpStaking.addPool(address(lpToken2), 1000);
        vm.prank(parameterAdminLPS);
        lpStaking.updatePool(address(lpToken2), 1000, false); 
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_PoolNotActive.selector, address(lpToken2)));
        lpStaking.stakeLPTokens(address(lpToken2), 100e18, 0);
    }
    function test_StakeLPTokens_Revert_TierNotActive() public {
        vm.prank(parameterAdminLPS);
        lpStaking.updateTier(0, MIN_STAKE_DURATION_LPS, 10000, 1000, false); 
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_TierNotActive.selector, 0));
        lpStaking.stakeLPTokens(address(lpToken1), 100e18, 0);
    }

    function test_UnstakeLPTokens_Success_AfterEnd_NoPenalty_ClaimsRewards() public {
        uint256 stakeAmount = 100e18;
        vm.prank(user1);
        uint256 posId = lpStaking.stakeLPTokens(address(lpToken1), stakeAmount, 0);
        
        (uint256 tierDuration, , , ) = lpStaking.getTierInfo(0);
        skip(tierDuration + 1 days);

        uint256 expectedRewards = lpStaking.calculateLPRewards(user1, posId);
        assertTrue(expectedRewards > 0);

        vm.prank(user1);
        vm.expectEmit(true, true, true, true); emit ILPStaking.LPRewardsClaimed(user1, expectedRewards, address(lpToken1), posId);
        vm.expectEmit(true, true, true, true); emit ILPStaking.LPUnstaked(user1, stakeAmount, address(lpToken1), posId, 0);
        uint256 unstaked = lpStaking.unstakeLPTokens(posId);
        assertEq(unstaked, stakeAmount);
    }
    
    function test_EmergencyWithdrawLP_Success() public {
        vm.prank(lpStakingActualOwner);
        lpStaking.setLPEmergencyWithdrawal(true, 1000); 

        uint256 stakeAmount = 100e18;
        vm.prank(user1);
        lpStaking.stakeLPTokens(address(lpToken1), stakeAmount, 0);

        uint256 penaltyAmt = (stakeAmount * 1000) / Constants.BPS_MAX;
        uint256 expectedWithdraw = stakeAmount - penaltyAmt;

        vm.prank(user1);
        vm.expectEmit(true, true, true, true); 
        emit ILPStaking.LPUnstaked(user1, expectedWithdraw, address(lpToken1), 0, penaltyAmt);
        assertEq(lpStaking.emergencyWithdrawLP(0), expectedWithdraw);
    }
    
    function test_EmergencyWithdrawLP_Revert_NotInitializedAC() public {
        LPStaking newLps = new LPStaking();
        vm.prank(user1);
        vm.expectRevert(NotInitialized.selector);
        newLps.emergencyWithdrawLP(0);
    }

    function test_ClaimLPRewards_Success() public {
        uint256 stakeAmount = 100e18;
        vm.prank(user1);
        uint256 posId = lpStaking.stakeLPTokens(address(lpToken1), stakeAmount, 0);
        (uint256 tierDuration, , , ) = lpStaking.getTierInfo(0);
        skip(tierDuration / 2);

        uint256 expectedRewards = lpStaking.calculateLPRewards(user1, posId);
        assertTrue(expectedRewards > 0);
        
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit ILPStaking.LPRewardsClaimed(user1, expectedRewards, address(lpToken1), posId);
        assertEq(lpStaking.claimLPRewards(posId), expectedRewards);
    }
    
    function test_AddPool_Success() public {
        vm.prank(parameterAdminLPS);
        uint256 aprBps = 500; 
        uint256 expectedScaledRate = calculatePoolInputRate(aprBps);

        vm.expectEmit(true, true, false, true);
        emit ILPStaking.PoolAdded(address(lpToken2), aprBps, expectedScaledRate, parameterAdminLPS);
        assertTrue(lpStaking.addPool(address(lpToken2), aprBps));
        
        (uint256 rateBpsOut,, bool isActive) = lpStaking.getPoolInfo(address(lpToken2));
        assertApproxEqAbs(rateBpsOut, aprBps, 2);
        assertTrue(isActive);
        assertTrue(lpStaking.isLPToken(address(lpToken2)));
    }
    
    function test_AddPool_Success_ZeroAPR() public {
        vm.prank(parameterAdminLPS);
        assertTrue(lpStaking.addPool(address(lpToken2), 0)); 
        (uint256 aprBpsFromInfo,,) = lpStaking.getPoolInfo(address(lpToken2)); 
        assertEq(aprBpsFromInfo, 0);
    }

    function test_AddPool_Revert_InvalidParams() public {
        vm.prank(parameterAdminLPS);
        vm.expectRevert(LPS_InvalidLPTokenAddress.selector);
        lpStaking.addPool(address(0), 1000);
        
        vm.prank(parameterAdminLPS);
        vm.expectRevert(abi.encodeWithSelector(LPS_PoolAlreadyExists.selector, address(lpToken1)));
        lpStaking.addPool(address(lpToken1), 1000); 

        vm.prank(parameterAdminLPS);
        vm.expectRevert(LPS_RewardRateZero.selector); 
        lpStaking.addPool(address(lpToken2), 50001);
    }

    function test_UpdatePool_Success() public {
        vm.prank(parameterAdminLPS);
        uint256 newAprBps = 2000; 
        uint256 expectedNewScaledRate = calculatePoolInputRate(newAprBps);
        
        vm.expectEmit(true, true, false, true);
        emit ILPStaking.PoolUpdated(address(lpToken1), newAprBps, expectedNewScaledRate, false, parameterAdminLPS);
        assertTrue(lpStaking.updatePool(address(lpToken1), newAprBps, false)); 
        
        (uint256 rateBpsOut,, bool isActive) = lpStaking.getPoolInfo(address(lpToken1));
        assertApproxEqAbs(rateBpsOut, newAprBps, 2);
        assertFalse(isActive);
    }

    function test_AddTier_Success() public {
        vm.prank(parameterAdminLPS);
        uint256 duration = MIN_STAKE_DURATION_LPS + 10 days;
        uint256 multiplier = 12000;
        uint256 penalty = 1500;
        vm.expectEmit(true, true, false, true);
        emit ILPStaking.TierAdded(1, duration, multiplier, penalty, parameterAdminLPS); 
        assertEq(lpStaking.addTier(duration, multiplier, penalty), 1);
    }

    function test_SetLPEmergencyWithdrawal_Success() public {
        vm.prank(lpStakingActualOwner); 
        vm.expectEmit(true, false, false, true);
        emit ILPStaking.LPStakingEmergencyWithdrawalSet(true, 500, lpStakingActualOwner);
        assertTrue(lpStaking.setLPEmergencyWithdrawal(true, 500));
        (bool enabled, uint256 penalty) = lpStaking.getLPEmergencyWithdrawalSettings();
        assertTrue(enabled);
        assertEq(penalty, 500);
    }
    function test_SetLPEmergencyWithdrawal_Revert_PenaltyTooHigh() public {
        vm.prank(lpStakingActualOwner);
        vm.expectRevert(abi.encodeWithSelector(LPS_PenaltyTooHigh.selector, Constants.MAX_PENALTY + 1, Constants.MAX_PENALTY));
        lpStaking.setLPEmergencyWithdrawal(true, Constants.MAX_PENALTY + 1);
    }

    function test_TransferOwnership_Revert_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert(NotOwner.selector);
        lpStaking.transferOwnership(user2);
    }

    function test_GetPoolInfo_Revert_PoolNotActiveOrInvalidLP() public {
        vm.expectRevert(LPS_InvalidLPTokenAddress.selector);
        lpStaking.getPoolInfo(address(0));
        
        vm.expectRevert(abi.encodeWithSelector(LPS_PoolNotActive.selector, address(lpToken2))); 
        lpStaking.getPoolInfo(address(lpToken2));
    }
    
    function test_GetPoolInfo_NotInitializedAC() public {
        LPStaking newLps = new LPStaking();
        vm.expectRevert(abi.encodeWithSelector(LPS_PoolNotActive.selector, address(lpToken1)));
        newLps.getPoolInfo(address(lpToken1));
    }
    
    function test_RecoverTokens_Revert_CannotRecoverStakedLP_IfIsLPToken() public {
        vm.prank(lpStakingActualOwner);
        vm.expectRevert(abi.encodeWithSelector(LPS_CannotRecoverStakedLP.selector, address(lpToken1)));
        lpStaking.recoverTokens(address(lpToken1), 10e18);
    }

    function test_CheckEmergencyStatus_CombinesPausableAndEC() public {
        vm.prank(address(mockEC));
        lpStaking.emergencyShutdown(Constants.EMERGENCY_LEVEL_CRITICAL);
        assertTrue(lpStaking.isEmergencyPaused());
        assertFalse(lpStaking.checkEmergencyStatus(bytes4(0)));
        
        setUp(); 

        mockEC.setMockSystemPaused(true);
        assertTrue(lpStaking.isEmergencyPaused());
        assertFalse(lpStaking.checkEmergencyStatus(bytes4(0)));
        mockEC.setMockSystemPaused(false);

        mockEC.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_CRITICAL);
        assertTrue(lpStaking.isEmergencyPaused());
        assertFalse(lpStaking.checkEmergencyStatus(bytes4(0)));
        mockEC.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_NORMAL);

        bytes4 stakeSelector = lpStaking.stakeLPTokens.selector;
        mockEC.setMockFunctionRestriction(stakeSelector, Constants.EMERGENCY_LEVEL_ALERT);
        mockEC.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_ALERT);
        assertFalse(lpStaking.checkEmergencyStatus(stakeSelector));
    }
    
    function test_EmergencyShutdown_Success_CriticalPauses_AlertEnablesWithdrawal() public {
        assertFalse(lpStaking.isEmergencyPaused());
        (bool ewEnabledBefore, ) = lpStaking.getLPEmergencyWithdrawalSettings();
        assertFalse(ewEnabledBefore);

        vm.prank(address(mockEC));
        vm.expectEmit(true, false, false, true); 
        emit ILPStaking.LPStakingEmergencyWithdrawalSet(true, Constants.DEFAULT_PENALTY, address(mockEC));
        vm.expectEmit(true, true, false, false); 
        emit IEmergencyAware.EmergencyShutdownHandled(Constants.EMERGENCY_LEVEL_CRITICAL, address(mockEC));

        assertTrue(lpStaking.emergencyShutdown(Constants.EMERGENCY_LEVEL_CRITICAL));
        assertTrue(lpStaking.isEmergencyPaused());
        (bool ewEnabledAfterCrit, ) = lpStaking.getLPEmergencyWithdrawalSettings();
        assertTrue(ewEnabledAfterCrit);

        setUp(); 
        assertFalse(lpStaking.isEmergencyPaused());
        (ewEnabledBefore, ) = lpStaking.getLPEmergencyWithdrawalSettings();
        assertFalse(ewEnabledBefore);
        
        vm.prank(address(mockEC));
        vm.expectEmit(true, false, false, true); 
        emit ILPStaking.LPStakingEmergencyWithdrawalSet(true, Constants.DEFAULT_PENALTY, address(mockEC));
        vm.expectEmit(true, true, false, false); 
        emit IEmergencyAware.EmergencyShutdownHandled(Constants.EMERGENCY_LEVEL_ALERT, address(mockEC));
        assertTrue(lpStaking.emergencyShutdown(Constants.EMERGENCY_LEVEL_ALERT));
        assertFalse(lpStaking.isEmergencyPaused());
        (bool ewEnabledAfterAlert, ) = lpStaking.getLPEmergencyWithdrawalSettings();
        assertTrue(ewEnabledAfterAlert);
    }
    
    function test_EmergencyShutdown_Revert_CallerNotEC() public {
        vm.prank(lpStakingActualOwner); 
        vm.expectRevert(LPS_CallerNotEmergencyController.selector);
        lpStaking.emergencyShutdown(Constants.EMERGENCY_LEVEL_CRITICAL);
    }
    function test_EmergencyShutdown_Revert_ECZero() public {
        LPStaking logic = new LPStaking();
        address newLpsOwner = makeAddr("newLpsOwner");
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        LPStaking newLps = LPStaking(payable(address(proxy)));
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "EmergencyController address for LPStaking init"));
        newLps.initialize(address(pREWAToken), address(mockLM), newLpsOwner, MIN_STAKE_DURATION_LPS, address(mockAC), address(0));
    }
}
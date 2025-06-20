// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../contracts/core/TokenStaking.sol";
import "../contracts/core/interfaces/ITokenStaking.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/MockAccessControl.sol";
import "../contracts/mocks/MockEmergencyController.sol";
import "../contracts/mocks/MockOracleIntegration.sol";
import "../contracts/libraries/Constants.sol";
import "../contracts/libraries/Errors.sol";
import "../contracts/proxy/TransparentProxy.sol";

contract TokenStakingTest is Test {
    TokenStaking tokenStaking;
    MockERC20 pREWAToken;

    MockAccessControl mockAC;
    MockEmergencyController mockEC;
    MockOracleIntegration mockOracle;

    address owner; 
    address parameterAdmin; 
    address pauser;
    address user1;
    address user2;
    address proxyAdmin;

    uint256 constant BASE_APR_BPS = 1000;
    uint256 constant MIN_DURATION = 1 days;
    uint256 constant MAX_POSITIONS = 10;
    uint256 constant TIER_0_DURATION = 1 days;
    uint256 constant TIER_0_MULTIPLIER = 10000;
    uint256 constant TIER_0_PENALTY = 2000;

    function setUp() public {
        owner = makeAddr("owner");
        parameterAdmin = makeAddr("parameterAdmin");
        pauser = makeAddr("pauser");
        user1 = makeAddr("user1TS");
        user2 = makeAddr("user2TS");
        proxyAdmin = makeAddr("proxyAdmin");

        pREWAToken = new MockERC20();
        pREWAToken.mockInitialize("pREWA Token", "PREWA", 18, owner);

        mockAC = new MockAccessControl();
        vm.prank(owner); 
        mockAC.setRole(mockAC.DEFAULT_ADMIN_ROLE(), owner, true);
        vm.prank(owner);
        mockAC.setRoleAdmin(mockAC.PARAMETER_ROLE(), mockAC.DEFAULT_ADMIN_ROLE());
        vm.prank(owner);
        mockAC.setRole(mockAC.PARAMETER_ROLE(), parameterAdmin, true);
        vm.prank(owner);
        mockAC.setRole(mockAC.PAUSER_ROLE(), pauser, true);

        mockEC = new MockEmergencyController(); 
        mockOracle = new MockOracleIntegration();

        TokenStaking logic = new TokenStaking();
        
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        tokenStaking = TokenStaking(payable(address(proxy)));
        tokenStaking.initialize(
            address(pREWAToken),
            address(mockAC),
            address(mockEC),
            address(mockOracle),
            BASE_APR_BPS, 
            MIN_DURATION,
            owner,
            MAX_POSITIONS
        );

        vm.prank(owner);
        pREWAToken.mintForTest(user1, 1_000_000 * 1e18);
        vm.prank(owner);
        pREWAToken.mintForTest(user2, 1_000_000 * 1e18);
        vm.prank(owner);
        pREWAToken.mintForTest(address(tokenStaking), 10_000_000 * 1e18);

        vm.prank(user1);
        pREWAToken.approve(address(tokenStaking), type(uint256).max);
        
        vm.prank(user2);
        pREWAToken.approve(address(tokenStaking), type(uint256).max);

        vm.prank(parameterAdmin);
        tokenStaking.addTier(TIER_0_DURATION, TIER_0_MULTIPLIER, TIER_0_PENALTY); 
    }

    function test_Initialize_Success() public view {
        assertEq(address(tokenStaking.accessControl()), address(mockAC));
        assertEq(address(tokenStaking.emergencyController()), address(mockEC));
        assertEq(address(tokenStaking.oracleIntegration()), address(mockOracle));
        assertEq(tokenStaking.owner(), owner);
        assertEq(tokenStaking.getStakingTokenAddress(), address(pREWAToken));
        assertEq(tokenStaking.getBaseAnnualPercentageRate(), BASE_APR_BPS);
        assertEq(tokenStaking.getMaxPositionsPerUser(), MAX_POSITIONS);
    }

    function test_Initialize_Revert_OnInvalidParams() public {
        TokenStaking logic = new TokenStaking();
        
        vm.expectRevert(TS_ACZero.selector);
        (new TransparentProxy(address(logic), proxyAdmin, abi.encodeWithSelector(logic.initialize.selector, address(pREWAToken), address(0), address(mockEC), address(mockOracle), 1, MIN_DURATION, owner, 1)));
        
        vm.expectRevert(TS_ECZero.selector);
        (new TransparentProxy(address(logic), proxyAdmin, abi.encodeWithSelector(logic.initialize.selector, address(pREWAToken), address(mockAC), address(0), address(mockOracle), 1, MIN_DURATION, owner, 1)));
        
        vm.expectRevert(TS_AdminZero.selector);
        (new TransparentProxy(address(logic), proxyAdmin, abi.encodeWithSelector(logic.initialize.selector, address(pREWAToken), address(mockAC), address(mockEC), address(mockOracle), 1, MIN_DURATION, address(0), 1)));

        vm.expectRevert(abi.encodeWithSelector(TS_AnnualRateTooHigh.selector, 50001));
        (new TransparentProxy(address(logic), proxyAdmin, abi.encodeWithSelector(logic.initialize.selector, address(pREWAToken), address(mockAC), address(mockEC), address(mockOracle), 50001, MIN_DURATION, owner, 1)));

        vm.expectRevert(TS_MinDurShort.selector);
        (new TransparentProxy(address(logic), proxyAdmin, abi.encodeWithSelector(logic.initialize.selector, address(pREWAToken), address(mockAC), address(mockEC), address(mockOracle), 1, Constants.MIN_STAKING_DURATION - 1, owner, 1)));
        
        vm.expectRevert(TS_MinDurLong.selector);
        (new TransparentProxy(address(logic), proxyAdmin, abi.encodeWithSelector(logic.initialize.selector, address(pREWAToken), address(mockAC), address(mockEC), address(mockOracle), 1, Constants.MAX_STAKING_DURATION + 1, owner, 1)));

        vm.expectRevert(LPS_MaxPositionsMustBePositive.selector);
        (new TransparentProxy(address(logic), proxyAdmin, abi.encodeWithSelector(logic.initialize.selector, address(pREWAToken), address(mockAC), address(mockEC), address(mockOracle), 1, MIN_DURATION, owner, 0)));
    }

    
    function test_Initialize_OracleCanBeZero() public {
        TokenStaking logic = new TokenStaking();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        TokenStaking newTs = TokenStaking(payable(address(proxy)));
        newTs.initialize(address(pREWAToken), address(mockAC), address(mockEC), address(0), BASE_APR_BPS, MIN_DURATION, owner, 1);
        assertEq(address(newTs.oracleIntegration()), address(0));
    }
    
    function test_Initialize_Revert_AlreadyInitialized() public {
        vm.prank(owner);
        vm.expectRevert("Initializable: contract is already initialized");
        tokenStaking.initialize(address(pREWAToken), address(mockAC), address(mockEC), address(mockOracle), 1, 1, owner, 1);
    }

    function test_Stake_Success() public {
        uint256 stakeAmount = 100 * 1e18;
        uint256 tierId = 0;

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit ITokenStaking.Staked(user1, stakeAmount, tierId, 0);
        uint256 positionId = tokenStaking.stake(stakeAmount, tierId);

        assertEq(positionId, 0);
        
        (uint256 amount, uint256 startTime, , , , bool active) = tokenStaking.getStakingPosition(user1, positionId);
        assertEq(amount, stakeAmount);
        assertTrue(active);
        assertEq(startTime, block.timestamp);
        assertEq(tokenStaking.totalStaked(), stakeAmount);
    }
    
    function test_Stake_Reverts() public {
        vm.prank(user1);
        vm.expectRevert(AmountIsZero.selector);
        tokenStaking.stake(0, 0);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_TierDoesNotExist.selector, 99));
        tokenStaking.stake(1e18, 99);

        vm.prank(parameterAdmin);
        tokenStaking.setMaxPositionsPerUser(1);
        vm.prank(user1);
        tokenStaking.stake(1e18, 0);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_MaxPositionsReached.selector, 1, 1));
        tokenStaking.stake(1e18, 0);
        
        setUp(); // Reset state
        vm.prank(parameterAdmin);
        tokenStaking.updateTier(0, TIER_0_DURATION, TIER_0_MULTIPLIER, TIER_0_PENALTY, false);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_TierNotActive.selector, 0));
        tokenStaking.stake(1e18, 0);

        setUp(); // Reset state
        vm.prank(user1);
        tokenStaking.stake(1e18, 0);
        vm.prank(user1);
        vm.expectRevert(LPS_MultiStakeInBlock.selector);
        tokenStaking.stake(1e18, 0);
    }
    
    function test_Unstake_Success_AfterEnd() public {
        uint256 stakeAmount = 100 * 1e18;
        vm.prank(user1);
        uint256 posId = tokenStaking.stake(stakeAmount, 0);

        (uint256 duration, , ,) = tokenStaking.getTierInfo(0);
        skip(duration + 1 days);
        
        uint256 userBalanceBefore = pREWAToken.balanceOf(user1);
        uint256 rewards = tokenStaking.calculateRewards(user1, posId);
        
        vm.prank(user1);
        uint256 unstakedAmount = tokenStaking.unstake(posId);
        
        assertEq(unstakedAmount, stakeAmount, "Unstaked amount should equal original stake");
        assertEq(pREWAToken.balanceOf(user1), userBalanceBefore + stakeAmount + rewards, "User balance after unstake is incorrect");
        
        (,,,, , bool active) = tokenStaking.getStakingPosition(user1, posId);
        assertFalse(active, "Position should be inactive after unstake");
    }

    function test_Unstake_Success_BeforeEnd_WithPenalty() public {
        uint256 stakeAmount = 100 * 1e18;
        vm.prank(user1);
        uint256 posId = tokenStaking.stake(stakeAmount, 0);

        uint256 userBalanceBefore = pREWAToken.balanceOf(user1);
        uint256 rewards = tokenStaking.calculateRewards(user1, posId);
        uint256 penalty = (stakeAmount * TIER_0_PENALTY) / Constants.BPS_MAX;
        uint256 expectedReturn = stakeAmount - penalty;

        vm.prank(user1);
        uint256 unstakedAmount = tokenStaking.unstake(posId);
        assertEq(unstakedAmount, expectedReturn);
        assertEq(pREWAToken.balanceOf(user1), userBalanceBefore + expectedReturn + rewards);
    }
    
    function test_Unstake_Reverts() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_PositionDoesNotExist.selector, 0));
        tokenStaking.unstake(0);

        vm.prank(user1);
        uint256 posId = tokenStaking.stake(1e18, 0);
        vm.prank(user1);
        tokenStaking.unstake(posId);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_PositionNotActive.selector, posId));
        tokenStaking.unstake(posId);
    }

    function test_ClaimRewards_Success() public {
        uint256 stakeAmount = 100 * 1e18;
        vm.prank(user1);
        uint256 posId = tokenStaking.stake(stakeAmount, 0);

        (uint256 duration, , ,) = tokenStaking.getTierInfo(0);
        skip(duration / 2);

        uint256 userBalanceBefore = pREWAToken.balanceOf(user1);
        uint256 rewards = tokenStaking.calculateRewards(user1, posId);
        assertTrue(rewards > 0, "Rewards should be greater than zero");

        vm.prank(user1);
        uint256 claimed = tokenStaking.claimRewards(posId);
        assertEq(claimed, rewards, "Claimed amount mismatch");
        assertEq(pREWAToken.balanceOf(user1), userBalanceBefore + rewards, "User balance after claim is incorrect");
    }

    function test_ClaimRewards_Reverts() public {
        vm.prank(user1);
        uint256 posId = tokenStaking.stake(1e18, 0);
        (uint256 duration,,,) = tokenStaking.getTierInfo(0);
        skip(duration + 1);

        vm.prank(user1);
        tokenStaking.claimRewards(posId); // First claim ok
        vm.prank(user1);
        vm.expectRevert(LPS_NoRewardsToClaim.selector);
        tokenStaking.claimRewards(posId); // Second claim should fail
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_PositionDoesNotExist.selector, 99));
        tokenStaking.claimRewards(99);
    }

    function test_EmergencyWithdraw_SuccessAndReverts() public {
        vm.prank(user1);
        vm.expectRevert(LPS_EMGWDNotEnabled.selector);
        tokenStaking.emergencyWithdraw(0);

        vm.prank(parameterAdmin);
        tokenStaking.setEmergencyWithdrawal(true, 1000);

        vm.prank(user1);
        uint256 posId = tokenStaking.stake(100e18, 0);
        
        uint256 expectedWithdrawal = 100e18 - (100e18 * 1000 / 10000);
        vm.prank(user1);
        uint256 withdrawn = tokenStaking.emergencyWithdraw(posId);
        assertEq(withdrawn, expectedWithdrawal);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_PositionNotActive.selector, posId));
        tokenStaking.emergencyWithdraw(posId);
    }

    function test_AdminFunctions_Reverts() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_DurationLessThanMin.selector, MIN_DURATION-1, MIN_DURATION));
        tokenStaking.addTier(MIN_DURATION-1, TIER_0_MULTIPLIER, TIER_0_PENALTY);
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_MultiplierTooLow.selector, Constants.MIN_REWARD_MULTIPLIER-1, Constants.MIN_REWARD_MULTIPLIER));
        tokenStaking.addTier(MIN_DURATION, Constants.MIN_REWARD_MULTIPLIER-1, TIER_0_PENALTY);
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_PenaltyTooHigh.selector, Constants.MAX_PENALTY+1, Constants.MAX_PENALTY));
        tokenStaking.addTier(MIN_DURATION, TIER_0_MULTIPLIER, Constants.MAX_PENALTY+1);

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(TS_AnnualRateTooHigh.selector, 50001));
        tokenStaking.setBaseAnnualPercentageRate(50001);
    }
    
    function test_PauseAndUnpause_SuccessAndReverts() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, mockAC.PAUSER_ROLE()));
        tokenStaking.pauseStaking();
        
        vm.prank(pauser);
        tokenStaking.pauseStaking();
        assertTrue(tokenStaking.isStakingPaused());

        vm.prank(user1);
        vm.expectRevert(ContractPaused.selector);
        tokenStaking.stake(1e18, 0);

        vm.prank(pauser);
        tokenStaking.unpauseStaking();
        assertFalse(tokenStaking.isStakingPaused());
    }

    function test_RecoverTokens_SuccessAndReverts() public {
        MockERC20 otherToken = new MockERC20();
        otherToken.mockInitialize("Other", "OTH", 18, owner);
        vm.prank(owner);
        otherToken.mintForTest(address(tokenStaking), 100e18);

        vm.prank(owner);
        tokenStaking.recoverTokens(address(otherToken), 100e18);
        assertEq(otherToken.balanceOf(owner), 100e18);

        vm.prank(owner);
        vm.expectRevert(TS_CannotUnprotectStakingToken.selector);
        tokenStaking.recoverTokens(address(pREWAToken), 1);
    }

    function test_Getters_RevertOnInvalidInput() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "userAddr for getStakingPosition"));
        tokenStaking.getStakingPosition(address(0), 0);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "userAddr for calculateRewards"));
        tokenStaking.calculateRewards(address(0), 0);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "userAddr for getPositionCount"));
        tokenStaking.getPositionCount(address(0));
    }

    function test_EmergencyAwareness() public {
        // Test normal operation
        assertTrue(tokenStaking.checkEmergencyStatus(bytes4(0)));

        // Test local pause
        vm.prank(pauser);
        tokenStaking.pauseStaking();
        assertFalse(tokenStaking.checkEmergencyStatus(bytes4(0)));
        vm.prank(pauser);
        tokenStaking.unpauseStaking();

        // Test EC pause
        mockEC.setMockSystemPaused(true);
        assertTrue(tokenStaking.isEmergencyPaused());
        assertFalse(tokenStaking.checkEmergencyStatus(bytes4(0)));
        mockEC.setMockSystemPaused(false);

        // Test EC level critical
        mockEC.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_CRITICAL);
        assertTrue(tokenStaking.isEmergencyPaused());
        assertFalse(tokenStaking.checkEmergencyStatus(bytes4(0)));
        mockEC.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_NORMAL);

        // Test EC function restriction
        bytes4 stakeSelector = tokenStaking.stake.selector;
        mockEC.setMockFunctionRestriction(stakeSelector, Constants.EMERGENCY_LEVEL_ALERT);
        mockEC.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_ALERT);
        assertFalse(tokenStaking.checkEmergencyStatus(stakeSelector));

        // Test EC failure
        mockEC.setShouldRevert(true);
        assertTrue(tokenStaking.checkEmergencyStatus(bytes4(0)));
        mockEC.setShouldRevert(false);
    }

    function test_EmergencyShutdown_FromEC() public {
        vm.prank(address(mockEC));
        tokenStaking.emergencyShutdown(Constants.EMERGENCY_LEVEL_ALERT);
        (bool enabled, ) = tokenStaking.getEmergencyWithdrawalSettings();
        assertTrue(enabled);
        assertFalse(tokenStaking.paused());

        vm.prank(address(mockEC));
        tokenStaking.emergencyShutdown(Constants.EMERGENCY_LEVEL_CRITICAL);
        assertTrue(tokenStaking.paused());
    }
    
    function test_EmergencyShutdown_RevertNotEC() public {
        vm.prank(owner);
        vm.expectRevert(TS_CallerNotEmergencyController.selector);
        tokenStaking.emergencyShutdown(1);
    }

    function test_SetEmergencyController_SuccessAndReverts() public {
        MockEmergencyController newEC = new MockEmergencyController();
        vm.prank(owner);
        tokenStaking.setEmergencyController(address(newEC));
        assertEq(address(tokenStaking.emergencyController()), address(newEC));

        vm.prank(owner);
        vm.expectRevert(TS_ECZero.selector);
        tokenStaking.setEmergencyController(address(0));

        address nonContract = makeAddr("nonContract");
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "emergencyController"));
        tokenStaking.setEmergencyController(nonContract);
    }

    function test_SetOracleIntegration_SuccessAndReverts() public {
        MockOracleIntegration newOracle = new MockOracleIntegration();
        vm.prank(owner);
        tokenStaking.setOracleIntegration(address(newOracle));
        assertEq(address(tokenStaking.oracleIntegration()), address(newOracle));

        vm.prank(owner);
        tokenStaking.setOracleIntegration(address(0));
        assertEq(address(tokenStaking.oracleIntegration()), address(0));

        address nonContract = makeAddr("nonContractOracle");
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "oracleIntegration"));
        tokenStaking.setOracleIntegration(nonContract);
    }
}
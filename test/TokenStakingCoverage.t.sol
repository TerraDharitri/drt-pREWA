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

contract TokenStakingCoverageTest is Test {
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

        // Add a basic tier
        vm.prank(parameterAdmin);
        tokenStaking.addTier(1 days, 10000, 2000);
    }

    // Test initialization edge cases
    function test_Initialize_ContractValidation() public {
        TokenStaking logic = new TokenStaking();
        
        // Test non-contract addresses
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "accessControl"));
        new TransparentProxy(address(logic), proxyAdmin, abi.encodeWithSelector(
            logic.initialize.selector,
            address(pREWAToken),
            address(0x1234), // EOA
            address(mockEC),
            address(mockOracle),
            BASE_APR_BPS,
            MIN_DURATION,
            owner,
            MAX_POSITIONS
        ));

        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "emergencyController"));
        new TransparentProxy(address(logic), proxyAdmin, abi.encodeWithSelector(
            logic.initialize.selector,
            address(pREWAToken),
            address(mockAC),
            address(0x1234), // EOA
            address(mockOracle),
            BASE_APR_BPS,
            MIN_DURATION,
            owner,
            MAX_POSITIONS
        ));

        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "oracleIntegration"));
        new TransparentProxy(address(logic), proxyAdmin, abi.encodeWithSelector(
            logic.initialize.selector,
            address(pREWAToken),
            address(mockAC),
            address(mockEC),
            address(0x1234), // EOA
            BASE_APR_BPS,
            MIN_DURATION,
            owner,
            MAX_POSITIONS
        ));
    }

    function test_Initialize_StakingTokenValidation() public {
        TokenStaking logic = new TokenStaking();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        TokenStaking newTs = TokenStaking(payable(address(proxy)));

        // Test zero staking token
        vm.expectRevert("TokenStaking: Staking token cannot be zero");
        newTs.initialize(
            address(0),
            address(mockAC),
            address(mockEC),
            address(mockOracle),
            BASE_APR_BPS,
            MIN_DURATION,
            owner,
            MAX_POSITIONS
        );
    }

    function test_Initialize_DoubleSetStakingToken() public {
        // This tests the internal _setStakingToken function's protection
        TokenStaking logic = new TokenStaking();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        TokenStaking newTs = TokenStaking(payable(address(proxy)));
        
        newTs.initialize(
            address(pREWAToken),
            address(mockAC),
            address(mockEC),
            address(mockOracle),
            BASE_APR_BPS,
            MIN_DURATION,
            owner,
            MAX_POSITIONS
        );

        // Try to initialize again should fail
        vm.expectRevert("Initializable: contract is already initialized");
        newTs.initialize(
            address(pREWAToken),
            address(mockAC),
            address(mockEC),
            address(mockOracle),
            BASE_APR_BPS,
            MIN_DURATION,
            owner,
            MAX_POSITIONS
        );
    }

    // Test modifier edge cases
    function test_OnlyParameterRole_AccessControlZero() public {
        TokenStaking newTs = new TokenStaking();
        
        vm.expectRevert(TS_ACZero.selector);
        newTs.addTier(1 days, 10000, 1000);
    }

    function test_OnlyPauserRole_AccessControlZero() public {
        TokenStaking newTs = new TokenStaking();
        
        vm.expectRevert(TS_ACZero.selector);
        newTs.pauseStaking();
    }

    // Test reward calculation edge cases
    function test_CalculateRewards_ZeroAPR() public {
        // Set APR to 0
        vm.prank(parameterAdmin);
        tokenStaking.setBaseAnnualPercentageRate(0);

        vm.prank(user1);
        uint256 posId = tokenStaking.stake(100e18, 0);

        skip(1 days);

        uint256 rewards = tokenStaking.calculateRewards(user1, posId);
        assertEq(rewards, 0);
    }

    function test_CalculateRewards_InactivePosition() public {
        vm.prank(user1);
        uint256 posId = tokenStaking.stake(100e18, 0);

        // Unstake to make position inactive
        vm.prank(user1);
        tokenStaking.unstake(posId);

        uint256 rewards = tokenStaking.calculateRewards(user1, posId);
        assertEq(rewards, 0);
    }

    function test_CalculateRewards_CurrentTimeBeforeLastClaim() public {
        vm.prank(user1);
        uint256 posId = tokenStaking.stake(100e18, 0);

        skip(1 days);

        // Claim rewards to update lastClaimTime
        vm.prank(user1);
        tokenStaking.claimRewards(posId);

        // Try to calculate rewards at the same time (should be 0)
        uint256 rewards = tokenStaking.calculateRewards(user1, posId);
        assertEq(rewards, 0);
    }

    function test_CalculateRewards_LastClaimAfterEndTime() public {
        vm.prank(user1);
        uint256 posId = tokenStaking.stake(100e18, 0);

        // Skip past end time
        skip(2 days);

        // Claim rewards (this sets lastClaimTime to current time, which is after endTime)
        vm.prank(user1);
        tokenStaking.claimRewards(posId);

        // Try to calculate rewards again (should be 0)
        uint256 rewards = tokenStaking.calculateRewards(user1, posId);
        assertEq(rewards, 0);
    }

    function test_CalculateRewards_CurrentTimeAfterEndTime() public {
        vm.prank(user1);
        uint256 posId = tokenStaking.stake(100e18, 0);

        // Skip past end time
        skip(2 days);

        // Calculate rewards - should only calculate up to endTime
        uint256 rewards = tokenStaking.calculateRewards(user1, posId);
        assertTrue(rewards > 0);
    }

    // Test tier management edge cases
    function test_AddTier_BoundaryValues() public {
        // Test minimum values
        vm.prank(parameterAdmin);
        uint256 tierId1 = tokenStaking.addTier(
            Constants.MIN_STAKING_DURATION,
            Constants.MIN_REWARD_MULTIPLIER,
            0 // Minimum penalty
        );

        // Test maximum values
        vm.prank(parameterAdmin);
        uint256 tierId2 = tokenStaking.addTier(
            Constants.MAX_STAKING_DURATION,
            Constants.MAX_REWARD_MULTIPLIER,
            Constants.MAX_PENALTY
        );

        assertEq(tierId1, 1);
        assertEq(tierId2, 2);
    }

    function test_AddTier_EdgeCaseValidation() public {
        // Test duration exactly at min boundary
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_DurationLessThanMin.selector, MIN_DURATION - 1, MIN_DURATION));
        tokenStaking.addTier(MIN_DURATION - 1, 10000, 1000);

        // Test duration exactly at max boundary
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_DurationExceedsMax.selector, Constants.MAX_STAKING_DURATION + 1, Constants.MAX_STAKING_DURATION));
        tokenStaking.addTier(Constants.MAX_STAKING_DURATION + 1, 10000, 1000);

        // Test multiplier exactly at boundaries
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_MultiplierTooLow.selector, Constants.MIN_REWARD_MULTIPLIER - 1, Constants.MIN_REWARD_MULTIPLIER));
        tokenStaking.addTier(MIN_DURATION, Constants.MIN_REWARD_MULTIPLIER - 1, 1000);

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_MultiplierTooHigh.selector, Constants.MAX_REWARD_MULTIPLIER + 1, Constants.MAX_REWARD_MULTIPLIER));
        tokenStaking.addTier(MIN_DURATION, Constants.MAX_REWARD_MULTIPLIER + 1, 1000);

        // Test penalty exactly at boundary
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_PenaltyTooHigh.selector, Constants.MAX_PENALTY + 1, Constants.MAX_PENALTY));
        tokenStaking.addTier(MIN_DURATION, 10000, Constants.MAX_PENALTY + 1);
    }

    function test_UpdateTier_AllValidations() public {
        // Test updating non-existent tier
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_TierDoesNotExist.selector, 99));
        tokenStaking.updateTier(99, MIN_DURATION, 10000, 1000, true);

        // Test all validation branches for updateTier
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_DurationLessThanMin.selector, MIN_DURATION - 1, MIN_DURATION));
        tokenStaking.updateTier(0, MIN_DURATION - 1, 10000, 1000, true);

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_DurationExceedsMax.selector, Constants.MAX_STAKING_DURATION + 1, Constants.MAX_STAKING_DURATION));
        tokenStaking.updateTier(0, Constants.MAX_STAKING_DURATION + 1, 10000, 1000, true);

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_MultiplierTooLow.selector, Constants.MIN_REWARD_MULTIPLIER - 1, Constants.MIN_REWARD_MULTIPLIER));
        tokenStaking.updateTier(0, MIN_DURATION, Constants.MIN_REWARD_MULTIPLIER - 1, 1000, true);

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_MultiplierTooHigh.selector, Constants.MAX_REWARD_MULTIPLIER + 1, Constants.MAX_REWARD_MULTIPLIER));
        tokenStaking.updateTier(0, MIN_DURATION, Constants.MAX_REWARD_MULTIPLIER + 1, 1000, true);

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_PenaltyTooHigh.selector, Constants.MAX_PENALTY + 1, Constants.MAX_PENALTY));
        tokenStaking.updateTier(0, MIN_DURATION, 10000, Constants.MAX_PENALTY + 1, true);
    }

    // Test emergency withdrawal edge cases
    function test_EmergencyWithdraw_ZeroAmountAfterPenalty() public {
        // Set emergency withdrawal with maximum penalty (50%)
        vm.prank(parameterAdmin);
        tokenStaking.setEmergencyWithdrawal(true, Constants.MAX_PENALTY);

        vm.prank(user1);
        uint256 posId = tokenStaking.stake(100e18, 0);

        vm.prank(user1);
        uint256 withdrawn = tokenStaking.emergencyWithdraw(posId);
        // With 50% penalty, user should get back approximately 50% of staked amount
        assertEq(withdrawn, 50e18); // 100e18 - 50% penalty = 50e18
    }

    function test_EmergencyWithdraw_EdgeCases() public {
        // Test non-existent position when emergency withdrawal not enabled
        vm.prank(user1);
        vm.expectRevert(LPS_EMGWDNotEnabled.selector);
        tokenStaking.emergencyWithdraw(99);

        // Enable emergency withdrawal
        vm.prank(parameterAdmin);
        tokenStaking.setEmergencyWithdrawal(true, 1000);

        // Now test non-existent position with emergency withdrawal enabled
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_PositionDoesNotExist.selector, 99));
        tokenStaking.emergencyWithdraw(99);

        vm.prank(user1);
        uint256 posId = tokenStaking.stake(100e18, 0);

        // Unstake first to make position inactive
        vm.prank(user1);
        tokenStaking.unstake(posId);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_PositionNotActive.selector, posId));
        tokenStaking.emergencyWithdraw(posId);
    }

    // Test parameter setting edge cases
    function test_SetEmergencyWithdrawal_BoundaryValues() public {
        // Test maximum penalty
        vm.prank(parameterAdmin);
        assertTrue(tokenStaking.setEmergencyWithdrawal(true, Constants.MAX_PENALTY));

        // Test penalty too high
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_PenaltyTooHigh.selector, Constants.MAX_PENALTY + 1, Constants.MAX_PENALTY));
        tokenStaking.setEmergencyWithdrawal(true, Constants.MAX_PENALTY + 1);
    }

    function test_SetBaseAnnualPercentageRate_BoundaryValues() public {
        // Test maximum APR
        vm.prank(parameterAdmin);
        assertTrue(tokenStaking.setBaseAnnualPercentageRate(50000));

        // Test APR too high
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(TS_AnnualRateTooHigh.selector, 50001));
        tokenStaking.setBaseAnnualPercentageRate(50001);
    }

    function test_SetMinStakeDuration_BoundaryValues() public {
        // Test minimum duration
        vm.prank(parameterAdmin);
        assertTrue(tokenStaking.setMinStakeDuration(Constants.MIN_STAKING_DURATION));

        // Test maximum duration
        vm.prank(parameterAdmin);
        assertTrue(tokenStaking.setMinStakeDuration(Constants.MAX_STAKING_DURATION));

        // Test too short
        vm.prank(parameterAdmin);
        vm.expectRevert(TS_MinDurShort.selector);
        tokenStaking.setMinStakeDuration(Constants.MIN_STAKING_DURATION - 1);

        // Test too long
        vm.prank(parameterAdmin);
        vm.expectRevert(TS_MinDurLong.selector);
        tokenStaking.setMinStakeDuration(Constants.MAX_STAKING_DURATION + 1);
    }

    function test_SetMaxPositionsPerUser_ZeroValue() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(LPS_MaxPositionsMustBePositive.selector);
        tokenStaking.setMaxPositionsPerUser(0);
    }

    // Test unstake edge cases
    function test_Unstake_ZeroPenalty() public {
        // Add tier with zero penalty
        vm.prank(parameterAdmin);
        uint256 tierId = tokenStaking.addTier(1 days, 10000, 0);

        vm.prank(user1);
        uint256 posId = tokenStaking.stake(100e18, tierId);

        // Unstake before end time (should have no penalty)
        vm.prank(user1);
        uint256 unstaked = tokenStaking.unstake(posId);
        assertEq(unstaked, 100e18);
    }

    function test_Unstake_ZeroRewards() public {
        vm.prank(user1);
        uint256 posId = tokenStaking.stake(100e18, 0);

        // Unstake immediately (no time passed, no rewards)
        vm.prank(user1);
        uint256 unstaked = tokenStaking.unstake(posId);
        assertTrue(unstaked > 0);
    }

    function test_Unstake_ZeroAmountAfterPenalty() public {
        // Add tier with maximum penalty (50%)
        vm.prank(parameterAdmin);
        uint256 tierId = tokenStaking.addTier(1 days, 10000, Constants.MAX_PENALTY);

        vm.prank(user1);
        uint256 posId = tokenStaking.stake(100e18, tierId);

        // Unstake before end time (50% penalty)
        vm.prank(user1);
        uint256 unstaked = tokenStaking.unstake(posId);
        // With 50% penalty, user should get back approximately 50% of staked amount
        assertEq(unstaked, 50e18); // 100e18 - 50% penalty = 50e18
    }

    // Test claim rewards edge cases
    function test_ClaimRewards_InactivePosition() public {
        vm.prank(user1);
        uint256 posId = tokenStaking.stake(100e18, 0);

        // Unstake to make position inactive
        vm.prank(user1);
        tokenStaking.unstake(posId);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_PositionNotActive.selector, posId));
        tokenStaking.claimRewards(posId);
    }

    // Test emergency shutdown edge cases
    function test_EmergencyShutdown_ECZero() public {
        TokenStaking newTs = new TokenStaking();
        
        vm.expectRevert(TS_ECZero.selector);
        newTs.emergencyShutdown(1);
    }

    function test_EmergencyShutdown_AlreadyPaused() public {
        // Pause first
        vm.prank(pauser);
        tokenStaking.pauseStaking();

        // Emergency shutdown at critical level (should not pause again)
        vm.prank(address(mockEC));
        assertTrue(tokenStaking.emergencyShutdown(Constants.EMERGENCY_LEVEL_CRITICAL));
        assertTrue(tokenStaking.paused());
    }

    function test_EmergencyShutdown_AlreadyEmergencyEnabled() public {
        // Enable emergency withdrawal first
        vm.prank(parameterAdmin);
        tokenStaking.setEmergencyWithdrawal(true, 1000);

        // Emergency shutdown at alert level (should not enable again)
        vm.prank(address(mockEC));
        assertTrue(tokenStaking.emergencyShutdown(Constants.EMERGENCY_LEVEL_ALERT));
        
        (bool enabled, ) = tokenStaking.getEmergencyWithdrawalSettings();
        assertTrue(enabled);
    }

    // Test check emergency status edge cases - removed as EC cannot be zero in initialize

    function test_CheckEmergencyStatus_ECReturnsTrue() public {
        // Set EC to return true for function restriction
        bytes4 selector = tokenStaking.stake.selector;
        mockEC.setMockFunctionRestriction(selector, Constants.EMERGENCY_LEVEL_ALERT);
        mockEC.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_ALERT);

        assertFalse(tokenStaking.checkEmergencyStatus(selector));
    }

    function test_CheckEmergencyStatus_ECThrows() public {
        // Set EC to throw on isFunctionRestricted call
        mockEC.setShouldRevert(true);

        // Should return true when EC throws
        assertTrue(tokenStaking.checkEmergencyStatus(bytes4(0)));
    }

    // Test recovery edge cases
    function test_RecoverTokens_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "tokenAddrRec for recovery"));
        tokenStaking.recoverTokens(address(0), 100e18);
    }

    function test_RecoverTokens_ZeroAmount() public {
        MockERC20 otherToken = new MockERC20();
        otherToken.mockInitialize("Other", "OTH", 18, owner);

        vm.prank(owner);
        vm.expectRevert(AmountIsZero.selector);
        tokenStaking.recoverTokens(address(otherToken), 0);
    }

    function test_RecoverTokens_InsufficientBalance() public {
        MockERC20 otherToken = new MockERC20();
        otherToken.mockInitialize("Other", "OTH", 18, owner);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, 0, 100e18));
        tokenStaking.recoverTokens(address(otherToken), 100e18);
    }

    // Test getter edge cases
    function test_GetTierInfo_NonExistentTier() public {
        vm.expectRevert(abi.encodeWithSelector(LPS_TierDoesNotExist.selector, 99));
        tokenStaking.getTierInfo(99);
    }

    function test_GetStakingPosition_NonExistentPosition() public {
        vm.expectRevert(abi.encodeWithSelector(LPS_PositionDoesNotExist.selector, 0));
        tokenStaking.getStakingPosition(user1, 0);
    }

    function test_CalculateRewards_NonExistentPosition() public {
        vm.expectRevert(abi.encodeWithSelector(LPS_PositionDoesNotExist.selector, 0));
        tokenStaking.calculateRewards(user1, 0);
    }

    // Test pause/unpause when already in desired state
    function test_PauseStaking_AlreadyPaused() public {
        vm.prank(pauser);
        tokenStaking.pauseStaking();
        assertTrue(tokenStaking.paused());

        // Try to pause again (OpenZeppelin prevents double pausing)
        vm.prank(pauser);
        vm.expectRevert("Pausable: paused");
        tokenStaking.pauseStaking();
    }

    function test_UnpauseStaking_AlreadyUnpaused() public {
        assertFalse(tokenStaking.paused());

        // Try to unpause when already unpaused (OpenZeppelin prevents double unpausing)
        vm.prank(pauser);
        vm.expectRevert("Pausable: not paused");
        tokenStaking.unpauseStaking();
    }

    // Test staking when paused by emergency controller
    function test_Stake_WhenEmergencyPaused() public {
        mockEC.setMockSystemPaused(true);

        vm.prank(user1);
        vm.expectRevert(ContractPaused.selector);
        tokenStaking.stake(100e18, 0);
    }

    function test_ClaimRewards_WhenEmergencyPaused() public {
        vm.prank(user1);
        uint256 posId = tokenStaking.stake(100e18, 0);

        skip(1 days);

        mockEC.setMockSystemPaused(true);

        vm.prank(user1);
        vm.expectRevert(ContractPaused.selector);
        tokenStaking.claimRewards(posId);
    }

    // Test comprehensive getter functions
    function test_GetterFunctions_Comprehensive() public view {
        assertEq(tokenStaking.getStakingTokenAddress(), address(pREWAToken));
        assertEq(tokenStaking.getBaseAnnualPercentageRate(), BASE_APR_BPS);
        assertEq(tokenStaking.getMaxPositionsPerUser(), MAX_POSITIONS);
        assertEq(tokenStaking.totalStaked(), 0);
        assertEq(tokenStaking.getPositionCount(user1), 0);
        
        (bool enabled, uint256 penalty) = tokenStaking.getEmergencyWithdrawalSettings();
        assertFalse(enabled);
        assertEq(penalty, Constants.DEFAULT_PENALTY);

        assertEq(tokenStaking.getEmergencyController(), address(mockEC));
        assertFalse(tokenStaking.isEmergencyPaused());
        assertFalse(tokenStaking.isStakingPaused());
    }
}
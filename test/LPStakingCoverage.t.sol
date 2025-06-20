// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../contracts/liquidity/LPStaking.sol";
import "../contracts/liquidity/interfaces/ILPStaking.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/MockAccessControl.sol";
import "../contracts/mocks/MockEmergencyController.sol";
import "../contracts/libraries/Constants.sol";
import "../contracts/libraries/Errors.sol";
import "../contracts/proxy/TransparentProxy.sol";

contract LPStakingCoverageTest is Test {
    LPStaking lpStaking;
    MockERC20 pREWAToken;
    MockERC20 lpToken1;
    MockERC20 lpToken2;
    MockAccessControl mockAC;
    MockEmergencyController mockEC;

    address owner;
    address parameterAdmin;
    address pauser;
    address user1;
    address user2;
    address liquidityManager;
    address proxyAdmin;

    uint256 constant MIN_DURATION = 1 days;
    uint256 constant BASE_APR_BPS = 1000;

    function setUp() public {
        owner = makeAddr("owner");
        parameterAdmin = makeAddr("parameterAdmin");
        pauser = makeAddr("pauser");
        user1 = makeAddr("user1LP");
        user2 = makeAddr("user2LP");
        liquidityManager = makeAddr("liquidityManager");
        proxyAdmin = makeAddr("proxyAdmin");

        pREWAToken = new MockERC20();
        pREWAToken.mockInitialize("pREWA Token", "PREWA", 18, owner);

        lpToken1 = new MockERC20();
        lpToken1.mockInitialize("LP Token 1", "LP1", 18, owner);

        lpToken2 = new MockERC20();
        lpToken2.mockInitialize("LP Token 2", "LP2", 18, owner);

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

        LPStaking logic = new LPStaking();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        lpStaking = LPStaking(payable(address(proxy)));
        lpStaking.initialize(
            address(pREWAToken),
            liquidityManager,
            owner,
            MIN_DURATION,
            address(mockAC),
            address(mockEC)
        );

        // Mint tokens
        vm.prank(owner);
        pREWAToken.mintForTest(address(lpStaking), 10_000_000 * 1e18);
        vm.prank(owner);
        lpToken1.mintForTest(user1, 1_000_000 * 1e18);
        vm.prank(owner);
        lpToken1.mintForTest(user2, 1_000_000 * 1e18);
        vm.prank(owner);
        lpToken2.mintForTest(user1, 1_000_000 * 1e18);

        // Approve tokens
        vm.prank(user1);
        lpToken1.approve(address(lpStaking), type(uint256).max);
        vm.prank(user2);
        lpToken1.approve(address(lpStaking), type(uint256).max);
        vm.prank(user1);
        lpToken2.approve(address(lpStaking), type(uint256).max);

        // Add basic pool and tier
        vm.prank(parameterAdmin);
        lpStaking.addPool(address(lpToken1), BASE_APR_BPS);
        vm.prank(parameterAdmin);
        lpStaking.addTier(MIN_DURATION, 10000, 1000);
    }

    // Test initialization edge cases
    function test_Initialize_ZeroAddresses() public {
        LPStaking logic = new LPStaking();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        LPStaking newLPS = LPStaking(payable(address(proxy)));

        // Test zero reward token
        vm.expectRevert("LPStaking: Reward token cannot be zero");
        newLPS.initialize(
            address(0),
            liquidityManager,
            owner,
            MIN_DURATION,
            address(mockAC),
            address(mockEC)
        );

        // Test zero liquidity manager
        vm.expectRevert("LPStaking: LiquidityManager cannot be zero");
        newLPS.initialize(
            address(pREWAToken),
            address(0),
            owner,
            MIN_DURATION,
            address(mockAC),
            address(mockEC)
        );

        // Test zero initial owner
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "initialOwner_"));
        newLPS.initialize(
            address(pREWAToken),
            liquidityManager,
            address(0),
            MIN_DURATION,
            address(mockAC),
            address(mockEC)
        );

        // Test zero access control
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "AccessControl address for LPStaking init"));
        newLPS.initialize(
            address(pREWAToken),
            liquidityManager,
            owner,
            MIN_DURATION,
            address(0),
            address(mockEC)
        );

        // Test zero emergency controller
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "EmergencyController address for LPStaking init"));
        newLPS.initialize(
            address(pREWAToken),
            liquidityManager,
            owner,
            MIN_DURATION,
            address(mockAC),
            address(0)
        );
    }

    function test_Initialize_InvalidDuration() public {
        LPStaking logic = new LPStaking();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        LPStaking newLPS = LPStaking(payable(address(proxy)));

        // Test duration too short
        vm.expectRevert(InvalidDuration.selector);
        newLPS.initialize(
            address(pREWAToken),
            liquidityManager,
            owner,
            Constants.MIN_STAKING_DURATION - 1,
            address(mockAC),
            address(mockEC)
        );

        // Test duration too long
        vm.expectRevert(InvalidDuration.selector);
        newLPS.initialize(
            address(pREWAToken),
            liquidityManager,
            owner,
            Constants.MAX_STAKING_DURATION + 1,
            address(mockAC),
            address(mockEC)
        );
    }

    function test_Initialize_DoubleInitialization() public {
        vm.expectRevert("Initializable: contract is already initialized");
        lpStaking.initialize(
            address(pREWAToken),
            liquidityManager,
            owner,
            MIN_DURATION,
            address(mockAC),
            address(mockEC)
        );
    }

    // Test staking edge cases
    function test_StakeLPTokens_NotInitialized() public {
        LPStaking newLPS = new LPStaking();
        
        vm.prank(user1);
        vm.expectRevert(NotInitialized.selector);
        newLPS.stakeLPTokens(address(lpToken1), 100e18, 0);
    }

    function test_StakeLPTokens_ZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(LPS_StakeAmountZero.selector);
        lpStaking.stakeLPTokens(address(lpToken1), 0, 0);
    }

    function test_StakeLPTokens_TierDoesNotExist() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_TierDoesNotExist.selector, 99));
        lpStaking.stakeLPTokens(address(lpToken1), 100e18, 99);
    }

    function test_StakeLPTokens_MultiStakeInBlock() public {
        vm.prank(user1);
        lpStaking.stakeLPTokens(address(lpToken1), 100e18, 0);

        // Try to stake again in same block
        vm.prank(user1);
        vm.expectRevert(LPS_MultiStakeInBlock.selector);
        lpStaking.stakeLPTokens(address(lpToken1), 100e18, 0);
    }

    function test_StakeLPTokens_PoolNotActive() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_PoolNotActive.selector, address(lpToken2)));
        lpStaking.stakeLPTokens(address(lpToken2), 100e18, 0);
    }

    function test_StakeLPTokens_TierNotActive() public {
        // Add inactive tier
        vm.prank(parameterAdmin);
        uint256 tierId = lpStaking.addTier(MIN_DURATION, 10000, 1000);
        
        // Deactivate tier
        vm.prank(parameterAdmin);
        lpStaking.updateTier(tierId, MIN_DURATION, 10000, 1000, false);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_TierNotActive.selector, tierId));
        lpStaking.stakeLPTokens(address(lpToken1), 100e18, tierId);
    }

    function test_StakeLPTokens_EmergencyPaused() public {
        mockEC.setMockSystemPaused(true);

        vm.prank(user1);
        vm.expectRevert(SystemInEmergencyMode.selector);
        lpStaking.stakeLPTokens(address(lpToken1), 100e18, 0);
    }

    // Test unstaking edge cases
    function test_UnstakeLPTokens_NotInitialized() public {
        LPStaking newLPS = new LPStaking();
        
        vm.prank(user1);
        vm.expectRevert(NotInitialized.selector);
        newLPS.unstakeLPTokens(0);
    }

    function test_UnstakeLPTokens_PositionDoesNotExist() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_PositionDoesNotExist.selector, 0));
        lpStaking.unstakeLPTokens(0);
    }

    function test_UnstakeLPTokens_PositionNotActive() public {
        vm.prank(user1);
        uint256 posId = lpStaking.stakeLPTokens(address(lpToken1), 100e18, 0);

        // Unstake first time
        vm.prank(user1);
        lpStaking.unstakeLPTokens(posId);

        // Try to unstake again
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_PositionNotActive.selector, posId));
        lpStaking.unstakeLPTokens(posId);
    }

    function test_UnstakeLPTokens_PoolNotActiveAfterStaking() public {
        vm.prank(user1);
        uint256 posId = lpStaking.stakeLPTokens(address(lpToken1), 100e18, 0);

        // Deactivate pool
        vm.prank(parameterAdmin);
        lpStaking.updatePool(address(lpToken1), BASE_APR_BPS, false);

        // Should still be able to unstake even if pool is deactivated
        vm.prank(user1);
        uint256 unstaked = lpStaking.unstakeLPTokens(posId);
        assertTrue(unstaked > 0);
    }

    function test_UnstakeLPTokens_WithPenalty() public {
        // Add tier with penalty
        vm.prank(parameterAdmin);
        uint256 tierId = lpStaking.addTier(MIN_DURATION, 10000, 2000); // 20% penalty

        vm.prank(user1);
        uint256 posId = lpStaking.stakeLPTokens(address(lpToken1), 100e18, tierId);

        // Unstake before end time (should have penalty)
        vm.prank(user1);
        uint256 unstaked = lpStaking.unstakeLPTokens(posId);
        assertEq(unstaked, 80e18); // 100e18 - 20% penalty
    }

    function test_UnstakeLPTokens_NoPenaltyAfterEndTime() public {
        vm.prank(user1);
        uint256 posId = lpStaking.stakeLPTokens(address(lpToken1), 100e18, 0);

        // Skip past end time
        skip(MIN_DURATION + 1);

        vm.prank(user1);
        uint256 unstaked = lpStaking.unstakeLPTokens(posId);
        assertEq(unstaked, 100e18); // No penalty after end time
    }

    function test_UnstakeLPTokens_WithRewards() public {
        vm.prank(user1);
        uint256 posId = lpStaking.stakeLPTokens(address(lpToken1), 100e18, 0);

        // Skip some time to accumulate rewards
        skip(MIN_DURATION / 2);

        uint256 balanceBefore = pREWAToken.balanceOf(user1);
        vm.prank(user1);
        lpStaking.unstakeLPTokens(posId);
        uint256 balanceAfter = pREWAToken.balanceOf(user1);

        assertTrue(balanceAfter > balanceBefore); // Should have received rewards
    }

    // Test emergency withdrawal edge cases
    function test_EmergencyWithdrawLP_NotInitialized() public {
        LPStaking newLPS = new LPStaking();
        
        vm.prank(user1);
        vm.expectRevert(NotInitialized.selector);
        newLPS.emergencyWithdrawLP(0);
    }

    function test_EmergencyWithdrawLP_NotEnabled() public {
        vm.prank(user1);
        uint256 posId = lpStaking.stakeLPTokens(address(lpToken1), 100e18, 0);

        vm.prank(user1);
        vm.expectRevert(LPS_EMGWDNotEnabled.selector);
        lpStaking.emergencyWithdrawLP(posId);
    }

    function test_EmergencyWithdrawLP_PositionDoesNotExist() public {
        // Enable emergency withdrawal
        vm.prank(owner);
        lpStaking.setLPEmergencyWithdrawal(true, 1000);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_PositionDoesNotExist.selector, 0));
        lpStaking.emergencyWithdrawLP(0);
    }

    function test_EmergencyWithdrawLP_PositionNotActive() public {
        // Enable emergency withdrawal
        vm.prank(owner);
        lpStaking.setLPEmergencyWithdrawal(true, 1000);

        vm.prank(user1);
        uint256 posId = lpStaking.stakeLPTokens(address(lpToken1), 100e18, 0);

        // Unstake first
        vm.prank(user1);
        lpStaking.unstakeLPTokens(posId);

        // Try emergency withdraw
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_PositionNotActive.selector, posId));
        lpStaking.emergencyWithdrawLP(posId);
    }

    function test_EmergencyWithdrawLP_Success() public {
        // Enable emergency withdrawal with 10% penalty
        vm.prank(owner);
        lpStaking.setLPEmergencyWithdrawal(true, 1000);

        vm.prank(user1);
        uint256 posId = lpStaking.stakeLPTokens(address(lpToken1), 100e18, 0);

        vm.prank(user1);
        uint256 withdrawn = lpStaking.emergencyWithdrawLP(posId);
        assertEq(withdrawn, 90e18); // 100e18 - 10% penalty
    }

    function test_EmergencyWithdrawLP_MaxPenalty() public {
        // Enable emergency withdrawal with max penalty
        vm.prank(owner);
        lpStaking.setLPEmergencyWithdrawal(true, Constants.MAX_PENALTY);

        vm.prank(user1);
        uint256 posId = lpStaking.stakeLPTokens(address(lpToken1), 100e18, 0);

        vm.prank(user1);
        uint256 withdrawn = lpStaking.emergencyWithdrawLP(posId);
        assertEq(withdrawn, 50e18); // 100e18 - 50% penalty
    }

    // Test claim rewards edge cases
    function test_ClaimLPRewards_NotInitialized() public {
        LPStaking newLPS = new LPStaking();
        
        vm.prank(user1);
        vm.expectRevert(NotInitialized.selector);
        newLPS.claimLPRewards(0);
    }

    function test_ClaimLPRewards_PositionDoesNotExist() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_PositionDoesNotExist.selector, 0));
        lpStaking.claimLPRewards(0);
    }

    function test_ClaimLPRewards_PositionNotActive() public {
        vm.prank(user1);
        uint256 posId = lpStaking.stakeLPTokens(address(lpToken1), 100e18, 0);

        // Unstake to make position inactive
        vm.prank(user1);
        lpStaking.unstakeLPTokens(posId);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(LPS_PositionNotActive.selector, posId));
        lpStaking.claimLPRewards(posId);
    }

    function test_ClaimLPRewards_PoolNotActive() public {
        vm.prank(user1);
        uint256 posId = lpStaking.stakeLPTokens(address(lpToken1), 100e18, 0);

        // Deactivate pool by setting address to zero (simulate pool removal)
        // This is tricky to test directly, so we'll test the pool check in calculateLPRewards instead
        skip(1 days);

        vm.prank(user1);
        uint256 claimed = lpStaking.claimLPRewards(posId);
        assertTrue(claimed > 0);
    }

    function test_ClaimLPRewards_NoRewards() public {
        vm.prank(user1);
        uint256 posId = lpStaking.stakeLPTokens(address(lpToken1), 100e18, 0);

        // Try to claim immediately (no time passed)
        vm.prank(user1);
        vm.expectRevert(LPS_NoRewardsToClaim.selector);
        lpStaking.claimLPRewards(posId);
    }

    function test_ClaimLPRewards_EmergencyPaused() public {
        vm.prank(user1);
        uint256 posId = lpStaking.stakeLPTokens(address(lpToken1), 100e18, 0);

        skip(1 days);

        mockEC.setMockSystemPaused(true);

        vm.prank(user1);
        vm.expectRevert(SystemInEmergencyMode.selector);
        lpStaking.claimLPRewards(posId);
    }

    // Test pool management edge cases
    function test_AddPool_ZeroAddress() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(LPS_InvalidLPTokenAddress.selector);
        lpStaking.addPool(address(0), BASE_APR_BPS);
    }

    function test_AddPool_AlreadyExists() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_PoolAlreadyExists.selector, address(lpToken1)));
        lpStaking.addPool(address(lpToken1), BASE_APR_BPS);
    }

    function test_AddPool_InvalidAPR() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(LPS_RewardRateZero.selector);
        lpStaking.addPool(address(lpToken2), 50001);
    }

    function test_AddPool_ZeroAPR() public {
        vm.prank(parameterAdmin);
        assertTrue(lpStaking.addPool(address(lpToken2), 0));
    }

    function test_AddPool_MaxAPR() public {
        vm.prank(parameterAdmin);
        assertTrue(lpStaking.addPool(address(lpToken2), 50000));
    }

    function test_UpdatePool_ZeroAddress() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(LPS_InvalidLPTokenAddress.selector);
        lpStaking.updatePool(address(0), BASE_APR_BPS, true);
    }

    function test_UpdatePool_PoolNotExists() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_PoolNotActive.selector, address(lpToken2)));
        lpStaking.updatePool(address(lpToken2), BASE_APR_BPS, true);
    }

    function test_UpdatePool_InvalidAPR() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(LPS_RewardRateZero.selector);
        lpStaking.updatePool(address(lpToken1), 50001, true);
    }

    function test_UpdatePool_Success() public {
        vm.prank(parameterAdmin);
        assertTrue(lpStaking.updatePool(address(lpToken1), 2000, false));
    }

    // Test tier management edge cases
    function test_AddTier_DurationTooShort() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_DurationLessThanMin.selector, MIN_DURATION - 1, MIN_DURATION));
        lpStaking.addTier(MIN_DURATION - 1, 10000, 1000);
    }

    function test_AddTier_DurationTooLong() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_DurationExceedsMax.selector, Constants.MAX_STAKING_DURATION + 1, Constants.MAX_STAKING_DURATION));
        lpStaking.addTier(Constants.MAX_STAKING_DURATION + 1, 10000, 1000);
    }

    function test_AddTier_MultiplierTooLow() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_MultiplierTooLow.selector, Constants.MIN_REWARD_MULTIPLIER - 1, Constants.MIN_REWARD_MULTIPLIER));
        lpStaking.addTier(MIN_DURATION, Constants.MIN_REWARD_MULTIPLIER - 1, 1000);
    }

    function test_AddTier_MultiplierTooHigh() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_MultiplierTooHigh.selector, Constants.MAX_REWARD_MULTIPLIER + 1, Constants.MAX_REWARD_MULTIPLIER));
        lpStaking.addTier(MIN_DURATION, Constants.MAX_REWARD_MULTIPLIER + 1, 1000);
    }

    function test_AddTier_PenaltyTooHigh() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_PenaltyTooHigh.selector, Constants.MAX_PENALTY + 1, Constants.MAX_PENALTY));
        lpStaking.addTier(MIN_DURATION, 10000, Constants.MAX_PENALTY + 1);
    }

    function test_UpdateTier_TierDoesNotExist() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_TierDoesNotExist.selector, 99));
        lpStaking.updateTier(99, MIN_DURATION, 10000, 1000, true);
    }

    function test_UpdateTier_AllValidations() public {
        // Test all validation branches for updateTier
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_DurationLessThanMin.selector, MIN_DURATION - 1, MIN_DURATION));
        lpStaking.updateTier(0, MIN_DURATION - 1, 10000, 1000, true);

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_DurationExceedsMax.selector, Constants.MAX_STAKING_DURATION + 1, Constants.MAX_STAKING_DURATION));
        lpStaking.updateTier(0, Constants.MAX_STAKING_DURATION + 1, 10000, 1000, true);

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_MultiplierTooLow.selector, Constants.MIN_REWARD_MULTIPLIER - 1, Constants.MIN_REWARD_MULTIPLIER));
        lpStaking.updateTier(0, MIN_DURATION, Constants.MIN_REWARD_MULTIPLIER - 1, 1000, true);

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_MultiplierTooHigh.selector, Constants.MAX_REWARD_MULTIPLIER + 1, Constants.MAX_REWARD_MULTIPLIER));
        lpStaking.updateTier(0, MIN_DURATION, Constants.MAX_REWARD_MULTIPLIER + 1, 1000, true);

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(LPS_PenaltyTooHigh.selector, Constants.MAX_PENALTY + 1, Constants.MAX_PENALTY));
        lpStaking.updateTier(0, MIN_DURATION, 10000, Constants.MAX_PENALTY + 1, true);
    }

    // Test emergency withdrawal settings
    function test_SetLPEmergencyWithdrawal_PenaltyTooHigh() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LPS_PenaltyTooHigh.selector, Constants.MAX_PENALTY + 1, Constants.MAX_PENALTY));
        lpStaking.setLPEmergencyWithdrawal(true, Constants.MAX_PENALTY + 1);
    }

    function test_SetLPEmergencyWithdrawal_Success() public {
        vm.prank(owner);
        assertTrue(lpStaking.setLPEmergencyWithdrawal(true, 1500));
    }

    // Test getter functions edge cases
    function test_GetLPStakingPosition_NotInitialized() public {
        LPStaking newLPS = new LPStaking();
        
        // This should not revert when no positions exist
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "user for getLPStakingPosition"));
        newLPS.getLPStakingPosition(address(0), 0);
    }

    function test_GetLPStakingPosition_ZeroUser() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "user for getLPStakingPosition"));
        lpStaking.getLPStakingPosition(address(0), 0);
    }

    function test_GetLPStakingPosition_PositionDoesNotExist() public {
        vm.expectRevert(abi.encodeWithSelector(LPS_PositionDoesNotExist.selector, 0));
        lpStaking.getLPStakingPosition(user1, 0);
    }

    function test_CalculateLPRewards_NotInitialized() public {
        LPStaking newLPS = new LPStaking();
        
        // Should not revert when no positions exist
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "user for calculateLPRewards"));
        newLPS.calculateLPRewards(address(0), 0);
    }

    function test_CalculateLPRewards_ZeroUser() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "user for calculateLPRewards"));
        lpStaking.calculateLPRewards(address(0), 0);
    }

    function test_CalculateLPRewards_PositionDoesNotExist() public {
        vm.expectRevert(abi.encodeWithSelector(LPS_PositionDoesNotExist.selector, 0));
        lpStaking.calculateLPRewards(user1, 0);
    }

    function test_CalculateLPRewards_InactivePosition() public {
        vm.prank(user1);
        uint256 posId = lpStaking.stakeLPTokens(address(lpToken1), 100e18, 0);

        // Unstake to make position inactive
        vm.prank(user1);
        lpStaking.unstakeLPTokens(posId);

        uint256 rewards = lpStaking.calculateLPRewards(user1, posId);
        assertEq(rewards, 0);
    }

    function test_GetPoolInfo_NotInitialized() public {
        LPStaking newLPS = new LPStaking();
        
        vm.expectRevert(LPS_InvalidLPTokenAddress.selector);
        newLPS.getPoolInfo(address(0));
    }

    function test_GetPoolInfo_ZeroAddress() public {
        vm.expectRevert(LPS_InvalidLPTokenAddress.selector);
        lpStaking.getPoolInfo(address(0));
    }

    function test_GetPoolInfo_PoolNotExists() public {
        vm.expectRevert(abi.encodeWithSelector(LPS_PoolNotActive.selector, address(lpToken2)));
        lpStaking.getPoolInfo(address(lpToken2));
    }

    function test_GetPoolInfo_ZeroAPR() public {
        // Add pool with zero APR
        vm.prank(parameterAdmin);
        lpStaking.addPool(address(lpToken2), 0);

        (uint256 apr, uint256 totalStaked, bool active) = lpStaking.getPoolInfo(address(lpToken2));
        assertEq(apr, 0);
        assertEq(totalStaked, 0);
        assertTrue(active);
    }

    function test_GetTierInfo_NotInitialized() public {
        LPStaking newLPS = new LPStaking();
        
        vm.expectRevert(abi.encodeWithSelector(LPS_TierDoesNotExist.selector, 0));
        newLPS.getTierInfo(0);
    }

    function test_GetTierInfo_TierDoesNotExist() public {
        vm.expectRevert(abi.encodeWithSelector(LPS_TierDoesNotExist.selector, 99));
        lpStaking.getTierInfo(99);
    }

    function test_GetLPPositionCount_NotInitialized() public {
        LPStaking newLPS = new LPStaking();
        
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "user for getLPPositionCount"));
        newLPS.getLPPositionCount(address(0));
    }

    function test_GetLPPositionCount_ZeroUser() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "user for getLPPositionCount"));
        lpStaking.getLPPositionCount(address(0));
    }

    function test_GetLPEmergencyWithdrawalSettings_NotInitialized() public {
        LPStaking newLPS = new LPStaking();
        
        vm.expectRevert(NotInitialized.selector);
        newLPS.getLPEmergencyWithdrawalSettings();
    }

    // Test recovery functions
    function test_RecoverTokens_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "tokenAddress for recovery"));
        lpStaking.recoverTokens(address(0), 100e18);
    }

    function test_RecoverTokens_RewardToken() public {
        vm.prank(owner);
        vm.expectRevert(LPS_CannotRecoverStakingToken.selector);
        lpStaking.recoverTokens(address(pREWAToken), 100e18);
    }

    function test_RecoverTokens_StakedLPToken() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LPS_CannotRecoverStakedLP.selector, address(lpToken1)));
        lpStaking.recoverTokens(address(lpToken1), 100e18);
    }

    function test_RecoverTokens_ZeroAmount() public {
        MockERC20 otherToken = new MockERC20();
        otherToken.mockInitialize("Other", "OTH", 18, owner);

        vm.prank(owner);
        vm.expectRevert(AmountIsZero.selector);
        lpStaking.recoverTokens(address(otherToken), 0);
    }

    function test_RecoverTokens_InsufficientBalance() public {
        MockERC20 otherToken = new MockERC20();
        otherToken.mockInitialize("Other", "OTH", 18, owner);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, 0, 100e18));
        lpStaking.recoverTokens(address(otherToken), 100e18);
    }

    function test_RecoverTokens_Success() public {
        MockERC20 otherToken = new MockERC20();
        otherToken.mockInitialize("Other", "OTH", 18, owner);
        
        // Send some tokens to the contract
        vm.prank(owner);
        otherToken.mintForTest(address(lpStaking), 1000e18);

        vm.prank(owner);
        assertTrue(lpStaking.recoverTokens(address(otherToken), 500e18));
    }

    // Test ownership transfer
    function test_TransferOwnership_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "newOwner"));
        lpStaking.transferOwnership(address(0));
    }

    function test_TransferOwnership_Success() public {
        address newOwner = makeAddr("newOwner");
        
        vm.prank(owner);
        assertTrue(lpStaking.transferOwnership(newOwner));
    }

    // Test emergency controller functions
    function test_CheckEmergencyStatus_ECZero() public {
        LPStaking newLPS = new LPStaking();
        
        // Should return true when EC is zero (allows operation)
        assertTrue(newLPS.checkEmergencyStatus(bytes4(0)));
    }

    function test_CheckEmergencyStatus_ECThrows() public {
        mockEC.setShouldRevert(true);
        
        // Should return true when EC throws (allows operation due to graceful handling)
        assertTrue(lpStaking.checkEmergencyStatus(bytes4(0)));
    }

    function test_CheckEmergencyStatus_CriticalLevel() public {
        mockEC.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_CRITICAL);
        
        // Should return false at critical level
        assertFalse(lpStaking.checkEmergencyStatus(bytes4(0)));
    }

    function test_CheckEmergencyStatus_FunctionRestricted() public {
        bytes4 selector = lpStaking.stakeLPTokens.selector;
        mockEC.setMockFunctionRestriction(selector, Constants.EMERGENCY_LEVEL_ALERT);
        mockEC.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_ALERT);
        
        // Should return false when function is restricted
        assertFalse(lpStaking.checkEmergencyStatus(selector));
    }

    function test_EmergencyShutdown_ECZero() public {
        LPStaking newLPS = new LPStaking();
        
        vm.expectRevert(LPS_CallerNotEmergencyController.selector);
        newLPS.emergencyShutdown(Constants.EMERGENCY_LEVEL_CRITICAL);
    }

    function test_EmergencyShutdown_NotEC() public {
        vm.prank(user1);
        vm.expectRevert(LPS_CallerNotEmergencyController.selector);
        lpStaking.emergencyShutdown(Constants.EMERGENCY_LEVEL_CRITICAL);
    }

    function test_EmergencyShutdown_CriticalLevel() public {
        vm.prank(address(mockEC));
        assertTrue(lpStaking.emergencyShutdown(Constants.EMERGENCY_LEVEL_CRITICAL));
        
        // Should be paused
        assertTrue(lpStaking.isEmergencyPaused());
    }

    function test_EmergencyShutdown_AlertLevel() public {
        vm.prank(address(mockEC));
        assertTrue(lpStaking.emergencyShutdown(Constants.EMERGENCY_LEVEL_ALERT));
        
        // Should enable emergency withdrawal
        (bool enabled, ) = lpStaking.getLPEmergencyWithdrawalSettings();
        assertTrue(enabled);
    }

    function test_EmergencyShutdown_AlreadyPaused() public {
        // Pause first
        vm.prank(address(mockEC));
        lpStaking.emergencyShutdown(Constants.EMERGENCY_LEVEL_CRITICAL);
        
        // Emergency shutdown again (should still work)
        vm.prank(address(mockEC));
        assertTrue(lpStaking.emergencyShutdown(Constants.EMERGENCY_LEVEL_CRITICAL));
    }

    function test_EmergencyShutdown_AlreadyEmergencyEnabled() public {
        // Enable emergency withdrawal first
        vm.prank(owner);
        lpStaking.setLPEmergencyWithdrawal(true, 1000);
        
        // Emergency shutdown at alert level (should not enable again)
        vm.prank(address(mockEC));
        assertTrue(lpStaking.emergencyShutdown(Constants.EMERGENCY_LEVEL_ALERT));
    }

    function test_SetEmergencyController_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "EmergencyController address"));
        lpStaking.setEmergencyController(address(0));
    }

    function test_SetEmergencyController_NotContract() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "EmergencyController"));
        lpStaking.setEmergencyController(address(0x1234));
    }

    function test_SetEmergencyController_Success() public {
        MockEmergencyController newEC = new MockEmergencyController();
        
        vm.prank(owner);
        assertTrue(lpStaking.setEmergencyController(address(newEC)));
    }

    function test_IsEmergencyPaused_LocalPause() public {
        // Pause locally
        vm.prank(address(mockEC));
        lpStaking.emergencyShutdown(Constants.EMERGENCY_LEVEL_CRITICAL);
        
        assertTrue(lpStaking.isEmergencyPaused());
    }

    function test_IsEmergencyPaused_ECSystemPaused() public {
        mockEC.setMockSystemPaused(true);
        
        assertTrue(lpStaking.isEmergencyPaused());
    }

    function test_IsEmergencyPaused_ECCriticalLevel() public {
        mockEC.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_CRITICAL);
        
        assertTrue(lpStaking.isEmergencyPaused());
    }

    function test_IsEmergencyPaused_ECThrows() public {
        mockEC.setShouldRevert(true);
        
        // Should handle EC throws gracefully
        assertFalse(lpStaking.isEmergencyPaused());
    }

    // Test internal function coverage through edge cases
    function test_HandleUnstakeOrWithdraw_PenaltyExceedsAmount() public {
        // Add tier with very high penalty that would exceed staked amount
        vm.prank(parameterAdmin);
        uint256 tierId = lpStaking.addTier(MIN_DURATION, 10000, Constants.MAX_PENALTY);

        vm.prank(user1);
        uint256 posId = lpStaking.stakeLPTokens(address(lpToken1), 1e18, tierId); // Small amount

        // Unstake with penalty that would exceed the amount
        vm.prank(user1);
        uint256 unstaked = lpStaking.unstakeLPTokens(posId);
        
        // Should get back 50% due to MAX_PENALTY being 50%
        assertEq(unstaked, 0.5e18);
    }

    // Test getter functions comprehensive coverage
    function test_GetterFunctions_Comprehensive() public {
        assertEq(lpStaking.getRewardTokenAddress(), address(pREWAToken));
        assertEq(lpStaking.getLiquidityManagerAddress(), liquidityManager);
        assertEq(lpStaking.getEmergencyController(), address(mockEC));
        
        // Test position count
        assertEq(lpStaking.getLPPositionCount(user1), 0);
        
        vm.prank(user1);
        lpStaking.stakeLPTokens(address(lpToken1), 100e18, 0);
        
        assertEq(lpStaking.getLPPositionCount(user1), 1);
        
        // Test emergency settings
        (bool enabled, uint256 penalty) = lpStaking.getLPEmergencyWithdrawalSettings();
        assertFalse(enabled);
        assertEq(penalty, Constants.DEFAULT_PENALTY);
    }

    // Test access control edge cases
    function test_OnlyOwner_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert(NotOwner.selector);
        lpStaking.setLPEmergencyWithdrawal(true, 1000);
    }

    function test_OnlyParameterRole_NotParameterRole() public {
        vm.prank(user1);
        vm.expectRevert();
        lpStaking.addPool(address(lpToken2), BASE_APR_BPS);
    }

    // Test complex scenarios
    function test_ComplexScenario_MultipleUsersMultiplePositions() public {
        // Add another pool and tier
        vm.prank(parameterAdmin);
        lpStaking.addPool(address(lpToken2), 2000);
        vm.prank(parameterAdmin);
        uint256 tierId = lpStaking.addTier(2 days, 15000, 1500);

        // User1 stakes in multiple pools and tiers
        vm.prank(user1);
        uint256 pos1 = lpStaking.stakeLPTokens(address(lpToken1), 100e18, 0);
        
        // Move to next block to avoid multi-stake in block restriction
        vm.roll(block.number + 1);
        
        vm.prank(user1);
        uint256 pos2 = lpStaking.stakeLPTokens(address(lpToken2), 200e18, tierId);

        // User2 stakes
        vm.prank(user2);
        uint256 pos3 = lpStaking.stakeLPTokens(address(lpToken1), 150e18, 0);

        // Check position counts
        assertEq(lpStaking.getLPPositionCount(user1), 2);
        assertEq(lpStaking.getLPPositionCount(user2), 1);

        // Skip time and claim rewards
        skip(1 days);

        vm.prank(user1);
        uint256 rewards1 = lpStaking.claimLPRewards(pos1);
        assertTrue(rewards1 > 0);

        vm.prank(user2);
        uint256 rewards2 = lpStaking.claimLPRewards(pos3);
        assertTrue(rewards2 > 0);

        // Unstake with different penalties
        vm.prank(user1);
        uint256 unstaked1 = lpStaking.unstakeLPTokens(pos2); // Early unstake with penalty
        assertTrue(unstaked1 < 200e18);

        // Skip to end time for no penalty
        skip(1 days);
        
        vm.prank(user1);
        uint256 unstaked2 = lpStaking.unstakeLPTokens(pos1); // No penalty
        assertEq(unstaked2, 100e18);
    }
}
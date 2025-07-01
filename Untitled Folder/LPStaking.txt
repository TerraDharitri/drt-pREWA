// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./LPStakingUtils.sol";        
import "./RewardCalculator.sol";      
import "./interfaces/ILPStaking.sol"; 
import "../libraries/Errors.sol"; 
import "../libraries/Constants.sol"; 
import "../libraries/RewardMath.sol"; 
import "../access/AccessControl.sol"; 
import "../controllers/EmergencyController.sol"; 

/**
 * @title LPStaking
 * @author Rewa
 * @notice A contract for staking LP (Liquidity Provider) tokens to earn rewards.
 * @dev This contract allows users to stake various LP tokens in different tiers, each with unique durations and
 * reward multipliers. It integrates with an EmergencyController for safety and uses a RewardCalculator library
 * for consistent reward computations. It inherits administrative and utility functions from LPStakingUtils.
 * The contract is upgradeable.
 */
contract LPStaking is
    Initializable,
    LPStakingUtils, 
    ILPStaking     
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev The address of the pREWA reward token.
    address private _rewardTokenAddress;
    /// @dev The address of the LiquidityManager, used for context but not direct calls.
    address private _liquidityManagerContractAddress;
    
    /// @dev An internal scaling factor for reward rate precision, from RewardMath.
    uint256 private constant INTERNAL_SCALE_RATE = RewardMath.SCALE_RATE;
    /// @dev An internal scaling factor for time-based precision, from RewardMath.
    uint256 private constant INTERNAL_SCALE_TIME = RewardMath.SCALE_TIME;

    /**
     * @notice Emitted when the contract's ownership is transferred.
     * @param previousOwner The address of the previous owner.
     * @param newOwner The address of the new owner.
     * @param operator The address that initiated the transfer.
     */
    event LPStakingOwnershipTransferred(address indexed previousOwner, address indexed newOwner, address indexed operator);
    /**
     * @notice Emitted when non-staked tokens are recovered from the contract by the owner.
     * @param token The address of the recovered token.
     * @param amount The amount recovered.
     * @param recipient The address that received the tokens.
     */
    event LPTokenRecovered(address indexed token, uint256 amount, address indexed recipient);

    /**
     * @dev Disables the regular constructor to make the contract upgradeable.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the LPStaking contract.
     * @dev Sets up the initial owner, staking parameters, and dependent contract addresses. Can only be called once.
     * @param pREWATokenAddress_ The address of the pREWA reward token.
     * @param liquidityManagerAddr_ The address of the LiquidityManager contract.
     * @param initialOwner_ The address of the initial owner of the contract.
     * @param minStakeDuration_ The minimum duration for any staking tier.
     * @param accessControlAddr_ The address of the AccessControl contract.
     * @param emergencyControllerAddr_ The address of the EmergencyController contract.
     */
    function initialize(
        address pREWATokenAddress_,
        address liquidityManagerAddr_,
        address initialOwner_,
        uint256 minStakeDuration_,
        address accessControlAddr_,     
        address emergencyControllerAddr_ 
    ) external initializer {
        __LPStakingUtils_init(); 

        _setRewardToken(pREWATokenAddress_);
        _setLiquidityManager(liquidityManagerAddr_);

        if (initialOwner_ == address(0)) revert ZeroAddress("initialOwner_");
        if (minStakeDuration_ < Constants.MIN_STAKING_DURATION || minStakeDuration_ > Constants.MAX_STAKING_DURATION) {
            revert InvalidDuration();
        }
        if (accessControlAddr_ == address(0)) revert ZeroAddress("AccessControl address for LPStaking init");
        if (emergencyControllerAddr_ == address(0)) revert ZeroAddress("EmergencyController address for LPStaking init");

        _owner = initialOwner_;
        _minStakeDuration = minStakeDuration_;

        accessControl = AccessControl(accessControlAddr_);
        emergencyController = EmergencyController(emergencyControllerAddr_);

        _emergencyWithdrawalPenalty = Constants.DEFAULT_PENALTY;
        _emergencyWithdrawalEnabled = false;
    }

    /**
     * @dev Modifier that reverts if the system is in an emergency state (paused locally or globally).
     */
    modifier whenLpStakingNotEmergency() { 
        if (this.isEmergencyPaused()) revert SystemInEmergencyMode();
        _;
    }

    /**
     * @inheritdoc ILPStaking
     */
    function stakeLPTokens(
        address lpToken,
        uint256 amount,
        uint256 tierId
    ) external override nonReentrant whenLpStakingNotEmergency returns (uint256 positionId) {
        if (address(accessControl) == address(0)) revert NotInitialized(); 
        if (amount == 0) revert LPS_StakeAmountZero();
        if (tierId >= _tierCount) revert LPS_TierDoesNotExist(tierId);

        if (_lastStakeBlockNumberLP[msg.sender] >= block.number) revert LPS_MultiStakeInBlock();
        _lastStakeBlockNumberLP[msg.sender] = block.number;

        LPPool storage pool = _pools[lpToken];
        if (pool.lpTokenAddress == address(0)) revert LPS_PoolNotActive(lpToken);
        if (!pool.active) revert LPS_PoolNotActive(lpToken);

        Tier storage tier = _tiers[tierId];
        if (!tier.active) revert LPS_TierNotActive(tierId);

        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + tier.duration;

        _userStakingPositions[msg.sender].push(LPStakingPosition({
            amount: amount,
            startTime: startTime,
            endTime: endTime,
            lastClaimTime: startTime,
            tierId: tierId,
            lpToken: lpToken,
            active: true
        }));
        positionId = _userStakingPositions[msg.sender].length - 1;

        _totalStaked += amount;
        _poolTotalStaked[lpToken] += amount;

        IERC20Upgradeable(lpToken).safeTransferFrom(msg.sender, address(this), amount);
        emit LPStaked(msg.sender, amount, lpToken, tierId, positionId);
        return positionId;
    }

    /**
     * @dev Internal function to handle the core logic of unstaking or withdrawing a position.
     * @param user The address of the user.
     * @param positionId The ID of the user's staking position.
     * @param penaltyBpsToApply The penalty in basis points to apply to the withdrawal.
     * @return amountTransferred The amount of LP tokens transferred back to the user after penalty.
     * @return actualPenaltyAmount The calculated penalty amount in LP tokens.
     */
    function _handleUnstakeOrWithdraw( 
        address user,
        uint256 positionId,
        uint256 penaltyBpsToApply
    ) internal returns (uint256 amountTransferred, uint256 actualPenaltyAmount) {
        LPStakingPosition storage position = _userStakingPositions[user][positionId];
        uint256 stakedAmount = position.amount;

        actualPenaltyAmount = Math.mulDiv(stakedAmount, penaltyBpsToApply, Constants.BPS_MAX);

        if (actualPenaltyAmount >= stakedAmount) {
            amountTransferred = 0;
            actualPenaltyAmount = stakedAmount;
        } else {
            amountTransferred = stakedAmount - actualPenaltyAmount;
        }

        position.active = false;
        
        unchecked {
            _totalStaked -= stakedAmount;
        }

        if (_poolTotalStaked[position.lpToken] >= stakedAmount) {
            _poolTotalStaked[position.lpToken] -= stakedAmount;
        } else {
            emit PoolTotalStakedInconsistency(position.lpToken, _poolTotalStaked[position.lpToken], stakedAmount);
            _poolTotalStaked[position.lpToken] = 0;
        }

        if (amountTransferred > 0) {
            IERC20Upgradeable(position.lpToken).safeTransfer(user, amountTransferred);
        }
        return (amountTransferred, actualPenaltyAmount);
    }

    /**
     * @inheritdoc ILPStaking
     * @dev An early withdrawal penalty may be applied if the staking duration has not been completed.
     */
    function unstakeLPTokens(uint256 positionId) external override nonReentrant returns (uint256 amountUnstaked) {
        if (address(accessControl) == address(0)) revert NotInitialized();
        if (positionId >= _userStakingPositions[msg.sender].length) revert LPS_PositionDoesNotExist(positionId);
        LPStakingPosition storage position = _userStakingPositions[msg.sender][positionId];
        if (!position.active) revert LPS_PositionNotActive(positionId);

        Tier storage tier = _tiers[position.tierId];
        uint256 currentPenaltyBps = (block.timestamp < position.endTime) ? tier.earlyWithdrawalPenalty : 0;

        LPPool storage pool = _pools[position.lpToken];
        if (pool.lpTokenAddress == address(0)) revert LPS_PoolNotActive(position.lpToken);

        uint256 rewards = RewardCalculator.calculateRewards(position, pool, tier, block.timestamp);
        if (rewards > 0) {
            position.lastClaimTime = block.timestamp;
            IERC20Upgradeable(_rewardTokenAddress).safeTransfer(msg.sender, rewards);
            emit LPRewardsClaimed(msg.sender, rewards, position.lpToken, positionId);
        }

        uint256 actualPenaltyValue;
        (amountUnstaked, actualPenaltyValue) = _handleUnstakeOrWithdraw(msg.sender, positionId, currentPenaltyBps);
        emit LPUnstaked(msg.sender, amountUnstaked, position.lpToken, positionId, actualPenaltyValue);
        return amountUnstaked;
    }

    /**
     * @inheritdoc ILPStaking
     * @dev This function can only be called if emergency withdrawal is enabled by the owner.
     * A fixed penalty is applied, and no rewards are paid.
     */
    function emergencyWithdrawLP(uint256 positionId) external override nonReentrant returns (uint256 amountWithdrawn) {
        if (address(accessControl) == address(0)) revert NotInitialized();
        if (!_emergencyWithdrawalEnabled) revert LPS_EMGWDNotEnabled();
        if (positionId >= _userStakingPositions[msg.sender].length) revert LPS_PositionDoesNotExist(positionId);
        LPStakingPosition storage position = _userStakingPositions[msg.sender][positionId];
        if (!position.active) revert LPS_PositionNotActive(positionId);

        uint256 actualPenaltyValue;
        (amountWithdrawn, actualPenaltyValue) = _handleUnstakeOrWithdraw(msg.sender, positionId, _emergencyWithdrawalPenalty);
        emit LPUnstaked(msg.sender, amountWithdrawn, position.lpToken, positionId, actualPenaltyValue); 
        return amountWithdrawn;
    }

    /**
     * @inheritdoc ILPStaking
     */
    function claimLPRewards(uint256 positionId) external override nonReentrant whenLpStakingNotEmergency returns (uint256 amountClaimed) {
        if (address(accessControl) == address(0)) revert NotInitialized();
        if (positionId >= _userStakingPositions[msg.sender].length) revert LPS_PositionDoesNotExist(positionId);
        LPStakingPosition storage position = _userStakingPositions[msg.sender][positionId];
        if (!position.active) revert LPS_PositionNotActive(positionId);

        Tier storage tier = _tiers[position.tierId];
        LPPool storage pool = _pools[position.lpToken];
        if (pool.lpTokenAddress == address(0)) revert LPS_PoolNotActive(position.lpToken);

        amountClaimed = RewardCalculator.calculateRewards(position, pool, tier, block.timestamp);
        
        if (amountClaimed > 0) {
            position.lastClaimTime = block.timestamp;
            IERC20Upgradeable(_rewardTokenAddress).safeTransfer(msg.sender, amountClaimed);
            emit LPRewardsClaimed(msg.sender, amountClaimed, position.lpToken, positionId);
        } else {
            revert LPS_NoRewardsToClaim();
        }

        return amountClaimed;
    }

    /**
     * @inheritdoc ILPStaking
     */
    function addPool(
        address lpToken,
        uint256 baseAPRBpsIn
    ) external override onlyParameterRole nonReentrant returns (bool success) {
        if (lpToken == address(0)) revert LPS_InvalidLPTokenAddress();
        if (_pools[lpToken].lpTokenAddress != address(0)) revert LPS_PoolAlreadyExists(lpToken);
        if (baseAPRBpsIn > 50000 && baseAPRBpsIn !=0 ) revert LPS_RewardRateZero();

        uint256 newScaledRate;
        if (baseAPRBpsIn == 0) {
            newScaledRate = 0;
        } else {
            uint256 actual_rps_numerator = baseAPRBpsIn;
            uint256 actual_rps_denominator = Constants.BPS_MAX * Constants.SECONDS_PER_YEAR;
            uint256 numerator_scaled = Math.mulDiv(actual_rps_numerator, INTERNAL_SCALE_RATE, 1);
            numerator_scaled = Math.mulDiv(numerator_scaled, INTERNAL_SCALE_TIME, 1);
            newScaledRate = Math.mulDiv(numerator_scaled, 1, actual_rps_denominator);
        }

        _pools[lpToken] = LPPool(lpToken, newScaledRate, true);
        isLPToken[lpToken] = true;
        emit PoolAdded(lpToken, baseAPRBpsIn, newScaledRate, msg.sender);
        success = true;
        return success;
    }

    /**
     * @inheritdoc ILPStaking
     */
    function updatePool(
        address lpToken,
        uint256 newBaseAPRBpsIn,
        bool active
    ) external override onlyParameterRole nonReentrant returns (bool success) {
        if (lpToken == address(0)) revert LPS_InvalidLPTokenAddress();
        LPPool storage pool = _pools[lpToken];
        if (pool.lpTokenAddress == address(0)) revert LPS_PoolNotActive(lpToken);
        if (newBaseAPRBpsIn > 50000 && newBaseAPRBpsIn !=0) revert LPS_RewardRateZero();

        uint256 newScaledRate;
        if (newBaseAPRBpsIn == 0) {
            newScaledRate = 0;
        } else {
            uint256 actual_rps_numerator = newBaseAPRBpsIn;
            uint256 actual_rps_denominator = Constants.BPS_MAX * Constants.SECONDS_PER_YEAR;
            uint256 numerator_scaled = Math.mulDiv(actual_rps_numerator, INTERNAL_SCALE_RATE, 1);
            numerator_scaled = Math.mulDiv(numerator_scaled, INTERNAL_SCALE_TIME, 1);
            newScaledRate = Math.mulDiv(numerator_scaled, 1, actual_rps_denominator);
        }

        pool.baseRewardRate = newScaledRate;
        pool.active = active;
        emit PoolUpdated(lpToken, newBaseAPRBpsIn, newScaledRate, active, msg.sender);
        success = true;
        return success;
    }

    /**
     * @dev Internal function to validate tier parameters.
     * @param durationIn The staking duration.
     * @param rewardMultiplierIn The reward multiplier.
     * @param earlyWithdrawalPenaltyIn The early withdrawal penalty.
     */
    function _validateTierParameters( 
        uint256 durationIn,
        uint256 rewardMultiplierIn,
        uint256 earlyWithdrawalPenaltyIn
    ) internal view {
        if (durationIn < _minStakeDuration) revert LPS_DurationLessThanMin(durationIn, _minStakeDuration);
        if (durationIn > Constants.MAX_STAKING_DURATION) revert LPS_DurationExceedsMax(durationIn, Constants.MAX_STAKING_DURATION);
        if (rewardMultiplierIn < Constants.MIN_REWARD_MULTIPLIER) revert LPS_MultiplierTooLow(rewardMultiplierIn, Constants.MIN_REWARD_MULTIPLIER);
        if (rewardMultiplierIn > Constants.MAX_REWARD_MULTIPLIER) revert LPS_MultiplierTooHigh(rewardMultiplierIn, Constants.MAX_REWARD_MULTIPLIER);
        if (earlyWithdrawalPenaltyIn > Constants.MAX_PENALTY) revert LPS_PenaltyTooHigh(earlyWithdrawalPenaltyIn, Constants.MAX_PENALTY);
    }

    /**
     * @inheritdoc ILPStaking
     */
    function addTier(
        uint256 durationIn, uint256 rewardMultiplierIn, uint256 earlyWithdrawalPenaltyIn
    ) external override onlyParameterRole nonReentrant returns (uint256 tierId) {
        _validateTierParameters(durationIn, rewardMultiplierIn, earlyWithdrawalPenaltyIn);
        tierId = _tierCount;
        _tiers[tierId] = Tier(durationIn, rewardMultiplierIn, earlyWithdrawalPenaltyIn, true);
        _tierCount++;
        emit TierAdded(tierId, durationIn, rewardMultiplierIn, earlyWithdrawalPenaltyIn, msg.sender);
        return tierId;
    }

    /**
     * @inheritdoc ILPStaking
     */
    function updateTier(
        uint256 tierId,
        uint256 durationIn,
        uint256 rewardMultiplierIn,
        uint256 earlyWithdrawalPenaltyIn,
        bool active
    ) external override onlyParameterRole nonReentrant returns (bool success) {
        if (tierId >= _tierCount) revert LPS_TierDoesNotExist(tierId);
        _validateTierParameters(durationIn, rewardMultiplierIn, earlyWithdrawalPenaltyIn);

        Tier storage tier = _tiers[tierId];
        tier.duration = durationIn;
        tier.rewardMultiplier = rewardMultiplierIn;
        tier.earlyWithdrawalPenalty = earlyWithdrawalPenaltyIn;
        tier.active = active;
        emit TierUpdated(tierId, durationIn, rewardMultiplierIn, earlyWithdrawalPenaltyIn, active, msg.sender);
        success = true;
        return success;
    }

    /**
     * @inheritdoc ILPStaking
     */
    function setLPEmergencyWithdrawal(bool enabled, uint256 penalty) external override onlyOwner nonReentrant returns (bool success) {
        if (penalty > Constants.MAX_PENALTY) revert LPS_PenaltyTooHigh(penalty, Constants.MAX_PENALTY);

        _emergencyWithdrawalEnabled = enabled;
        _emergencyWithdrawalPenalty = penalty;
        emit LPStakingEmergencyWithdrawalSet(enabled, penalty, msg.sender);
        success = true;
        return success;
    }

    /**
     * @inheritdoc ILPStaking
     */
    function getLPStakingPosition(address user, uint256 positionId) external view override returns (
        uint256 amount, uint256 startTime, uint256 endTime,
        uint256 lastClaimTime, uint256 tierIdOut, address lpTokenOut, bool activeFlag
    ) {
        if (address(accessControl) == address(0) && _userStakingPositions[user].length > 0 ) revert NotInitialized();
        if (user == address(0)) revert ZeroAddress("user for getLPStakingPosition");
        if (positionId >= _userStakingPositions[user].length) revert LPS_PositionDoesNotExist(positionId);
        LPStakingPosition storage pos = _userStakingPositions[user][positionId];
        amount = pos.amount;
        startTime = pos.startTime;
        endTime = pos.endTime;
        lastClaimTime = pos.lastClaimTime;
        tierIdOut = pos.tierId;
        lpTokenOut = pos.lpToken;
        activeFlag = pos.active;
    }

    /**
     * @inheritdoc ILPStaking
     */
    function calculateLPRewards(address user, uint256 positionId) external view override returns (uint256 rewardsAmount) {
        if (address(accessControl) == address(0) && _userStakingPositions[user].length > 0) revert NotInitialized();
        if (user == address(0)) revert ZeroAddress("user for calculateLPRewards");
        if (positionId >= _userStakingPositions[user].length) revert LPS_PositionDoesNotExist(positionId);

        LPStakingPosition memory position_ = _userStakingPositions[user][positionId];
        if (!position_.active) return 0;

        Tier memory tier_ = _tiers[position_.tierId];
        LPPool memory pool_ = _pools[position_.lpToken];
        if(pool_.lpTokenAddress == address(0)) return 0;

        rewardsAmount = RewardCalculator.calculateRewards(position_, pool_, tier_, block.timestamp);
        return rewardsAmount;
    }

    /**
     * @inheritdoc ILPStaking
     */
    function getPoolInfo(address lpToken) external view override returns (
        uint256 baseAPRBpsOut,
        uint256 totalStakedInPoolOut,
        bool isActiveOut
    ) {
        if (address(accessControl) == address(0) && _pools[lpToken].lpTokenAddress != address(0)) revert NotInitialized();
        if (lpToken == address(0)) revert LPS_InvalidLPTokenAddress();
        LPPool storage pool = _pools[lpToken];
        if (pool.lpTokenAddress == address(0)) {
             revert LPS_PoolNotActive(lpToken);
        }

        if (pool.baseRewardRate == 0) {
            baseAPRBpsOut = 0;
        } else {
            uint256 annualFactor = Constants.SECONDS_PER_YEAR * Constants.BPS_MAX;
            uint256 scalingDivisor = INTERNAL_SCALE_RATE * INTERNAL_SCALE_TIME;
            baseAPRBpsOut = Math.mulDiv(pool.baseRewardRate, annualFactor, scalingDivisor);
        }
        totalStakedInPoolOut = _poolTotalStaked[lpToken];
        isActiveOut = pool.active;
    }

    /**
     * @inheritdoc ILPStaking
     */
    function getTierInfo(uint256 tierId) external view override returns (
        uint256 durationOut, uint256 rewardMultiplierOut, uint256 earlyWithdrawalPenaltyOut, bool activeOut
    ) {
        if (address(accessControl) == address(0) && tierId < _tierCount) revert NotInitialized();
        if (tierId >= _tierCount) revert LPS_TierDoesNotExist(tierId);
        Tier storage tier = _tiers[tierId];
        durationOut = tier.duration;
        rewardMultiplierOut = tier.rewardMultiplier;
        earlyWithdrawalPenaltyOut = tier.earlyWithdrawalPenalty;
        activeOut = tier.active;
    }

    /**
     * @inheritdoc ILPStaking
     */
    function getLPPositionCount(address user) external view override returns (uint256 count) {
        if (address(accessControl) == address(0) && _userStakingPositions[user].length > 0) revert NotInitialized();
        if (user == address(0)) revert ZeroAddress("user for getLPPositionCount");
        count = _userStakingPositions[user].length;
        return count;
    }

    /**
     * @inheritdoc ILPStaking
     */
    function getLPEmergencyWithdrawalSettings() external view override returns (bool enabled, uint256 penaltyBps) {
        if (address(accessControl) == address(0) ) revert NotInitialized();
        enabled = _emergencyWithdrawalEnabled;
        penaltyBps = _emergencyWithdrawalPenalty;
    }

    /**
     * @notice Returns the address of the reward token.
     * @return The address of the reward token.
     */
    function getRewardTokenAddress() external view returns (address) {
        return _rewardTokenAddress;
    }

    /**
     * @notice Returns the address of the LiquidityManager contract.
     * @return The address of the LiquidityManager contract.
     */
    function getLiquidityManagerAddress() external view returns (address) {
        return _liquidityManagerContractAddress;
    }

    /**
     * @dev Internal function to set the reward token address, callable only once during initialization.
     * @param tokenAddr_ The address of the reward token.
     */
    function _setRewardToken(address tokenAddr_) internal {
        require(_rewardTokenAddress == address(0), "LPStaking: Reward token already set");
        require(tokenAddr_ != address(0), "LPStaking: Reward token cannot be zero");
        _rewardTokenAddress = tokenAddr_;
    }

    /**
     * @dev Internal function to set the LiquidityManager address, callable only once during initialization.
     * @param lmAddr_ The address of the LiquidityManager.
     */
    function _setLiquidityManager(address lmAddr_) internal {
        require(_liquidityManagerContractAddress == address(0), "LPStaking: LiquidityManager already set");
        require(lmAddr_ != address(0), "LPStaking: LiquidityManager cannot be zero");
        _liquidityManagerContractAddress = lmAddr_;
    }

    /**
     * @notice Recovers ERC20 tokens mistakenly sent to this contract.
     * @dev Cannot be used to recover the reward token or any actively staked LP tokens.
     * @param tokenAddressRec The address of the token to recover.
     * @param amountRec The amount of the token to recover.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function recoverTokens(address tokenAddressRec, uint256 amountRec) external onlyOwner nonReentrant returns (bool successFlag) {
        if (tokenAddressRec == address(0)) revert ZeroAddress("tokenAddress for recovery");
        if (tokenAddressRec == _rewardTokenAddress) revert LPS_CannotRecoverStakingToken();
        if (isLPToken[tokenAddressRec]) {
             revert LPS_CannotRecoverStakedLP(tokenAddressRec);
        }
        if (amountRec == 0) revert AmountIsZero();

        IERC20Upgradeable recoveryToken = IERC20Upgradeable(tokenAddressRec);
        uint256 contractBalance = recoveryToken.balanceOf(address(this));
        if (amountRec > contractBalance) revert InsufficientBalance(contractBalance, amountRec);

        recoveryToken.safeTransfer(_owner, amountRec);
        emit LPTokenRecovered(tokenAddressRec, amountRec, _owner);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Transfers ownership of the contract to a new address.
     * @param newOwner The address of the new owner.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function transferOwnership(address newOwner) external onlyOwner nonReentrant returns (bool successFlag) {
        if (newOwner == address(0)) revert ZeroAddress("newOwner");
        address oldOwner = _owner;
        _owner = newOwner;
        emit LPStakingOwnershipTransferred(oldOwner, newOwner, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function checkEmergencyStatus(bytes4 operation) external view override returns (bool allowed) {
        bool isPausedByUtils = PausableUpgradeable.paused();
        bool isGloballyPausedByEC = false; 
        bool opIsSpecificallyRestrictedByEC = false;

        if (address(emergencyController) != address(0)) {
            try emergencyController.isSystemPaused() returns (bool p) { 
                isGloballyPausedByEC = p; 
            } catch { }

            uint8 ecLevel = Constants.EMERGENCY_LEVEL_NORMAL;
            try emergencyController.getEmergencyLevel() returns (uint8 l) {
                ecLevel = l;
                if (ecLevel >= Constants.EMERGENCY_LEVEL_CRITICAL) {
                    isGloballyPausedByEC = true;
                }
            } catch { }

            if (!isGloballyPausedByEC) { 
                try emergencyController.isFunctionRestricted(operation) returns (bool r) {
                    opIsSpecificallyRestrictedByEC = r;
                } catch { 
                    opIsSpecificallyRestrictedByEC = false;
                }
            }
        }
        
        allowed = !isPausedByUtils && !isGloballyPausedByEC && !opIsSpecificallyRestrictedByEC; 
        return allowed;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function emergencyShutdown(uint8 emergencyLevelInput) external override returns (bool success) {
        if (address(emergencyController) == address(0)) revert LPS_CallerNotEmergencyController();
        if (msg.sender != address(emergencyController)) revert LPS_CallerNotEmergencyController();

        if (emergencyLevelInput >= Constants.EMERGENCY_LEVEL_CRITICAL && !PausableUpgradeable.paused()) {
            _pause();
        }
        if (emergencyLevelInput >= Constants.EMERGENCY_LEVEL_ALERT && !_emergencyWithdrawalEnabled) {
            _emergencyWithdrawalEnabled = true;
            emit LPStakingEmergencyWithdrawalSet(true, _emergencyWithdrawalPenalty, address(emergencyController)); 
        }
        emit EmergencyShutdownHandled(emergencyLevelInput, msg.sender);
        success = true;
        return success;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function getEmergencyController() external view override returns (address controller) {
        controller = address(emergencyController);
        return controller;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function setEmergencyController(address controller) external override onlyOwner returns (bool success) {
        if (controller == address(0)) revert ZeroAddress("EmergencyController address");
        uint256 codeSize;
        assembly { codeSize := extcodesize(controller) }
        if (codeSize == 0) revert NotAContract("EmergencyController");

        address oldController = address(emergencyController);
        emergencyController = EmergencyController(controller);
        emit LPStakingEmergencyControllerSet(oldController, controller, msg.sender);
        success = true;
        return success;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function isEmergencyPaused() public view override returns (bool isPaused) {
        bool localPause = PausableUpgradeable.paused();
        bool ecSystemPaused = false;
        uint8 ecCurrentSystemLevel = Constants.EMERGENCY_LEVEL_NORMAL;
        if (address(emergencyController) != address(0)) {
            try emergencyController.isSystemPaused() returns (bool sP) { ecSystemPaused = sP; } catch {}
            try emergencyController.getEmergencyLevel() returns (uint8 cL) { ecCurrentSystemLevel = cL; } catch {}
        }
        isPaused = localPause || ecSystemPaused || (ecCurrentSystemLevel >= Constants.EMERGENCY_LEVEL_CRITICAL);
        return isPaused;
    }
}
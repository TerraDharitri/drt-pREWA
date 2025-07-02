// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./storage/TokenStakingStorage.sol"; 
import "./interfaces/ITokenStaking.sol";   
import "../libraries/RewardMath.sol";
import "../libraries/Constants.sol";
import "../interfaces/IEmergencyAware.sol";
import "../controllers/EmergencyController.sol";
import "../oracle/OracleIntegration.sol";
import "../access/AccessControl.sol";
import "../libraries/Errors.sol";
import "../utils/EmergencyAwareBase.sol";

/**
 * @title TokenStaking
 * @author Rewa
 * @notice A contract for staking a native platform token (pREWA) to earn rewards in the same token.
 * @dev This contract allows users to stake tokens in various tiers, each with unique durations, reward multipliers,
 * and early withdrawal penalties. It integrates with AccessControl, EmergencyController, and an OracleIntegration.
 * Rewards are paid out in the same token being staked.
 * The contract is upgradeable and inherits from EmergencyAwareBase.
 */
contract TokenStaking is
    Initializable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    TokenStakingStorage,
    ITokenStaking,
    EmergencyAwareBase
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice The contract that controls roles and permissions.
    AccessControl public accessControl;
    /// @notice The contract that provides reliable price feeds (optional).
    OracleIntegration public oracleIntegration;

    /// @dev An internal scaling factor for reward rate precision, from RewardMath.
    uint256 private constant INTERNAL_SCALE_RATE = RewardMath.SCALE_RATE;
    /// @dev An internal scaling factor for time-based precision, from RewardMath.
    uint256 private constant INTERNAL_SCALE_TIME = RewardMath.SCALE_TIME;

    /**
     * @notice Emitted when non-staked tokens are recovered from the contract.
     * @param token The address of the recovered token.
     * @param amount The amount recovered.
     * @param recipient The address that received the tokens.
     */
    event TokenRecovered(address indexed token, uint256 amount, address indexed recipient);
    /**
     * @notice Emitted when the EmergencyController address is changed.
     * @param oldController The previous controller address.
     * @param newController The new controller address.
     * @param setter The address that performed the update.
     */
    event TokenStakingEmergencyControllerSet(address indexed oldController, address indexed newController, address indexed setter);
    /**
     * @notice Emitted when the OracleIntegration address is changed.
     * @param oldOracle The previous oracle address.
     * @param newOracle The new oracle address.
     * @param setter The address that performed the update.
     */
    event TokenStakingOracleIntegrationSet(address indexed oldOracle, address indexed newOracle, address indexed setter);

    /**
     * @dev Disables the regular constructor to make the contract upgradeable.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function initialize(
        address stakingTokenAddress_,
        address accessControlAddr_,
        address emergencyControllerAddr_,
        address oracleIntegrationAddr_,
        uint256 initialBaseAPRBps_,
        uint256 minStakeDurationVal_,
        address adminAddr_,
        uint256 initialMaxPositionsPerUser_
    ) external initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init();
        
        _setStakingToken(stakingTokenAddress_);

        if (accessControlAddr_ == address(0)) revert TS_ACZero();
        if (emergencyControllerAddr_ == address(0)) revert TS_ECZero();
        if (adminAddr_ == address(0)) revert TS_AdminZero();
        if (initialBaseAPRBps_ > 50000) revert TS_AnnualRateTooHigh(initialBaseAPRBps_);
        if (minStakeDurationVal_ < Constants.MIN_STAKING_DURATION) revert TS_MinDurShort();
        if (minStakeDurationVal_ > Constants.MAX_STAKING_DURATION) revert TS_MinDurLong();
        if (initialMaxPositionsPerUser_ == 0) revert LPS_MaxPositionsMustBePositive();

        uint256 codeSize;
        assembly { codeSize := extcodesize(accessControlAddr_) }
        if (codeSize == 0) revert NotAContract("accessControl");
        assembly { codeSize := extcodesize(emergencyControllerAddr_) }
        if (codeSize == 0) revert NotAContract("emergencyController");
        if (oracleIntegrationAddr_ != address(0)) {
            assembly { codeSize := extcodesize(oracleIntegrationAddr_) }
            if (codeSize == 0) revert NotAContract("oracleIntegration");
        }

        accessControl = AccessControl(accessControlAddr_);
        emergencyController = EmergencyController(emergencyControllerAddr_);
        
        _baseAPRBps = initialBaseAPRBps_;
        _minStakeDuration = minStakeDurationVal_;
        _transferOwnership(adminAddr_);
        _maxPositionsPerUser = initialMaxPositionsPerUser_;

        if (oracleIntegrationAddr_ != address(0)) {
            oracleIntegration = OracleIntegration(oracleIntegrationAddr_);
        }

        _emergencyWithdrawalPenalty = Constants.DEFAULT_PENALTY;
        _emergencyWithdrawalEnabled = false;

        uint256 correspondingScaledRate = _getScaledRateFromBps(initialBaseAPRBps_);
        emit BaseAPRUpdated(0, initialBaseAPRBps_, correspondingScaledRate, msg.sender);
    }

    /**
     * @dev Modifier to restrict functions to accounts with the PARAMETER_ROLE.
     */
    modifier onlyParameterRole() {
        if (address(accessControl) == address(0)) revert TS_ACZero();
        if (!accessControl.hasRole(accessControl.PARAMETER_ROLE(), msg.sender)) revert NotAuthorized(accessControl.PARAMETER_ROLE());
        _;
    }

    /**
     * @dev Modifier to restrict functions to accounts with the PAUSER_ROLE.
     */
    modifier onlyPauserRole() {
        if (address(accessControl) == address(0)) revert TS_ACZero();
        if (!accessControl.hasRole(accessControl.PAUSER_ROLE(), msg.sender)) revert NotAuthorized(accessControl.PAUSER_ROLE());
        _;
    }

    /**
     * @dev Modifier that reverts if the contract is paused locally or by the global EmergencyController.
     */
    modifier whenNotStakingPaused() {
        if (PausableUpgradeable.paused() || _isEffectivelyPaused()) revert ContractPaused();
        _;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function stake(uint256 amount, uint256 tierId) external override nonReentrant whenNotStakingPaused returns (uint256 positionId) {
        if (amount == 0) revert AmountIsZero();
        if (tierId >= _tierCount) revert LPS_TierDoesNotExist(tierId);

        uint256 userPosCount = _userStakingPositions[msg.sender].length;
        if (userPosCount >= _maxPositionsPerUser) revert LPS_MaxPositionsReached(userPosCount, _maxPositionsPerUser);

        Tier storage tier = _tiers[tierId];
        if (!tier.active) revert LPS_TierNotActive(tierId);

        if (_lastStakeBlockNumber[msg.sender] >= block.number) revert LPS_MultiStakeInBlock();
        _lastStakeBlockNumber[msg.sender] = block.number;

        uint256 sTime = block.timestamp;
        StakingPosition memory pos = StakingPosition(amount, sTime, sTime + tier.duration, sTime, tierId, true);
        _userStakingPositions[msg.sender].push(pos);
        positionId = userPosCount;
        _totalStaked += amount;

        IERC20Upgradeable(_tokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount, tierId, positionId);
        return positionId;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function unstake(uint256 positionId) external override nonReentrant returns (uint256 amountUnstaked) {
        if (positionId >= _userStakingPositions[msg.sender].length) revert LPS_PositionDoesNotExist(positionId);
        StakingPosition storage pos = _userStakingPositions[msg.sender][positionId];
        if (!pos.active) revert LPS_PositionNotActive(positionId);

        uint256 penaltyAmount = 0;
        uint256 positionAmount = pos.amount;
        if (block.timestamp < pos.endTime) {
            Tier storage tier = _tiers[pos.tierId];
            penaltyAmount = Math.mulDiv(positionAmount, tier.earlyWithdrawalPenalty, Constants.BPS_MAX);
        }
        uint256 rewardsAmount = _calculateRewardsForPosition(pos);
        amountUnstaked = positionAmount - penaltyAmount;

        pos.active = false;
        pos.lastClaimTime = block.timestamp; 
        unchecked { _totalStaked -= positionAmount; }
        
        emit Unstaked(msg.sender, amountUnstaked, positionId, penaltyAmount);
        
        IERC20Upgradeable token = IERC20Upgradeable(_tokenAddress);
        if (rewardsAmount > 0) {
            token.safeTransfer(msg.sender, rewardsAmount);
            emit RewardsClaimed(msg.sender, rewardsAmount, positionId);
        }
        if (amountUnstaked > 0) {
            token.safeTransfer(msg.sender, amountUnstaked);
        }

        return amountUnstaked;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function claimRewards(uint256 positionId) external override nonReentrant whenNotStakingPaused returns (uint256 amountClaimed) {
        if (positionId >= _userStakingPositions[msg.sender].length) revert LPS_PositionDoesNotExist(positionId);
        StakingPosition storage pos = _userStakingPositions[msg.sender][positionId];
        if (!pos.active) revert LPS_PositionNotActive(positionId);

        amountClaimed = _calculateRewardsForPosition(pos);
        if (amountClaimed > 0) {
            pos.lastClaimTime = block.timestamp;
            IERC20Upgradeable(_tokenAddress).safeTransfer(msg.sender, amountClaimed);
            emit RewardsClaimed(msg.sender, amountClaimed, positionId);
        } else {
            revert LPS_NoRewardsToClaim();
        }
        return amountClaimed;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function emergencyWithdraw(uint256 positionId) external override nonReentrant returns (uint256 amountWithdrawn) {
        if (!_emergencyWithdrawalEnabled) revert LPS_EMGWDNotEnabled();
        if (positionId >= _userStakingPositions[msg.sender].length) revert LPS_PositionDoesNotExist(positionId);
        StakingPosition storage pos = _userStakingPositions[msg.sender][positionId];
        if (!pos.active) revert LPS_PositionNotActive(positionId);

        uint256 positionAmount = pos.amount;
        uint256 penaltyAmount = Math.mulDiv(positionAmount, _emergencyWithdrawalPenalty, Constants.BPS_MAX);

        pos.active = false;
        unchecked { _totalStaked -= positionAmount; }
        amountWithdrawn = positionAmount - penaltyAmount;

        if (amountWithdrawn > 0) {
            IERC20Upgradeable(_tokenAddress).safeTransfer(msg.sender, amountWithdrawn);
        }
        emit Unstaked(msg.sender, amountWithdrawn, positionId, penaltyAmount);
        return amountWithdrawn;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function addTier(
        uint256 durationVal, uint256 rewardMultiplierVal, uint256 earlyWithdrawalPenaltyVal
    ) external override onlyParameterRole nonReentrant returns (uint256 tierId) {
        if (durationVal < _minStakeDuration) revert LPS_DurationLessThanMin(durationVal, _minStakeDuration);
        if (durationVal > Constants.MAX_STAKING_DURATION) revert LPS_DurationExceedsMax(durationVal, Constants.MAX_STAKING_DURATION);
        if (rewardMultiplierVal < Constants.MIN_REWARD_MULTIPLIER) revert LPS_MultiplierTooLow(rewardMultiplierVal, Constants.MIN_REWARD_MULTIPLIER);
        if (rewardMultiplierVal > Constants.MAX_REWARD_MULTIPLIER) revert LPS_MultiplierTooHigh(rewardMultiplierVal, Constants.MAX_REWARD_MULTIPLIER);
        if (earlyWithdrawalPenaltyVal > Constants.MAX_PENALTY) revert LPS_PenaltyTooHigh(earlyWithdrawalPenaltyVal, Constants.MAX_PENALTY);

        tierId = _tierCount;
        _tiers[tierId] = Tier(durationVal, rewardMultiplierVal, earlyWithdrawalPenaltyVal, true);
        _tierCount++;
        emit TierAdded(tierId, durationVal, rewardMultiplierVal, earlyWithdrawalPenaltyVal, msg.sender);
        return tierId;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function updateTier(
        uint256 tierId, uint256 durationVal, uint256 rewardMultiplierVal,
        uint256 earlyWithdrawalPenaltyVal, bool isActive
    ) external override onlyParameterRole nonReentrant returns (bool successFlag) {
        if (tierId >= _tierCount) revert LPS_TierDoesNotExist(tierId);
        if (durationVal < _minStakeDuration) revert LPS_DurationLessThanMin(durationVal, _minStakeDuration);
        if (durationVal > Constants.MAX_STAKING_DURATION) revert LPS_DurationExceedsMax(durationVal, Constants.MAX_STAKING_DURATION);
        if (rewardMultiplierVal < Constants.MIN_REWARD_MULTIPLIER) revert LPS_MultiplierTooLow(rewardMultiplierVal, Constants.MIN_REWARD_MULTIPLIER);
        if (rewardMultiplierVal > Constants.MAX_REWARD_MULTIPLIER) revert LPS_MultiplierTooHigh(rewardMultiplierVal, Constants.MAX_REWARD_MULTIPLIER);
        if (earlyWithdrawalPenaltyVal > Constants.MAX_PENALTY) revert LPS_PenaltyTooHigh(earlyWithdrawalPenaltyVal, Constants.MAX_PENALTY);

        Tier storage tierToUpdate = _tiers[tierId];
        tierToUpdate.duration = durationVal;
        tierToUpdate.rewardMultiplier = rewardMultiplierVal;
        tierToUpdate.earlyWithdrawalPenalty = earlyWithdrawalPenaltyVal;
        tierToUpdate.active = isActive;

        emit TierUpdated(tierId, durationVal, rewardMultiplierVal, earlyWithdrawalPenaltyVal, isActive, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function setEmergencyWithdrawal(bool isEnabled, uint256 penaltyVal) external override onlyParameterRole nonReentrant returns (bool successFlag) {
        if (penaltyVal > Constants.MAX_PENALTY) revert LPS_PenaltyTooHigh(penaltyVal, Constants.MAX_PENALTY);

        _emergencyWithdrawalEnabled = isEnabled;
        _emergencyWithdrawalPenalty = penaltyVal;
        emit EmergencyWithdrawalSettingsUpdated(isEnabled, penaltyVal, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function setBaseAnnualPercentageRate(uint256 newBaseAPRBps) external override onlyParameterRole nonReentrant returns (bool success) {
        if (newBaseAPRBps > 50000) revert TS_AnnualRateTooHigh(newBaseAPRBps);

        uint256 oldAPRBps = _baseAPRBps;
        _baseAPRBps = newBaseAPRBps;

        uint256 newScaledRate = _getScaledRateFromBps(newBaseAPRBps);

        emit BaseAPRUpdated(oldAPRBps, newBaseAPRBps, newScaledRate, msg.sender);
        success = true;
        return success;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function setMinStakeDuration(uint256 durationVal) external override onlyParameterRole nonReentrant returns (bool successFlag) {
        if (durationVal < Constants.MIN_STAKING_DURATION) revert TS_MinDurShort();
        if (durationVal > Constants.MAX_STAKING_DURATION) revert TS_MinDurLong();
        uint256 oldDurationVal = _minStakeDuration;
        _minStakeDuration = durationVal;
        emit MinStakeDurationUpdated(oldDurationVal, durationVal, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function setMaxPositionsPerUser(uint256 maxPositions) external override onlyParameterRole nonReentrant returns (bool successFlag) {
        if (maxPositions == 0) revert LPS_MaxPositionsMustBePositive();
        uint256 oldMax = _maxPositionsPerUser;
        _maxPositionsPerUser = maxPositions;
        emit MaxPositionsPerUserUpdated(oldMax, maxPositions, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function pauseStaking() external override onlyPauserRole nonReentrant returns (bool successFlag) {
        _pause();
        emit StakingPaused(msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function unpauseStaking() external override onlyPauserRole nonReentrant returns (bool successFlag) {
        _unpause();
        emit StakingUnpaused(msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function isStakingPaused() public view override returns (bool) {
        return PausableUpgradeable.paused() || _isEffectivelyPaused();
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function getTierInfo(uint256 tierId) external view override returns (
        uint256 durationVal, uint256 rewardMultiplierVal, uint256 earlyWithdrawalPenaltyVal, bool isActive
    ) {
        if (tierId >= _tierCount) revert LPS_TierDoesNotExist(tierId);
        Tier storage tier = _tiers[tierId];
        durationVal = tier.duration;
        rewardMultiplierVal = tier.rewardMultiplier;
        earlyWithdrawalPenaltyVal = tier.earlyWithdrawalPenalty;
        isActive = tier.active;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function getStakingPosition(address userAddr, uint256 positionId) external view override returns (
        uint256 amountVal, uint256 startTimeVal, uint256 endTimeVal,
        uint256 lastClaimTimeVal, uint256 tierIdVal, bool isActiveFlag
    ) {
        if (userAddr == address(0)) revert ZeroAddress("userAddr for getStakingPosition");
        if (positionId >= _userStakingPositions[userAddr].length) revert LPS_PositionDoesNotExist(positionId);
        StakingPosition storage pos = _userStakingPositions[userAddr][positionId];
        amountVal = pos.amount; startTimeVal = pos.startTime; endTimeVal = pos.endTime;
        lastClaimTimeVal = pos.lastClaimTime; tierIdVal = pos.tierId; isActiveFlag = pos.active;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function calculateRewards(address userAddr, uint256 positionId) external view override returns (uint256 rewardsAmount) {
        if (userAddr == address(0)) revert ZeroAddress("userAddr for calculateRewards");
        if (positionId >= _userStakingPositions[userAddr].length) revert LPS_PositionDoesNotExist(positionId);
        StakingPosition storage pos = _userStakingPositions[userAddr][positionId];
        rewardsAmount = _calculateRewardsForPosition(pos);
        return rewardsAmount;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function totalStaked() external view override returns (uint256 totalStakedAmount) {
        totalStakedAmount = _totalStaked;
        return totalStakedAmount;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function getPositionCount(address userAddr) external view override returns (uint256 countVal) {
        if (userAddr == address(0)) revert ZeroAddress("userAddr for getPositionCount");
        countVal = _userStakingPositions[userAddr].length;
        return countVal;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function getStakingTokenAddress() external view override returns (address) { return _tokenAddress; }

    /**
     * @inheritdoc ITokenStaking
     */
    function getBaseAnnualPercentageRate() external view override returns (uint256 aprBps) {
        return _baseAPRBps;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function getEmergencyWithdrawalSettings() external view override returns (bool isEnabled, uint256 penaltyBps) {
        isEnabled = _emergencyWithdrawalEnabled;
        penaltyBps = _emergencyWithdrawalPenalty;
    }

    /**
     * @inheritdoc ITokenStaking
     */
    function getMaxPositionsPerUser() external view override returns (uint256 maxPositions) {
        maxPositions = _maxPositionsPerUser;
        return maxPositions;
    }

    /**
     * @notice Recovers ERC20 tokens mistakenly sent to this contract.
     * @dev Cannot be used to recover the staking token. Only callable by the owner.
     * @param tokenAddrRec The address of the token to recover.
     * @param amountVal The amount to recover.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function recoverTokens(address tokenAddrRec, uint256 amountVal) external onlyOwner nonReentrant returns (bool successFlag) {
        if (tokenAddrRec == address(0)) revert ZeroAddress("tokenAddrRec for recovery");
        if (tokenAddrRec == _tokenAddress) revert TS_CannotUnprotectStakingToken();
        if (amountVal == 0) revert AmountIsZero();

        IERC20Upgradeable tokenInst = IERC20Upgradeable(tokenAddrRec);
        uint256 balance = tokenInst.balanceOf(address(this));
        if (amountVal > balance) revert InsufficientBalance(balance, amountVal);

        tokenInst.safeTransfer(owner(), amountVal);
        emit TokenRecovered(tokenAddrRec, amountVal, owner());
        successFlag = true;
        return successFlag;
    }

    /**
     * @dev Internal function to set the staking token address, callable only once during initialization.
     * @param tokenAddr_ The address of the staking token.
     */
    function _setStakingToken(address tokenAddr_) internal {
        require(_tokenAddress == address(0), "TokenStaking: Staking token already set");
        require(tokenAddr_ != address(0), "TokenStaking: Staking token cannot be zero");
        _tokenAddress = tokenAddr_;
    }

    /**
     * @dev Internal function to convert an APR in BPS to the internal scaled rate used for calculations.
     * @param aprBps The APR in basis points.
     * @return The corresponding scaled rate.
     */
    function _getScaledRateFromBps(uint256 aprBps) internal pure returns (uint256) {
        if (aprBps == 0) {
            return 0;
        }
        uint256 actual_rps_numerator = aprBps;
        uint256 actual_rps_denominator = Constants.BPS_MAX * Constants.SECONDS_PER_YEAR;
        uint256 numerator_scaled = Math.mulDiv(actual_rps_numerator, INTERNAL_SCALE_RATE, 1);
        numerator_scaled = Math.mulDiv(numerator_scaled, INTERNAL_SCALE_TIME, 1);
        return Math.mulDiv(numerator_scaled, 1, actual_rps_denominator);
    }
    
    /**
     * @dev Internal function to calculate pending rewards for a position.
     * @param pos The user's staking position.
     * @return amountToReturn The calculated rewards.
     */
    function _calculateRewardsForPosition(StakingPosition storage pos) internal view returns (uint256 amountToReturn) {
        if (!pos.active) return 0;
        Tier storage tier = _tiers[pos.tierId];

        uint256 currentBaseRewardRate = _getScaledRateFromBps(_baseAPRBps);

        uint256 currentTime = block.timestamp;
        uint256 effectiveLastClaimTime = pos.lastClaimTime;
        uint256 effectiveEndTime = pos.endTime;

        if (currentTime <= effectiveLastClaimTime) return 0;
        if (effectiveLastClaimTime >= effectiveEndTime) return 0;

        uint256 rewardEndTime = currentTime > effectiveEndTime ? effectiveEndTime : currentTime;
        uint256 timeDelta = rewardEndTime - effectiveLastClaimTime;

        amountToReturn = RewardMath.calculateReward(pos.amount, currentBaseRewardRate, timeDelta, tier.rewardMultiplier);
        return amountToReturn;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function checkEmergencyStatus(bytes4 operation) external view override returns (bool allowed) {
        allowed = !(PausableUpgradeable.paused() || _isEffectivelyPaused());
        if (allowed && address(emergencyController) != address(0)) {
            bool opRestrictedByEC = false;
            try emergencyController.isFunctionRestricted(operation) returns (bool r) {
                opRestrictedByEC = r;
            } catch {
                return true;
            }
            if (opRestrictedByEC) {
                allowed = false;
            }
        }
        return allowed;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function emergencyShutdown(uint8 emergencyLevelInput) external override returns (bool successFlag) {
        if (address(emergencyController) == address(0)) revert TS_ECZero();
        if (msg.sender != address(emergencyController)) revert TS_CallerNotEmergencyController();

        if (emergencyLevelInput >= Constants.EMERGENCY_LEVEL_CRITICAL && !PausableUpgradeable.paused()) {
            _pause();
            emit StakingPaused(msg.sender);
        }
        if (emergencyLevelInput >= Constants.EMERGENCY_LEVEL_ALERT && !_emergencyWithdrawalEnabled) {
            _emergencyWithdrawalEnabled = true;
            emit EmergencyWithdrawalSettingsUpdated(true, _emergencyWithdrawalPenalty, msg.sender);
        }
        emit EmergencyShutdownHandled(emergencyLevelInput, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function getEmergencyController() external view override returns (address controllerAddress) {
        controllerAddress = address(emergencyController);
        return controllerAddress;
    }
    
    /**
     * @inheritdoc IEmergencyAware
     */
    function setEmergencyController(address controllerAddr) external override onlyOwner returns (bool successFlag) {
        if (controllerAddr == address(0)) revert TS_ECZero();
        uint256 codeSize;
        assembly { codeSize := extcodesize(controllerAddr) }
        if (codeSize == 0) revert NotAContract("emergencyController");

        address oldController = address(emergencyController);
        emergencyController = EmergencyController(controllerAddr);
        emit TokenStakingEmergencyControllerSet(oldController, controllerAddr, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Sets the OracleIntegration contract address.
     * @dev Only callable by the owner.
     * @param oracleAddr The address of the new OracleIntegration contract.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function setOracleIntegration(address oracleAddr) external onlyOwner returns (bool successFlag) {
        if (oracleAddr != address(0)) {
            uint256 codeSize;
            assembly { codeSize := extcodesize(oracleAddr) }
            if (codeSize == 0) revert NotAContract("oracleIntegration");
        }
        address oldOracle = address(oracleIntegration);
        oracleIntegration = OracleIntegration(oracleAddr);
        emit TokenStakingOracleIntegrationSet(oldOracle, oracleAddr, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function isEmergencyPaused() public view override returns (bool isPausedStatus) {
        isPausedStatus = PausableUpgradeable.paused() || _isEffectivelyPaused();
        return isPausedStatus;
    }
}
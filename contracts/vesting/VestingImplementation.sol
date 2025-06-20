// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./storage/VestingStorage.sol";
import "./interfaces/IVesting.sol";
import "../interfaces/IEmergencyAware.sol"; 
import "../controllers/EmergencyController.sol"; 
import "../oracle/OracleIntegration.sol"; 
import "../libraries/Errors.sol";
import "../libraries/Constants.sol";
import "../utils/EmergencyAwareBase.sol";

/**
 * @title VestingImplementation
 * @author Rewa
 * @notice A contract that manages a single token vesting schedule for a beneficiary.
 * @dev This contract handles the linear release of tokens over a specified duration, with an optional cliff.
 * It can be revocable by the owner. It is designed to be deployed behind a proxy by a VestingFactory.
 * It inherits from EmergencyAwareBase to be compliant with the system's emergency protocols.
 */
contract VestingImplementation is
    Initializable,
    ReentrancyGuardUpgradeable,
    VestingStorage,
    IVesting,
    EmergencyAwareBase
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice The contract that provides reliable price feeds (optional).
    OracleIntegration public oracleIntegration;

    /**
     * @notice Emitted when the ownership of the vesting schedule is transferred.
     * @param previousOwner The address of the previous owner.
     * @param newOwner The address of the new owner.
     */
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    /**
     * @notice Emitted when the EmergencyController address is changed.
     * @param oldController The previous controller address.
     * @param newController The new controller address.
     * @param setter The address that performed the update.
     */
    event EmergencyControllerSet(address indexed oldController, address indexed newController, address indexed setter);
    /**
     * @notice Emitted when the OracleIntegration address is changed.
     * @param oldOracle The previous oracle address.
     * @param newOracle The new oracle address.
     * @param setter The address that performed the update.
     */
    event OracleIntegrationSet(address indexed oldOracle, address indexed newOracle, address indexed setter);
    
    /**
     * @dev Disables the regular constructor to make the contract upgradeable.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Internal core initialization logic. Shared by both `initialize` overloads.
     * @param tokenAddress_ The address of the token being vested.
     * @param beneficiaryAddress_ The recipient of the vested tokens.
     * @param startTimeValue_ The start time of the vesting period.
     * @param cliffDurationValue_ The duration of the cliff.
     * @param durationValue_ The total duration of the vesting.
     * @param isRevocable_ True if the vesting can be revoked.
     * @param totalVestingAmount_ The total amount of tokens to vest.
     * @param initialOwnerAddress_ The owner of the vesting schedule.
     * @param emergencyControllerAddress_ The address of the EmergencyController.
     * @param oracleIntegrationAddress_ The address of the OracleIntegration contract.
     */
    function _initializeCore(
        address tokenAddress_,
        address beneficiaryAddress_,
        uint256 startTimeValue_,
        uint256 cliffDurationValue_,
        uint256 durationValue_,
        bool isRevocable_,
        uint256 totalVestingAmount_,
        address initialOwnerAddress_,
        address emergencyControllerAddress_,
        address oracleIntegrationAddress_
    ) internal {
        __ReentrancyGuard_init();

        if (tokenAddress_ == address(0)) revert Vesting_TokenZero();
        if (beneficiaryAddress_ == address(0)) revert Vesting_BeneficiaryZero();
        if (initialOwnerAddress_ == address(0)) revert Vesting_OwnerZeroV();
        if (durationValue_ == 0) revert Vesting_DurationZero();
        if (totalVestingAmount_ == 0) revert Vesting_AmountZeroV();
        if (cliffDurationValue_ > durationValue_) revert Vesting_CliffLongerThanDuration();
        if (startTimeValue_ < block.timestamp && startTimeValue_ != 0) revert Vesting_StartTimeInvalid();

        _tokenAddress = tokenAddress_;
        _factoryAddress = msg.sender; 
        _owner = initialOwnerAddress_;

        if (emergencyControllerAddress_ != address(0)) {
            uint256 codeSize;
            assembly { codeSize := extcodesize(emergencyControllerAddress_) }
            if (codeSize == 0) revert NotAContract("emergencyController");
            emergencyController = EmergencyController(emergencyControllerAddress_);
        }
        if (oracleIntegrationAddress_ != address(0)) {
            uint256 codeSize;
            assembly { codeSize := extcodesize(oracleIntegrationAddress_) }
            if (codeSize == 0) revert NotAContract("oracleIntegration");
            oracleIntegration = OracleIntegration(oracleIntegrationAddress_);
        }

        _vestingSchedule = VestingSchedule({
            beneficiary: beneficiaryAddress_,
            totalAmount: totalVestingAmount_,
            startTime: startTimeValue_ == 0 ? block.timestamp : startTimeValue_, 
            cliffDuration: cliffDurationValue_,
            duration: durationValue_,
            releasedAmount: 0,
            revocable: isRevocable_,
            revoked: false
        });
    }

    /**
     * @inheritdoc IVesting
     */
    function initialize(
        address tokenAddress_,
        address beneficiaryAddress_,
        uint256 startTimeValue_,
        uint256 cliffDurationValue_,
        uint256 durationValue_,
        bool isRevocable_,
        uint256 totalVestingAmount_,
        address initialOwnerAddress_,
        address emergencyControllerAddress_,
        address oracleIntegrationAddress_
    ) external override initializer {
        _initializeCore(
            tokenAddress_,
            beneficiaryAddress_,
            startTimeValue_,
            cliffDurationValue_,
            durationValue_,
            isRevocable_,
            totalVestingAmount_,
            initialOwnerAddress_,
            emergencyControllerAddress_,
            oracleIntegrationAddress_
        );
    }

    /**
     * @inheritdoc IVesting
     */
    function initialize(
        address tokenAddress_,
        address beneficiaryAddress_,
        uint256 startTimeValue_,
        uint256 cliffDurationValue_,
        uint256 durationValue_,
        bool isRevocable_,
        uint256 totalVestingAmount_,
        address initialOwnerAddress_
    ) external override initializer {
        _initializeCore(
            tokenAddress_,
            beneficiaryAddress_,
            startTimeValue_,
            cliffDurationValue_,
            durationValue_,
            isRevocable_,
            totalVestingAmount_,
            initialOwnerAddress_,
            address(0),
            address(0)
        );
    }

    /**
     * @dev Modifier to restrict access to the owner of the vesting schedule.
     */
    modifier onlyOwner() {
        if (msg.sender != _owner) revert NotOwner();
        _;
    }

    /**
     * @dev Modifier that reverts if the system is in an emergency state.
     */
    modifier whenNotEmergency() {
        if (_isEffectivelyPaused()) {
            revert SystemInEmergencyMode();
        }
        _;
    }

    /**
     * @inheritdoc IVesting
     */
    function release() external override nonReentrant whenNotEmergency returns (uint256 amountReleased) {
        VestingSchedule storage schedule = _vestingSchedule;
        if (schedule.revoked) revert Vesting_AlreadyRevoked();

        amountReleased = releasableAmount();
        if (amountReleased > 0) {
            schedule.releasedAmount += amountReleased;
            IERC20Upgradeable(_tokenAddress).safeTransfer(schedule.beneficiary, amountReleased);
            emit TokensReleased(schedule.beneficiary, amountReleased);
        } else {
            revert Vesting_NoTokensDue();
        }
        return amountReleased;
    }

    /**
     * @inheritdoc IVesting
     */
    function revoke() external override onlyOwner nonReentrant returns (uint256 amountRefundedToOwner) {
        VestingSchedule storage schedule = _vestingSchedule;

        if (!schedule.revocable) revert Vesting_NotRevocable();
        if (schedule.revoked) revert Vesting_AlreadyRevoked();

        uint256 vestedAtRevocation = vestedAmount(block.timestamp);
        uint256 unreleasedAndVested = 0;

        if (vestedAtRevocation > schedule.releasedAmount) {
            unreleasedAndVested = vestedAtRevocation - schedule.releasedAmount;
        }

        amountRefundedToOwner = schedule.totalAmount - vestedAtRevocation; 
        
        schedule.revoked = true;
        schedule.releasedAmount = schedule.totalAmount;

        IERC20Upgradeable token = IERC20Upgradeable(_tokenAddress);
        if (unreleasedAndVested > 0) { 
            token.safeTransfer(schedule.beneficiary, unreleasedAndVested);
            emit TokensReleased(schedule.beneficiary, unreleasedAndVested);
        }
        if (amountRefundedToOwner > 0) {
            token.safeTransfer(_owner, amountRefundedToOwner);
        }
        emit VestingRevoked(msg.sender, amountRefundedToOwner);
        return amountRefundedToOwner;
    }

    /**
     * @inheritdoc IVesting
     */
    function getVestingSchedule() external view override returns (
        address beneficiaryOut,
        uint256 totalAmountOut,
        uint256 startTimeOut,
        uint256 cliffDurationOut,
        uint256 durationOut,
        uint256 releasedAmountOut,
        bool revocableOut,
        bool revokedOut
    ) {
        VestingSchedule storage s = _vestingSchedule;
        beneficiaryOut = s.beneficiary;
        totalAmountOut = s.totalAmount;
        startTimeOut = s.startTime;
        cliffDurationOut = s.cliffDuration;
        durationOut = s.duration;
        releasedAmountOut = s.releasedAmount;
        revocableOut = s.revocable;
        revokedOut = s.revoked;
    }

    /**
     * @inheritdoc IVesting
     */
    function releasableAmount() public view override returns (uint256 releasable) {
        VestingSchedule storage schedule = _vestingSchedule;
        if (schedule.revoked) return 0;

        uint256 currentVested = vestedAmount(block.timestamp);
        if (currentVested <= schedule.releasedAmount) return 0;

        releasable = currentVested - schedule.releasedAmount;
        return releasable;
    }

    /**
     * @inheritdoc IVesting
     */
    function vestedAmount(uint256 timestamp) public view override returns (uint256 vested) {
        VestingSchedule storage s = _vestingSchedule;

        if (timestamp < s.startTime + s.cliffDuration) return 0;
        if (timestamp >= s.startTime + s.duration) return s.totalAmount;
        
        uint256 timeElapsedSinceStart = timestamp - s.startTime;
        vested = (s.totalAmount * timeElapsedSinceStart) / s.duration;
        
        return vested > s.totalAmount ? s.totalAmount : vested; 
    }

    /**
     * @inheritdoc IVesting
     */
    function owner() external view override returns (address) {
        return _owner;
    }

    /**
     * @notice Gets the address of the vested token.
     * @return tokenAddr_ The ERC20 token address.
     */
    function getTokenAddress() external view returns (address tokenAddr_) {
        tokenAddr_ = _tokenAddress;
        return tokenAddr_;
    }

    /**
     * @notice Gets the address of the factory that created this vesting contract.
     * @return factoryAddr_ The factory address.
     */
    function getFactoryAddress() external view returns (address factoryAddr_) {
        factoryAddr_ = _factoryAddress;
        return factoryAddr_;
    }

    /**
     * @notice Transfers ownership of the vesting contract to a new address.
     * @param newOwner The address of the new owner.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function transferOwnership(address newOwner) external onlyOwner nonReentrant returns (bool successFlag) {
        if (newOwner == address(0)) revert ZeroAddress("newOwner");
        address oldOwnerAddr = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwnerAddr, newOwner);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function checkEmergencyStatus(bytes4 ) external view override returns (bool allowed) {
        allowed = !_isEffectivelyPaused();
        return allowed;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function emergencyShutdown(uint8 emergencyLevel) external override returns (bool successFlag) {
        if (address(emergencyController) == address(0) && msg.sender != _factoryAddress) { 
            revert Vesting_CallerNotEmergencyController();
        }
        if (address(emergencyController) != address(0) && msg.sender != address(emergencyController)) {
            revert Vesting_CallerNotEmergencyController();
        }
        emit EmergencyShutdownHandled(emergencyLevel, msg.sender);
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
        address oldController = address(emergencyController); 
        if (controllerAddr != address(0)) {
            uint256 codeSize;
            assembly { codeSize := extcodesize(controllerAddr) }
            if (codeSize == 0) revert NotAContract("emergencyController");
        }
        emergencyController = EmergencyController(controllerAddr);
        emit EmergencyControllerSet(oldController, controllerAddr, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Sets the OracleIntegration contract address.
     * @param oracleAddr The address of the new OracleIntegration contract.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function setOracleIntegration(address oracleAddr) external onlyOwner returns (bool successFlag) {
        address oldOracle = address(oracleIntegration);
        if (oracleAddr != address(0)) {
            uint256 codeSize;
            assembly { codeSize := extcodesize(oracleAddr) }
            if (codeSize == 0) revert NotAContract("oracleIntegration");
        }
        oracleIntegration = OracleIntegration(oracleAddr);
        emit OracleIntegrationSet(oldOracle, oracleAddr, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function isEmergencyPaused() external view override returns (bool isPausedStatus) {
        isPausedStatus = _isEffectivelyPaused();
        return isPausedStatus;
    }
}
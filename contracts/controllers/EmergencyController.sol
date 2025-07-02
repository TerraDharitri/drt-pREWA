// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../access/AccessControl.sol";
import "../interfaces/IEmergencyAware.sol";
import "../interfaces/IEmergencyController.sol";
import "../controllers/EmergencyTimelockController.sol"; 
import "../libraries/Errors.sol";
import "../libraries/Constants.sol";

/**
 * @title EmergencyController
 * @author Rewa
 * @notice A central controller for managing system-wide emergency states and actions.
 * @dev This contract orchestrates responses to security threats across multiple integrated contracts.
 * It defines several emergency levels, can globally pause the system, and enables emergency withdrawals.
 * Critical actions, like escalating to the highest emergency level, require a multi-approval and timelock process.
 * This contract is upgradeable.
 */
contract EmergencyController is
    Initializable,
    ReentrancyGuardUpgradeable,
    IEmergencyController
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice The maximum number of approvals required for a Level 3 emergency escalation.
    uint256 public constant MAX_REQUIRED_APPROVALS = 20;

    /// @notice The contract that controls roles and permissions.
    AccessControl public accessControl;
    /// @notice The timelock controller for scheduling privileged emergency actions (optional).
    EmergencyTimelockController public timelockController;

    /// @notice The current system-wide emergency level (0=Normal, 1=Caution, 2=Alert, 3=Critical).
    uint8 public emergencyLevel;
    /// @notice The number of unique approvals required to initiate the Level 3 timelock.
    uint256 public requiredApprovals;
    
    /// @dev Tracks which proposal ID an address has approved for Level 3 escalation.
    mapping(address => uint256) public emergencyApprovalProposalIds;
    /// @dev A unique identifier for the current Level 3 proposal, invalidating old approvals on reset.
    uint256 public level3ProposalId;

    /// @notice A list of addresses that have approved the current Level 3 escalation.
    address[] public currentApprovers;
    /// @notice The current number of approvals for a Level 3 escalation.
    uint256 public currentApprovalCount;
    /// @notice The timestamp when the Level 3 timelock began.
    uint256 public level3ApprovalTime;
    /// @notice The duration of the timelock for Level 3 escalation.
    uint256 public level3TimelockDuration;
    /// @notice A flag indicating if a Level 3 escalation timelock is currently active.
    bool public level3TimelockInProgress;
    /// @notice A flag indicating if emergency withdrawal is globally enabled.
    bool public emergencyWithdrawalEnabled;
    /// @notice The penalty (in BPS) applied to emergency withdrawals.
    uint256 public emergencyWithdrawalPenalty;
    /// @notice A flag indicating if the entire system is globally paused.
    bool public systemPaused;

    /// @dev An array of all registered contracts that are aware of emergency states.
    address[] private _emergencyAwareContracts;
    /// @dev A mapping to check if a contract is registered as emergency-aware.
    mapping(address => bool) private _isEmergencyAwareContract;
    /// @dev A mapping from an emergency-aware contract address to its index in the array for O(1) removal.
    mapping(address => uint256) private _emergencyAwareContractIndices;

    /// @notice Maps a function selector to the minimum emergency level at which it becomes restricted.
    mapping(bytes4 => uint8) public restrictedFunctions;
    /// @dev Tracks if an emergency level has been broadcast to aware contracts to prevent re-notification.
    mapping(uint8 => bool) public emergencyLevelNotified;
    /// @dev Stores the timestamp when an emergency level was last broadcast.
    mapping(uint8 => uint256) public emergencyLevelTimestamp;
    /// @dev Tracks if a specific contract has processed a specific emergency level notification.
    mapping(address => mapping(uint8 => bool)) public contractProcessedEmergency;
    /// @notice The address authorized to receive tokens recovered via the `recoverTokens` function.
    address public recoveryAdminAddress;

    /**
     * @notice Emitted when a new contract is registered as emergency-aware.
     * @param contractAddress The address of the registered contract.
     * @param registrar The address that performed the registration.
     */
    event EmergencyAwareContractRegistered(address indexed contractAddress, address indexed registrar);
    /**
     * @notice Emitted when an emergency-aware contract is removed from the registry.
     * @param contractAddress The address of the removed contract.
     * @param remover The address that performed the removal.
     */
    event EmergencyAwareContractRemoved(address indexed contractAddress, address indexed remover);
    /**
     * @notice Emitted when the number of required approvals for Level 3 is updated.
     * @param oldValue The previous number of approvals.
     * @param newValue The new number of approvals.
     * @param updater The address that performed the update.
     */
    event RequiredApprovalsUpdated(uint256 oldValue, uint256 newValue, address indexed updater);
    /**
     * @notice Emitted when the timelock duration for Level 3 is updated.
     * @param oldDuration The previous timelock duration in seconds.
     * @param newDuration The new timelock duration in seconds.
     * @param updater The address that performed the update.
     */
    event Level3TimelockDurationUpdated(uint256 oldDuration, uint256 newDuration, address indexed updater);
    /**
     * @notice Emitted when an address approves a Level 3 escalation.
     * @param approver The address that submitted the approval.
     * @param currentCount The total number of approvals after this one.
     * @param requiredCount The number of approvals required to start the timelock.
     */
    event EmergencyApprovalAdded(address indexed approver, uint256 currentCount, uint256 requiredCount);
    /**
     * @notice Emitted when the timelock for a Level 3 escalation begins.
     * @param unlockTime The timestamp when the timelock will expire.
     * @param starter The address that submitted the final required approval.
     */
    event Level3TimelockStarted(uint256 unlockTime, address indexed starter);
    /**
     * @notice Emitted when a Level 3 escalation is cancelled.
     * @param canceller The address that cancelled the escalation.
     */
    event Level3TimelockCancelled(address indexed canceller);
    /**
     * @notice Emitted when an emergency-aware contract successfully processes an emergency shutdown signal.
     * @param level The emergency level that was processed.
     * @param contractAddress The address of the contract that was notified.
     * @param success A flag indicating if the call to the contract succeeded.
     */
    event EmergencyNotificationProcessed(uint8 level, address indexed contractAddress, bool success);
    /**
     * @notice Emitted if notifying an emergency-aware contract fails.
     * @param contractAddress The address of the contract that failed to be notified.
     * @param reason A string describing the reason for failure.
     */
    event NotificationFailure(address indexed contractAddress, string reason);
    /**
     * @notice Emitted when the emergency level restriction for a function is updated.
     * @param selector The 4-byte selector of the function.
     * @param threshold The new minimum emergency level for the restriction to apply.
     * @param updater The address that performed the update.
     */
    event FunctionRestrictionUpdated(bytes4 indexed selector, uint8 threshold, address indexed updater);
    /**
     * @notice Emitted when the state for a Level 3 approval process is reset.
     */
    event EmergencyApprovalReset();
    /**
     * @notice Emitted when the recovery admin address is updated.
     * @param oldAdmin The previous recovery admin address.
     * @param newAdmin The new recovery admin address.
     * @param updater The address that performed the update.
     */
    event RecoveryAdminAddressUpdated(address indexed oldAdmin, address indexed newAdmin, address indexed updater);

    /**
     * @dev Modifier for functions restricted to accounts with the EMERGENCY_ROLE.
     */
    modifier onlyEmergencyRole() {
        if (address(accessControl) == address(0)) revert EC_AccessControlZero();
        if (!accessControl.hasRole(accessControl.EMERGENCY_ROLE(), msg.sender)) revert EC_MustHaveEmergencyRole();
        _;
    }

    /**
     * @dev Modifier for functions restricted to accounts with the PAUSER_ROLE.
     */
    modifier onlyPauserRole() {
        if (address(accessControl) == address(0)) revert EC_AccessControlZero();
        if (!accessControl.hasRole(accessControl.PAUSER_ROLE(), msg.sender)) revert EC_MustHavePauserRole();
        _;
    }

    /**
     * @dev Modifier for functions restricted to accounts with the DEFAULT_ADMIN_ROLE.
     */
    modifier onlyAdminRole() {
        if (address(accessControl) == address(0)) revert EC_AccessControlZero();
        if (!accessControl.hasRole(accessControl.DEFAULT_ADMIN_ROLE(), msg.sender)) revert EC_MustHaveAdminRole();
        _;
    }

    /**
     * @dev Disables the regular constructor to make the contract upgradeable.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the EmergencyController contract.
     * @dev Sets up the initial configuration, including dependent contract addresses and parameters. Can only be called once.
     * @param accessControlAddress_ The address of the AccessControl contract.
     * @param timelockControllerAddress_ The address of the EmergencyTimelockController (can be address(0)).
     * @param initialRequiredApprovals_ The initial number of approvals for a Level 3 emergency.
     * @param initialLevel3TimelockDuration_ The initial timelock duration for a Level 3 emergency.
     * @param initialRecoveryAdminAddress_ The address for receiving recovered tokens.
     */
    function initialize(
        address accessControlAddress_,
        address timelockControllerAddress_,
        uint256 initialRequiredApprovals_,
        uint256 initialLevel3TimelockDuration_,
        address initialRecoveryAdminAddress_
    ) external initializer {
        __ReentrancyGuard_init();

        if (accessControlAddress_ == address(0)) revert EC_AccessControlZero();
        if (initialRequiredApprovals_ == 0) revert EC_RequiredApprovalsZero();
        if (initialRequiredApprovals_ > MAX_REQUIRED_APPROVALS) revert EC_RequiredApprovalsTooHigh(initialRequiredApprovals_, MAX_REQUIRED_APPROVALS);
        if (initialLevel3TimelockDuration_ < Constants.MIN_TIMELOCK_DURATION) revert EC_TimelockTooShort();
        if (initialLevel3TimelockDuration_ > Constants.MAX_TIMELOCK_DURATION) revert EC_TimelockTooLong();
        if (initialRecoveryAdminAddress_ == address(0)) revert ZeroAddress("initialRecoveryAdminAddress_");

        uint256 codeSize;
        assembly { codeSize := extcodesize(accessControlAddress_) }
        if (codeSize == 0) revert NotAContract("accessControl");
        if (timelockControllerAddress_ != address(0)) {
            assembly { codeSize := extcodesize(timelockControllerAddress_) }
            if (codeSize == 0) revert NotAContract("timelockController");
        }

        accessControl = AccessControl(accessControlAddress_);
        if (timelockControllerAddress_ != address(0)) {
            timelockController = EmergencyTimelockController(timelockControllerAddress_);
        }
        recoveryAdminAddress = initialRecoveryAdminAddress_;

        emergencyLevel = Constants.EMERGENCY_LEVEL_NORMAL;
        emergencyWithdrawalEnabled = false;
        emergencyWithdrawalPenalty = Constants.DEFAULT_PENALTY;
        systemPaused = false;
        requiredApprovals = initialRequiredApprovals_;
        level3TimelockDuration = initialLevel3TimelockDuration_;
        level3ProposalId = 1;
    }

    /**
     * @notice Sets the number of approvals required to trigger a Level 3 emergency timelock.
     * @param newRequiredApprovals The new number of approvals.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function setRequiredApprovals(uint256 newRequiredApprovals) external onlyAdminRole returns (bool successFlag) {
        if (newRequiredApprovals == 0) revert EC_RequiredApprovalsZero();
        if (newRequiredApprovals > MAX_REQUIRED_APPROVALS) revert EC_RequiredApprovalsTooHigh(newRequiredApprovals, MAX_REQUIRED_APPROVALS);

        uint256 oldValue = requiredApprovals;
        requiredApprovals = newRequiredApprovals;
        _resetApprovals();
        emit RequiredApprovalsUpdated(oldValue, newRequiredApprovals, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Sets the duration of the timelock for a Level 3 emergency escalation.
     * @param newDuration The new timelock duration in seconds.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function setLevel3TimelockDuration(uint256 newDuration) external onlyAdminRole returns (bool successFlag) {
        if (newDuration < Constants.MIN_TIMELOCK_DURATION) revert EC_TimelockTooShort();
        if (newDuration > Constants.MAX_TIMELOCK_DURATION) revert EC_TimelockTooLong();

        uint256 oldDuration = level3TimelockDuration;
        level3TimelockDuration = newDuration;
        emit Level3TimelockDurationUpdated(oldDuration, newDuration, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Sets the address that will receive tokens recovered from this contract.
     * @param newRecoveryAdminAddress The new recovery admin address.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function setRecoveryAdminAddress(address newRecoveryAdminAddress) external onlyAdminRole returns (bool successFlag) {
        if (newRecoveryAdminAddress == address(0)) revert ZeroAddress("newRecoveryAdminAddress");
        address oldAdmin = recoveryAdminAddress;
        recoveryAdminAddress = newRecoveryAdminAddress;
        emit RecoveryAdminAddressUpdated(oldAdmin, newRecoveryAdminAddress, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Submits an approval for escalating to a Level 3 (Critical) emergency.
     * @dev Once the required number of approvals is met, a timelock begins. This system uses a proposal ID
     * to ensure approvals are only valid for the current escalation attempt, preventing the use of stale approvals.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function approveLevel3Emergency() external onlyEmergencyRole nonReentrant returns (bool successFlag) {
        if (emergencyLevel >= Constants.EMERGENCY_LEVEL_CRITICAL) revert EC_AlreadyAtLevel3();
        
        if (emergencyApprovalProposalIds[msg.sender] == level3ProposalId) {
            successFlag = true;
            return successFlag;
        }

        emergencyApprovalProposalIds[msg.sender] = level3ProposalId;
        currentApprovers.push(msg.sender);
        currentApprovalCount++;
        emit EmergencyApprovalAdded(msg.sender, currentApprovalCount, requiredApprovals);

        if (currentApprovalCount >= requiredApprovals && !level3TimelockInProgress) {
            level3ApprovalTime = block.timestamp;
            level3TimelockInProgress = true;
            emit Level3TimelockStarted(level3ApprovalTime + level3TimelockDuration, msg.sender);
        }
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Cancels an in-progress Level 3 emergency escalation.
     * @dev This resets all approvals and stops the timelock.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function cancelLevel3Emergency() external onlyEmergencyRole nonReentrant returns (bool successFlag) {
        if (!level3TimelockInProgress && currentApprovalCount == 0) revert EC_NoLevel3EscalationInProgress();
        _resetApprovals();
        emit Level3TimelockCancelled(msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Executes the escalation to a Level 3 emergency after the timelock has passed.
     * @dev Sets the emergency level to Critical, enables emergency withdrawals, and pauses the system.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function executeLevel3Emergency() external onlyEmergencyRole nonReentrant returns (bool successFlag) {
        if (!level3TimelockInProgress) revert EC_NoLevel3EscalationInProgress();
        if (block.timestamp < (level3ApprovalTime + level3TimelockDuration)) revert EC_Level3TimelockNotExpired();

        emergencyLevel = Constants.EMERGENCY_LEVEL_CRITICAL;
        if (!emergencyWithdrawalEnabled) {
            emergencyWithdrawalEnabled = true;
            emit EmergencyWithdrawalSet(true, emergencyWithdrawalPenalty);
        }
        if (!systemPaused) {
            systemPaused = true;
            emit SystemPaused(msg.sender);
        }
        emit EmergencyLevelSet(Constants.EMERGENCY_LEVEL_CRITICAL, msg.sender);

        _resetApprovals();

        uint8 currentLevel = Constants.EMERGENCY_LEVEL_CRITICAL;
        if (!emergencyLevelNotified[currentLevel] || emergencyLevelTimestamp[currentLevel] < level3ApprovalTime) {
            emergencyLevelNotified[currentLevel] = true;
            emergencyLevelTimestamp[currentLevel] = block.timestamp;
        }
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc IEmergencyController
     */
    function setEmergencyLevel(uint8 level) external override onlyEmergencyRole nonReentrant returns (bool successFlag) {
        if (level > Constants.EMERGENCY_LEVEL_CRITICAL) revert EC_InvalidEmergencyLevel(level);
        if (level == Constants.EMERGENCY_LEVEL_CRITICAL) revert EC_UseApproveForLevel3();

        uint8 oldLevel = emergencyLevel;
        emergencyLevel = level;

        if (level >= Constants.EMERGENCY_LEVEL_ALERT && !emergencyWithdrawalEnabled) {
            emergencyWithdrawalEnabled = true;
            emit EmergencyWithdrawalSet(true, emergencyWithdrawalPenalty);
        }

        if (level == Constants.EMERGENCY_LEVEL_NORMAL) {
            if (emergencyWithdrawalEnabled) {
                emergencyWithdrawalEnabled = false;
                emit EmergencyWithdrawalSet(false, emergencyWithdrawalPenalty);
            }
            if (systemPaused) {
                systemPaused = false;
                emit SystemUnpaused(msg.sender);
            }
            if (level3TimelockInProgress || currentApprovalCount > 0) {
                _resetApprovals();
                emit Level3TimelockCancelled(msg.sender);
            }
        }

        emit EmergencyLevelSet(level, msg.sender);
        
        if (level > oldLevel && (!emergencyLevelNotified[level] || (emergencyLevelTimestamp[level] < block.timestamp - 1 hours))) {
            emergencyLevelNotified[level] = true;
            emergencyLevelTimestamp[level] = block.timestamp;
        }
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc IEmergencyController
     */
    function enableEmergencyWithdrawal(
        bool enabled,
        uint256 penalty
    ) external override onlyEmergencyRole nonReentrant returns (bool successFlag) {
        if (penalty > Constants.MAX_PENALTY) revert EC_PenaltyTooHigh(penalty);

        emergencyWithdrawalEnabled = enabled;
        emergencyWithdrawalPenalty = penalty;
        emit EmergencyWithdrawalSet(enabled, penalty);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc IEmergencyController
     */
    function pauseSystem() external override onlyPauserRole nonReentrant returns (bool successFlag) {
        if (systemPaused) revert EC_SystemAlreadyPaused();
        systemPaused = true;
        emit SystemPaused(msg.sender);

        uint8 impliedLevel = Constants.EMERGENCY_LEVEL_CRITICAL;
        if (!emergencyLevelNotified[impliedLevel] || (emergencyLevelTimestamp[impliedLevel] < block.timestamp - 1 hours)) {
            emergencyLevelNotified[impliedLevel] = true;
            emergencyLevelTimestamp[impliedLevel] = block.timestamp;
        }
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc IEmergencyController
     */
    function unpauseSystem() external override onlyPauserRole nonReentrant returns (bool successFlag) {
        if (!systemPaused) revert EC_SystemNotPaused();
        if (emergencyLevel >= Constants.EMERGENCY_LEVEL_CRITICAL) revert EC_CannotUnpauseAtLevel3();

        systemPaused = false;
        emit SystemUnpaused(msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc IEmergencyController
     */
    function recoverTokens(
        address tokenAddress,
        uint256 amount
    ) external override onlyEmergencyRole nonReentrant returns (bool successFlag) {
        if (recoveryAdminAddress == address(0)) revert EC_RecoveryAdminNotSet();
        if (tokenAddress == address(0)) revert ZeroAddress("tokenAddress for recovery");
        if (amount == 0) revert AmountIsZero();

        IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        if (amount > balance) revert EC_InsufficientBalanceToRecover();

        token.safeTransfer(recoveryAdminAddress, amount);
        emit TokensRecovered(tokenAddress, amount, recoveryAdminAddress);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Registers a contract as being "emergency-aware".
     * @dev Aware contracts can be notified of emergency state changes.
     * @param contractAddr The address of the contract to register.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function registerEmergencyAwareContract(address contractAddr) external onlyEmergencyRole returns (bool successFlag) {
        if (contractAddr == address(0)) revert EC_ContractAddressZero();
        if (_isEmergencyAwareContract[contractAddr]) {
            successFlag = true;
            return successFlag;
        }

        _isEmergencyAwareContract[contractAddr] = true;
        _emergencyAwareContracts.push(contractAddr);
        _emergencyAwareContractIndices[contractAddr] = _emergencyAwareContracts.length - 1;

        emit EmergencyAwareContractRegistered(contractAddr, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Removes an emergency-aware contract from the registry.
     * @dev Uses the "swap and pop" technique for O(1) gas complexity.
     * @param contractAddr The address of the contract to remove.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function removeEmergencyAwareContract(address contractAddr) external onlyEmergencyRole returns (bool successFlag) {
        if (contractAddr == address(0)) revert EC_ContractAddressZero();
        if (!_isEmergencyAwareContract[contractAddr]) revert EC_ContractNotRegistered(contractAddr);

        uint256 indexToRemove = _emergencyAwareContractIndices[contractAddr];
        address[] storage awareContracts = _emergencyAwareContracts;
        uint256 lastIndex = awareContracts.length - 1;

        if (indexToRemove != lastIndex) {
            address contractToMove = awareContracts[lastIndex];
            awareContracts[indexToRemove] = contractToMove;
            _emergencyAwareContractIndices[contractToMove] = indexToRemove;
        }

        awareContracts.pop();
        delete _emergencyAwareContractIndices[contractAddr];
        _isEmergencyAwareContract[contractAddr] = false;

        emit EmergencyAwareContractRemoved(contractAddr, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Triggers the `emergencyShutdown` function on a specific registered contract.
     * @dev This allows for granular control over emergency responses. It is guarded against being called too
     * frequently for the same contract and level to prevent misuse.
     * @param contractAddr The address of the target emergency-aware contract.
     * @param level The emergency level to pass to the target contract.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function processEmergencyForContract(address contractAddr, uint8 level) external nonReentrant returns (bool successFlag) {
        if (contractAddr == address(0)) revert EC_ContractAddressZero();
        if (level > Constants.EMERGENCY_LEVEL_CRITICAL) revert EC_InvalidEmergencyLevel(level);
        if (emergencyLevel < level) revert EC_LevelNotInEmergency(level);
        if (contractProcessedEmergency[contractAddr][level] && emergencyLevelTimestamp[level] > 0 && block.timestamp - emergencyLevelTimestamp[level] < 1 days) {
           revert EC_AlreadyProcessed(contractAddr, level);
        }
        if (!_isEmergencyAwareContract[contractAddr]) revert EC_ContractNotRegistered(contractAddr);

        contractProcessedEmergency[contractAddr][level] = true;

        // This is a low-level call to an external, arbitrary contract. It is a necessary part of the
        // emergency broadcast system. The function being called (`emergencyShutdown`) is part of a
        // standardized interface (IEmergencyAware), and access to this `processEmergencyForContract`
        // function is highly restricted, mitigating reentrancy and other risks.
        bytes memory callData = abi.encodeWithSelector(IEmergencyAware.emergencyShutdown.selector, level);
        
        (bool callSuccess, ) = contractAddr.call(callData);

        if (!callSuccess) {
            revert EC_EmergencyShutdownCallFailed();
        }

        successFlag = true;
        emit EmergencyNotificationProcessed(level, contractAddr, true);
        return successFlag;
    }

    /**
     * @notice Sets or updates the minimum emergency level at which a function becomes restricted.
     * @param funcSelector The 4-byte selector of the function to restrict.
     * @param thresholdVal The minimum emergency level (1-3) for the restriction to apply. 0 to unrestrict.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function updateFunctionRestriction(bytes4 funcSelector, uint8 thresholdVal) external onlyEmergencyRole returns (bool successFlag) {
        if (thresholdVal > Constants.EMERGENCY_LEVEL_CRITICAL) revert EC_ThresholdInvalid(thresholdVal);
        restrictedFunctions[funcSelector] = thresholdVal;
        emit FunctionRestrictionUpdated(funcSelector, thresholdVal, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc IEmergencyController
     */
    function getEmergencyLevel() external view override returns (uint8 levelOut) {
        levelOut = emergencyLevel;
        return levelOut;
    }

    /**
     * @inheritdoc IEmergencyController
     */
    function getEmergencyWithdrawalSettings() external view override returns (bool enabledOut, uint256 penaltyOut) {
        enabledOut = emergencyWithdrawalEnabled;
        penaltyOut = emergencyWithdrawalPenalty;
    }

    /**
     * @inheritdoc IEmergencyController
     */
    function isSystemPaused() external view override returns (bool isPausedFlag) {
        isPausedFlag = systemPaused;
        return isPausedFlag;
    }

    /**
     * @inheritdoc IEmergencyController
     */
    function getEmergencyAwareContractsPaginated(uint256 offset, uint256 limit) external view override returns (address[] memory page, uint256 totalContracts) {
        if (limit == 0) revert EC_LimitIsZero();
    
        address[] storage awareContracts = _emergencyAwareContracts;
        totalContracts = awareContracts.length;

        if (offset >= totalContracts) {
            page = new address[](0);
            return (page, totalContracts);
        }

        uint256 count = totalContracts - offset < limit ? totalContracts - offset : limit;
        page = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            page[i] = awareContracts[offset + i];
        }
        return (page, totalContracts);
    }

    /**
     * @notice Gets the current status of the Level 3 emergency approval process.
     * @param approversOffset The starting index for paginating through the list of approvers.
     * @param approversLimit The maximum number of approver addresses to return.
     * @return currentCountOut The number of approvals received so far.
     * @return requiredOut The number of approvals required.
     * @return approversPage A paginated list of addresses that have approved.
     * @return nextApproverOffset The offset for the next page of approvers.
     * @return totalApprovers The total number of approvers.
     * @return timelockActiveOut True if the timelock is currently active.
     * @return executeAfterOut The timestamp when the timelock expires.
     */
    function getApprovalStatus(uint256 approversOffset, uint256 approversLimit) external view returns (
        uint256 currentCountOut,
        uint256 requiredOut,
        address[] memory approversPage,
        uint256 nextApproverOffset,
        uint256 totalApprovers,
        bool timelockActiveOut,
        uint256 executeAfterOut
    ) {
        currentCountOut = currentApprovalCount;
        requiredOut = requiredApprovals;
        timelockActiveOut = level3TimelockInProgress;
        executeAfterOut = level3TimelockInProgress ? (level3ApprovalTime + level3TimelockDuration) : 0;

        address[] storage approversArray = currentApprovers;
        totalApprovers = approversArray.length;

        if (approversLimit == 0 || approversOffset >= totalApprovers) {
            approversPage = new address[](0);
            nextApproverOffset = totalApprovers;
        } else {
            uint256 count = totalApprovers - approversOffset < approversLimit ? totalApprovers - approversOffset : approversLimit;
            approversPage = new address[](count);
            for (uint256 i = 0; i < count; i++) {
                approversPage[i] = approversArray[approversOffset + i];
            }
            nextApproverOffset = approversOffset + count;
        }
    }

    /**
     * @notice Checks if a specific function is currently restricted due to the system's emergency level.
     * @param functionSelector The 4-byte selector of the function to check.
     * @return isRestrictedFlag True if the function is currently restricted.
     */
    function isFunctionRestricted(bytes4 functionSelector) external view returns (bool isRestrictedFlag) {
        uint8 threshold = restrictedFunctions[functionSelector];
        isRestrictedFlag = (threshold > Constants.EMERGENCY_LEVEL_NORMAL && emergencyLevel >= threshold);
        return isRestrictedFlag;
    }

    /**
     * @dev Internal function to reset the Level 3 approval state. It increments the proposal ID,
     * which efficiently invalidates all previous approvals for the old proposal in O(1) time without
     * needing to iterate through the approvers mapping.
     */
    function _resetApprovals() internal {
        if (level3ProposalId < type(uint256).max) {
            level3ProposalId++;
        } else {
            level3ProposalId = 1; // Safe wraparound for the unlikely case of overflow.
        }

        delete currentApprovers; 
        currentApprovalCount = 0;
        level3TimelockInProgress = false;
        level3ApprovalTime = 0;
        emit EmergencyApprovalReset();
    }
}
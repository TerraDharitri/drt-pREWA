// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "../interfaces/IEmergencyAware.sol";
import "../controllers/EmergencyController.sol";
import "../access/AccessControl.sol";
import "../oracle/OracleIntegration.sol";
import "../libraries/Errors.sol";
import "../libraries/Constants.sol";

/**
 * @title SecurityModule
 * @author Rewa
 * @notice A comprehensive security contract designed to monitor and mitigate various on-chain risks.
 * @dev This contract provides a suite of security features including flash loan detection, price anomaly validation,
 * volume monitoring, and transaction sequencing checks. It integrates with an EmergencyController to respond
 * to system-wide threats and an OracleIntegration for reliable price data. This contract is upgradeable.
 */
contract SecurityModule is
    Initializable,
    ReentrancyGuardUpgradeable,
    IEmergencyAware
{
    /// @notice The contract that controls roles and permissions.
    AccessControl public accessControl;
    /// @notice The central controller for system-wide emergency states.
    EmergencyController public emergencyController;
    /// @notice The contract that provides reliable price feeds for tokens.
    OracleIntegration public oracleIntegration;

    /// @notice The default threshold in basis points for detecting a potential flash loan based on a rapid balance increase.
    uint256 public flashLoanDetectionThresholdBps;
    /// @notice The maximum allowed price deviation in basis points between a provided price and the oracle price.
    uint256 public priceDeviationThresholdBps;
    /// @notice The threshold in basis points for detecting an anomalous trading volume spike.
    uint256 public volumeAnomalyThresholdBps;

    /// @notice Per-token overrides for the flash loan detection threshold in basis points.
    mapping(address => uint256) public tokenFlashLoanThresholdsBps;

    /// @notice The minimum number of blocks that must pass between transactions from the same account for certain checks.
    uint256 public transactionCooldownBlocks;
    /// @notice A flag to manually pause the security features of this module.
    bool public securityPaused;

    /// @notice Records the timestamp of the last transaction for a given account.
    mapping(address => uint256) public lastTransactionTimestamp;
    /// @notice Records the block number of the last transaction for a given account.
    mapping(address => uint256) public lastTransactionBlock;
    /// @notice Counts the number of transactions for a given account.
    mapping(address => uint256) public transactionCount;
    /// @dev Stores the last known balance of a token for a given account to detect anomalous changes.
    mapping(address => mapping(address => uint256)) private _lastKnownBalances;

    /// @notice The total volume recorded in the previous 24-hour period.
    uint256 public lastDailyVolume;
    /// @notice The accumulating volume for the current 24-hour period.
    uint256 public currentDailyVolume;
    /// @notice The timestamp when the daily volume was last reset.
    uint256 public lastVolumeUpdateTime;
    /// @notice The maximum gas to be used for external calls (e.g., to oracles or token contracts).
    uint256 public maxGasForExternalCalls;

    /**
     * @notice Emitted when a large, suspicious transaction is detected within the cooldown period.
     * @param user The address of the user.
     * @param token The address of the token.
     * @param amount The suspicious transaction amount.
     * @param detectedAtBlock The block number of detection.
     */
    event FlashLoanDetected(address indexed user, address indexed token, uint256 amount, uint256 detectedAtBlock);
    /**
     * @notice Emitted when a user's balance increases by more than the configured threshold within the cooldown period.
     * @param account The address of the account.
     * @param token The address of the token.
     * @param previousBalance The account's balance before the anomalous increase.
     * @param currentBalance The account's balance after the anomalous increase.
     */
    event PotentialFlashLoanDetected(address indexed account, address indexed token, uint256 previousBalance, uint256 currentBalance);
    /**
     * @notice Emitted when a provided price deviates from the oracle price by more than the configured threshold.
     * @param token The address of the token.
     * @param expectedPrice The price from the oracle.
     * @param actualPrice The price that was provided for validation.
     * @param detectedAtTime The timestamp of detection.
     */
    event PriceAnomalyDetected(address indexed token, uint256 expectedPrice, uint256 actualPrice, uint256 detectedAtTime);
    /**
     * @notice Emitted when the daily trading volume exceeds the expected prorated volume by more than the configured threshold.
     * @param expectedVolume The expected volume based on the previous day.
     * @param actualVolume The current accumulated volume.
     * @param detectedAtTime The timestamp of detection.
     */
    event VolumeAnomalyDetected(uint256 expectedVolume, uint256 actualVolume, uint256 detectedAtTime);
    /**
     * @notice Emitted when the security module is paused.
     * @param pauser The address that initiated the pause.
     * @param timestamp The timestamp of the pause.
     */
    event SecurityPaused(address indexed pauser, uint256 timestamp);
    /**
     * @notice Emitted when the security module is resumed from a paused state.
     * @param resumer The address that initiated the resume.
     * @param timestamp The timestamp of the resume.
     */
    event SecurityResumed(address indexed resumer, uint256 timestamp);
    /**
     * @notice Emitted when global security parameters are updated.
     * @param newFlashLoanThresholdBps The new default flash loan detection threshold.
     * @param newPriceDeviationThresholdBps The new price deviation threshold.
     * @param newVolumeAnomalyThresholdBps The new volume anomaly threshold.
     * @param updater The address that performed the update.
     */
    event SecurityParametersUpdated(
        uint256 newFlashLoanThresholdBps,
        uint256 newPriceDeviationThresholdBps,
        uint256 newVolumeAnomalyThresholdBps,
        address indexed updater
    );
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
     * @notice Emitted when a token-specific flash loan threshold is set or updated.
     * @param token The address of the token.
     * @param oldThresholdBps The previous threshold.
     * @param newThresholdBps The new threshold.
     * @param setter The address that performed the update.
     */
    event TokenFlashLoanThresholdSet(address indexed token, uint256 oldThresholdBps, uint256 newThresholdBps, address indexed setter);
    /**
     * @notice Emitted when an external call to an oracle or token contract fails.
     * @param token The address of the token involved in the failed call.
     * @param reason A string describing the reason for failure.
     */
    event OracleFailure(address indexed token, string reason);
    /**
     * @notice Emitted when the maximum gas limit for external calls is updated.
     * @param oldLimit The previous gas limit.
     * @param newLimit The new gas limit.
     * @param setter The address that performed the update.
     */
    event MaxGasForExternalCallsUpdated(uint256 oldLimit, uint256 newLimit, address indexed setter);
    /**
     * @notice Emitted when the transaction cooldown period (in blocks) is updated.
     * @param oldCooldown The previous cooldown period.
     * @param newCooldown The new cooldown period.
     * @param updater The address that performed the update.
     */
    event TransactionCooldownUpdated(uint256 oldCooldown, uint256 newCooldown, address indexed updater);
    /**
     * @notice Emitted as a warning when the price data from an oracle is older than the staleness threshold.
     * @param token The address of the token with stale price data.
     * @param priceTimestamp The timestamp of the stale price.
     * @param currentTimestamp The current block timestamp.
     */
    event StalePriceWarning(address indexed token, uint256 priceTimestamp, uint256 currentTimestamp);

    /**
     * @dev Reserved storage space to allow for future upgrades without storage collisions.
     * This is a best practice for upgradeable contracts.
     */
    uint256[44] private __gap;

    /**
     * @dev Disables the regular constructor to make the contract upgradeable.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the SecurityModule contract.
     * @dev This function sets up the initial state of the contract, including addresses for access control,
     * emergency management, and oracle integration. It can only be called once.
     * @param accessControlAddr_ The address of the AccessControl contract.
     * @param emergencyControllerAddress_ The address of the EmergencyController contract.
     * @param oracleIntegrationAddress_ The address of the OracleIntegration contract.
     */
    function initialize(
        address accessControlAddr_,
        address emergencyControllerAddress_,
        address oracleIntegrationAddress_
    ) external initializer {
        __ReentrancyGuard_init();

        if (accessControlAddr_ == address(0)) revert EC_AccessControlZero();
        if (emergencyControllerAddress_ == address(0)) revert SM_ControllerZero();
        if (oracleIntegrationAddress_ == address(0)) revert SM_OracleZero();
        
        uint256 codeSize;
        assembly { codeSize := extcodesize(accessControlAddr_) }
        if (codeSize == 0) revert NotAContract("accessControl");
        assembly { codeSize := extcodesize(emergencyControllerAddress_) }
        if (codeSize == 0) revert NotAContract("emergencyController");
        assembly { codeSize := extcodesize(oracleIntegrationAddress_) }
        if (codeSize == 0) revert NotAContract("oracleIntegration");
        
        accessControl = AccessControl(accessControlAddr_);
        emergencyController = EmergencyController(emergencyControllerAddress_);
        oracleIntegration = OracleIntegration(oracleIntegrationAddress_);

        flashLoanDetectionThresholdBps = 1000; 
        priceDeviationThresholdBps = 500;    
        volumeAnomalyThresholdBps = 3000;    
        transactionCooldownBlocks = 1;
        securityPaused = false;
        lastVolumeUpdateTime = block.timestamp;
        maxGasForExternalCalls = 100_000;
    }
    
    /**
     * @dev Modifier to restrict access to functions to addresses with the DEFAULT_ADMIN_ROLE.
     */
    modifier onlyAdminRole() {
        if (address(accessControl) == address(0)) revert EC_AccessControlZero();
        if (!accessControl.hasRole(accessControl.DEFAULT_ADMIN_ROLE(), msg.sender)) revert NotAuthorized(accessControl.DEFAULT_ADMIN_ROLE());
        _;
    }

    /**
     * @dev Modifier to restrict access to functions to addresses with the PARAMETER_ROLE.
     */
    modifier onlyParameterRole() {
        if (address(accessControl) == address(0)) revert EC_AccessControlZero();
        if (!accessControl.hasRole(accessControl.PARAMETER_ROLE(), msg.sender)) revert NotAuthorized(accessControl.PARAMETER_ROLE());
        _;
    }

    /**
     * @dev Modifier to restrict access to functions to addresses with the PAUSER_ROLE.
     */
    modifier onlyPauserRole() {
        if (address(accessControl) == address(0)) revert EC_AccessControlZero();
        if (!accessControl.hasRole(accessControl.PAUSER_ROLE(), msg.sender)) revert NotAuthorized(accessControl.PAUSER_ROLE());
        _;
    }

    /**
     * @dev Internal function to check if the module or the entire system is effectively paused.
     * @return A boolean indicating if the system is considered paused.
     */
    function _isEffectivelyPaused() internal view returns (bool) {
        if (securityPaused) return true;

        if (address(emergencyController) == address(0)) {
            return false;
        }
        bool ecSystemPaused = false;
        uint8 ecCurrentSystemLevel = Constants.EMERGENCY_LEVEL_NORMAL;
        try emergencyController.isSystemPaused() returns (bool sP) { ecSystemPaused = sP; } catch {}
        try emergencyController.getEmergencyLevel() returns (uint8 cL_) {
            ecCurrentSystemLevel = cL_;
        } catch {}

        return ecSystemPaused || (ecCurrentSystemLevel >= Constants.EMERGENCY_LEVEL_CRITICAL);
    }

    /**
     * @notice Sets a custom flash loan detection threshold for a specific token.
     * @param token The address of the token to configure.
     * @param thresholdBps The new threshold in basis points (e.g., 1000 for 10%).
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function setTokenFlashLoanThreshold(address token, uint256 thresholdBps) external onlyParameterRole returns (bool successFlag) {
        if (token == address(0)) revert SM_TokenZero();
        if (thresholdBps > Constants.BPS_MAX) revert SM_ThresholdTooHigh("token flash loan BPS");

        uint256 oldThresholdBps = tokenFlashLoanThresholdsBps[token];
        tokenFlashLoanThresholdsBps[token] = thresholdBps;
        emit TokenFlashLoanThresholdSet(token, oldThresholdBps, thresholdBps, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Sets the maximum gas limit for external calls made by this contract.
     * @dev This helps prevent gas-griefing attacks from malicious external contracts.
     * @param newLimit The new gas limit. Must be between 20,000 and 1,000,000.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function setMaxGasForExternalCalls(uint256 newLimit) external onlyAdminRole returns (bool successFlag) {
        if (newLimit < 20_000 || newLimit > 1_000_000) revert SM_GasLimitInvalid();

        uint256 oldLimit = maxGasForExternalCalls;
        maxGasForExternalCalls = newLimit;
        emit MaxGasForExternalCallsUpdated(oldLimit, newLimit, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Sets the transaction cooldown period in blocks.
     * @dev This defines the window for detecting rapid, successive transactions from the same account.
     * @param newCooldown The new cooldown period in blocks. Max 600.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function setTransactionCooldownBlocks(uint256 newCooldown) external onlyParameterRole returns (bool successFlag) {
        if (newCooldown > 600 && newCooldown != 0) { 
            revert SM_CooldownTooHigh();
        }
        uint256 oldCooldown = transactionCooldownBlocks;
        transactionCooldownBlocks = newCooldown;
        emit TransactionCooldownUpdated(oldCooldown, newCooldown, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Updates the main security parameters for anomaly detection.
     * @param newFlashLoanThresholdBps The new default flash loan detection threshold (BPS).
     * @param newPriceDeviationThresholdBps The new price deviation threshold (BPS).
     * @param newVolumeAnomalyThresholdBps The new volume anomaly threshold (BPS).
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function setSecurityParameters(
        uint256 newFlashLoanThresholdBps,
        uint256 newPriceDeviationThresholdBps,
        uint256 newVolumeAnomalyThresholdBps
    ) external onlyParameterRole returns (bool successFlag) {
        if (newFlashLoanThresholdBps == 0 && flashLoanDetectionThresholdBps != 0) revert SM_ThresholdNotPositive("flash loan BPS");
        if (newFlashLoanThresholdBps > Constants.BPS_MAX) revert SM_ThresholdTooHigh("flash loan BPS");
        if (newPriceDeviationThresholdBps == 0 && priceDeviationThresholdBps != 0) revert SM_ThresholdNotPositive("price deviation BPS");
        if (newPriceDeviationThresholdBps > Constants.BPS_MAX) revert SM_ThresholdTooHigh("price deviation BPS");
        if (newVolumeAnomalyThresholdBps == 0 && volumeAnomalyThresholdBps != 0) revert SM_ThresholdNotPositive("volume anomaly BPS");
        if (newVolumeAnomalyThresholdBps > (Constants.BPS_MAX * 20)) revert SM_ThresholdTooHigh("volume anomaly BPS (max 20x)");

        flashLoanDetectionThresholdBps = newFlashLoanThresholdBps;
        priceDeviationThresholdBps = newPriceDeviationThresholdBps;
        volumeAnomalyThresholdBps = newVolumeAnomalyThresholdBps;

        emit SecurityParametersUpdated(newFlashLoanThresholdBps, newPriceDeviationThresholdBps, newVolumeAnomalyThresholdBps, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Pauses the security checks within this module.
     * @dev This is a local pause and does not affect the global `EmergencyController` state.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function pauseSecurity() external onlyPauserRole returns (bool successFlag) {
        if (securityPaused) revert SM_SecurityPaused();
        securityPaused = true;
        emit SecurityPaused(msg.sender, block.timestamp);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Resumes the security checks within this module.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function resumeSecurity() external onlyPauserRole returns (bool successFlag) {
        if (!securityPaused) revert SM_SecurityNotPaused();
        securityPaused = false;
        emit SecurityResumed(msg.sender, block.timestamp);
        successFlag = true;
        return successFlag;
    }

    /**
     * @dev Internal function to detect unusually large balance increases, potentially indicative of flash loans.
     * @param token The address of the token being checked.
     * @param account The address of the user account.
     * @param amount The transaction amount being processed (used for large absolute amount checks).
     * @param previousBlockNumber The block number of the user's previous transaction.
     * @return isAnomalous A boolean indicating if the balance change is considered anomalous.
     * @return currentBalance The user's current balance of the token.
     */
    function detectAnomalousBalanceChange(
        address token,
        address account,
        uint256 amount,
        uint256 previousBlockNumber
    ) internal returns (bool isAnomalous, uint256 currentBalance) {
        if (_isEffectivelyPaused()) return (false, 0);
        if (token == address(0)) revert SM_TokenZero();
        if (account == address(0)) revert SM_AccountZero();

        try IERC20Upgradeable(token).balanceOf{gas: maxGasForExternalCalls}(account) returns (uint256 bal) {
            currentBalance = bal;
        } catch {
            emit OracleFailure(token, "Balance fetch failed in detectAnomalousBalanceChange");
            return (true, 0);
        }

        uint256 previousBalance = _lastKnownBalances[account][token];

        uint8 tokenDecimalsValue = 18;
        try IERC20MetadataUpgradeable(token).decimals{gas: maxGasForExternalCalls}() returns (uint8 d) {
            if (d > 0 && d <= 30) tokenDecimalsValue = d;
        } catch { }

        uint256 minAbsoluteIncreaseForFlashLoan = (10**uint256(tokenDecimalsValue)) / 100;

        if (transactionCooldownBlocks > 0 && block.number - previousBlockNumber < transactionCooldownBlocks) {
            if (previousBalance > 0 && currentBalance > previousBalance) {
                uint256 increaseAmount = currentBalance - previousBalance;
                uint256 thresholdBps = tokenFlashLoanThresholdsBps[token] > 0 ? tokenFlashLoanThresholdsBps[token] : flashLoanDetectionThresholdBps;
                if (thresholdBps > 0 &&
                    increaseAmount >= minAbsoluteIncreaseForFlashLoan &&
                    Math.mulDiv(increaseAmount, Constants.BPS_MAX, previousBalance) > thresholdBps) {
                    emit PotentialFlashLoanDetected(account, token, previousBalance, currentBalance);
                    return (true, currentBalance);
                }
            }
        }

        uint256 largeAmountThreshold = 1_000_000 * (10**tokenDecimalsValue);
        if (transactionCooldownBlocks > 0 && block.number - previousBlockNumber < transactionCooldownBlocks) {
            if (amount > largeAmountThreshold) {
                emit FlashLoanDetected(account, token, amount, block.number);
                return (true, currentBalance);
            }
        }
        return (false, currentBalance);
    }

    /**
     * @notice Validates a given price against the integrated oracle.
     * @dev Checks for staleness and deviation from the oracle price. The deviation threshold is halved
     * if the oracle is using a fallback price.
     * @param token The address of the token whose price is being validated.
     * @param priceToValidate The price to check against the oracle.
     * @return isValid A boolean indicating if the price is valid.
     */
    function validatePrice(
        address token,
        uint256 priceToValidate
    ) external nonReentrant returns (bool isValid) {
        if (_isEffectivelyPaused()) return true;
        if (token == address(0)) revert SM_TokenZero();
        if (priceToValidate == 0) revert SM_PriceNotPositive();
        if (address(oracleIntegration) == address(0)) return true;

        uint256 oraclePrice;
        uint256 oracleTimestamp;
        bool isFallback;
        bool priceFetchSuccess = false;

        try oracleIntegration.getTokenPrice{gas: maxGasForExternalCalls}(token) returns (uint256 oPrice, bool oIsFallback, uint256 oTimestamp) {
            if (oPrice > 0 && oTimestamp > 0) {
                oraclePrice = oPrice;
                oracleTimestamp = oTimestamp;
                isFallback = oIsFallback;
                priceFetchSuccess = true;
            } else {
                emit OracleFailure(token, "Oracle returned zero price or timestamp");
            }
        } catch (bytes memory reasonDataFromCatch) {
            string memory reasonString = "OracleIntegration.getTokenPrice reverted";
             if (reasonDataFromCatch.length >= 4) {
                bytes4 selector;
                assembly { selector := mload(add(reasonDataFromCatch, 0x20)) selector := shr(224, selector) }
                if (selector == bytes4(keccak256("Error(string)"))) {
                    reasonString = "OracleIntegration.getTokenPrice reverted with Error(string)";
                } else if (selector == bytes4(keccak256("Panic(uint256)"))) {
                    reasonString = "OracleIntegration.getTokenPrice reverted with Panic(uint256)";
                } else {
                     reasonString = "OracleIntegration.getTokenPrice reverted with unknown error or custom error";
                }
            }
            emit OracleFailure(token, reasonString);
        }

        if (!priceFetchSuccess) return false;

        uint256 stalenessThreshold;
        try oracleIntegration.getStalenessThreshold() returns (uint256 st) { stalenessThreshold = st; } catch { stalenessThreshold = Constants.ORACLE_MAX_STALENESS; }

        if (stalenessThreshold != type(uint256).max && (block.timestamp > oracleTimestamp && block.timestamp - oracleTimestamp > stalenessThreshold)) {
            emit StalePriceWarning(token, oracleTimestamp, block.timestamp);
            return false;
        }

        uint256 deviationBps;
        if (priceToValidate >= oraclePrice) {
            deviationBps = Math.mulDiv(priceToValidate - oraclePrice, Constants.BPS_MAX, oraclePrice);
        } else {
            deviationBps = Math.mulDiv(oraclePrice - priceToValidate, Constants.BPS_MAX, oraclePrice);
        }

        uint256 currentDeviationThresholdBps = priceDeviationThresholdBps;
        if (isFallback) {
            currentDeviationThresholdBps = priceDeviationThresholdBps / 2;
            if (currentDeviationThresholdBps == 0 && priceDeviationThresholdBps > 0 && priceDeviationThresholdBps % 2 != 0) {
                currentDeviationThresholdBps = 1;
            }
        }

        if (deviationBps > currentDeviationThresholdBps) {
            emit PriceAnomalyDetected(token, oraclePrice, priceToValidate, block.timestamp);
            return false;
        }
        return true;
    }

    /**
     * @notice Monitors transaction volume to detect anomalies.
     * @dev Compares the current daily volume against a prorated expectation based on the previous day's volume.
     * @param amount The value of the current transaction to be added to the daily volume.
     * @return isVolumeNormal A boolean indicating if the volume is within normal thresholds.
     */
    function monitorVolatility(
        address, 
        uint256 amount
    ) public nonReentrant returns (bool isVolumeNormal) {
        if (_isEffectivelyPaused()) return true;
        if (amount == 0) return true;

        currentDailyVolume += amount;

        if (block.timestamp - lastVolumeUpdateTime >= Constants.SECONDS_PER_DAY) {
            lastDailyVolume = currentDailyVolume - amount;
            currentDailyVolume = amount;
            lastVolumeUpdateTime = block.timestamp;
            return true;
        }

        if (lastDailyVolume > 0 && volumeAnomalyThresholdBps > 0) {
            uint256 elapsedTimeWithinDay = block.timestamp - lastVolumeUpdateTime;

            if (elapsedTimeWithinDay == 0) {
                return true;
            }

            uint256 expectedVolumeProrated = Math.mulDiv(lastDailyVolume, elapsedTimeWithinDay, Constants.SECONDS_PER_DAY);

            if (currentDailyVolume > expectedVolumeProrated) {
                uint256 deviationBps;
                
                if (expectedVolumeProrated > 0) {
                    deviationBps = Math.mulDiv(currentDailyVolume - expectedVolumeProrated, Constants.BPS_MAX, expectedVolumeProrated);
                } else {
                    deviationBps = type(uint256).max;
                }
                
                if (deviationBps > volumeAnomalyThresholdBps) {
                    emit VolumeAnomalyDetected(expectedVolumeProrated, currentDailyVolume, block.timestamp);
                    return false;
                }
            }
        }
        return true;
    }

    /**
     * @notice Validates the sequence of a transaction, checking for anomalous balance changes.
     * @dev This function updates transaction tracking data and calls `detectAnomalousBalanceChange`.
     * @param account The user account performing the transaction.
     * @param token The token involved in the transaction.
     * @param amount The amount of the transaction.
     * @return isValid A boolean indicating if the transaction sequence is valid.
     */
    function validateTransactionSequence(
        address account,
        address token,
        uint256 amount
    ) external nonReentrant returns (bool isValid) {
        if (_isEffectivelyPaused()) return true;
        if (account == address(0)) revert SM_AccountZero();
        if (token == address(0)) revert SM_TokenZero();

        uint256 previousBlock = lastTransactionBlock[account];
        lastTransactionBlock[account] = block.number;
        transactionCount[account]++;
        lastTransactionTimestamp[account] = block.timestamp;

        (bool isAnomalous, uint256 currentBalance) = detectAnomalousBalanceChange(
            token,
            account,
            amount,
            previousBlock
        );

        if (isAnomalous) {
            revert("Anomalous balance change detected");
        }

        _lastKnownBalances[account][token] = currentBalance;
        
        return true;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function checkEmergencyStatus(bytes4 operation) external view override returns (bool finalOperationAllowed) {
        if (securityPaused) {
             return false;
        }
        if (address(emergencyController) == address(0)) {
            return true;
        }
        bool ecSystemIsPaused = false;
        uint8 ecLevel = Constants.EMERGENCY_LEVEL_NORMAL;
        bool opIsRestrictedByEC = false;
        try emergencyController.isSystemPaused() returns (bool p) { ecSystemIsPaused = p; } catch { }
        try emergencyController.getEmergencyLevel() returns (uint8 l_) {
            ecLevel = l_;
            if (l_ >= Constants.EMERGENCY_LEVEL_CRITICAL) ecSystemIsPaused = true;
        } catch { }
        if (!ecSystemIsPaused) {
            try emergencyController.isFunctionRestricted(operation) returns (bool r) { opIsRestrictedByEC = r; } catch { }
        }
        finalOperationAllowed = !ecSystemIsPaused && !opIsRestrictedByEC;
        return finalOperationAllowed;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function emergencyShutdown(uint8 emergencyLevelInput) external override returns (bool successFlag) {
        if (address(emergencyController) == address(0)) revert SM_ControllerZero();
        if (msg.sender != address(emergencyController)) revert NotAuthorized(bytes32(uint256(uint160(address(emergencyController)))));

        if (emergencyLevelInput >= Constants.EMERGENCY_LEVEL_CRITICAL && !securityPaused) {
            securityPaused = true;
            emit SecurityPaused(msg.sender, block.timestamp);
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
    function setEmergencyController(address controller) external override onlyAdminRole returns (bool successFlag) {
        if (controller == address(0)) revert SM_ControllerZero();
        uint256 codeSize;
        assembly { codeSize := extcodesize(controller) }
        if (codeSize == 0) revert NotAContract("EmergencyController");
        address oldController = address(emergencyController);
        emergencyController = EmergencyController(controller);
        emit EmergencyControllerSet(oldController, controller, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Sets the OracleIntegration contract address.
     * @param oracle The address of the new OracleIntegration contract.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function setOracleIntegration(address oracle) external onlyAdminRole returns (bool successFlag) {
        if (oracle == address(0)) revert SM_OracleZero();
        uint256 codeSize;
        assembly { codeSize := extcodesize(oracle) }
        if (codeSize == 0) revert NotAContract("OracleIntegration");
        address oldOracle = address(oracleIntegration);
        oracleIntegration = OracleIntegration(oracle);
        emit OracleIntegrationSet(oldOracle, oracle, msg.sender);
        successFlag = true;
        return successFlag;
    }
    
    /**
     * @inheritdoc IEmergencyAware
     */
    function isEmergencyPaused() public view override returns (bool isPausedStatus) {
        isPausedStatus = _isEffectivelyPaused();
        return isPausedStatus;
    }

    /**
     * @notice A view function to validate a commit-reveal hash for front-running prevention.
     * @param commitHash The hash previously committed by the user.
     * @param operationType An enum or integer representing the type of operation.
     * @param parameters The encoded parameters of the operation.
     * @param salt A random value used to prevent hash collisions.
     * @return isValid A boolean indicating if the provided details match the commit hash.
     */
    function preventFrontRunning(
        bytes32 commitHash,
        uint8 operationType,
        bytes memory parameters,
        bytes32 salt
    ) external view returns (bool isValid) {
        if (commitHash == bytes32(0)) revert SM_CommitHashZero(); 
        if (parameters.length == 0 && operationType != 0 ) revert SM_ParamsEmpty(); 
        if (salt == bytes32(0)) revert SM_SaltZero(); 

        bytes32 calculatedHash = keccak256(abi.encodePacked(msg.sender, operationType, parameters, salt, block.chainid));
        isValid = (commitHash == calculatedHash);
        return isValid;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../libraries/DecimalMath.sol";
import "../oracle/OracleIntegration.sol";
import "../interfaces/IEmergencyAware.sol";
import "../controllers/EmergencyController.sol";
import "../libraries/Constants.sol";
import "../libraries/Errors.sol";

/**
 * @title PriceGuard
 * @author Rewa
 * @notice A security contract to protect against price manipulation and high slippage in swaps.
 * @dev This contract provides functions to check the price impact of a trade against an expected price
 * (derived from an oracle), validate slippage, and implement a commit-reveal scheme to mitigate
 * front-running. It is upgradeable and integrates with OracleIntegration and EmergencyController.
 */
contract PriceGuard is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IEmergencyAware
{
    using DecimalMath for uint256;

    /// @notice The contract that provides reliable price feeds.
    OracleIntegration public oracleIntegration;
    /// @notice The central controller for system-wide emergency states.
    EmergencyController public emergencyController;

    /// @notice The maximum allowed price impact (BPS) for a swap during normal operation.
    uint256 public maxPriceImpactNormal;
    /// @notice The maximum allowed price impact (BPS) for a swap during an emergency.
    uint256 public maxPriceImpactEmergency;
    /// @notice The maximum allowed price deviation (BPS) from the oracle during normal operation.
    uint256 public maxPriceDeviationNormal;
    /// @notice The maximum allowed price deviation (BPS) from the oracle during an emergency.
    uint256 public maxPriceDeviationEmergency;

    /// @notice The minimum number of blocks that must pass between committing and revealing.
    uint256 public minBlockDelay;
    /// @notice The maximum number of blocks that can pass between committing and revealing.
    uint256 public maxBlockDelay;

    /// @notice The minimum acceptable price value (in 1e18 precision) for any price check.
    uint256 public minAcceptablePrice;

    /// @dev Stores active commitments for the commit-reveal scheme.
    mapping(bytes32 => bool) public commitments;
    /// @dev Stores the block number at which a commitment was made.
    mapping(bytes32 => uint256) public commitmentBlocks;
    /// @dev Stores the address that created a commitment.
    mapping(bytes32 => address) public commitmentCreators;

    /**
     * @notice Emitted when a trade's price impact exceeds the allowed threshold.
     * @param token0 The address of the first token in the pair.
     * @param token1 The address of the second token in the pair.
     * @param expectedPrice The expected price from the oracle.
     * @param actualPrice The actual price of the trade.
     * @param impactBps The calculated price impact in basis points.
     */
    event PriceImpactExceeded(
        address indexed token0,
        address indexed token1,
        uint256 expectedPrice,
        uint256 actualPrice,
        uint256 impactBps
    );
    /**
     * @notice Emitted when the core price guard parameters are updated.
     * @param newMaxPriceImpactNormal The new max price impact for normal conditions.
     * @param newMaxPriceImpactEmergency The new max price impact for emergency conditions.
     * @param newMaxPriceDeviationNormal The new max price deviation for normal conditions.
     * @param newMaxPriceDeviationEmergency The new max price deviation for emergency conditions.
     * @param updater The address that performed the update.
     */
    event PriceGuardParametersUpdated(
        uint256 newMaxPriceImpactNormal,
        uint256 newMaxPriceImpactEmergency,
        uint256 newMaxPriceDeviationNormal,
        uint256 newMaxPriceDeviationEmergency,
        address indexed updater
    );
    /**
     * @notice Emitted when a new commitment is registered for the commit-reveal scheme.
     * @param commitHash The hash of the commitment.
     * @param committer The address that made the commitment.
     * @param blockNumber The block number at which the commitment was made.
     */
    event CommitmentRegistered(
        bytes32 indexed commitHash,
        address indexed committer,
        uint256 blockNumber
    );
    /**
     * @notice Emitted when a commitment is successfully revealed and verified.
     * @param commitHash The hash of the commitment.
     * @param revealer The address that revealed the commitment.
     * @param operationHash A hash of the revealed operation parameters.
     * @param blockDelay The number of blocks between commit and reveal.
     */
    event CommitmentRevealed(
        bytes32 indexed commitHash,
        address indexed revealer,
        bytes32 operationHash,
        uint256 blockDelay
    );
    /**
     * @notice Emitted when the OracleIntegration contract address is updated.
     * @param oldOracle The previous oracle address.
     * @param newOracle The new oracle address.
     * @param setter The address that performed the update.
     */
    event OracleIntegrationSet(address indexed oldOracle, address indexed newOracle, address indexed setter);
    /**
     * @notice Emitted when the EmergencyController contract address is updated.
     * @param oldController The previous controller address.
     * @param newController The new controller address.
     * @param setter The address that performed the update.
     */
    event EmergencyControllerSet(address indexed oldController, address indexed newController, address indexed setter);
    /**
     * @notice Emitted when the minimum acceptable price is updated.
     * @param oldPrice The previous minimum price.
     * @param newPrice The new minimum price.
     * @param updater The address that performed the update.
     */
    event MinAcceptablePriceUpdated(uint256 oldPrice, uint256 newPrice, address indexed updater);
    /**
     * @notice Emitted when the block delay parameters for the commit-reveal scheme are updated.
     * @param oldMinBlockDelay The previous minimum block delay.
     * @param newMinBlockDelay The new minimum block delay.
     * @param oldMaxBlockDelay The previous maximum block delay.
     * @param newMaxBlockDelay The new maximum block delay.
     * @param updater The address that performed the update.
     */
    event CommitRevealParametersUpdated(uint256 oldMinBlockDelay, uint256 newMinBlockDelay, uint256 oldMaxBlockDelay, uint256 newMaxBlockDelay, address indexed updater);

    /**
     * @dev Disables the regular constructor to make the contract upgradeable.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the PriceGuard contract.
     * @dev Sets up the initial owner and dependent contract addresses. Can only be called once.
     * @param initialOwner_ The initial owner of the contract.
     * @param oracleIntegrationAddress_ The address of the OracleIntegration contract.
     * @param emergencyControllerAddress_ The address of the EmergencyController contract.
     */
    function initialize(
        address initialOwner_,
        address oracleIntegrationAddress_,
        address emergencyControllerAddress_
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        if (initialOwner_ == address(0)) revert ZeroAddress("initialOwner_");
        if (oracleIntegrationAddress_ == address(0)) revert SM_OracleZero(); 
        if (emergencyControllerAddress_ == address(0)) revert SM_ControllerZero(); 

        oracleIntegration = OracleIntegration(oracleIntegrationAddress_);
        emergencyController = EmergencyController(emergencyControllerAddress_);

        maxPriceImpactNormal = 200; 
        maxPriceImpactEmergency = 50; 
        maxPriceDeviationNormal = 500; 
        maxPriceDeviationEmergency = 100; 
        minBlockDelay = 1;
        maxBlockDelay = 100;
        minAcceptablePrice = 1; 

        _transferOwnership(initialOwner_);
    }

    /**
     * @dev Modifier that reverts if the system is effectively paused.
     */
    modifier whenNotEffectivelyPaused() {
        if (this.isEmergencyPaused()) revert SystemInEmergencyMode();
        _;
    }

    /**
     * @notice Checks if the price impact of a trade is within acceptable limits.
     * @dev The acceptable limit depends on the current system emergency level.
     * @param token0 Address of the input token.
     * @param token1 Address of the output token.
     * @param expectedPrice The expected price from a reliable source (e.g., oracle), scaled.
     * @param actualPrice The actual price realized from the trade, scaled.
     * @return isAcceptable True if the price impact is within the allowed threshold.
     */
    function checkPriceImpact(
        address token0,
        address token1,
        uint256 expectedPrice, 
        uint256 actualPrice    
    ) external nonReentrant whenNotEffectivelyPaused returns (bool isAcceptable) {
        if (token0 == address(0)) revert ZeroAddress("token0 for checkPriceImpact");
        if (token1 == address(0)) revert ZeroAddress("token1 for checkPriceImpact");
        if (expectedPrice == 0) revert SM_PriceNotPositive(); 
        if (actualPrice == 0) revert SM_PriceNotPositive();   
        if (expectedPrice < minAcceptablePrice) revert OI_MinPriceNotMet(expectedPrice, minAcceptablePrice); 
        if (actualPrice < minAcceptablePrice) revert OI_MinPriceNotMet(actualPrice, minAcceptablePrice);

        uint256 impactBps;
        if (actualPrice >= expectedPrice) {
            impactBps = Math.mulDiv(actualPrice - expectedPrice, Constants.BPS_MAX, expectedPrice);
        } else {
            impactBps = Math.mulDiv(expectedPrice - actualPrice, Constants.BPS_MAX, expectedPrice);
        }

        uint256 thresholdBps;
        uint8 currentEmergencyLevel = Constants.EMERGENCY_LEVEL_NORMAL;

        if (address(emergencyController) != address(0)) {
            try emergencyController.getEmergencyLevel() returns (uint8 level) {
                currentEmergencyLevel = level;
            } catch { }
        }

        if (currentEmergencyLevel >= Constants.EMERGENCY_LEVEL_ALERT) { 
            thresholdBps = maxPriceImpactEmergency;
        } else {
            thresholdBps = maxPriceImpactNormal;
        }

        isAcceptable = impactBps <= thresholdBps;

        if (!isAcceptable) {
            emit PriceImpactExceeded(token0, token1, expectedPrice, actualPrice, impactBps);
        }
        return isAcceptable;
    }

    /**
     * @notice Gets the expected price ratio between two tokens from the oracle.
     * @dev Reverts if the oracle is using a fallback price, as these are considered less reliable for this check.
     * @param token0 The address of the base token.
     * @param token1 The address of the quote token.
     * @return price The price of token1 in terms of token0 (price = price1 / price0), scaled by 1e18.
     */
    function getExpectedPrice( 
        address token0,
        address token1
    ) external view whenNotEffectivelyPaused returns (uint256 price) {
        if (token0 == address(0)) revert ZeroAddress("token0 for getExpectedPrice");
        if (token1 == address(0)) revert ZeroAddress("token1 for getExpectedPrice");
        if (address(oracleIntegration) == address(0)) revert SM_OracleZero(); 

        (uint256 price0_1e18, bool isFallback0, ) = oracleIntegration.getTokenPrice(token0);
        (uint256 price1_1e18, bool isFallback1, ) = oracleIntegration.getTokenPrice(token1);
        
        if (isFallback0 || isFallback1) {
            revert PG_FallbackPriceNotAllowed();
        }

        if (price0_1e18 == 0) revert SM_PriceNotPositive(); 
        if (price1_1e18 < minAcceptablePrice && price1_1e18 != 0) revert OI_MinPriceNotMet(price1_1e18, minAcceptablePrice); 

        price = DecimalMath.divScaled(price1_1e18, price0_1e18);
        
        if (price < minAcceptablePrice && price !=0) revert OI_MinPriceNotMet(price, minAcceptablePrice);

        return price;
    }

    /**
     * @notice Validates if an actual received amount is within the expected range after applying slippage.
     * @param expectedAmount The amount expected without any slippage.
     * @param actualAmount The actual amount received.
     * @param slippageBps The slippage tolerance in basis points.
     * @return isWithinTolerance True if the actual amount is greater than or equal to the minimum acceptable amount.
     */
    function validateSlippage(
        uint256 expectedAmount,
        uint256 actualAmount,
        uint256 slippageBps
    ) external pure returns (bool isWithinTolerance) {
        if (expectedAmount == 0 && actualAmount !=0) revert AmountIsZero(); 
        if (expectedAmount == 0 && actualAmount ==0) return true; 
        if (slippageBps > Constants.MAX_SLIPPAGE) revert LM_SlippageInvalid(slippageBps); 

        uint256 minAmountAfterSlippage = DecimalMath.applySlippage(expectedAmount, slippageBps);
        isWithinTolerance = actualAmount >= minAmountAfterSlippage;
        return isWithinTolerance;
    }

    /**
     * @notice Calculates the minimum output amount for a swap given an input amount, price, and slippage.
     * @param inputAmount The amount of the input token.
     * @param price The price of the output token in terms of the input token, scaled by 1e18.
     * @param slippageBps The slippage tolerance in basis points.
     * @return minOutputAmount The minimum expected output amount after accounting for slippage.
     */
    function calculateMinimumOutput(
        uint256 inputAmount,
        uint256 price, 
        uint256 slippageBps
    ) external pure returns (uint256 minOutputAmount) {
        if (inputAmount == 0) return 0;
        if (price == 0) revert SM_PriceNotPositive();
        if (slippageBps > Constants.MAX_SLIPPAGE) revert LM_SlippageInvalid(slippageBps); 

        uint256 expectedOutput = DecimalMath.mulScaled(inputAmount, price);
        minOutputAmount = DecimalMath.applySlippage(expectedOutput, slippageBps);
        return minOutputAmount;
    }

    /**
     * @notice Registers a commitment hash for the commit-reveal scheme.
     * @param commitHash The hash of the user's intended transaction details.
     * @return success True if the commitment was registered successfully.
     */
    function registerCommitment(bytes32 commitHash) external nonReentrant whenNotEffectivelyPaused returns (bool success) {
        if (commitHash == bytes32(0)) revert SM_CommitHashZero(); 
        if (commitments[commitHash]) revert InvalidAmount(); 

        commitments[commitHash] = true;
        commitmentBlocks[commitHash] = block.number;
        commitmentCreators[commitHash] = msg.sender;

        emit CommitmentRegistered(commitHash, msg.sender, block.number);
        success = true;
        return success;
    }

    /**
     * @notice Verifies a revealed commitment against a previously registered one.
     * @dev The caller must be the original committer, and the call must occur within the allowed block delay.
     * @param operationType An enum or integer representing the type of operation.
     * @param parameters The encoded parameters of the operation.
     * @param salt A random value used to prevent hash collisions.
     * @return isValid True if the revealed details match the commitment and all conditions are met.
     */
    function verifyCommitment(
        uint8 operationType,
        bytes memory parameters,
        bytes32 salt
    ) external nonReentrant whenNotEffectivelyPaused returns (bool isValid) {
        bytes32 commitHash = keccak256(abi.encodePacked(msg.sender, operationType, parameters, salt, block.chainid));

        if (commitHash == bytes32(0)) revert SM_CommitHashZero();
        if (!commitments[commitHash]) revert InvalidAmount(); 
        if (commitmentCreators[commitHash] != msg.sender) revert NotAuthorized(bytes32(0)); 

        uint256 currentBlock = block.number;
        uint256 committedBlock = commitmentBlocks[commitHash];
        if (currentBlock <= committedBlock) revert InvalidAmount(); 

        uint256 blockDelay = currentBlock - committedBlock;
        if (blockDelay < minBlockDelay) revert InvalidAmount(); 
        if (maxBlockDelay > 0 && blockDelay > maxBlockDelay) revert InvalidAmount(); 

        delete commitments[commitHash];
        delete commitmentBlocks[commitHash];
        delete commitmentCreators[commitHash];

        emit CommitmentRevealed(commitHash, msg.sender, keccak256(parameters), blockDelay);
        isValid = true;
        return isValid;
    }
    
    /**
     * @notice Sets the main price protection parameters.
     * @param newMaxPriceImpactNormal_ New max price impact for normal conditions (BPS).
     * @param newMaxPriceImpactEmergency_ New max price impact for emergency conditions (BPS).
     * @param newMaxPriceDeviationNormal_ New max price deviation for normal conditions (BPS).
     * @param newMaxPriceDeviationEmergency_ New max price deviation for emergency conditions (BPS).
     * @return success True if the parameters were updated successfully.
     */
    function setPriceGuardParameters(
        uint256 newMaxPriceImpactNormal_,
        uint256 newMaxPriceImpactEmergency_,
        uint256 newMaxPriceDeviationNormal_,
        uint256 newMaxPriceDeviationEmergency_
    ) external onlyOwner returns (bool success) {
        if (newMaxPriceImpactNormal_ > Constants.BPS_MAX / 2) revert InvalidAmount(); 
        if (newMaxPriceImpactEmergency_ > Constants.BPS_MAX / 4) revert InvalidAmount();
        if (newMaxPriceDeviationNormal_ > Constants.BPS_MAX / 2) revert InvalidAmount();
        if (newMaxPriceDeviationEmergency_ > Constants.BPS_MAX / 4) revert InvalidAmount();
        if (newMaxPriceImpactEmergency_ > newMaxPriceImpactNormal_) revert InvalidAmount(); 
        if (newMaxPriceDeviationEmergency_ > newMaxPriceDeviationNormal_) revert InvalidAmount(); 

        maxPriceImpactNormal = newMaxPriceImpactNormal_;
        maxPriceImpactEmergency = newMaxPriceImpactEmergency_;
        maxPriceDeviationNormal = newMaxPriceDeviationNormal_;
        maxPriceDeviationEmergency = newMaxPriceDeviationEmergency_;

        emit PriceGuardParametersUpdated(
            newMaxPriceImpactNormal_,
            newMaxPriceImpactEmergency_,
            newMaxPriceDeviationNormal_,
            newMaxPriceDeviationEmergency_,
            msg.sender
        );
        success = true;
        return success;
    }

    /**
     * @notice Sets the block delay parameters for the commit-reveal scheme.
     * @param newMinBlockDelay_ The new minimum block delay.
     * @param newMaxBlockDelay_ The new maximum block delay.
     * @return success True if the parameters were updated successfully.
     */
    function setCommitRevealParameters(
        uint256 newMinBlockDelay_,
        uint256 newMaxBlockDelay_
    ) external onlyOwner returns (bool success) {
        if (newMinBlockDelay_ == 0 && minBlockDelay !=0) revert SM_CooldownNotPositive(); 
        if (newMaxBlockDelay_ != 0 && newMaxBlockDelay_ <= newMinBlockDelay_) revert InvalidDuration(); 
        if (newMaxBlockDelay_ > 1000 && newMaxBlockDelay_ !=0) revert SM_CooldownTooHigh(); 

        uint256 oldMin = minBlockDelay;
        uint256 oldMax = maxBlockDelay;
        minBlockDelay = newMinBlockDelay_;
        maxBlockDelay = newMaxBlockDelay_;

        emit CommitRevealParametersUpdated(oldMin, newMinBlockDelay_, oldMax, newMaxBlockDelay_, msg.sender);
        success = true;
        return success;
    }

    /**
     * @notice Sets the minimum acceptable price for any check.
     * @param newMinPrice The new minimum price, scaled to 1e18 decimals.
     * @return success True if the parameter was updated successfully.
     */
    function setMinAcceptablePrice(uint256 newMinPrice) external onlyOwner returns (bool success) {
        if (newMinPrice == 0) revert OI_MinAcceptablePriceZero(); 

        uint256 oldMinPrice = minAcceptablePrice;
        minAcceptablePrice = newMinPrice;

        emit MinAcceptablePriceUpdated(oldMinPrice, newMinPrice, msg.sender);
        success = true;
        return success;
    }

    /**
     * @notice Sets the OracleIntegration contract address.
     * @param oracleAddress The address of the new OracleIntegration contract.
     * @return success True if the address was updated successfully.
     */
    function setOracleIntegration(address oracleAddress) external onlyOwner returns (bool success) {
        if (oracleAddress == address(0)) revert SM_OracleZero(); 
        uint256 codeSize;
        assembly { codeSize := extcodesize(oracleAddress) }
        if (codeSize == 0) revert NotAContract("OracleIntegration");

        address oldOracle = address(oracleIntegration);
        oracleIntegration = OracleIntegration(oracleAddress);
        emit OracleIntegrationSet(oldOracle, oracleAddress, msg.sender);
        success = true;
        return success;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function checkEmergencyStatus(bytes4 operation) external view override returns (bool finalOperationAllowed) {
        if (address(emergencyController) == address(0)) {
            return true;
        }
        bool opIsRestrictedByEC = false;
        bool sysIsPausedByEC = false;
        uint8 ecLevel = Constants.EMERGENCY_LEVEL_NORMAL;

        try emergencyController.isFunctionRestricted(operation) returns (bool r) { opIsRestrictedByEC = r; } catch { }
        try emergencyController.isSystemPaused() returns (bool p) { sysIsPausedByEC = p; } catch { }
        try emergencyController.getEmergencyLevel() returns (uint8 l_) {
            ecLevel = l_;
            if (l_ >= Constants.EMERGENCY_LEVEL_CRITICAL) sysIsPausedByEC = true;
        } catch { }

        finalOperationAllowed = !opIsRestrictedByEC && !sysIsPausedByEC;
        return finalOperationAllowed;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function emergencyShutdown(uint8 emergencyLevelInput) external override returns (bool successFlag) {
        if (address(emergencyController) == address(0)) revert SM_ControllerZero(); 
        if (msg.sender != address(emergencyController)) revert NotAuthorized(bytes32(uint256(uint160(address(emergencyController)))));

        emit EmergencyShutdownHandled(emergencyLevelInput, msg.sender);
        successFlag = true;
        return successFlag;
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
        if (controller == address(0)) revert SM_ControllerZero(); 
        uint256 codeSize;
        assembly { codeSize := extcodesize(controller) }
        if (codeSize == 0) revert NotAContract("EmergencyController");

        address oldController = address(emergencyController);
        emergencyController = EmergencyController(controller);
        emit EmergencyControllerSet(oldController, controller, msg.sender);
        success = true;
        return success;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function isEmergencyPaused() public view override returns (bool isPaused) {
        if (address(emergencyController) == address(0)) {
            return false;
        }
        bool ecSystemPaused = false;
        uint8 ecCurrentSystemLevel = Constants.EMERGENCY_LEVEL_NORMAL;
        try emergencyController.isSystemPaused() returns (bool sP) { ecSystemPaused = sP; } catch {}
        try emergencyController.getEmergencyLevel() returns (uint8 cL_) {
            ecCurrentSystemLevel = cL_;
        } catch {}

        isPaused = ecSystemPaused || (ecCurrentSystemLevel >= Constants.EMERGENCY_LEVEL_CRITICAL);
        return isPaused;
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
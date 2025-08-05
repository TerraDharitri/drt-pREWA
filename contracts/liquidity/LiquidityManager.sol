// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./storage/LiquidityManagerStorage.sol";
import "./interfaces/ILiquidityManager.sol";
import "./interfaces/IPancakeRouter.sol";
import "./interfaces/IPancakeFactory.sol";
import "./interfaces/IPancakePair.sol";
import "../access/AccessControl.sol";
import "../controllers/EmergencyController.sol";
import "../oracle/OracleIntegration.sol";
import "../security/PriceGuard.sol";
import "../libraries/Constants.sol";
import "../libraries/Errors.sol";
import "../utils/EmergencyAwareBase.sol";

/**
 * @title LiquidityManager
 * @author Rewa
 * @notice Manages liquidity for pREWA token pairs on a DEX (e.g., PancakeSwap).
 * @dev This contract provides an interface for users to add and remove liquidity for pREWA against other tokens,
 * including BNB. It interacts with a DEX router and factory. It integrates with AccessControl for permissions,
 * an EmergencyController for safety, an OracleIntegration for price data, and a PriceGuard for slippage control.
 * This contract is upgradeable and inherits emergency-aware functionality from EmergencyAwareBase.
 */
contract LiquidityManager is
    Initializable,
    ReentrancyGuardUpgradeable,
    LiquidityManagerStorage,
    ILiquidityManager,
    EmergencyAwareBase
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice The contract that controls roles and permissions.
    AccessControl public accessControl;
    /// @notice The contract that provides reliable price feeds.
    OracleIntegration public oracleIntegration;
    /// @notice The contract that provides price impact and slippage checks.
    PriceGuard public priceGuard;

    /// @notice The maximum time in the future that a transaction deadline can be set.
    uint256 public maxDeadlineOffset;

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
     * @notice Emitted when the PriceGuard address is changed.
     * @param oldGuard The previous PriceGuard address.
     * @param newGuard The new PriceGuard address.
     * @param setter The address that performed the update.
     */
    event PriceGuardSet(address indexed oldGuard, address indexed newGuard, address indexed setter);
    /**
     * @notice Emitted when non-essential tokens are recovered from the contract.
     * @param token The address of the recovered token.
     * @param amount The amount recovered.
     * @param recipient The address that received the tokens.
     */
    event LiquidityManagerTokenRecovered(address indexed token, uint256 amount, address indexed recipient);

    /**
     * @dev Disables the regular constructor to make the contract upgradeable.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the LiquidityManager contract.
     * @dev Sets up initial contract addresses and parameters. Can only be called once.
     * @param pREWATokenAddress_ The address of the pREWA token.
     * @param routerAddress_ The address of the DEX router.
     * @param accessControlAddr_ The address of the AccessControl contract.
     * @param emergencyControllerAddr_ The address of the EmergencyController contract.
     * @param oracleIntegrationAddr_ The address of the OracleIntegration contract.
     * @param priceGuardAddr_ The address of the PriceGuard contract.
     */
    function initialize(
        address pREWATokenAddress_,
        address routerAddress_,
        address accessControlAddr_,
        address emergencyControllerAddr_,
        address oracleIntegrationAddr_,
        address priceGuardAddr_
    ) external initializer {
        __ReentrancyGuard_init();

        if (pREWATokenAddress_ == address(0)) revert LM_PTokenZero();
        if (routerAddress_ == address(0)) revert LM_RouterZero();
        if (accessControlAddr_ == address(0)) revert LM_AccessControlZero();
        if (emergencyControllerAddr_ == address(0)) revert LM_EmergencyControllerZero();
        if (oracleIntegrationAddr_ == address(0)) revert LM_OracleIntegrationZero();
        if (priceGuardAddr_ == address(0)) revert LM_PriceGuardZero();

        uint256 codeSize;
        assembly { codeSize := extcodesize(routerAddress_) }
        if (codeSize == 0) revert NotAContract("router");
        assembly { codeSize := extcodesize(accessControlAddr_) }
        if (codeSize == 0) revert NotAContract("accessControl");
        assembly { codeSize := extcodesize(emergencyControllerAddr_) }
        if (codeSize == 0) revert NotAContract("emergencyController");
        assembly { codeSize := extcodesize(oracleIntegrationAddr_) }
        if (codeSize == 0) revert NotAContract("oracleIntegration");
        assembly { codeSize := extcodesize(priceGuardAddr_) }
        if (codeSize == 0) revert NotAContract("priceGuard");

        _pREWATokenAddress = pREWATokenAddress_;
        _routerAddress = routerAddress_;

        accessControl = AccessControl(accessControlAddr_);
        emergencyController = EmergencyController(emergencyControllerAddr_);
        oracleIntegration = OracleIntegration(oracleIntegrationAddr_);
        priceGuard = PriceGuard(priceGuardAddr_);

        _slippageTolerance = Constants.DEFAULT_SLIPPAGE;
        maxDeadlineOffset = 1 hours;

        address factoryAddr = address(0);
        try IPancakeRouter(routerAddress_).factory() returns (address factoryReturn) {
            if (factoryReturn == address(0)) revert LM_RouterReturnedZeroAddress("factory");
            factoryAddr = factoryReturn;
        } catch {
            revert LM_FactoryFail();
        }
        if (factoryAddr == address(0)) revert LM_InvalidFactory();
        _factoryAddress = factoryAddr;
    }

    /**
     * @dev Modifier to restrict access to functions to addresses with the DEFAULT_ADMIN_ROLE.
     */
    modifier onlyAdminRole() {
        if (address(accessControl) == address(0)) revert LM_AccessControlZero();
        if (!accessControl.hasRole(accessControl.DEFAULT_ADMIN_ROLE(), msg.sender)) revert NotAuthorized(accessControl.DEFAULT_ADMIN_ROLE());
        _;
    }

    /**
     * @dev Modifier to restrict access to functions to addresses with the PARAMETER_ROLE.
     */
    modifier onlyParameterRole() {
        if (address(accessControl) == address(0)) revert LM_AccessControlZero();
        if (!accessControl.hasRole(accessControl.PARAMETER_ROLE(), msg.sender)) revert NotAuthorized(accessControl.PARAMETER_ROLE());
        _;
    }

    /**
     * @dev Modifier that reverts if the system is in an emergency state.
     */
    modifier whenNotEmergency() {
        if (_isEffectivelyPaused()) revert SystemInEmergencyMode();
        _;
    }

    /**
     * @dev Modifier to validate the transaction deadline.
     * @param deadline The timestamp to validate.
     */
    modifier validateDeadline(uint256 deadline) {
        if (deadline < block.timestamp) revert DeadlineExpired();
        if (deadline > block.timestamp + maxDeadlineOffset) revert DeadlineTooFar();
        _;
    }

    /**
     * @dev Internal function to deterministically generate a unique ID for a pair.
     * @param tokenAddress The address of the non-pREWA token.
     * @return pairId The unique bytes32 ID for the pair.
     */
    function _getPairId(address tokenAddress) private view returns (bytes32 pairId) {
        if (tokenAddress == _pREWATokenAddress) revert InvalidAmount();
        (address token0, address token1) = tokenAddress < _pREWATokenAddress ? (tokenAddress, _pREWATokenAddress) : (_pREWATokenAddress, tokenAddress);
        pairId = keccak256(abi.encodePacked(token0, token1));
    }

    /**
     * @dev Internal wrapper for the DEX router's `addLiquidity` function.
     * @param tokenOtherAddress The address of the other token in the pair.
     * @param amountPREWADesired The desired amount of pREWA.
     * @param amountOtherDesired The desired amount of the other token.
     * @param amountPREWAMin The minimum amount of pREWA to add.
     * @param amountOtherMin The minimum amount of the other token to add.
     * @param deadline The transaction deadline.
     * @return actualPREWA The actual amount of pREWA added.
     * @return actualOther The actual amount of the other token added.
     * @return lp The amount of LP tokens received.
     */
    function _executeAddLiquidityRouterCall(
        address tokenOtherAddress,
        uint256 amountPREWADesired,
        uint256 amountOtherDesired,
        uint256 amountPREWAMin,
        uint256 amountOtherMin,
        uint256 deadline
    ) internal returns (uint256 actualPREWA, uint256 actualOther, uint256 lp) {
        (actualPREWA, actualOther, lp) = IPancakeRouter(_routerAddress).addLiquidity(
            _pREWATokenAddress,
            tokenOtherAddress,
            amountPREWADesired,
            amountOtherDesired,
            amountPREWAMin,
            amountOtherMin,
            msg.sender,
            deadline
        );
        return (actualPREWA, actualOther, lp);
    }

    /**
     * @inheritdoc ILiquidityManager
     * @dev This function adheres to the Checks-Effects-Interactions (CEI) pattern. Tokens are transferred
     * from the user right before the interaction with the external router to mitigate reentrancy risks.
     */
    function addLiquidity(
        address otherToken,
        uint256 pREWAAmountDesired,
        uint256 otherAmountDesired,
        uint256 pREWAMin,
        uint256 otherMin,
        uint256 deadline
    ) external override nonReentrant whenNotEmergency validateDeadline(deadline)
      returns (uint256 actualPREWAAdded, uint256 actualOtherAdded, uint256 lpReceived) {
        bytes32 pairId = _getPairId(otherToken);
        PairInfo storage pair = _pairs[pairId];
        if (pair.pairAddress == address(0)) revert LM_PairDoesNotExist("Pair not registered for the given token.");
        if (!pair.active) revert LM_PairNotActive("Pair not active for the given token.");
        if (pREWAMin == 0 || otherMin == 0) revert AmountIsZero();

        IERC20Upgradeable pREWAInst = IERC20Upgradeable(_pREWATokenAddress);
        IERC20Upgradeable otherTokenInst = IERC20Upgradeable(pair.tokenAddress);

        pREWAInst.safeTransferFrom(msg.sender, address(this), pREWAAmountDesired);
        otherTokenInst.safeTransferFrom(msg.sender, address(this), otherAmountDesired);

        pREWAInst.safeApprove(_routerAddress, pREWAAmountDesired);
        otherTokenInst.safeApprove(_routerAddress, otherAmountDesired);

        (actualPREWAAdded, actualOtherAdded, lpReceived) = _executeAddLiquidityRouterCall(
            pair.tokenAddress,
            pREWAAmountDesired,
            otherAmountDesired,
            pREWAMin,
            otherMin,
            deadline
        );

        if (pREWAAmountDesired > actualPREWAAdded) {
            pREWAInst.safeTransfer(msg.sender, pREWAAmountDesired - actualPREWAAdded);
        }
        if (otherAmountDesired > actualOtherAdded) {
            otherTokenInst.safeTransfer(msg.sender, otherAmountDesired - actualOtherAdded);
        }

        pREWAInst.safeApprove(_routerAddress, 0);
        otherTokenInst.safeApprove(_routerAddress, 0);

        emit LiquidityAdded(otherToken, actualPREWAAdded, actualOtherAdded, lpReceived, msg.sender);
    }

    /**
     * @dev Internal wrapper for the DEX router's `addLiquidityETH` function.
     * @param amountPREWADesired The desired amount of pREWA.
     * @param amountPREWAMin The minimum amount of pREWA to add.
     * @param amountBNBMin The minimum amount of BNB to add.
     * @param deadline The transaction deadline.
     * @param msgValue The amount of BNB sent with the transaction.
     * @return actualPREWA The actual amount of pREWA added.
     * @return actualBNB The actual amount of BNB added.
     * @return lp The amount of LP tokens received.
     */
    function _executeAddLiquidityETHRouterCall(
        uint256 amountPREWADesired,
        uint256 amountPREWAMin,
        uint256 amountBNBMin,
        uint256 deadline,
        uint256 msgValue
    ) internal returns (uint256 actualPREWA, uint256 actualBNB, uint256 lp) {
        (actualPREWA, actualBNB, lp) = IPancakeRouter(_routerAddress).addLiquidityETH{value: msgValue}(
            _pREWATokenAddress,
            amountPREWADesired,
            amountPREWAMin,
            amountBNBMin,
            msg.sender,
            deadline
        );
        return (actualPREWA, actualBNB, lp);
    }

    /**
     * @inheritdoc ILiquidityManager
     * @dev This function follows the CEI pattern. It also handles BNB refunds gracefully by tracking failed
     * refunds for later administrative recovery, preventing user funds from being stuck.
     */
    function addLiquidityBNB(
        uint256 pREWAAmountDesired,
        uint256 pREWAMin,
        uint256 bnbMin,
        uint256 deadline
    ) external payable override nonReentrant whenNotEmergency validateDeadline(deadline)
      returns (uint256 actualPREWAAdded, uint256 actualBNBAdded, uint256 lpReceived) {
        address wethAddress;
        try IPancakeRouter(_routerAddress).WETH() returns (address wethReturn) { wethAddress = wethReturn; } catch { revert LM_WETHFail(); }

        bytes32 pairId = _getPairId(wethAddress);
        PairInfo storage pairBNB = _pairs[pairId];
        if (pairBNB.pairAddress == address(0)) revert LM_BNBPairDoesNotExist();
        if (!pairBNB.active) revert LM_BNBPairNotActive();
        if (pREWAMin == 0 || bnbMin == 0) revert AmountIsZero();

        IERC20Upgradeable pREWAInst = IERC20Upgradeable(_pREWATokenAddress);

        pREWAInst.safeTransferFrom(msg.sender, address(this), pREWAAmountDesired);
        pREWAInst.safeApprove(_routerAddress, pREWAAmountDesired);

        (actualPREWAAdded, actualBNBAdded, lpReceived) = _executeAddLiquidityETHRouterCall(
            pREWAAmountDesired,
            pREWAMin,
            bnbMin,
            deadline,
            msg.value
        );

        if (pREWAAmountDesired > actualPREWAAdded) {
            pREWAInst.safeTransfer(msg.sender, pREWAAmountDesired - actualPREWAAdded);
        }

        if (msg.value > actualBNBAdded) {
            uint256 refundAmount = msg.value - actualBNBAdded;
            (bool success, ) = msg.sender.call{value: refundAmount}("");
            if (!success) {
                pendingBNBRefunds[msg.sender] += refundAmount;
                emit BNBRefundFailed(msg.sender, refundAmount);
            }
        }

        pREWAInst.safeApprove(_routerAddress, 0);
        emit LiquidityAdded(wethAddress, actualPREWAAdded, actualBNBAdded, lpReceived, msg.sender);
    }

    /**
     * @dev Internal wrapper for the DEX router's `removeLiquidity` function.
     * @param tokenOtherAddress The address of the other token in the pair.
     * @param liquidityToRemove The amount of LP tokens to burn.
     * @param amountPREWAMin The minimum amount of pREWA to receive.
     * @param amountOtherMin The minimum amount of the other token to receive.
     * @param deadline The transaction deadline.
     * @return amountPREWA The amount of pREWA received.
     * @return amountOther The amount of the other token received.
     */
    function _executeRemoveLiquidityRouterCall(
        address tokenOtherAddress,
        uint256 liquidityToRemove,
        uint256 amountPREWAMin,
        uint256 amountOtherMin,
        uint256 deadline
    ) internal returns (uint256 amountPREWA, uint256 amountOther) {
        (amountPREWA, amountOther) = IPancakeRouter(_routerAddress).removeLiquidity(
            _pREWATokenAddress,
            tokenOtherAddress,
            liquidityToRemove,
            amountPREWAMin,
            amountOtherMin,
            msg.sender,
            deadline
        );
        return (amountPREWA, amountOther);
    }

    /**
     * @inheritdoc ILiquidityManager
     * @dev This function adheres to the CEI pattern by transferring LP tokens from the user just
     * before the interaction with the external router to mitigate reentrancy risks.
     */
    function removeLiquidity(
        address otherToken,
        uint256 liquidity,
        uint256 pREWAMin,
        uint256 otherMin,
        uint256 deadline
    ) external override nonReentrant whenNotEmergency validateDeadline(deadline)
      returns(uint256 amountToken, uint256 amountOther) {
        bytes32 pairId = _getPairId(otherToken);
        PairInfo storage pair = _pairs[pairId];
        if (pair.pairAddress == address(0)) revert LM_PairDoesNotExist("Pair not registered for the given token.");
        if (!pair.active) revert LM_PairNotActive("Pair not active for the given token.");
        if (pREWAMin == 0 || otherMin == 0 || liquidity == 0) revert AmountIsZero();

        IERC20Upgradeable lpTokenInst = IERC20Upgradeable(pair.pairAddress);
        
        lpTokenInst.safeTransferFrom(msg.sender, address(this), liquidity);
        lpTokenInst.safeApprove(_routerAddress, liquidity);

        (amountToken, amountOther) = _executeRemoveLiquidityRouterCall(
            pair.tokenAddress,
            liquidity,
            pREWAMin,
            otherMin,
            deadline
        );

        lpTokenInst.safeApprove(_routerAddress, 0);
        emit LiquidityRemoved(otherToken, amountToken, amountOther, liquidity, msg.sender);
    }

    /**
     * @dev Internal wrapper for the DEX router's `removeLiquidityETH` function.
     * @param liquidityToRemove The amount of LP tokens to burn.
     * @param amountPREWAMin The minimum amount of pREWA to receive.
     * @param amountBNBMin The minimum amount of BNB to receive.
     * @param deadline The transaction deadline.
     * @return amountPREWA The amount of pREWA received.
     * @return amountBNB The amount of BNB received.
     */
    function _executeRemoveLiquidityETHRouterCall(
        uint256 liquidityToRemove,
        uint256 amountPREWAMin,
        uint256 amountBNBMin,
        uint256 deadline
    ) internal returns (uint256 amountPREWA, uint256 amountBNB) {
        (amountPREWA, amountBNB) = IPancakeRouter(_routerAddress).removeLiquidityETH(
            _pREWATokenAddress,
            liquidityToRemove,
            amountPREWAMin,
            amountBNBMin,
            msg.sender,
            deadline
        );
        return (amountPREWA, amountBNB);
    }

    /**
     * @inheritdoc ILiquidityManager
     */
    function removeLiquidityBNB(
        uint256 liquidity,
        uint256 pREWAMin,
        uint256 bnbMin,
        uint256 deadline
    ) external override nonReentrant whenNotEmergency validateDeadline(deadline)
      returns(uint256 amountToken, uint256 amountBNB) {
        address wethAddress;
        try IPancakeRouter(_routerAddress).WETH() returns (address wethReturn) { wethAddress = wethReturn; } catch { revert LM_WETHFail(); }
        
        bytes32 pairId = _getPairId(wethAddress);
        PairInfo storage pair = _pairs[pairId];
        if (pair.pairAddress == address(0)) revert LM_BNBPairDoesNotExist();
        if (!pair.active) revert LM_BNBPairNotActive();
        if (pREWAMin == 0 || bnbMin == 0 || liquidity == 0) revert AmountIsZero();

        IERC20Upgradeable lpTokenInst = IERC20Upgradeable(pair.pairAddress);
        
        lpTokenInst.safeTransferFrom(msg.sender, address(this), liquidity);
        lpTokenInst.safeApprove(_routerAddress, liquidity);

        (amountToken, amountBNB) = _executeRemoveLiquidityETHRouterCall(
            liquidity,
            pREWAMin,
            bnbMin,
            deadline
        );

        lpTokenInst.safeApprove(_routerAddress, 0);
        emit LiquidityRemoved(wethAddress, amountToken, amountBNB, liquidity, msg.sender);
    }

    /**
     * @inheritdoc ILiquidityManager
     */
    function registerPair(address tokenAddress) external override onlyParameterRole returns(bool successFlag) {
        address actualTokenAddress = tokenAddress;
        if (tokenAddress == address(0)) {
            try IPancakeRouter(_routerAddress).WETH() returns(address wethAddr) {
                if (wethAddr == address(0)) revert LM_RouterReturnedZeroAddress("weth");
                actualTokenAddress = wethAddr;
            } catch { revert LM_WETHFail(); }
        }
        if (actualTokenAddress == _pREWATokenAddress) revert InvalidAmount();
        
        bytes32 pairId = _getPairId(actualTokenAddress);
        if (_pairs[pairId].pairAddress != address(0)) revert LM_PairAlreadyRegistered("Pair for this token is already registered.");
        
        if (_pairRegistrationInProgress[pairId]) revert("Pair registration already in progress");
        _pairRegistrationInProgress[pairId] = true;

        address pairAddr;
        try IPancakeFactory(_factoryAddress).getPair(_pREWATokenAddress, actualTokenAddress) returns(address existingPair) {
            pairAddr = existingPair;
        } catch { /* This is expected if the pair doesn't exist; proceed to creation. */ }

        if (pairAddr == address(0)) {
            try IPancakeFactory(_factoryAddress).createPair(_pREWATokenAddress, actualTokenAddress) returns(address createdPair) {
                if (createdPair == address(0)) revert LM_CreatePairReturnedZero("Pair for this token could not be created.", actualTokenAddress);
                pairAddr = createdPair;
            } catch (bytes memory reasonData) {
                string memory reason = "Factory createPair reverted";
                 if (reasonData.length >= 4) {
                    bytes4 errorSelector;
                    assembly { errorSelector := mload(add(reasonData, 0x20)) errorSelector := shr(224, errorSelector) }
                    if (errorSelector == bytes4(keccak256("Error(string)"))) {
                        reason = "Factory createPair reverted with Error(string)";
                    } else if (errorSelector == bytes4(keccak256("Panic(uint256)"))) {
                         reason = "Factory createPair reverted with Panic(uint256)";
                    }
                }
                revert LM_CreatePairReverted("Pair for this token could not be created.", actualTokenAddress, reason);
            }
        }
        if (pairAddr == address(0)) revert LM_FactoryFail();

        _pairs[pairId] = PairInfo({
            pairAddress: pairAddr,
            tokenAddress: actualTokenAddress,
            active: true
        });
        _isRegisteredAndActiveLpToken[pairAddr] = true;
        emit PairRegistered(pairId, pairAddr, actualTokenAddress, msg.sender);

        if (address(oracleIntegration) != address(0)) {
            try oracleIntegration.registerLPToken(pairAddr, _pREWATokenAddress, actualTokenAddress) {
                // Success
            } catch {
                emit LPTokenOracleRegistrationFailed(pairAddr, _pREWATokenAddress, actualTokenAddress);
            }
        }
        
        delete _pairRegistrationInProgress[pairId];
        successFlag = true;
        return successFlag;
    }
    
    /**
     * @inheritdoc ILiquidityManager
     */
    function setPairStatus(address otherToken, bool active) external override onlyParameterRole nonReentrant returns(bool successFlag) {
        address actualTokenAddress = otherToken == address(0) ? IPancakeRouter(_routerAddress).WETH() : otherToken;
        bytes32 pairId = _getPairId(actualTokenAddress);
        PairInfo storage pair = _pairs[pairId];
        if (pair.pairAddress == address(0)) revert LM_PairDoesNotExist("Pair not registered for the given token.");

        if (pair.active == active) {
             successFlag = true;
             return successFlag;
        }
        pair.active = active;
        _isRegisteredAndActiveLpToken[pair.pairAddress] = active;

        emit PairStatusUpdated(otherToken, active, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc ILiquidityManager
     */
    function getPairInfo(address otherToken) external view override returns (
        address pairAddressOut, address tokenAddressOut, bool activeOut,
        uint256 reserve0Out, uint256 reserve1Out, bool pREWAIsToken0Out, uint32 blockTimestampLastOut
    ) {
        address actualTokenAddress = otherToken == address(0) ? IPancakeRouter(_routerAddress).WETH() : otherToken;
        bytes32 pairId = _getPairId(actualTokenAddress);
        address queriedPairAddress = _pairs[pairId].pairAddress;
        if (queriedPairAddress == address(0)) {
            return (address(0), address(0), false, 0, 0, false, 0);
        }

        PairInfo storage pair = _pairs[pairId];
        pairAddressOut = pair.pairAddress;
        tokenAddressOut = pair.tokenAddress;
        activeOut = pair.active;

        reserve0Out = 0;
        reserve1Out = 0;
        blockTimestampLastOut = 0;
        try IPancakePair(pair.pairAddress).getReserves() returns(uint112 r0, uint112 r1, uint32 ts) {
            reserve0Out = r0;
            reserve1Out = r1;
            blockTimestampLastOut = ts;
        } catch { }

        pREWAIsToken0Out = false;
        try IPancakePair(pair.pairAddress).token0() returns(address t0) {
            pREWAIsToken0Out = (t0 == _pREWATokenAddress);
        } catch { }
    }

    /**
     * @inheritdoc ILiquidityManager
     */
    function getLPTokenAddress(address otherToken) external view override returns(address lpTokenAddr_) {
        address actualTokenAddress = otherToken == address(0) ? IPancakeRouter(_routerAddress).WETH() : otherToken;
        bytes32 pairId = _getPairId(actualTokenAddress);
        lpTokenAddr_ = _pairs[pairId].pairAddress;
        return lpTokenAddr_;
    }

    /**
     * @inheritdoc ILiquidityManager
     */
    function setSlippageTolerance(uint256 tolerance) external override onlyParameterRole nonReentrant returns(bool successFlag) {
        if (tolerance == 0 || tolerance > Constants.MAX_SLIPPAGE) revert LM_SlippageInvalid(tolerance);
        uint256 oldSlippage = _slippageTolerance;
        _slippageTolerance = tolerance;
        emit SlippageToleranceUpdated(oldSlippage, tolerance, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc ILiquidityManager
     */
    function setMaxDeadlineOffset(uint256 offset) external override onlyParameterRole nonReentrant returns(bool successFlag) {
        if (offset < 5 minutes || offset > 1 days) revert LM_DeadlineOffsetInvalid(offset);
        uint256 oldOffset = maxDeadlineOffset;
        maxDeadlineOffset = offset;
        emit MaxDeadlineOffsetUpdated(oldOffset, offset, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc ILiquidityManager
     */
    function setRouterAddress(address routerAddr) external override onlyAdminRole nonReentrant returns(bool successFlag) {
        if (routerAddr == address(0)) revert LM_RouterZero();
        address factoryAddr = address(0);
        try IPancakeRouter(routerAddr).factory() returns(address factoryReturn) {
            if (factoryReturn == address(0)) revert LM_RouterUpdateInvalidFactory();
            factoryAddr = factoryReturn;
        } catch { revert LM_RouterUpdateFactoryFail(); }
        
        if (factoryAddr == address(0)) revert LM_RouterUpdateInvalidFactory();

        address oldRouter = _routerAddress;
        _routerAddress = routerAddr;
        _factoryAddress = factoryAddr;
        emit RouterAddressUpdated(oldRouter, routerAddr, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc ILiquidityManager
     */
    function recoverTokens(address tokenAddressRec, uint256 amountRec, address recipient) external override onlyAdminRole nonReentrant returns(bool successFlag) {
        if (tokenAddressRec == address(0)) revert ZeroAddress("tokenAddress for recovery");
        if (recipient == address(0)) revert ZeroAddress("recipient for recovery");
        if (tokenAddressRec == _pREWATokenAddress) revert LM_CannotRecoverPToken();
        if (amountRec == 0) revert AmountIsZero();
        if (_isRegisteredAndActiveLpToken[tokenAddressRec]) revert LM_CannotRecoverActiveLP();

        IERC20Upgradeable tokenInst = IERC20Upgradeable(tokenAddressRec);
        uint256 balance = tokenInst.balanceOf(address(this));
        if (amountRec > balance) revert InsufficientBalance(balance, amountRec);

        tokenInst.safeTransfer(recipient, amountRec);
        emit LiquidityManagerTokenRecovered(tokenAddressRec, amountRec, recipient);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc ILiquidityManager
     */
    function recoverFailedBNBRefund(address user) external override onlyAdminRole nonReentrant returns(bool successFlag) {
        if (user == address(0)) revert ZeroAddress("user for BNB recovery");
        uint256 amountToRefund = pendingBNBRefunds[user];
        if (amountToRefund == 0) revert LM_NoPendingRefund();

        pendingBNBRefunds[user] = 0;
        
        (bool success, ) = user.call{value: amountToRefund}("");
        if (!success) {
            // If the recovery call fails, revert and leave the amount in the pending map
            // so the admin can try again later, perhaps after instructing the user
            // to ensure their contract can receive BNB.
            pendingBNBRefunds[user] = amountToRefund;
            revert("BNB recovery transfer failed");
        }

        emit BNBRefundRecovered(user, amountToRefund, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function checkEmergencyStatus(bytes4) external view override returns(bool allowedStatus) {
        allowedStatus = !_isEffectivelyPaused();
        return allowedStatus;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function emergencyShutdown(uint8 emergencyLevelInput) external override returns(bool successFlag) {
        if (address(emergencyController) == address(0)) revert LM_ControllerNotSet("emergencyController");
        if (msg.sender != address(emergencyController)) revert LM_CallerNotEmergencyController();

        emit EmergencyShutdownHandled(emergencyLevelInput, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function getEmergencyController() external view override returns(address controllerAddress) {
        controllerAddress = address(emergencyController);
        return controllerAddress;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function setEmergencyController(address controllerAddress) external override onlyAdminRole returns(bool successFlag) {
        if (controllerAddress == address(0)) revert LM_EmergencyControllerZero();
        uint256 codeSize;
        assembly { codeSize := extcodesize(controllerAddress) }
        if (codeSize == 0) revert NotAContract("emergencyController");

        address oldController = address(emergencyController);
        emergencyController = EmergencyController(controllerAddress);
        emit EmergencyControllerSet(oldController, controllerAddress, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Updates the OracleIntegration contract address.
     * @dev Only callable by an admin.
     * @param oracleAddress The address of the new OracleIntegration contract.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function updateOracleIntegration(address oracleAddress) external onlyAdminRole returns(bool successFlag){
        if (oracleAddress == address(0)) revert LM_OracleIntegrationZero();
        uint256 codeSize;
        assembly { codeSize := extcodesize(oracleAddress) }
        if (codeSize == 0) revert NotAContract("oracleIntegration");

        address oldOracle = address(oracleIntegration);
        oracleIntegration = OracleIntegration(oracleAddress);
        emit OracleIntegrationSet(oldOracle, oracleAddress, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Updates the PriceGuard contract address.
     * @dev Only callable by an admin.
     * @param priceGuardAddress_ The address of the new PriceGuard contract.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function updatePriceGuard(address priceGuardAddress_) external onlyAdminRole returns(bool successFlag){
        if (priceGuardAddress_ == address(0)) revert LM_PriceGuardZero();
        uint256 codeSize;
        assembly { codeSize := extcodesize(priceGuardAddress_) }
        if (codeSize == 0) revert LM_PriceGuardNotContract();

        address oldGuard = address(priceGuard);
        priceGuard = PriceGuard(priceGuardAddress_);
        emit PriceGuardSet(oldGuard, priceGuardAddress_, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function isEmergencyPaused() public view override returns(bool isPausedStatus) {
        isPausedStatus = _isEffectivelyPaused();
        return isPausedStatus;
    }

    /**
     * @dev Allows the contract to receive native currency (e.g., BNB) for `addLiquidityBNB`.
     */
    receive() external payable {}
}
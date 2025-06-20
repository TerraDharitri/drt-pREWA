// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../interfaces/IEmergencyAware.sol";

/**
 * @title ILiquidityManager Interface
 * @notice Defines the external interface for the LiquidityManager contract.
 */
interface ILiquidityManager is IEmergencyAware {
    /**
     * @notice Emitted when liquidity is successfully added to a pair.
     * @param otherToken The address of the non-pREWA token in the pair.
     * @param pREWAAmount The amount of pREWA token added.
     * @param otherAmount The amount of the other token added.
     * @param liquidityReceived The amount of LP tokens minted.
     * @param user The address of the liquidity provider.
     */
    event LiquidityAdded(address indexed otherToken, uint256 pREWAAmount, uint256 otherAmount, uint256 liquidityReceived, address indexed user);
    
    /**
     * @notice Emitted when liquidity is successfully removed from a pair.
     * @param otherToken The address of the non-pREWA token in the pair.
     * @param pREWAAmount The amount of pREWA token withdrawn.
     * @param otherAmount The amount of the other token withdrawn.
     * @param liquidityBurned The amount of LP tokens burned.
     * @param user The address of the liquidity provider.
     */
    event LiquidityRemoved(address indexed otherToken, uint256 pREWAAmount, uint256 otherAmount, uint256 liquidityBurned, address indexed user);
    
    /**
     * @notice Emitted when a new liquidity pair is registered.
     * @param pairId The deterministic ID of the pair.
     * @param pairAddress The address of the LP token contract.
     * @param tokenAddress The address of the non-pREWA token in the pair.
     * @param registrar The address that registered the pair.
     */
    event PairRegistered(bytes32 indexed pairId, address indexed pairAddress, address indexed tokenAddress, address registrar);
    
    /**
     * @notice Emitted when a registered pair's active status is updated.
     * @param otherToken The address of the non-pREWA token in the pair.
     * @param active The new active status.
     * @param updater The address that updated the status.
     */
    event PairStatusUpdated(address indexed otherToken, bool active, address indexed updater);
    
    /**
     * @notice Emitted when the DEX router address is updated.
     * @param oldRouter The address of the old router.
     * @param newRouter The address of the new router.
     * @param updater The address that performed the update.
     */
    event RouterAddressUpdated(address indexed oldRouter, address indexed newRouter, address indexed updater);
    
    /**
     * @notice Emitted when the default slippage tolerance is updated.
     * @param oldTolerance The old slippage tolerance in basis points.
     * @param newTolerance The new slippage tolerance in basis points.
     * @param updater The address that performed the update.
     */
    event SlippageToleranceUpdated(uint256 oldTolerance, uint256 newTolerance, address indexed updater);
    
    /**
     * @notice Emitted when the maximum deadline offset is updated.
     * @param oldOffset The old offset in seconds.
     * @param newOffset The new offset in seconds.
     * @param updater The address that performed the update.
     */
    event MaxDeadlineOffsetUpdated(uint256 oldOffset, uint256 newOffset, address indexed updater);
    
    /**
     * @notice Emitted if registering an LP token with the OracleIntegration contract fails.
     * @param lpTokenAddress The address of the LP token.
     * @param token0 The address of the first underlying token.
     * @param token1 The address of the second underlying token.
     */
    event LPTokenOracleRegistrationFailed(address indexed lpTokenAddress, address indexed token0, address indexed token1);
    
    /**
     * @notice Emitted if refunding excess BNB during `addLiquidityBNB` fails.
     * @param user The address that should have received the refund.
     * @param amount The amount of BNB that failed to be refunded.
     */
    event BNBRefundFailed(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a previously failed BNB refund is successfully recovered by an admin.
     * @param user The address that received the recovered BNB.
     * @param amount The amount of BNB that was recovered.
     * @param admin The address of the admin who initiated the recovery.
     */
    event BNBRefundRecovered(address indexed user, uint256 amount, address indexed admin);

    /**
     * @notice Adds liquidity to a pREWA-ERC20 pair.
     * @param otherToken The address of the other token in the pair.
     * @param pREWAAmountDesired The desired amount of pREWA to add.
     * @param otherAmountDesired The desired amount of the other token to add.
     * @param pREWAMin The minimum amount of pREWA to add.
     * @param otherMin The minimum amount of the other token to add.
     * @param deadline The transaction deadline.
     * @return actualPREWAAdded The actual amount of pREWA added.
     * @return actualOtherAdded The actual amount of the other token added.
     * @return lpReceived The amount of LP tokens received.
     */
    function addLiquidity(address otherToken, uint256 pREWAAmountDesired, uint256 otherAmountDesired, uint256 pREWAMin, uint256 otherMin, uint256 deadline) external returns (uint256 actualPREWAAdded, uint256 actualOtherAdded, uint256 lpReceived);
    
    /**
     * @notice Adds liquidity to the pREWA-BNB pair.
     * @param pREWAAmountDesired The desired amount of pREWA to add.
     * @param pREWAMin The minimum amount of pREWA to add.
     * @param bnbMin The minimum amount of BNB to add.
     * @param deadline The transaction deadline.
     * @return actualPREWAAdded The actual amount of pREWA added.
     * @return actualBNBAdded The actual amount of BNB added.
     * @return lpReceived The amount of LP tokens received.
     */
    function addLiquidityBNB(uint256 pREWAAmountDesired, uint256 pREWAMin, uint256 bnbMin, uint256 deadline) external payable returns (uint256 actualPREWAAdded, uint256 actualBNBAdded, uint256 lpReceived);

    /**
     * @notice Removes liquidity from a pREWA-ERC20 pair.
     * @param otherToken The address of the other token in the pair.
     * @param liquidity The amount of LP tokens to burn.
     * @param pREWAMin The minimum amount of pREWA to receive.
     * @param otherMin The minimum amount of the other token to receive.
     * @param deadline The transaction deadline.
     * @return amountToken The amount of pREWA received.
     * @return amountOther The amount of the other token received.
     */
    function removeLiquidity(address otherToken, uint256 liquidity, uint256 pREWAMin, uint256 otherMin, uint256 deadline) external returns (uint256 amountToken, uint256 amountOther);
    
    /**
     * @notice Removes liquidity from the pREWA-BNB pair.
     * @param liquidity The amount of LP tokens to burn.
     * @param pREWAMin The minimum amount of pREWA to receive.
     * @param bnbMin The minimum amount of BNB to receive.
     * @param deadline The transaction deadline.
     * @return amountToken The amount of pREWA received.
     * @return amountBNB The amount of BNB received.
     */
    function removeLiquidityBNB(uint256 liquidity, uint256 pREWAMin, uint256 bnbMin, uint256 deadline) external returns (uint256 amountToken, uint256 amountBNB);

    /**
     * @notice Registers a new pREWA pair with the manager, creating it on the DEX if it doesn't exist.
     * @param tokenAddress The address of the non-pREWA token to pair with. Use address(0) for the native wrapped token (e.g., WBNB).
     * @return success True if the operation was successful.
     */
    function registerPair(address tokenAddress) external returns (bool success);
    
    /**
     * @notice Activates or deactivates a registered pair for liquidity operations.
     * @param otherToken The address of the non-pREWA token in the pair to update.
     * @param active The new active status for the pair.
     * @return success True if the operation was successful.
     */
    function setPairStatus(address otherToken, bool active) external returns (bool success);

    /**
     * @notice Retrieves detailed information about a registered pair.
     * @param otherToken The address of the non-pREWA token in the pair.
     * @return pairAddressOut The address of the LP token contract.
     * @return tokenAddressOut The address of the non-pREWA token.
     * @return activeOut The active status of the pair.
     * @return reserve0Out The reserve of token0.
     * @return reserve1Out The reserve of token1.
     * @return pREWAIsToken0Out True if pREWA is token0 in the pair.
     * @return blockTimestampLastOut The timestamp of the last interaction with the pair.
     */
    function getPairInfo(address otherToken) external view returns (address pairAddressOut, address tokenAddressOut, bool activeOut, uint256 reserve0Out, uint256 reserve1Out, bool pREWAIsToken0Out, uint32 blockTimestampLastOut);
    
    /**
     * @notice Retrieves the LP token address for a given pair.
     * @param otherToken The address of the non-pREWA token in the pair.
     * @return lpTokenAddr_ The address of the LP token contract.
     */
    function getLPTokenAddress(address otherToken) external view returns (address lpTokenAddr_);

    /**
     * @notice Sets the default slippage tolerance for liquidity operations.
     * @param tolerance The new slippage tolerance in basis points.
     * @return success True if the operation was successful.
     */
    function setSlippageTolerance(uint256 tolerance) external returns (bool success);
    
    /**
     * @notice Sets the maximum time offset for transaction deadlines.
     * @param offset The new maximum offset in seconds.
     * @return success True if the operation was successful.
     */
    function setMaxDeadlineOffset(uint256 offset) external returns (bool success);
    
    /**
     * @notice Sets the address of the DEX router.
     * @param routerAddress The new router address.
     * @return success True if the operation was successful.
     */
    function setRouterAddress(address routerAddress) external returns (bool success);
    
    /**
     * @notice Recovers non-essential ERC20 tokens mistakenly sent to the contract.
     * @param tokenAddressRec The address of the token to recover.
     * @param amountRec The amount to recover.
     * @param recipient The address to receive the recovered tokens.
     * @return successFlag True if the operation was successful.
     */
    function recoverTokens(address tokenAddressRec, uint256 amountRec, address recipient) external returns(bool successFlag);

    /**
     * @notice Allows an admin to recover BNB for a user whose refund failed during `addLiquidityBNB`.
     * @dev This function should be called after off-chain communication confirms the user and amount.
     * @param user The address of the user who is owed a refund.
     * @return successFlag True if the recovery was successful.
     */
    function recoverFailedBNBRefund(address user) external returns(bool successFlag);
}
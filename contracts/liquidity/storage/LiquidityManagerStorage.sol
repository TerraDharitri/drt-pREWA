// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title LiquidityManagerStorage
 * @author Rewa
 * @notice Defines the storage layout for the LiquidityManager contract.
 * @dev This contract is not meant to be deployed. It is inherited by LiquidityManager to separate
 * storage variables from logic, which can help in managing upgrades.
 */
contract LiquidityManagerStorage {
    /**
     * @notice Represents a registered liquidity pair.
     * @param pairAddress The address of the DEX LP token contract.
     * @param tokenAddress The address of the non-pREWA token in the pair.
     * @param active A flag indicating if liquidity operations are enabled for this pair.
     */
    struct PairInfo {
        address pairAddress;
        address tokenAddress;
        bool active;
    }

    /// @dev The address of the pREWA token.
    address internal _pREWATokenAddress;
    /// @dev The address of the DEX router contract (e.g., PancakeSwap Router).
    address internal _routerAddress;
    /// @dev The address of the DEX factory contract (e.g., PancakeSwap Factory).
    address internal _factoryAddress;
    /// @dev The default slippage tolerance for liquidity operations, in basis points.
    uint256 internal _slippageTolerance;
    /// @dev A mapping from a pair's deterministic ID to its PairInfo struct.
    mapping(bytes32 => PairInfo) internal _pairs;
    /// @dev A mapping to quickly check if an LP token address is registered and active, used for token recovery checks.
    mapping(address => bool) internal _isRegisteredAndActiveLpToken;
    
    /// @dev A reentrancy lock for the registerPair function to prevent reentrancy for a specific pair ID.
    mapping(bytes32 => bool) internal _pairRegistrationInProgress;
    
    /// @notice Tracks BNB amounts that failed to be refunded to users in `addLiquidityBNB`.
    mapping(address => uint256) public pendingBNBRefunds;
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title LiquidityManagerStorage
 * @author drt-pREWA
 * @notice Defines the storage layout for the LiquidityManager contract.
 * @dev This contract is not meant to be deployed directly. It is inherited by LiquidityManager
 * to separate storage variables from logic, following the unstructured storage pattern for upgradeability.
 */
contract LiquidityManagerStorage {
    /**
     * @notice Struct to hold information about a registered and approved liquidity pair.
     * @param pairAddress The address of the PancakeSwap V2 LP token contract.
     * @param tokenAddress The address of the non-pREWA token in the pair.
     * @param active A flag indicating if liquidity operations are currently enabled for this pair.
     */
    struct PairInfo {
        address pairAddress;
        address tokenAddress;
        bool active;
    }

    /// @notice The address of the pREWA token contract.
    address internal _pREWATokenAddress;
    /// @notice The address of the PancakeSwap V2 Router contract.
    address internal _routerAddress;
    /// @notice The address of the PancakeSwap V2 Factory contract, derived from the router.
    address internal _factoryAddress;

    /// @notice The default slippage tolerance for liquidity operations, in basis points (e.g., 50 for 0.5%).
    uint256 internal _slippageTolerance;

    /// @notice A mapping from a pair's unique ID (keccak256 of sorted token addresses) to its PairInfo.
    mapping(bytes32 => PairInfo) internal _pairs;

    /// @notice Mapping to track users who have failed BNB refunds from `addLiquidityBNB`.
    mapping(address => uint256) public pendingBNBRefunds;

    /// @notice A lock to prevent a single address from registering multiple pairs in the same transaction, mitigating reentrancy.
    mapping(bytes32 => bool) internal _pairRegistrationInProgress;

    /// @notice A quick lookup mapping to check if an LP token address is both registered and active.
    mapping(address => bool) internal _isRegisteredAndActiveLpToken;

    /// @notice Reserved storage space to allow for future upgrades without storage collisions.
    uint256[49] private __gap;
}
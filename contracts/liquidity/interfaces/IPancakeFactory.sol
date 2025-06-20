// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IPancakeFactory Interface
 * @notice Defines the external interface for a PancakeSwap V2 Factory contract.
 * @dev This interface includes functions to get existing pairs and create new ones.
 */
interface IPancakeFactory {
    /**
     * @notice Gets the address of the pair for two tokens.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @return pair The address of the LP pair contract, or address(0) if it does not exist.
     */
    function getPair(address tokenA, address tokenB) external view returns (address pair);

    /**
     * @notice Creates a liquidity pair for two tokens.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @return pair The address of the newly created LP pair contract.
     */
    function createPair(address tokenA, address tokenB) external returns (address pair);

    /**
     * @notice Sets the address that will receive protocol fees.
     * @param _feeTo The address to receive fees.
     */
    function setFeeTo(address _feeTo) external;

    /**
     * @notice Sets the address that is allowed to change the fee-to address.
     * @param _feeToSetter The new fee-to setter address.
     */
    function setFeeToSetter(address _feeToSetter) external;

    /**
     * @notice Returns the address that receives protocol fees.
     * @return The address of the fee recipient.
     */
    function feeTo() external view returns (address);

    /**
     * @notice Returns the address that is allowed to change the fee-to address.
     * @return The address of the fee-to setter.
     */
    function feeToSetter() external view returns (address);

    /**
     * @notice Returns the total number of pairs created by the factory.
     * @return The total number of pairs.
     */
    function allPairsLength() external view returns (uint);

    /**
     * @notice Returns the address of the pair at a specific index.
     * @param _index The index of the pair in the `allPairs` array.
     * @return pair The address of the LP pair contract.
     */
    function allPairs(uint _index) external view returns (address pair);
}
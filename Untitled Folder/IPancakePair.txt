// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IPancakePair Interface
 * @notice Defines the external interface for a PancakeSwap V2 LP Pair contract.
 * @dev This interface includes functions for querying reserves, prices, and performing swaps directly on the pair.
 */
interface IPancakePair {
    /**
     * @notice Returns the address of the first token in the pair.
     * @return The address of token0.
     */
    function token0() external view returns (address);

    /**
     * @notice Returns the address of the second token in the pair.
     * @return The address of token1.
     */
    function token1() external view returns (address);

    /**
     * @notice Returns the reserves of the pair and the timestamp of the last block in which an interaction occurred.
     * @return reserve0 The reserve of token0.
     * @return reserve1 The reserve of token1.
     * @return blockTimestampLast The timestamp of the last interaction.
     */
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    /**
     * @notice Returns the cumulative price of token0.
     * @return The last cumulative price for token0.
     */
    function price0CumulativeLast() external view returns (uint); 

    /**
     * @notice Returns the cumulative price of token1.
     * @return The last cumulative price for token1.
     */
    function price1CumulativeLast() external view returns (uint); 

    /**
     * @notice Returns the total supply of LP tokens.
     * @return The total supply.
     */
    function totalSupply() external view returns (uint); 

    /**
     * @notice Returns the LP token balance of an owner.
     * @param owner The address of the balance holder.
     * @return The balance amount.
     */
    function balanceOf(address owner) external view returns (uint); 

    /**
     * @notice Returns the allowance a spender has from an owner.
     * @param owner The address of the token owner.
     * @param spender The address of the spender.
     * @return The allowance amount.
     */
    function allowance(address owner, address spender) external view returns (uint); 

    /**
     * @notice Approves a spender to use an amount of LP tokens.
     * @param spender The address of the spender.
     * @param value The amount to approve.
     * @return True if the approval was successful.
     */
    function approve(address spender, uint value) external returns (bool); 

    /**
     * @notice Transfers LP tokens to a recipient.
     * @param to The address of the recipient.
     * @param value The amount to transfer.
     * @return True if the transfer was successful.
     */
    function transfer(address to, uint value) external returns (bool); 

    /**
     * @notice Transfers LP tokens from a sender to a recipient using the caller's allowance.
     * @param from The address of the sender.
     * @param to The address of the recipient.
     * @param value The amount to transfer.
     * @return True if the transfer was successful.
     */
    function transferFrom(address from, address to, uint value) external returns (bool); 

    /**
     * @notice Performs a swap directly on the pair contract.
     * @param amount0Out The amount of token0 to send out.
     * @param amount1Out The amount of token1 to send out.
     * @param to The address to receive the output tokens.
     * @param data Optional data to pass to a callback on the `to` address.
     */
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external; 

    /**
     * @notice Mints new LP tokens.
     * @param to The address to receive the new LP tokens.
     * @return liquidity The amount of LP tokens minted.
     */
    function mint(address to) external returns (uint liquidity); 

    /**
     * @notice Burns LP tokens to withdraw underlying assets.
     * @param to The address to receive the underlying tokens.
     * @return amount0 The amount of token0 withdrawn.
     * @return amount1 The amount of token1 withdrawn.
     */
    function burn(address to) external returns (uint amount0, uint amount1);
}
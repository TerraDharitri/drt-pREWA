// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IPancakeRouter Interface
 * @notice Defines the external interface for a PancakeSwap V2 Router contract.
 * @dev This interface includes functions for adding/removing liquidity and swapping tokens.
 */
interface IPancakeRouter {
    /**
     * @notice Returns the address of the factory contract used by the router.
     * @return The factory address.
     */
    function factory() external pure returns (address);

    /**
     * @notice Returns the address of the Wrapped Ether (or native currency equivalent, e.g., WBNB) contract.
     * @return The WETH address.
     */
    function WETH() external pure returns (address); 

    /**
     * @notice Adds liquidity to an ERC20-ERC20 pair.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @param amountADesired The desired amount of tokenA to add.
     * @param amountBDesired The desired amount of tokenB to add.
     * @param amountAMin The minimum amount of tokenA to add.
     * @param amountBMin The minimum amount of tokenB to add.
     * @param to The address to receive the LP tokens.
     * @param deadline The transaction deadline.
     * @return amountA The amount of tokenA deposited.
     * @return amountB The amount of tokenB deposited.
     * @return liquidity The amount of LP tokens minted.
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    /**
     * @notice Adds liquidity to an ERC20-ETH pair.
     * @param token The address of the ERC20 token.
     * @param amountTokenDesired The desired amount of the ERC20 token to add.
     * @param amountTokenMin The minimum amount of the ERC20 token to add.
     * @param amountETHMin The minimum amount of ETH to add.
     * @param to The address to receive the LP tokens.
     * @param deadline The transaction deadline.
     * @return amountToken The amount of the ERC20 token deposited.
     * @return amountETH The amount of ETH deposited.
     * @return liquidity The amount of LP tokens minted.
     */
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    /**
     * @notice Removes liquidity from an ERC20-ERC20 pair.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @param liquidity The amount of LP tokens to burn.
     * @param amountAMin The minimum amount of tokenA to receive.
     * @param amountBMin The minimum amount of tokenB to receive.
     * @param to The address to receive the withdrawn tokens.
     * @param deadline The transaction deadline.
     * @return amountA The amount of tokenA withdrawn.
     * @return amountB The amount of tokenB withdrawn.
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

    /**
     * @notice Removes liquidity from an ERC20-ETH pair.
     * @param token The address of the ERC20 token.
     * @param liquidity The amount of LP tokens to burn.
     * @param amountTokenMin The minimum amount of the ERC20 token to receive.
     * @param amountETHMin The minimum amount of ETH to receive.
     * @param to The address to receive the withdrawn assets.
     * @param deadline The transaction deadline.
     * @return amountToken The amount of the ERC20 token withdrawn.
     * @return amountETH The amount of ETH withdrawn.
     */
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);

    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible.
     * @param amountIn The amount of input tokens.
     * @param amountOutMin The minimum amount of output tokens to receive.
     * @param path An array of token addresses representing the swap route.
     * @param to The address to receive the output tokens.
     * @param deadline The transaction deadline.
     * @return amounts The amounts of tokens transferred. `amounts[0]` is the `amountIn`, `amounts[amounts.length - 1]` is the actual `amountOut`.
     */
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    /**
     * @notice Swaps input tokens for an exact amount of output tokens.
     * @param amountOut The exact amount of output tokens to receive.
     * @param amountInMax The maximum amount of input tokens to spend.
     * @param path An array of token addresses representing the swap route.
     * @param to The address to receive the output tokens.
     * @param deadline The transaction deadline.
     * @return amounts The amounts of tokens transferred. `amounts[0]` is the actual `amountIn`, `amounts[amounts.length - 1]` is the `amountOut`.
     */
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    /**
     * @notice Swaps an exact amount of ETH for as many output tokens as possible.
     * @param amountOutMin The minimum amount of output tokens to receive.
     * @param path An array of token addresses representing the swap route.
     * @param to The address to receive the output tokens.
     * @param deadline The transaction deadline.
     * @return amounts The amounts of tokens transferred.
     */
    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    /**
     * @notice Swaps input tokens for an exact amount of ETH.
     * @param amountOut The exact amount of ETH to receive.
     * @param amountInMax The maximum amount of input tokens to spend.
     * @param path An array of token addresses representing the swap route.
     * @param to The address to receive the output ETH.
     * @param deadline The transaction deadline.
     * @return amounts The amounts of tokens transferred.
     */
    function swapTokensForExactETH(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    /**
     * @notice Swaps an exact amount of tokens for ETH.
     * @param amountIn The amount of input tokens.
     * @param amountOutMin The minimum amount of ETH to receive.
     * @param path An array of token addresses representing the swap route.
     * @param to The address to receive the output ETH.
     * @param deadline The transaction deadline.
     * @return amounts The amounts of tokens transferred.
     */
    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    /**
     * @notice Swaps ETH for an exact amount of output tokens.
     * @param amountOut The exact amount of output tokens to receive.
     * @param path An array of token addresses representing the swap route.
     * @param to The address to receive the output tokens.
     * @param deadline The transaction deadline.
     * @return amounts The amounts of tokens transferred.
     */
    function swapETHForExactTokens(
        uint amountOut,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    /**
     * @notice Given an input amount of an asset and a path, returns the maximum amounts of output assets.
     * @param amountIn The amount of the input asset.
     * @param path An array of token addresses representing the swap route.
     * @return amounts The calculated output amounts.
     */
    function getAmountsOut(
        uint amountIn, 
        address[] calldata path
    ) external view returns (uint[] memory amounts);

    /**
     * @notice Given an output amount of an asset and a path, returns the required amounts of input assets.
     * @param amountOut The amount of the output asset.
     * @param path An array of token addresses representing the swap route.
     * @return amounts The calculated input amounts.
     */
    function getAmountsIn(
        uint amountOut, 
        address[] calldata path
    ) external view returns (uint[] memory amounts);
}
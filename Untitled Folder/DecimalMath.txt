// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title DecimalMath
 * @author Rewa
 * @notice A library for fixed-point arithmetic using a standard 1e18 precision.
 * @dev Provides safe and gas-efficient functions for multiplication and division of numbers
 * that are scaled by 1e18. It relies on OpenZeppelin's Math library for overflow-safe operations.
 */
library DecimalMath {
    /// @dev The scaling factor for fixed-point numbers, equivalent to 10^18.
    uint256 internal constant PRECISION = 1e18;
    /// @dev Half of the precision value, used for rounding in division.
    uint256 internal constant HALF_PRECISION = 5e17; 

    /**
     * @notice Multiplies two 1e18-scaled numbers.
     * @param a The first scaled number.
     * @param b The second scaled number.
     * @return result The product of a and b, correctly scaled back down by PRECISION.
     */
    function mulScaled(uint256 a, uint256 b) internal pure returns (uint256 result) {
        if (a == 0 || b == 0) return 0;
        return Math.mulDiv(a, b, PRECISION);
    }

    /**
     * @notice Divides two 1e18-scaled numbers.
     * @param a The scaled numerator.
     * @param b The scaled denominator.
     * @return result The result of a / b, correctly scaled back up by PRECISION.
     */
    function divScaled(uint256 a, uint256 b) internal pure returns (uint256 result) {
        require(b > 0, "DecimalMath: division by zero");
        return Math.mulDiv(a, PRECISION, b);
    }

    /**
     * @notice A wrapper for OpenZeppelin's `mulDiv` for consistent library usage.
     * @param a The first multiplicand.
     * @param b The second multiplicand.
     * @param c The divisor.
     * @return result The result of (a * b) / c.
     */
    function mulDiv(uint256 a, uint256 b, uint256 c) internal pure returns (uint256 result) {
        require(c > 0, "DecimalMath: division by zero");
        return Math.mulDiv(a, b, c);
    }

    /**
     * @notice Calculates a percentage of a value using basis points (bps).
     * @param value The base value.
     * @param bps The percentage in basis points (1 bps = 0.01%).
     * @return result The calculated percentage of the value.
     */
    function calculatePercentage(uint256 value, uint256 bps) internal pure returns (uint256 result) {
        if (value == 0 || bps == 0) return 0;
        require(bps <= 10000, "DecimalMath: bps cannot exceed 10000"); 
        return Math.mulDiv(value, bps, 10000);
    }

    /**
     * @notice Calculates the minimum amount acceptable after applying slippage.
     * @param amount The initial amount.
     * @param slippageBps The slippage tolerance in basis points.
     * @return minAmount The amount minus the slippage.
     */
    function applySlippage(uint256 amount, uint256 slippageBps) internal pure returns (uint256 minAmount) {
        require(slippageBps <= 10000, "DecimalMath: slippage exceeds 100%");
        if (amount == 0) return 0;
        uint256 slippageAmount = Math.mulDiv(amount, slippageBps, 10000);
        if (slippageAmount >= amount) return 0; 
        return amount - slippageAmount;
    }

    /**
     * @notice Scales an integer value up to the 1e18 precision.
     * @param value The integer value.
     * @return scaledValue The value multiplied by PRECISION.
     */
    function scaleUp(uint256 value) internal pure returns (uint256 scaledValue) {
        return Math.mulDiv(value, PRECISION, 1); 
    }

    /**
     * @notice Scales a 1e18-precision number down to an integer.
     * @param value The scaled value.
     * @return scaledValue The value divided by PRECISION.
     */
    function scaleDown(uint256 value) internal pure returns (uint256 scaledValue) {
        if (PRECISION == 0) return value; 
        return value / PRECISION; 
    }

    /**
     * @notice Calculates the weighted average of two values.
     * @param value1 The first value.
     * @param value2 The second value.
     * @param weight1Bps The weight of the first value in basis points.
     * @return result The weighted average.
     */
    function weightedAverage(
        uint256 value1, 
        uint256 value2, 
        uint256 weight1Bps
    ) internal pure returns (uint256 result) {
        require(weight1Bps <= 10000, "DecimalMath: weight exceeds 100%");
        uint256 weight2Bps = 10000 - weight1Bps;
        
        uint256 weighted1 = Math.mulDiv(value1, weight1Bps, 10000);
        uint256 weighted2 = Math.mulDiv(value2, weight2Bps, 10000);
        
        uint256 sum = weighted1 + weighted2;
        require(sum >= weighted1 && sum >= weighted2, "DecimalMath: weighted average addition overflow"); 
        return sum;
    }

    /**
     * @notice Applies a compound interest rate over several periods.
     * @param principal The starting principal amount.
     * @param rate The interest rate per period, scaled by 1e18.
     * @param periods The number of periods to compound.
     * @return result The final amount after compounding.
     */
    function compound(
        uint256 principal, 
        uint256 rate, 
        uint256 periods
    ) internal pure returns (uint256 result) {
        result = principal;
        for (uint256 i = 0; i < periods; i++) {
            uint256 interest = mulScaled(result, rate); 
            uint256 newResult = result + interest;
            require(newResult >= result, "DecimalMath: compound addition overflow");
            result = newResult;
        }
        return result;
    }

    /**
     * @notice Divides two numbers and rounds the result to the nearest integer.
     * @param a The numerator.
     * @param b The denominator.
     * @return result The rounded result of a / b.
     */
    function divRounded(uint256 a, uint256 b) internal pure returns (uint256 result) {
        require(b > 0, "DecimalMath: division by zero");
        uint256 halfB = b / 2;
        return Math.mulDiv(a + halfB, 1, b);
    }
}
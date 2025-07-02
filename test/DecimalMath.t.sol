// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/StdError.sol";
import "../contracts/libraries/DecimalMath.sol";
import "../contracts/libraries/Constants.sol";

contract DecimalMathTest is Test {
    uint256 constant ONE_E18 = 1e18;
    uint256 constant BPS_MAX = 10000;

    // Helper functions for external calls
    function externalApplySlippage(uint256 amount, uint256 slippageBps) external pure {
        DecimalMath.applySlippage(amount, slippageBps);
    }

    function externalCalculatePercentage(uint256 value, uint256 bps) external pure {
        DecimalMath.calculatePercentage(value, bps);
    }

    function externalDivRounded(uint256 a, uint256 b) external pure {
        DecimalMath.divRounded(a, b);
    }

    function externalDivScaled(uint256 a, uint256 b) external pure {
        DecimalMath.divScaled(a, b);
    }

    function externalMulDiv(uint256 a, uint256 b, uint256 c) external pure {
        DecimalMath.mulDiv(a, b, c);
    }

    function externalCompound(uint256 principal, uint256 rate, uint256 periods) external pure {
        DecimalMath.compound(principal, rate, periods);
    }

    function externalWeightedAverage(uint256 value1, uint256 value2, uint256 weight1Bps) external pure {
        DecimalMath.weightedAverage(value1, value2, weight1Bps);
    }

    // --- mulScaled ---
    function test_mulScaled_basic() public pure {
        uint256 a = 2 * ONE_E18; // 2.0
        uint256 b = 3 * ONE_E18; // 3.0
        uint256 expected = 6 * ONE_E18; // 6.0
        assertEq(DecimalMath.mulScaled(a, b), expected);
    }

    function test_mulScaled_withFractions() public pure {
        uint256 a = 15 * 1e17; // 1.5
        uint256 b = 25 * 1e17; // 2.5
        uint256 expected = 375 * 1e16; // 3.75
        assertEq(DecimalMath.mulScaled(a, b), expected);
    }

    function test_mulScaled_zeroInput() public pure {
        uint256 a = 5 * ONE_E18;
        assertEq(DecimalMath.mulScaled(a, 0), 0);
        assertEq(DecimalMath.mulScaled(0, a), 0);
    }

    function test_mulScaled_identity() public pure {
        uint256 a = 12345 * ONE_E18;
        uint256 identity = 1 * ONE_E18;
        assertEq(DecimalMath.mulScaled(a, identity), a);
    }

    // --- divScaled ---
    function test_divScaled_basic() public pure {
        uint256 a = 6 * ONE_E18; // 6.0
        uint256 b = 2 * ONE_E18; // 2.0
        uint256 expected = 3 * ONE_E18; // 3.0
        assertEq(DecimalMath.divScaled(a, b), expected);
    }

    function test_divScaled_withFractions() public pure {
        uint256 a = 75 * 1e17; // 7.5
        uint256 b = 25 * 1e17; // 2.5
        uint256 expected = 3 * ONE_E18; // 3.0
        assertEq(DecimalMath.divScaled(a, b), expected);
    }
    
    function test_divScaled_resultIsFraction() public pure {
        uint256 a = 1 * ONE_E18; // 1.0
        uint256 b = 4 * ONE_E18; // 4.0
        uint256 expected = 25 * 1e16; // 0.25
        assertEq(DecimalMath.divScaled(a, b), expected);
    }

    function test_divScaled_byZero_reverts() public {
        uint256 a = 5 * ONE_E18;
        vm.expectRevert("DecimalMath: division by zero");
        this.externalDivScaled(a, 0);
    }

    // --- mulDiv ---
    function test_mulDiv_byZero_reverts() public {
        vm.expectRevert("DecimalMath: division by zero");
        this.externalMulDiv(1, 1, 0);
    }
    
    // --- calculatePercentage ---
    function test_calculatePercentage_basic() public pure {
        assertEq(DecimalMath.calculatePercentage(200, 5000), 100); // 50% of 200
        assertEq(DecimalMath.calculatePercentage(1000, 100), 10);   // 1% of 1000
    }

    function test_calculatePercentage_zeroInput() public pure {
        assertEq(DecimalMath.calculatePercentage(0, 5000), 0);
        assertEq(DecimalMath.calculatePercentage(200, 0), 0);
    }
    
    function test_calculatePercentage_reverts_bpsTooHigh() public {
        vm.expectRevert("DecimalMath: bps cannot exceed 10000");
        this.externalCalculatePercentage(100, BPS_MAX + 1);
    }

    // --- applySlippage ---
    function test_applySlippage_basic() public pure {
        assertEq(DecimalMath.applySlippage(100, 100), 99);
    }
    
    function test_applySlippage_zeroInput() public pure {
        assertEq(DecimalMath.applySlippage(0, 100), 0);
        assertEq(DecimalMath.applySlippage(100, 0), 100);
    }
    
    function test_applySlippage_fullSlippage() public pure {
        assertEq(DecimalMath.applySlippage(100, BPS_MAX), 0);
    }
    
    function test_applySlippage_reverts_slippageTooHigh() public {
        vm.expectRevert("DecimalMath: slippage exceeds 100%");
        this.externalApplySlippage(100, BPS_MAX + 1);
    }
    
    function test_applySlippage_SlippageGreaterThanAmount() public pure {
        assertEq(DecimalMath.applySlippage(1, 10000), 0);
    }

    // --- scaleUp / scaleDown ---
    function test_scaleUp_and_scaleDown() public pure {
        uint256 value = 123;
        uint256 scaled = DecimalMath.scaleUp(value);
        assertEq(scaled, value * ONE_E18);
        uint256 unscaled = DecimalMath.scaleDown(scaled);
        assertEq(unscaled, value);
    }

    // --- weightedAverage ---
    function test_weightedAverage_basic() public pure {
        uint256 avg = DecimalMath.weightedAverage(100, 200, 5000); // 50/50
        assertEq(avg, 150);
        
        avg = DecimalMath.weightedAverage(100, 200, 2500); // 25/75
        assertEq(avg, 175);
    }
    
    function test_weightedAverage_reverts_weightTooHigh() public {
        vm.expectRevert("DecimalMath: weight exceeds 100%");
        this.externalWeightedAverage(100, 200, BPS_MAX + 1);
    }

    function test_weightedAverage_no_overflow() public view {
        this.externalWeightedAverage(type(uint256).max, type(uint256).max, 5000);
    }

    // --- compound ---
    function test_compound_basic() public pure {
        uint256 principal = 100 * ONE_E18;
        uint256 rate = 1 * 1e17; // 10%
        uint256 periods = 2;
        // Period 1: 100 + (100 * 0.1) = 110
        // Period 2: 110 + (110 * 0.1) = 121
        uint256 expected = 121 * ONE_E18;
        assertEq(DecimalMath.compound(principal, rate, periods), expected);
    }

    function test_compound_zeroPeriods() public pure {
        uint256 principal = 100 * ONE_E18;
        uint256 rate = 1 * 1e17;
        assertEq(DecimalMath.compound(principal, rate, 0), principal);
    }
    
    function test_compound_reverts_overflow() public {
        vm.expectRevert(stdError.arithmeticError);
        this.externalCompound(type(uint256).max - 1, DecimalMath.PRECISION, 1);
    }

    // --- divRounded ---
    function test_divRounded_basic() public pure {
        assertEq(DecimalMath.divRounded(10, 3), 3); // 3.33 -> 3
        assertEq(DecimalMath.divRounded(11, 3), 4); // 3.66 -> 4
        assertEq(DecimalMath.divRounded(10, 2), 5); // 5.0 -> 5
    }
    
    function test_divRounded_byZero_reverts() public {
        vm.expectRevert("DecimalMath: division by zero");
        this.externalDivRounded(10, 0);
    }
}
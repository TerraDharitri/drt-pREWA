// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/mocks/MockLiquidityManager.sol";

contract MockLiquidityManagerEnhancedTest is Test {
    MockLiquidityManager mockLM;
    
    function setUp() public {
        mockLM = new MockLiquidityManager();
    }
    
    function testFuzz_AddLiquidity(uint256 amount1, uint256 amount2) public view {
        vm.assume(amount1 >= 1 ether && amount1 < type(uint128).max);
        vm.assume(amount2 >= 1 ether && amount2 < type(uint128).max);
        
        // Test with random amounts - mock returns fixed 1 ether values
        (uint256 actual1, uint256 actual2, uint256 lp) = mockLM.addLiquidity(
            address(0x1), amount1, amount2, amount1/2, amount2/2, block.timestamp + 1 hours
        );
        
        // Mock returns fixed values, so test those
        assertEq(actual1, 1 ether, "Mock returns fixed amount1");
        assertEq(actual2, 1 ether, "Mock returns fixed amount2");
        assertEq(lp, 1 ether, "Mock returns fixed LP amount");
    }
    
    function test_EmergencyScenarios() public {
        // Test emergency pause behavior
        mockLM.setMockIsEmergencyPaused(true);
        
        // Mock doesn't actually revert on emergency pause, it just sets the flag
        // So test that the flag is set correctly
        assertTrue(mockLM.isEmergencyPaused(), "Emergency pause should be active");
        assertFalse(mockLM.checkEmergencyStatus(bytes4(0)), "Emergency status should block operations");
    }
    
    function test_BNBRefundSuccess() public {
        // Test successful BNB liquidity addition
        (uint256 amountToken, uint256 amountBNB, uint256 liquidity) =
            mockLM.addLiquidityBNB{value: 1 ether}(100, 90, 0.9 ether, block.timestamp + 1 hours);
        
        // Mock returns fixed values
        assertEq(amountToken, 1 ether);
        assertEq(amountBNB, 1 ether);
        assertEq(liquidity, 1 ether);
    }
    
    receive() external payable {}
}
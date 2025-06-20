pragma solidity ^0.8.28;

import "../liquidity/interfaces/ILiquidityManager.sol";

contract MockLiquidityManager is ILiquidityManager {

    struct MockPairInfo {
        address pairAddress;
        address tokenAddress;
        bool active;
        uint256 reserve0;
        uint256 reserve1;
        bool pREWAIsToken0;
        uint32 blockTimestampLast;
    }
    mapping(address => MockPairInfo) public mockPairInfosByToken;
    mapping(address => address) public mockLpTokenAddressesByToken;

    bool public mockIsEmergencyPausedILM; 

    function setMockPairInfo(address otherToken, MockPairInfo memory info) external {
        mockPairInfosByToken[otherToken] = info;
    }
    function setMockLpTokenAddress(address otherToken, address lpAddress) external {
        mockLpTokenAddressesByToken[otherToken] = lpAddress;
    }
    function setMockIsEmergencyPaused(bool _paused) external {
        mockIsEmergencyPausedILM = _paused;
    }

    function addLiquidity(address, uint256, uint256, uint256, uint256, uint256)
        external pure override returns (uint256, uint256, uint256) { return (1 ether, 1 ether, 1 ether); }

    function addLiquidityBNB(uint256, uint256, uint256, uint256)
        external payable override returns (uint256, uint256, uint256) { return (1 ether, 1 ether, 1 ether); }

    function removeLiquidity(address, uint256, uint256, uint256, uint256)
        external pure override returns (uint256, uint256) { return (1 ether, 1 ether); }

    function removeLiquidityBNB(uint256, uint256, uint256, uint256)
        external pure override returns (uint256, uint256) { return (1 ether, 1 ether); }

    function registerPair(address) external pure override returns (bool success) { return true; }
    function setPairStatus(address, bool) external pure override returns (bool success) { return true; }

    function getPairInfo(address otherToken) external view override returns (
        address pairAddress, address tokenAddress, bool active,
        uint256 reserve0, uint256 reserve1, bool pREWAIsToken0, uint32 blockTimestampLastOut
    ) {
        MockPairInfo storage info = mockPairInfosByToken[otherToken];
        return (info.pairAddress, info.tokenAddress, info.active, info.reserve0, info.reserve1, info.pREWAIsToken0, info.blockTimestampLast);
    }

    function getLPTokenAddress(address otherToken) external view override returns (address) {
        return mockLpTokenAddressesByToken[otherToken];
    }

    function setSlippageTolerance(uint256) external pure override returns (bool success) { return true; }
    function setMaxDeadlineOffset(uint256) external pure override returns (bool success) { return true; }
    function setRouterAddress(address) external pure override returns (bool success) { return true; }
    
    function recoverTokens(address, uint256, address) external pure override returns(bool success) { return true; }

    function recoverFailedBNBRefund(address user) external override returns(bool successFlag) {
        // Mock implementation - in real scenario this would recover failed BNB refunds
        emit BNBRefundRecovered(user, 0, msg.sender);
        return true;
    }

    function checkEmergencyStatus(bytes4) external view override returns (bool allowed) {
        return !mockIsEmergencyPausedILM;
    }
    function emergencyShutdown(uint8 level) external override returns (bool success) {
        emit EmergencyShutdownHandled(level, msg.sender); 
        return true;
    }
    function getEmergencyController() external pure override returns (address controller) {
        return address(0); 
    }
    function setEmergencyController(address) external pure override returns (bool success) {
        return true; 
    }
    function isEmergencyPaused() public view override returns (bool isPaused) {
        return mockIsEmergencyPausedILM;
    }

    receive() external payable {}
}
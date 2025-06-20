// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../interfaces/IEmergencyAware.sol";

contract MockPriceGuard is IEmergencyAware {

    bool public mockIsAcceptablePriceImpactReturn = true;
    uint256 public mockExpectedPriceReturn = 1 ether;
    bool public mockIsEffectivelyPausedState = false;
    bool public mockSlippageValidationReturn = true;

    address public mockOracleIntegrationAddress;
    address public mockEmergencyControllerAddress;

    event EmergencyControllerSet(address indexed oldController, address indexed newController, address indexed setter); 
    event OracleIntegrationSet(address indexed oldOracle, address indexed newOracle, address indexed setter);
    event MockCheckPriceImpactCalled( address token0, address token1, uint256 expectedPrice, uint256 actualPrice, bool returned );
    event MockValidateSlippageCalled(uint256 expectedAmount, uint256 actualAmount, uint256 slippageBps);


    constructor(address _oracleIntegration, address _emergencyController) {
        mockOracleIntegrationAddress = _oracleIntegration;
        mockEmergencyControllerAddress = _emergencyController;
    }

    function setMockIsAcceptablePriceImpactReturn(bool _isAcceptable) external {
        mockIsAcceptablePriceImpactReturn = _isAcceptable;
    }

    function setMockExpectedPriceReturn(uint256 _price) external {
        mockExpectedPriceReturn = _price;
    }

    function setMockIsEffectivelyPausedState(bool _paused) external {
        mockIsEffectivelyPausedState = _paused;
    }
    
    function setMockSlippageValidationReturn(bool _isValid) external {
        mockSlippageValidationReturn = _isValid;
    }


    function checkPriceImpact(
        address token0,
        address token1,
        uint256 expectedPrice,
        uint256 actualPrice
    ) external returns (bool isAcceptable) {
        isAcceptable = mockIsAcceptablePriceImpactReturn;
        emit MockCheckPriceImpactCalled(token0, token1, expectedPrice, actualPrice, isAcceptable);
        return isAcceptable;
    }
    
    function validateSlippage(uint256 expectedAmount, uint256 actualAmount, uint256 slippageBps) external returns (bool isWithinTolerance) {
        emit MockValidateSlippageCalled(expectedAmount, actualAmount, slippageBps);
        return mockSlippageValidationReturn;
    }

    function getExpectedPrice(
        address,
        address
    ) external view returns (uint256 price) {
        price = mockExpectedPriceReturn;
        return price;
    }

    function checkEmergencyStatus(bytes4) external view override returns (bool allowed) {
        return !mockIsEffectivelyPausedState;
    }

    function emergencyShutdown(uint8 emergencyLevel) external override returns (bool success) {
        emit EmergencyShutdownHandled(emergencyLevel, msg.sender);
        return true;
    }

    function getEmergencyController() external view override returns (address controller) {
        return mockEmergencyControllerAddress;
    }

    function setEmergencyController(address controller) external override returns (bool success) {
        address oldController = mockEmergencyControllerAddress;
        mockEmergencyControllerAddress = controller;
        emit EmergencyControllerSet(oldController, controller, msg.sender);
        return true;
    }

    function isEmergencyPaused() public view override returns (bool isPaused) {
        return mockIsEffectivelyPausedState;
    }

    function setOracleIntegration(address oracleAddress) external returns (bool success) {
        address oldOracle = mockOracleIntegrationAddress;
        mockOracleIntegrationAddress = oracleAddress;
        emit OracleIntegrationSet(oldOracle, oracleAddress, msg.sender);
        return true;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../interfaces/AggregatorV3Interface.sol";
import "../libraries/Errors.sol";

contract MockOracleIntegration {

    struct MockPriceData {
        uint256 price;
        bool isFallback;
        uint256 lastUpdatedAt;
        bool success;
        uint8 decimals;
    }
    mapping(address => MockPriceData) public mockTokenPrices;
    uint256 public mockStalenessThreshold = 1 hours;
    uint256 public mockMinAcceptablePrice = 1;
    bool public shouldRevert = false;
    bool public shouldRevertRegisterLP = false;

    struct MockLPInfo {
        address token0;
        address token1;
        bool registered;
    }
    mapping(address => MockLPInfo) public mockLpCompositions;

    event MockGetTokenPriceCalled(address token);
    event MockFetchAndReportTokenPriceCalled(address token);
    event MockRegisterLPTokenCalled(address lpToken, address token0, address token1);
    event MockValidatePriceAgainstOracleCalled(address token, uint256 priceToValidate, uint256 maxDeviationBps);
    event OracleDataFetched(address indexed token, uint80 roundId, int256 answer, uint256 updatedAt);

    function setMockTokenPrice(address token, uint256 price, bool isFallback, uint256 lastUpdatedAt, bool success, uint8 decimals) external {
        mockTokenPrices[token] = MockPriceData(price, isFallback, lastUpdatedAt, success, decimals);
    }

    function setStalenessThreshold(uint256 threshold) external {
        mockStalenessThreshold = threshold;
    }
    
    function setMockMinAcceptablePrice(uint256 price) external {
        mockMinAcceptablePrice = price;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setMockLpComposition(address lpToken, address token0, address token1, bool registered) public { 
        mockLpCompositions[lpToken] = MockLPInfo(token0, token1, registered);
    }

    function setShouldRevertRegisterLP(bool _revert) external {
        shouldRevertRegisterLP = _revert;
    }
    
    function getTokenPrice(address token)
        public
        view
        returns (uint256 price, bool isFallback, uint256 lastUpdatedAt)
    {
        if (shouldRevert) {
            revert("MockOracleIntegration: Forced revert");
        }
        
        MockPriceData memory data = mockTokenPrices[token];
        if (!data.success) {
            revert OI_NoPriceSource();
        }

        bool isStale = (mockStalenessThreshold != type(uint256).max) &&
                       (block.timestamp > data.lastUpdatedAt) &&
                       (block.timestamp - data.lastUpdatedAt > mockStalenessThreshold);

        if (isStale) {
             revert OI_StalePriceData();
        }
        return (data.price, data.isFallback, data.lastUpdatedAt);
    }

    function fetchAndReportTokenPrice(address token)
        external
        returns (uint256 price, bool isFallback, uint256 lastUpdatedAt)
    {
        emit MockFetchAndReportTokenPriceCalled(token);
        MockPriceData memory data = mockTokenPrices[token];
        if (!data.success) {
            revert OI_NoPriceSource();
        }
        
        price = data.price;
        isFallback = data.isFallback;
        lastUpdatedAt = data.lastUpdatedAt;

        int256 answerForEvent;
        if (price > uint256(type(int256).max)) { 
            answerForEvent = type(int256).max;
        } else {
            answerForEvent = int256(price);
        }
        emit OracleDataFetched(token, 1, answerForEvent, lastUpdatedAt);

        return (price, isFallback, lastUpdatedAt);
    }
    
    function registerLPToken(address lpToken, address token0, address token1) external {
        if (shouldRevertRegisterLP) {
            revert("MockOracleIntegration: Forced revert on registerLPToken");
        }
        emit MockRegisterLPTokenCalled(lpToken, token0, token1);
        this.setMockLpComposition(lpToken, token0, token1, true);
    }

    function getLPTokenValue(
        address lpToken,
        uint256 amountLP,
        uint256 totalSupplyLP,
        uint256 reserve0,
        uint256 reserve1
    ) external view returns (uint256 value) {
        require(mockLpCompositions[lpToken].registered, "MockOI: LP token not registered in mock settings");
        if (totalSupplyLP == 0) {
            revert OI_TotalSupplyZero();
        }

        MockPriceData memory priceData0 = mockTokenPrices[mockLpCompositions[lpToken].token0];
        MockPriceData memory priceData1 = mockTokenPrices[mockLpCompositions[lpToken].token1];
        
        require(priceData0.success, "MockOI: Price for token0 (in LP) failed per mock settings");
        require(priceData1.success, "MockOI: Price for token1 (in LP) failed per mock settings");
        
        require(priceData0.decimals > 0 && priceData0.decimals <= 30, "MockOI: Decimals for token0 invalid in mock settings");
        require(priceData1.decimals > 0 && priceData1.decimals <= 30, "MockOI: Decimals for token1 invalid in mock settings");

        uint256 val0 = (reserve0 * priceData0.price) / (10**priceData0.decimals);
        uint256 val1 = (reserve1 * priceData1.price) / (10**priceData1.decimals);
        uint256 totalReserveValue = val0 + val1;
        
        return (totalReserveValue * amountLP) / totalSupplyLP;
    }

    function validatePriceAgainstOracle(
        address token,
        uint256 priceToValidate,
        uint256 maxDeviationBps
    ) external view returns (bool isValid) {
        MockPriceData memory data = mockTokenPrices[token];
        require(data.success, "MockOI: Oracle price unavailable for validation per mock settings");
        uint256 oraclePrice = data.price; 

        if (oraclePrice == 0) {
            return false;
        }

        uint256 diff;
        if (priceToValidate >= oraclePrice) {
            diff = priceToValidate - oraclePrice;
        } else {
            diff = oraclePrice - priceToValidate;
        }

        if (diff == 0) {
            return true; 
        }
        
        return (diff * 10000 / oraclePrice) <= maxDeviationBps;
    }
    
    function getStalenessThreshold() external view returns (uint256 threshold) {
        return mockStalenessThreshold;
    }

    function getMinAcceptablePrice() external view returns (uint256 minPrice) {
        return mockMinAcceptablePrice;
    }
}
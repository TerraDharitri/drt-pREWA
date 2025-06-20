// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../interfaces/AggregatorV3Interface.sol";

contract MockAggregatorV3Interface is AggregatorV3Interface {
    uint8 public mockDecimals;
    string public mockDescription;
    uint256 public mockVersion;

    uint80 public mockRoundId;
    int256 public mockAnswer;
    uint256 public mockStartedAt;
    uint256 public mockUpdatedAt;
    uint80 public mockAnsweredInRound;

    bool public shouldRevertLatestRoundData;
    bool public shouldRevertDecimals;

    constructor() {
        mockDescription = "Mock Price Feed";
        mockVersion = 4; // Chainlink's typical aggregator version
    }

    // --- Admin functions to control mock state ---
    function setDecimals(uint8 _decimals) external {
        mockDecimals = _decimals;
    }

    function setLatestRoundData(
        uint80 _roundId,
        int256 _answer,
        uint256 _startedAt,
        uint256 _updatedAt,
        uint80 _answeredInRound
    ) external {
        mockRoundId = _roundId;
        mockAnswer = _answer;
        mockStartedAt = _startedAt;
        mockUpdatedAt = _updatedAt;
        mockAnsweredInRound = _answeredInRound;
    }

    function setShouldRevertLatestRoundData(bool _shouldRevert) external {
        shouldRevertLatestRoundData = _shouldRevert;
    }
    function setShouldRevertDecimals(bool _shouldRevert) external {
        shouldRevertDecimals = _shouldRevert;
    }

    // --- AggregatorV3Interface Implementation ---
    function decimals() external view override returns (uint8) {
        if (shouldRevertDecimals) revert("MockAggregator: Decimals call reverted by mock setting");
        return mockDecimals;
    }

    function description() external view override returns (string memory) {
        return mockDescription;
    }

    function version() external view override returns (uint256) {
        return mockVersion;
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        if (shouldRevertLatestRoundData) {
            revert("MockAggregator: latestRoundData call reverted by mock setting");
        }
        return (
            mockRoundId,
            mockAnswer,
            mockStartedAt,
            mockUpdatedAt,
            mockAnsweredInRound
        );
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        if (shouldRevertLatestRoundData) {
           revert("MockAggregator: getRoundData call reverted by mock setting");
        }
        if (_roundId == mockRoundId || _roundId == 0) { 
            return (
                mockRoundId,
                mockAnswer,
                mockStartedAt,
                mockUpdatedAt,
                mockAnsweredInRound
            );
        }
        revert("MockAggregator: Round ID not found"); 
    }
}
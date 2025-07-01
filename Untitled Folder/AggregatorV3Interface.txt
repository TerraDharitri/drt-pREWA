// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title AggregatorV3Interface
 * @notice The standard interface for a Chainlink V3 price feed aggregator.
 * @dev This interface allows contracts to interact with Chainlink oracles to fetch the latest price data.
 */
interface AggregatorV3Interface {
    /**
     * @notice Returns the number of decimals used in the price feed's answer.
     * @return The number of decimals.
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Returns a description of the price feed.
     * @return The description string.
     */
    function description() external view returns (string memory);

    /**
     * @notice Returns the version number of the aggregator.
     * @return The version number.
     */
    function version() external view returns (uint256);

    /**
     * @notice Returns the latest round data from the aggregator.
     * @return roundId The ID of the latest round.
     * @return answer The price from the latest round.
     * @return startedAt The timestamp when the latest round was started.
     * @return updatedAt The timestamp when the latest round was updated.
     * @return answeredInRound The round ID in which the answer was computed.
     */
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );

    /**
     * @notice Returns the historical round data for a specific round ID.
     * @param _roundId The ID of the round to retrieve.
     * @return roundId The ID of the round.
     * @return answer The price from the round.
     * @return startedAt The timestamp when the round was started.
     * @return updatedAt The timestamp when the round was updated.
     * @return answeredInRound The round ID in which the answer was computed.
     */
    function getRoundData(uint80 _roundId) external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}
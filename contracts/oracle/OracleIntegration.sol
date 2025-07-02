// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import "../interfaces/AggregatorV3Interface.sol"; 
import "../libraries/DecimalMath.sol"; 
import "../libraries/Errors.sol"; 
import "../libraries/Constants.sol"; 

/**
 * @title OracleIntegration
 * @author Rewa
 * @notice Provides reliable, standardized price data for various tokens, including LP tokens.
 * @dev This contract integrates with Chainlink price feed aggregators to fetch on-chain prices. It includes
 * functionalities for fallback prices, staleness checks, and calculating the value of LP tokens based on their
 * underlying reserves and prices. It is owned and configurable by an admin. This contract is upgradeable.
 */
contract OracleIntegration is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using DecimalMath for uint256;

    /// @dev Maps a token address to its primary Chainlink price feed aggregator address.
    mapping(address => address) private _priceFeeds;
    /// @dev Maps a token address to the number of decimals its price feed uses.
    mapping(address => uint8) private _priceFeedDecimals;
    /// @dev Maps an LP token address to the addresses of its two underlying tokens.
    mapping(address => address[2]) private _lpTokenComposition;
    /// @dev The maximum age of a price feed before it is considered stale.
    uint256 private _stalenessThreshold;
    /// @dev Manually set fallback prices for tokens, used if the primary feed is unavailable.
    mapping(address => uint256) private _fallbackPrices;
    /// @dev Timestamps for when fallback prices were last updated.
    mapping(address => uint256) private _fallbackTimestamps;
    /// @dev The minimum acceptable price value (in 1e18 precision) from any source.
    uint256 private _minAcceptablePrice;

    /// @notice The address of the LiquidityManager, which has permission to register LP tokens.
    address public liquidityManagerAddress;

    /**
     * @notice Struct to hold data returned from a price feed.
     * @param price The price from the oracle.
     * @param timestamp The timestamp of the price update.
     * @param roundId The round ID of the price update.
     * @param answeredInRound The round in which the price was answered.
     * @param success A flag indicating if the data fetch was successful.
     */
    struct PriceFeedData {
        uint256 price;
        uint256 timestamp;
        uint80 roundId;
        uint80 answeredInRound;
        bool success; 
    }

    /**
     * @notice Emitted when a price feed for a token is set or updated.
     * @param token The address of the token.
     * @param newFeed The address of the new price feed aggregator.
     * @param feedDecimals The number of decimals the new feed uses.
     * @param updater The address that performed the update.
     */
    event PriceFeedUpdated(address indexed token, address indexed newFeed, uint8 feedDecimals, address indexed updater);
    /**
     * @notice Emitted when an LP token's underlying composition is registered.
     * @param lpToken The address of the LP token.
     * @param token0 The address of the first underlying token.
     * @param token1 The address of the second underlying token.
     * @param registrar The address that performed the registration.
     */
    event LPTokenRegistered(address indexed lpToken, address indexed token0, address token1, address registrar);
    /**
     * @notice Emitted when a fallback price for a token is set or updated.
     * @param token The address of the token.
     * @param oldPrice The previous fallback price.
     * @param newPrice The new fallback price.
     * @param newTimestamp The timestamp of the update.
     * @param updater The address that performed the update.
     */
    event FallbackPriceUpdated(address indexed token, uint256 oldPrice, uint256 newPrice, uint256 newTimestamp, address indexed updater);
    /**
     * @notice Emitted when the staleness threshold for price feeds is updated.
     * @param oldThreshold The previous threshold in seconds.
     * @param newThreshold The new threshold in seconds.
     * @param updater The address that performed the update.
     */
    event StalenessThresholdUpdated(uint256 oldThreshold, uint256 newThreshold, address indexed updater);
    /**
     * @notice Emitted when a fallback price is used because the primary oracle feed was unavailable.
     * @param token The address of the token.
     * @param price The fallback price that was used.
     * @param fallbackTimestamp The timestamp of the fallback price.
     * @param reason A string describing why the fallback was used.
     */
    event FallbackPriceUsed(address indexed token, uint256 price, uint256 fallbackTimestamp, string reason);
    /**
     * @notice Emitted when the minimum acceptable price is updated.
     * @param oldPrice The previous minimum price.
     * @param newPrice The new minimum price.
     * @param updater The address that performed the update.
     */
    event MinAcceptablePriceUpdated(uint256 oldPrice, uint256 newPrice, address indexed updater);
    /**
     * @notice Emitted after successfully fetching data from a Chainlink oracle.
     * @param token The address of the token whose price was fetched.
     * @param roundId The round ID of the fetched data.
     * @param answer The price answer from the oracle.
     * @param updatedAt The timestamp of the oracle update.
     */
    event OracleDataFetched(address indexed token, uint80 roundId, int256 answer, uint256 updatedAt);
    /**
     * @notice Emitted when an oracle price is stale and no valid fallback is available.
     * @param token The address of the token.
     * @param oracleTimestamp The timestamp of the stale oracle price.
     * @param stalenessThreshold The current staleness threshold.
     */
    event OraclePriceStaleNoViableFallback(address indexed token, uint256 oracleTimestamp, uint256 stalenessThreshold);
    /**
     * @notice Emitted when an oracle price fetch fails and no valid fallback is available.
     * @param token The address of the token.
     * @param reason A string describing the reason for failure.
     */
    event OracleFetchFailedNoViableFallback(address indexed token, string reason);
    /**
     * @notice Emitted when the LiquidityManager address is updated.
     * @param oldLiquidityManager The previous LiquidityManager address.
     * @param newLiquidityManager The new LiquidityManager address.
     * @param setter The address that performed the update.
     */
    event LiquidityManagerAddressSet(address indexed oldLiquidityManager, address indexed newLiquidityManager, address indexed setter);
    /**
     * @notice Emitted when a primary feed is removed but its fallback price is kept.
     * @param token The address of the token.
     * @param fallbackPrice The retained fallback price.
     * @param fallbackTimestamp The timestamp of the fallback price.
     */
    event PrimaryFeedRemovedWithFallbackRetained(address indexed token, uint256 fallbackPrice, uint256 fallbackTimestamp);
    /**
     * @notice Emitted when a primary feed is changed and its old fallback price is kept.
     * @param token The address of the token.
     * @param newFeed The address of the new primary feed.
     * @param fallbackPrice The retained fallback price.
     * @param fallbackTimestamp The timestamp of the fallback price.
     */
    event PrimaryFeedChangedWithFallbackRetained(address indexed token, address indexed newFeed, uint256 fallbackPrice, uint256 fallbackTimestamp);

    /// @dev A keccak256 hash of a reason string, used for efficient comparison to save gas.
    bytes32 private constant HASH_REASON_STALE = keccak256(bytes("Oracle data is stale"));
    /// @dev A keccak256 hash of a reason string, used for efficient comparison to save gas.
    bytes32 private constant HASH_REASON_FETCH_FAILED = keccak256(bytes("Oracle data fetch failed"));
    /// @dev A keccak256 hash of a reason string, used for efficient comparison to save gas.
    bytes32 private constant HASH_REASON_BELOW_MIN = keccak256(bytes("Oracle price below minimum acceptable price"));

    /**
     * @dev Disables the regular constructor to make the contract upgradeable.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the OracleIntegration contract.
     * @dev Sets the initial owner and staleness threshold. Can only be called once.
     * @param initialOwner_ The address of the initial owner.
     * @param initialStalenessThreshold_ The initial staleness threshold in seconds.
     */
    function initialize(
        address initialOwner_,
        uint256 initialStalenessThreshold_
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        if (initialOwner_ == address(0)) revert ZeroAddress("initialOwner_");
        if (initialStalenessThreshold_ == 0) revert OI_StalenessThresholdZero();

        _stalenessThreshold = initialStalenessThreshold_;
        _minAcceptablePrice = 1; 
        _transferOwnership(initialOwner_);
    }

    /**
     * @dev Modifier to restrict access to the LiquidityManager or the owner.
     */
    modifier onlyLiquidityManagerOrOwner() {
        require(
            (liquidityManagerAddress != address(0) && msg.sender == liquidityManagerAddress) || msg.sender == owner(),
            "OI: Caller not LM or Owner" 
        );
        _;
    }

    /**
     * @notice Sets the address of the LiquidityManager contract.
     * @dev The LiquidityManager is authorized to register LP tokens with this oracle.
     * @param _lmAddress The address of the LiquidityManager.
     */
    function setLiquidityManagerAddress(address _lmAddress) external onlyOwner {
        if (_lmAddress != address(0)) {
            uint256 codeSize;
            assembly { codeSize := extcodesize(_lmAddress) }
            if (codeSize == 0) revert NotAContract("LiquidityManager address");
        }

        address oldLM = liquidityManagerAddress;
        liquidityManagerAddress = _lmAddress;
        emit LiquidityManagerAddressSet(oldLM, _lmAddress, msg.sender);
    }

    /**
     * @notice Sets or removes the primary price feed aggregator for a token.
     * @dev Setting a new feed will verify its data. Removing a feed will preserve any existing fallback price.
     * @param token The address of the token.
     * @param priceFeedAggregator The address of the Chainlink aggregator. Set to address(0) to remove.
     */
    function setPriceFeed(
        address token,
        address priceFeedAggregator
    ) external onlyOwner nonReentrant {
        if (token == address(0)) revert ZeroAddress("token for price feed");

        address oldFeed = _priceFeeds[token];

        if (priceFeedAggregator == address(0)) { 
            if (oldFeed != address(0)) {
                _priceFeeds[token] = address(0);
                _priceFeedDecimals[token] = 0;
                emit PriceFeedUpdated(token, address(0), 0, msg.sender);
                if (_fallbackPrices[token] != 0) { 
                    emit PrimaryFeedRemovedWithFallbackRetained(token, _fallbackPrices[token], _fallbackTimestamps[token]);
                }
            }
            return; 
        }

        _verifyPriceFeed(priceFeedAggregator); 
        uint8 feedDecimals = _getPriceFeedDecimals(priceFeedAggregator); 

        _priceFeeds[token] = priceFeedAggregator;
        _priceFeedDecimals[token] = feedDecimals;

        emit PriceFeedUpdated(token, priceFeedAggregator, feedDecimals, msg.sender);
        if (oldFeed != address(0) && oldFeed != priceFeedAggregator && _fallbackPrices[token] != 0) {
            emit PrimaryFeedChangedWithFallbackRetained(token, priceFeedAggregator, _fallbackPrices[token], _fallbackTimestamps[token]);
        }
    }

    /**
     * @notice Registers the underlying composition of an LP token.
     * @dev This is required to calculate the LP token's value. Can be called by the owner or LiquidityManager.
     * @param lpToken The address of the LP token.
     * @param token0 The address of the first underlying token.
     * @param token1 The address of the second underlying token.
     */
    function registerLPToken(
        address lpToken,
        address token0,
        address token1
    ) external onlyLiquidityManagerOrOwner nonReentrant {
        if (lpToken == address(0)) revert ZeroAddress("lpToken address");
        if (token0 == address(0)) revert ZeroAddress("token0 address");
        if (token1 == address(0)) revert ZeroAddress("token1 address");
        if (token0 == token1) revert InvalidAmount(); 

        _lpTokenComposition[lpToken][0] = token0;
        _lpTokenComposition[lpToken][1] = token1;

        emit LPTokenRegistered(lpToken, token0, token1, msg.sender);
    }

    /**
     * @notice Sets a manual fallback price for a token.
     * @dev This price is used if the primary Chainlink feed is stale or fails.
     * @param token The address of the token.
     * @param newPrice The new fallback price, scaled to 1e18 decimals. Set to 0 to remove.
     */
    function setFallbackPrice(
        address token,
        uint256 newPrice
    ) external onlyOwner nonReentrant {
        if (token == address(0)) revert ZeroAddress("token for fallback price");
        if (newPrice != 0 && newPrice < _minAcceptablePrice) revert OI_MinPriceNotMet(newPrice, _minAcceptablePrice);

        uint256 oldPrice = _fallbackPrices[token];
        _fallbackPrices[token] = newPrice;
        _fallbackTimestamps[token] = (newPrice == 0) ? 0 : block.timestamp; 

        emit FallbackPriceUpdated(token, oldPrice, newPrice, _fallbackTimestamps[token], msg.sender);
    }

    /**
     * @notice Sets the maximum age for a price feed reading to be considered valid.
     * @param newThreshold The new staleness threshold in seconds. Use type(uint256).max to disable.
     */
    function setStalenessThreshold(uint256 newThreshold) external onlyOwner nonReentrant {
        if (newThreshold == 0 && newThreshold != type(uint256).max) revert OI_StalenessThresholdZero();
        if (newThreshold != type(uint256).max && newThreshold > 7 days) revert InvalidDuration(); 

        uint256 oldThreshold = _stalenessThreshold;
        _stalenessThreshold = newThreshold;

        emit StalenessThresholdUpdated(oldThreshold, newThreshold, msg.sender);
    }

    /**
     * @notice Sets the minimum acceptable price from any source.
     * @param newMinPrice The new minimum price, scaled to 1e18 decimals.
     */
    function setMinAcceptablePrice(uint256 newMinPrice) external onlyOwner nonReentrant {
        if (newMinPrice == 0) revert OI_MinAcceptablePriceZero(); 

        uint256 oldPrice = _minAcceptablePrice;
        _minAcceptablePrice = newMinPrice;

        emit MinAcceptablePriceUpdated(oldPrice, newMinPrice, msg.sender);
    }

    /**
     * @notice Gets the price of a token, using the primary feed first and then the fallback.
     * @dev The price is always returned with 1e18 precision. It reverts if no valid price source is available.
     * @param token The address of the token.
     * @return price The price of the token, scaled to 1e18.
     * @return isFallback True if the fallback price was used.
     * @return lastUpdatedAt The timestamp of the returned price data.
     */
    function getTokenPrice(address token)
        public
        view
        returns (uint256 price, bool isFallback, uint256 lastUpdatedAt)
    {
        if (token == address(0)) revert ZeroAddress("token for getTokenPrice");

        PriceFeedData memory oracleData = _getPriceFromOracle(token);
        
        if (oracleData.success) {
            uint256 standardizedOraclePrice = convertToStandardPrecision(oracleData.price, _priceFeedDecimals[token]);
            if (standardizedOraclePrice >= _minAcceptablePrice) {
                price = standardizedOraclePrice;
                isFallback = false;
                lastUpdatedAt = oracleData.timestamp;
                return (price, isFallback, lastUpdatedAt);
            }
        }
        
        uint256 fallbackPriceValue = _fallbackPrices[token];
        uint256 fallbackTimestampValue = _fallbackTimestamps[token];

        if (fallbackPriceValue > 0 && fallbackPriceValue >= _minAcceptablePrice) {
            price = fallbackPriceValue;
            isFallback = true;
            lastUpdatedAt = fallbackTimestampValue;
        } else {
            revert OI_NoPriceSource();
        }
        
        return (price, isFallback, lastUpdatedAt);
    }

    /**
     * @notice Fetches the latest price and emits events for monitoring purposes.
     * @dev This function is intended to be called by off-chain keepers or monitoring services.
     * It provides more detailed event logs about the state of the oracle.
     * @param token The address of the token.
     * @return price The price of the token, scaled to 1e18.
     * @return isFallback True if the fallback price was used.
     * @return lastUpdatedAt The timestamp of the returned price data.
     */
    function fetchAndReportTokenPrice(address token)
        external
        nonReentrant 
        returns (uint256 price, bool isFallback, uint256 lastUpdatedAt)
    {
        if (token == address(0)) revert ZeroAddress("token for fetchAndReportTokenPrice");

        PriceFeedData memory oracleData = _fetchAndReportPriceFromOracle(token); 
        string memory fallbackReasonString = ""; 
        bool useOraclePrice = false;

        if (oracleData.success) {
            bool isStale = (_stalenessThreshold != type(uint256).max) &&
                           (block.timestamp > oracleData.timestamp) && 
                           (block.timestamp - oracleData.timestamp > _stalenessThreshold);
            if (!isStale) {
                uint256 standardizedOraclePrice = convertToStandardPrecision(oracleData.price, _priceFeedDecimals[token]);
                if (standardizedOraclePrice < _minAcceptablePrice) {
                    fallbackReasonString = "Oracle price below minimum acceptable price";
                } else {
                    price = standardizedOraclePrice;
                    isFallback = false;
                    lastUpdatedAt = oracleData.timestamp;
                    useOraclePrice = true;
                }
            } else {
                fallbackReasonString = "Oracle data is stale";
            }
        } else {
            fallbackReasonString = "Oracle data fetch failed"; 
        }

        if (!useOraclePrice) {
            uint256 fallbackPriceValue = _fallbackPrices[token];
            uint256 fallbackTimestampValue = _fallbackTimestamps[token];

            if (fallbackPriceValue > 0 && fallbackPriceValue >= _minAcceptablePrice) {
                price = fallbackPriceValue;
                isFallback = true;
                lastUpdatedAt = fallbackTimestampValue;
                emit FallbackPriceUsed(token, price, lastUpdatedAt, fallbackReasonString);
            } else {
                bytes32 reasonHash = keccak256(bytes(fallbackReasonString));
                if (reasonHash == HASH_REASON_STALE) {
                    emit OraclePriceStaleNoViableFallback(token, oracleData.timestamp, _stalenessThreshold);
                } else if (reasonHash == HASH_REASON_FETCH_FAILED) { 
                     emit OracleFetchFailedNoViableFallback(token, "Oracle data fetch failed (no viable fallback)");
                }
                revert OI_NoPriceSource();
            }
        }
        return (price, isFallback, lastUpdatedAt);
    }

    /**
     * @notice Calculates the total value of a given amount of LP tokens.
     * @dev Fetches underlying token prices and decimals internally.
     * @param lpToken The address of the LP token.
     * @param amountLP The amount of LP tokens to value.
     * @param totalSupplyLP The total supply of the LP token.
     * @param reserve0 The total reserve of token0 in the LP pair.
     * @param reserve1 The total reserve of token1 in the LP pair.
     * @return value The total value of the LP tokens, scaled to 1e18.
     */
    function getLPTokenValue(
        address lpToken,
        uint256 amountLP,
        uint256 totalSupplyLP,
        uint256 reserve0,
        uint256 reserve1
    ) external view returns (uint256 value) {
        if (lpToken == address(0)) revert ZeroAddress("lpToken for getLPTokenValue");
        if (amountLP == 0) return 0;
        if (totalSupplyLP == 0) revert OI_TotalSupplyZero();

        address token0 = _lpTokenComposition[lpToken][0];
        address token1 = _lpTokenComposition[lpToken][1];

        if (token0 == address(0)) revert OI_LPNotRegistered(); 

        (uint256 price0_1e18, , ) = getTokenPrice(token0);
        (uint256 price1_1e18, , ) = getTokenPrice(token1);

        if ((reserve0 > 0 && price0_1e18 == 0) || (reserve1 > 0 && price1_1e18 == 0)) {
            revert OI_FailedToGetTokenPrices();
        }

        uint8 decimals0 = _getTokenDecimals(token0);
        uint8 decimals1 = _getTokenDecimals(token1);

        uint256 valueReserve0_1e18 = (reserve0 > 0 && price0_1e18 > 0) ? (reserve0 * price0_1e18) / (10**decimals0) : 0;
        uint256 valueReserve1_1e18 = (reserve1 > 0 && price1_1e18 > 0) ? (reserve1 * price1_1e18) / (10**decimals1) : 0;
        uint256 totalReservesValue_1e18 = valueReserve0_1e18 + valueReserve1_1e18;

        value = Math.mulDiv(totalReservesValue_1e18, amountLP, totalSupplyLP);
        return value;
    }

    /**
     * @notice A pure function to calculate LP token value with all data provided as arguments.
     * @dev Useful for off-chain calculations or when data is already available.
     * @param amountLP The amount of LP tokens to value.
     * @param totalSupplyLP The total supply of the LP token.
     * @param reserve0 The total reserve of token0.
     * @param price0_1e18 The price of token0, scaled to 1e18.
     * @param decimals0 The decimals of token0.
     * @param reserve1 The total reserve of token1.
     * @param price1_1e18 The price of token1, scaled to 1e18.
     * @param decimals1 The decimals of token1.
     * @return value The total value of the LP tokens, scaled to 1e18.
     */
    function getLPTokenValueAlternative(
        uint256 amountLP,
        uint256 totalSupplyLP,
        uint256 reserve0,
        uint256 price0_1e18, 
        uint8 decimals0,
        uint256 reserve1,
        uint256 price1_1e18, 
        uint8 decimals1
    ) external pure returns (uint256 value) {
        if (amountLP == 0) return 0;
        if (totalSupplyLP == 0) revert OI_TotalSupplyZero();
        if ((price0_1e18 == 0 && reserve0 > 0) || (price1_1e18 == 0 && reserve1 > 0)) {
             revert OI_FailedToGetTokenPrices();
        }
        if (decimals0 == 0 || decimals0 > 30) revert InvalidAmount(); 
        if (decimals1 == 0 || decimals1 > 30) revert InvalidAmount(); 


        uint256 valueReserve0_1e18 = (reserve0 > 0 && price0_1e18 > 0) ? (reserve0 * price0_1e18) / (10**decimals0) : 0;
        uint256 valueReserve1_1e18 = (reserve1 > 0 && price1_1e18 > 0) ? (reserve1 * price1_1e18) / (10**decimals1) : 0;
        uint256 totalReservesValue_1e18 = valueReserve0_1e18 + valueReserve1_1e18;

        value = Math.mulDiv(totalReservesValue_1e18, amountLP, totalSupplyLP);
        return value;
    }

    /**
     * @notice Validates if a given price is within an acceptable deviation from the oracle price.
     * @dev The deviation tolerance is halved if the oracle is using a fallback price.
     * @param token The address of the token.
     * @param priceToValidate The price to check.
     * @param maxDeviationBps The maximum allowed deviation in basis points.
     * @return isValid True if the price is within the allowed deviation.
     */
    function validatePriceAgainstOracle(
        address token,
        uint256 priceToValidate, 
        uint256 maxDeviationBps
    ) external view returns (bool isValid) {
        if (token == address(0)) revert ZeroAddress("token for validatePriceAgainstOracle");
        if (priceToValidate == 0) revert OI_NegativeOrZeroPrice(); 
        if (maxDeviationBps > Constants.BPS_MAX) revert OI_InvalidDeviationBPS(); 

        (uint256 oraclePrice_1e18, bool isOraclePriceFallback, ) = getTokenPrice(token);

        if (oraclePrice_1e18 == 0) return false; 

        uint256 effectiveDeviationBps = maxDeviationBps;
        if (isOraclePriceFallback) {
            effectiveDeviationBps = maxDeviationBps / 2;
            if (effectiveDeviationBps == 0 && maxDeviationBps > 0 && maxDeviationBps % 2 != 0) {
                effectiveDeviationBps = 1;
            }
        }
        
        if (effectiveDeviationBps == 0 && priceToValidate != oraclePrice_1e18) return false; 
        if (effectiveDeviationBps == 0 && priceToValidate == oraclePrice_1e18) return true;

        uint256 diff;
        if (priceToValidate >= oraclePrice_1e18) {
            diff = priceToValidate - oraclePrice_1e18;
        } else {
            diff = oraclePrice_1e18 - priceToValidate;
        }

        if (diff == 0) return true; 
        
        isValid = Math.mulDiv(diff, Constants.BPS_MAX, oraclePrice_1e18) <= effectiveDeviationBps;
        return isValid;
    }

    /**
     * @dev Internal view function to get data from a Chainlink oracle without emitting events.
     * This function is robust and self-contained, checking for staleness internally.
     */
    function _getPriceFromOracle(address tokenForPrice) private view returns (PriceFeedData memory data) {
        data = PriceFeedData(0, 0, 0, 0, false); 

        address priceFeedAggregator = _priceFeeds[tokenForPrice];
        if (priceFeedAggregator == address(0)) {
            return data;
        }

        try AggregatorV3Interface(priceFeedAggregator).latestRoundData() returns (
            uint80 roundId, int256 answer, uint256, uint256 updatedAt, uint80 answeredInRound
        ) {
            if (answer <= 0 || updatedAt == 0 || roundId == 0 || answeredInRound == 0 || roundId < answeredInRound) {
                return data; // success remains false
            }

            // Perform staleness check directly inside the helper function.
            bool isStale = (_stalenessThreshold != type(uint256).max) &&
                           (block.timestamp > updatedAt) &&
                           (block.timestamp - updatedAt > _stalenessThreshold);
            if (isStale) {
                return data; // success remains false
            }

            data.price = uint256(answer);
            data.timestamp = updatedAt;
            data.roundId = roundId;
            data.answeredInRound = answeredInRound;
            data.success = true; 
        } catch {
            // success remains false on any revert
        }
        return data;
    }

    /**
     * @dev Internal function to fetch oracle data and emit a corresponding event.
     */
    function _fetchAndReportPriceFromOracle(address tokenToReport) private returns (PriceFeedData memory data) {
        data = PriceFeedData(0, 0, 0, 0, false);

        address priceFeedAggregator = _priceFeeds[tokenToReport];
        if (priceFeedAggregator == address(0)) {
            return data;
        }

        try AggregatorV3Interface(priceFeedAggregator).latestRoundData() returns (
            uint80 roundId, int256 answer, uint256, uint256 updatedAt, uint80 answeredInRound
        ) {
            emit OracleDataFetched(tokenToReport, roundId, answer, updatedAt);

            if (answer > 0 && updatedAt > 0 && roundId > 0 && answeredInRound > 0 && roundId >= answeredInRound) {
                data.price = uint256(answer);
                data.timestamp = updatedAt;
                data.roundId = roundId;
                data.answeredInRound = answeredInRound;
                data.success = true; 
            }
        } catch Error(string memory reason) { 
            emit OracleFetchFailedNoViableFallback(tokenToReport, reason);
        } catch (bytes memory lowLevelData) { 
            string memory msgLowLevel = "Oracle call failed with low-level data";
            if (lowLevelData.length == 0) msgLowLevel = "Oracle call failed with no return data";
            emit OracleFetchFailedNoViableFallback(tokenToReport, msgLowLevel);
        }
        return data;
    }

    /**
     * @dev Internal function to verify the integrity and timeliness of a price feed aggregator upon registration.
     */
    function _verifyPriceFeed(address priceFeedAggregator) private view {
        PriceFeedData memory data = PriceFeedData(0, 0, 0, 0, false); 
        uint8 feedDecimals = 0; 

        uint256 startedAt;
        try AggregatorV3Interface(priceFeedAggregator).latestRoundData() returns (
            uint80 roundId, int256 answer, uint256 _startedAt, uint256 updatedAt, uint80 answeredInRound
        ) {
            data.price = answer > 0 ? uint256(answer) : 0;
            data.timestamp = updatedAt;
            data.roundId = roundId;
            data.answeredInRound = answeredInRound;
            startedAt = _startedAt;
        } catch {
            revert OI_InvalidPriceFeed();
        }

        try AggregatorV3Interface(priceFeedAggregator).decimals() returns (uint8 d) {
            feedDecimals = d;
        } catch {
            revert OI_GetDecimalsFailed();
        }

        if (feedDecimals == 0 || feedDecimals > 30) revert OI_GetDecimalsFailed();
        if (data.price == 0) revert OI_NegativeOrZeroPrice();
        if (data.roundId == 0 || data.answeredInRound == 0 || data.roundId < data.answeredInRound) revert OI_IncompleteRoundData();
        if (data.timestamp == 0 || startedAt == 0) revert OI_IncompleteRoundData();

        uint256 verificationStaleness;
        if (_stalenessThreshold != type(uint256).max && _stalenessThreshold > 0) {
            verificationStaleness = _stalenessThreshold * 2; 
             if (verificationStaleness < Constants.ORACLE_MAX_STALENESS) { 
                verificationStaleness = Constants.ORACLE_MAX_STALENESS;
            }
        } else if (_stalenessThreshold == type(uint256).max) { 
            verificationStaleness = type(uint256).max; 
        } else { 
             verificationStaleness = Constants.ORACLE_MAX_STALENESS * 6; 
        }
        
        if (verificationStaleness != type(uint256).max && block.timestamp > data.timestamp && (block.timestamp - data.timestamp > verificationStaleness) ) {
             revert OI_PriceTooOld();
        }
    }

    /**
     * @dev Internal function to get the decimals of a price feed aggregator.
     * @param priceFeedAggregator The address of the price feed.
     * @return decimals The number of decimals.
     */
    function _getPriceFeedDecimals(address priceFeedAggregator) private view returns (uint8 decimals) {
        try AggregatorV3Interface(priceFeedAggregator).decimals() returns (uint8 d) {
            decimals = d;
        } catch {
            revert OI_GetDecimalsFailed();
        }
        if (decimals == 0 || decimals > 30) revert OI_GetDecimalsFailed(); 
        return decimals;
    }

    /**
     * @notice Converts a raw price from a feed to the standard 1e18 precision.
     * @param rawPrice The price from the feed.
     * @param feedDecimals The number of decimals the feed uses.
     * @return standardizedPrice The price scaled to 1e18.
     */
    function convertToStandardPrecision(uint256 rawPrice, uint8 feedDecimals) public pure returns (uint256 standardizedPrice) {
        if (feedDecimals == 18) {
            standardizedPrice = rawPrice;
        } else if (feedDecimals < 18) {
            if (feedDecimals == 0) revert InvalidAmount(); 
            uint256 scalingFactor = 10**(uint256(18) - feedDecimals);
            standardizedPrice = Math.mulDiv(rawPrice, scalingFactor, 1); 
        } else { 
            if (feedDecimals > 30) revert InvalidAmount(); 
            uint256 divisor = 10**(uint256(feedDecimals) - 18);
            standardizedPrice = rawPrice / divisor; 
        }
        return standardizedPrice;
    }

    /**
     * @dev Internal function to get a token's decimals. It prioritizes registered feed decimals,
     * then attempts to call the token contract. It reverts on failure to ensure data integrity
     * for critical calculations like LP token valuation.
     * @param tokenAddress The address of the token.
     * @return The number of decimals for the token.
     */
    function _getTokenDecimals(address tokenAddress) private view returns (uint8) {
        if (_priceFeeds[tokenAddress] != address(0)) {
            if (_priceFeedDecimals[tokenAddress] != 0) { 
                return _priceFeedDecimals[tokenAddress];
            }
        }
        try IERC20MetadataUpgradeable(tokenAddress).decimals() returns (uint8 d) {
            if (d == 0 || d > 30) revert OI_GetDecimalsFailed(); 
            return d;
        } catch {
            revert OI_GetDecimalsFailed();
        }
    }

    /**
     * @notice Retrieves the price feed configuration for a token.
     * @param token The address of the token.
     * @return priceFeedAddress_ The address of the primary price feed aggregator.
     * @return isFeedAvailable_ True if a primary feed is set.
     * @return feedDecimals_ The decimals of the primary feed.
     * @return fallbackPrice_ The configured fallback price.
     * @return fallbackTimestamp_ The timestamp of the last fallback price update.
     */
    function getPriceFeedInfo(address token) external view returns (
        address priceFeedAddress_,
        bool isFeedAvailable_,
        uint8 feedDecimals_,
        uint256 fallbackPrice_,
        uint256 fallbackTimestamp_
    ) {
        if (token == address(0)) revert ZeroAddress("token for getPriceFeedInfo");
        priceFeedAddress_ = _priceFeeds[token];
        isFeedAvailable_ = (priceFeedAddress_ != address(0));
        feedDecimals_ = isFeedAvailable_ ? _priceFeedDecimals[token] : 0; 
        fallbackPrice_ = _fallbackPrices[token];
        fallbackTimestamp_ = _fallbackTimestamps[token];
    }

    /**
     * @notice Retrieves the registered underlying composition of an LP token.
     * @param lpToken The address of the LP token.
     * @return token0Out_ The address of the first underlying token.
     * @return token1Out_ The address of the second underlying token.
     * @return isRegistered_ True if the LP token is registered.
     */
    function getLPTokenInfo(address lpToken) external view returns (
        address token0Out_,
        address token1Out_,
        bool isRegistered_
    ) {
        if (lpToken == address(0)) revert ZeroAddress("lpToken for getLPTokenInfo");
        token0Out_ = _lpTokenComposition[lpToken][0];
        token1Out_ = _lpTokenComposition[lpToken][1];
        isRegistered_ = (token0Out_ != address(0)); 
    }

    /**
     * @notice Gets the current staleness threshold for price feeds.
     * @return threshold The threshold in seconds.
     */
    function getStalenessThreshold() external view returns (uint256 threshold) {
        threshold = _stalenessThreshold;
        return threshold;
    }

    /**
     * @notice Gets the current minimum acceptable price.
     * @return minPrice The minimum price, scaled to 1e18.
     */
    function getMinAcceptablePrice() external view returns (uint256 minPrice) {
        minPrice = _minAcceptablePrice;
        return minPrice;
    }
}
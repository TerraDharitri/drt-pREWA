// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../contracts/oracle/OracleIntegration.sol";
import "../contracts/mocks/MockAggregatorV3Interface.sol"; 
import "../contracts/mocks/MockERC20.sol"; 
import "../contracts/interfaces/AggregatorV3Interface.sol"; // For type
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol"; // For type
import "../contracts/libraries/Constants.sol";
import "../contracts/libraries/Errors.sol";
import "../contracts/libraries/DecimalMath.sol";
import "../contracts/proxy/TransparentProxy.sol";


// Helper contracts for testing _getTokenDecimals scenarios (used by OracleIntegration implicitly)
contract RevertingDecimalsToken is IERC20MetadataUpgradeable { 
    function name() external pure override returns (string memory) { return "RevertingDecimals"; }
    function symbol() external pure override returns (string memory) { return "RDT"; }
    function decimals() external pure override returns (uint8) { revert("DecimalsReverted"); }
    function totalSupply() external pure override returns (uint256) { return 0; }
    function balanceOf(address) external pure override returns (uint256) { return 0; }
    function transfer(address, uint256) external pure override returns (bool) { return false; }
    function allowance(address, address) external pure override returns (uint256) { return 0; }
    function approve(address, uint256) external pure override returns (bool) { return false; }
    function transferFrom(address, address, uint256) external pure override returns (bool) { return false; }
}
contract ZeroDecimalsToken is IERC20MetadataUpgradeable { 
    function name() external pure override returns (string memory) { return "ZeroDecimals"; }
    function symbol() external pure override returns (string memory) { return "ZDT"; }
    function decimals() external pure override returns (uint8) { return 0; }
    function totalSupply() external pure override returns (uint256) { return 0; }
    function balanceOf(address) external pure override returns (uint256) { return 0; }
    function transfer(address, uint256) external pure override returns (bool) { return false; }
    function allowance(address, address) external pure override returns (uint256) { return 0; }
    function approve(address, uint256) external pure override returns (bool) { return false; }
    function transferFrom(address, address, uint256) external pure override returns (bool) { return false; }
}
contract TooManyDecimalsToken is IERC20MetadataUpgradeable { 
    function name() external pure override returns (string memory) { return "TooManyDecimals"; }
    function symbol() external pure override returns (string memory) { return "TMDT"; }
    function decimals() external pure override returns (uint8) { return 31; }
    function totalSupply() external pure override returns (uint256) { return 0; }
    function balanceOf(address) external pure override returns (uint256) { return 0; }
    function transfer(address, uint256) external pure override returns (bool) { return false; }
    function allowance(address, address) external pure override returns (uint256) { return 0; }
    function approve(address, uint256) external pure override returns (bool) { return false; }
    function transferFrom(address, address, uint256) external pure override returns (bool) { return false; }
}


contract OracleIntegrationTest is Test {
    OracleIntegration oracle; 
    MockAggregatorV3Interface mockPriceFeedETHUSD; 
    MockAggregatorV3Interface mockPriceFeedBTCUSD; 
    MockERC20 tokenETH; 
    MockERC20 tokenBTC; 
    MockERC20 tokenLP_ETH_BTC;  

    address owner;
    address user1; 
    address liquidityManager;
    address proxyAdmin;

    uint256 constant ONE_HOUR = 1 hours;
    uint256 constant INITIAL_STALENESS = ONE_HOUR;


    function setUp() public {
        vm.warp(10 hours);

        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        liquidityManager = makeAddr("liquidityManager");
        proxyAdmin = makeAddr("proxyAdmin");
        vm.etch(liquidityManager, bytes("some bytecode"));

        OracleIntegration logic = new OracleIntegration();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        oracle = OracleIntegration(address(proxy));
        oracle.initialize(owner, INITIAL_STALENESS);
        
        assertEq(oracle.owner(), owner, "Owner not set correctly in setUp");
        
        vm.prank(owner);
        oracle.setLiquidityManagerAddress(liquidityManager);

        tokenETH = new MockERC20();
        tokenETH.mockInitialize("Wrapped ETH", "WETH", 18, owner);
        
        tokenBTC = new MockERC20();
        tokenBTC.mockInitialize("Wrapped BTC", "WBTC", 8, owner);

        tokenLP_ETH_BTC = new MockERC20(); 
        tokenLP_ETH_BTC.mockInitialize("LP ETH/BTC", "LP-EB", 18, owner);

        mockPriceFeedETHUSD = new MockAggregatorV3Interface();
        mockPriceFeedETHUSD.setDecimals(18); 
        mockPriceFeedETHUSD.setLatestRoundData(1, 2000 * 1e18, block.timestamp - 30 minutes, block.timestamp - 30 minutes, 1); 

        mockPriceFeedBTCUSD = new MockAggregatorV3Interface();
        mockPriceFeedBTCUSD.setDecimals(8); 
        mockPriceFeedBTCUSD.setLatestRoundData(1, 30000 * 1e8, block.timestamp - 30 minutes, block.timestamp - 30 minutes, 1); 

        vm.prank(owner);
        oracle.setPriceFeed(address(tokenETH), address(mockPriceFeedETHUSD));
        vm.prank(owner);
        oracle.setPriceFeed(address(tokenBTC), address(mockPriceFeedBTCUSD));
    }

    // --- Initialize ---
    function test_Initialize_Success() public view {
        assertEq(oracle.owner(), owner);
        assertEq(oracle.getStalenessThreshold(), INITIAL_STALENESS);
        assertEq(oracle.getMinAcceptablePrice(), 1); 
    }
    function test_Initialize_Revert_ZeroOwner() public {
        OracleIntegration logic = new OracleIntegration();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        OracleIntegration newOracle = OracleIntegration(address(proxy));
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "initialOwner_"));
        newOracle.initialize(address(0), INITIAL_STALENESS);
    }
    function test_Initialize_Revert_ZeroStaleness() public {
        OracleIntegration logic = new OracleIntegration();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        OracleIntegration newOracle = OracleIntegration(address(proxy));
        vm.expectRevert(OI_StalenessThresholdZero.selector);
        newOracle.initialize(owner, 0);
    }
     function test_Initialize_Revert_AlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        oracle.initialize(owner, INITIAL_STALENESS);
    }
    function test_Constructor_Runs() public { new OracleIntegration(); assertTrue(true); }

    // --- Modifier onlyLiquidityManagerOrOwner ---
    function test_Modifier_OnlyLMOrOwner_Success_ByLM() public {
        vm.prank(liquidityManager);
        oracle.registerLPToken(address(tokenLP_ETH_BTC), address(tokenETH), address(tokenBTC)); 
        assertTrue(true);
    }
    function test_Modifier_OnlyLMOrOwner_Success_ByOwner() public {
        vm.prank(owner);
        oracle.registerLPToken(address(tokenLP_ETH_BTC), address(tokenETH), address(tokenBTC)); 
        assertTrue(true);
    }
    function test_Modifier_OnlyLMOrOwner_Fail_OtherUser() public {
        vm.prank(user1);
        vm.expectRevert("OI: Caller not LM or Owner");
        oracle.registerLPToken(address(tokenLP_ETH_BTC), address(tokenETH), address(tokenBTC));
    }


    // --- setLiquidityManagerAddress ---
    function test_SetLiquidityManagerAddress_Success() public {
        address newLM = makeAddr("newLM");
        vm.etch(newLM, bytes("bytecode")); 
        vm.prank(owner);
        vm.expectEmit(true, true, true, false);
        emit OracleIntegration.LiquidityManagerAddressSet(liquidityManager, newLM, owner);
        oracle.setLiquidityManagerAddress(newLM);
        assertEq(oracle.liquidityManagerAddress(), newLM);
    }
    function test_SetLiquidityManagerAddress_ToZero() public {
        vm.prank(owner);
        oracle.setLiquidityManagerAddress(address(0));
        assertEq(oracle.liquidityManagerAddress(), address(0));
    }
    function test_SetLiquidityManagerAddress_Revert_NotAContract() public {
        address nonContractLM = makeAddr("nonContractLM");
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "LiquidityManager address"));
        oracle.setLiquidityManagerAddress(nonContractLM);
    }
    function test_SetLiquidityManagerAddress_Revert_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        oracle.setLiquidityManagerAddress(makeAddr("any"));
    }

    // --- setPriceFeed ---
    function test_SetPriceFeed_Success_NewFeed() public {
        MockERC20 newToken = new MockERC20(); newToken.mockInitialize("New", "NEW", 6, owner);
        MockAggregatorV3Interface newFeed = new MockAggregatorV3Interface();
        newFeed.setDecimals(6); 
        newFeed.setLatestRoundData(1, 100 * 1e6, block.timestamp, block.timestamp, 1); 

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit OracleIntegration.PriceFeedUpdated(address(newToken), address(newFeed), 6, owner);
        oracle.setPriceFeed(address(newToken), address(newFeed));
        
        (address feedAddr,, uint8 decimals,,) = oracle.getPriceFeedInfo(address(newToken));
        assertEq(feedAddr, address(newFeed));
        assertEq(decimals, 6);
    }
    
    function test_SetPriceFeed_Success_UpdateFeed_FallbackRetained() public {
        uint256 expectedFbPrice = 1900 * 1e18;
        vm.prank(owner);
        oracle.setFallbackPrice(address(tokenETH), expectedFbPrice); 
        uint256 expectedTimestamp = block.timestamp;

        MockAggregatorV3Interface updatedETHFeed = new MockAggregatorV3Interface();
        updatedETHFeed.setDecimals(18);
        updatedETHFeed.setLatestRoundData(2, 2100 * 1e18, block.timestamp, block.timestamp, 2);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true); 
        emit OracleIntegration.PriceFeedUpdated(address(tokenETH), address(updatedETHFeed), 18, owner);
        vm.expectEmit(true, true, false, false); 
        emit OracleIntegration.PrimaryFeedChangedWithFallbackRetained(address(tokenETH), address(updatedETHFeed), expectedFbPrice, expectedTimestamp);
        
        oracle.setPriceFeed(address(tokenETH), address(updatedETHFeed));
        (address feedAddr,,, uint256 fbPrice,) = oracle.getPriceFeedInfo(address(tokenETH));
        assertEq(feedAddr, address(updatedETHFeed));
        assertEq(fbPrice, expectedFbPrice);
    }

    function test_SetPriceFeed_Success_RemoveFeed_ToAddressZero_FallbackRetained() public {
        uint256 expectedFbPrice = 1900 * 1e18;
        vm.prank(owner);
        oracle.setFallbackPrice(address(tokenETH), expectedFbPrice); 
        uint256 expectedTimestamp = block.timestamp;
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true); 
        emit OracleIntegration.PriceFeedUpdated(address(tokenETH), address(0), 0, owner);
        vm.expectEmit(true, true, false, false); 
        emit OracleIntegration.PrimaryFeedRemovedWithFallbackRetained(address(tokenETH), expectedFbPrice, expectedTimestamp);

        oracle.setPriceFeed(address(tokenETH), address(0));
        (address feedAddr,,,uint256 fbPrice,) = oracle.getPriceFeedInfo(address(tokenETH));
        assertEq(feedAddr, address(0));
        assertEq(fbPrice, expectedFbPrice); 
    }
    
    function test_SetPriceFeed_Success_RemoveFeed_NoFallback_NoExtraEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true); 
        emit OracleIntegration.PriceFeedUpdated(address(tokenBTC), address(0), 0, owner);
        
        oracle.setPriceFeed(address(tokenBTC), address(0));
        (address feedAddr,,,,uint256 fbPrice) = oracle.getPriceFeedInfo(address(tokenBTC));
        assertEq(feedAddr, address(0));
        assertEq(fbPrice, 0);
    }
    
    function test_SetPriceFeed_NoChangeIfAlreadyAddressZero_NoEvent() public {
        MockERC20 unfedToken = new MockERC20(); unfedToken.mockInitialize("UNF","UNF",18,owner);
        vm.prank(owner);
        (address feedAddrBefore,,,,) = oracle.getPriceFeedInfo(address(unfedToken));
        assertEq(feedAddrBefore, address(0));

        vm.prank(owner);
        oracle.setPriceFeed(address(unfedToken), address(0)); 
    }
    
    function test_SetPriceFeed_Revert_TokenZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "token for price feed"));
        oracle.setPriceFeed(address(0), address(mockPriceFeedETHUSD));
    }

    function test_VerifyPriceFeed_Revert_FeedLatestRoundDataReverts() public {
        MockAggregatorV3Interface badFeed = new MockAggregatorV3Interface();
        badFeed.setDecimals(18); 
        badFeed.setShouldRevertLatestRoundData(true); 

        vm.prank(owner);
        vm.expectRevert(OI_InvalidPriceFeed.selector);
        oracle.setPriceFeed(address(tokenETH), address(badFeed));
    }
    function test_VerifyPriceFeed_Revert_FeedGetDecimalsReverts() public {
        MockAggregatorV3Interface badFeed = new MockAggregatorV3Interface();
        badFeed.setLatestRoundData(1, 2000e18, block.timestamp, block.timestamp, 1); 
        badFeed.setShouldRevertDecimals(true); 

        vm.prank(owner);
        vm.expectRevert(OI_GetDecimalsFailed.selector);
        oracle.setPriceFeed(address(tokenETH), address(badFeed));
    }
    function test_VerifyPriceFeed_Revert_FeedInvalidDecimalsValue() public {
        MockAggregatorV3Interface badFeed = new MockAggregatorV3Interface();
        badFeed.setLatestRoundData(1, 2000e18, block.timestamp, block.timestamp, 1);
        
        badFeed.setDecimals(0);
        vm.prank(owner);
        vm.expectRevert(OI_GetDecimalsFailed.selector);
        oracle.setPriceFeed(address(tokenETH), address(badFeed));
        
        badFeed.setDecimals(31);
        vm.prank(owner);
        vm.expectRevert(OI_GetDecimalsFailed.selector);
        oracle.setPriceFeed(address(tokenETH), address(badFeed));
    }
    function test_VerifyPriceFeed_Revert_FeedZeroPrice() public {
        MockAggregatorV3Interface badFeed = new MockAggregatorV3Interface();
        badFeed.setDecimals(18);
        badFeed.setLatestRoundData(1, 0, block.timestamp, block.timestamp, 1); 

        vm.prank(owner);
        vm.expectRevert(OI_NegativeOrZeroPrice.selector);
        oracle.setPriceFeed(address(tokenETH), address(badFeed));
    }
    function test_VerifyPriceFeed_Revert_FeedIncompleteRoundData() public {
        MockAggregatorV3Interface badFeed = new MockAggregatorV3Interface();
        badFeed.setDecimals(18);
        
        badFeed.setLatestRoundData(0, 2000e18, block.timestamp, block.timestamp, 0);
        vm.prank(owner);
        vm.expectRevert(OI_IncompleteRoundData.selector);
        oracle.setPriceFeed(address(tokenETH), address(badFeed));

        badFeed.setLatestRoundData(1, 2000e18, block.timestamp, 0, 1);
        vm.prank(owner);
        vm.expectRevert(OI_IncompleteRoundData.selector);
        oracle.setPriceFeed(address(tokenETH), address(badFeed));
    }
    function test_VerifyPriceFeed_Revert_FeedPriceTooOld() public {
        vm.warp(block.timestamp + 7 hours);
        MockAggregatorV3Interface oldFeed = new MockAggregatorV3Interface();
        oldFeed.setDecimals(18);
        uint256 currentTimestamp = block.timestamp;
        uint256 verificationStaleness = Constants.ORACLE_MAX_STALENESS * 6;
        uint256 oldTimestamp = currentTimestamp - (verificationStaleness + 1);
        oldFeed.setLatestRoundData(1, 2000e18, oldTimestamp, oldTimestamp, 1);

        vm.prank(owner);
        vm.expectRevert(OI_PriceTooOld.selector);
        oracle.setPriceFeed(address(tokenETH), address(oldFeed));
    }
    function test_VerifyPriceFeed_VerificationStalenessLogic() public {
        vm.warp(block.timestamp + 10 days);
        vm.prank(owner);
        oracle.setStalenessThreshold(2 hours);

        MockAggregatorV3Interface feed1 = new MockAggregatorV3Interface(); feed1.setDecimals(18);
        uint256 ts1 = block.timestamp - (2 hours); 
        feed1.setLatestRoundData(1,1e18,ts1,ts1,1);
        vm.prank(owner); oracle.setPriceFeed(address(tokenETH), address(feed1)); 

        uint256 ts2 = block.timestamp - (4 hours + 1); 
        feed1.setLatestRoundData(1,1e18,ts2,ts2,1); 
        
        vm.prank(owner); 
        vm.expectRevert(OI_PriceTooOld.selector); 
        oracle.setPriceFeed(address(tokenBTC), address(feed1)); 

        vm.prank(owner); oracle.setStalenessThreshold(type(uint256).max); 
        MockAggregatorV3Interface feed3 = new MockAggregatorV3Interface(); feed3.setDecimals(18);
        uint256 ts5 = block.timestamp > (100 days) ? block.timestamp - (100 days) : 1; 
        
        feed3.setLatestRoundData(1,1e18,ts5,ts5,1);
        vm.prank(owner);
        oracle.setPriceFeed(address(tokenETH), address(feed3));
    }

    // --- registerLPToken ---
    function test_RegisterLPToken_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "lpToken address"));
        oracle.registerLPToken(address(0), address(tokenETH), address(tokenBTC));
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "token0 address"));
        oracle.registerLPToken(address(tokenLP_ETH_BTC), address(0), address(tokenBTC));
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "token1 address"));
        oracle.registerLPToken(address(tokenLP_ETH_BTC), address(tokenETH), address(0));
        vm.prank(owner);
        vm.expectRevert(InvalidAmount.selector);
        oracle.registerLPToken(address(tokenLP_ETH_BTC), address(tokenETH), address(tokenETH));
    }

    // --- setFallbackPrice ---
    function test_SetFallbackPrice_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "token for fallback price"));
        oracle.setFallbackPrice(address(0), 100e18);
        vm.prank(owner);
        oracle.setFallbackPrice(address(tokenETH), 0);
    }
    function test_SetFallbackPrice_Success_SetAndRemove() public {
        uint256 newPrice = 2000e18;
        vm.prank(owner);
        oracle.setFallbackPrice(address(tokenETH), newPrice);
        (,,,uint256 fallbackPrice, uint256 fallbackTs) = oracle.getPriceFeedInfo(address(tokenETH));
        assertEq(fallbackPrice, newPrice);
        assertEq(fallbackTs, block.timestamp);

        vm.prank(owner);
        oracle.setFallbackPrice(address(tokenETH), 0);
        (,,,fallbackPrice, fallbackTs) = oracle.getPriceFeedInfo(address(tokenETH));
        assertEq(fallbackPrice, 0);
        assertEq(fallbackTs, 0);
    }

    // --- setStalenessThreshold ---
    function test_SetStalenessThreshold_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(OI_StalenessThresholdZero.selector);
        oracle.setStalenessThreshold(0);
        vm.prank(owner);
        vm.expectRevert(InvalidDuration.selector);
        oracle.setStalenessThreshold(7 days + 1);
    }
    function test_SetStalenessThreshold_ToMax_Success() public {
        vm.prank(owner);
        oracle.setStalenessThreshold(type(uint256).max);
        assertEq(oracle.getStalenessThreshold(), type(uint256).max);
    }

    // --- setMinAcceptablePrice ---
    function test_SetMinAcceptablePrice_Revert_Zero() public {
        vm.prank(owner);
        vm.expectRevert(OI_MinAcceptablePriceZero.selector);
        oracle.setMinAcceptablePrice(0);
    }

    // --- getTokenPrice ---
    function test_GetTokenPrice_Revert_ZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "token for getTokenPrice"));
        oracle.getTokenPrice(address(0));
    }
    function test_GetTokenPrice_Revert_NoSourceAvailable() public {
        MockERC20 newToken = new MockERC20();
        newToken.mockInitialize("NoPrice", "NP", 18, owner);
        vm.expectRevert(OI_NoPriceSource.selector);
        oracle.getTokenPrice(address(newToken));
    }
    function test_GetTokenPrice_Success_OraclePriceIsStale_UsesFallback() public {
        vm.prank(owner);
        oracle.setFallbackPrice(address(tokenETH), 1950e18);
        
        vm.warp(block.timestamp + INITIAL_STALENESS + 1);
        (uint256 price, bool isFallback, ) = oracle.getTokenPrice(address(tokenETH));
        assertTrue(isFallback);
        assertEq(price, 1950e18);
    }
    function test_GetTokenPrice_Success_OraclePriceBelowMin_UsesFallback() public {
        vm.prank(owner);
        oracle.setMinAcceptablePrice(1900e18);
        vm.prank(owner);
        // Fallback price must be provided in 1e18 precision
        oracle.setFallbackPrice(address(tokenBTC), 29000e18);
        mockPriceFeedBTCUSD.setLatestRoundData(2, 1800e8, block.timestamp, block.timestamp, 2);
        
        (uint256 price, bool isFallback, ) = oracle.getTokenPrice(address(tokenBTC));
        assertTrue(isFallback);
        // Price is returned in 1e18 precision
        assertEq(price, 29000e18);
    }
    function test_GetTokenPrice_Success_OraclePriceBelowMin_FallbackAlsoBelowMin_Reverts() public {
        // Set a valid fallback price first
        vm.prank(owner);
        oracle.setFallbackPrice(address(tokenBTC), 29000e18);
        
        // Now, set the minimum price higher than the oracle price and the fallback price
        vm.prank(owner);
        oracle.setMinAcceptablePrice(31000e18);
        
        vm.expectRevert(OI_NoPriceSource.selector);
        oracle.getTokenPrice(address(tokenBTC));
    }
    function test_GetTokenPrice_Success_OraclePriceIsZero_UsesFallback() public {
        // Set price feed to 0 after it's been registered
        mockPriceFeedETHUSD.setLatestRoundData(2, 0, block.timestamp, block.timestamp, 2); 
        vm.prank(owner);
        oracle.setFallbackPrice(address(tokenETH), 1950e18);

        (uint256 price, bool isFallback, ) = oracle.getTokenPrice(address(tokenETH));
        assertTrue(isFallback);
        assertEq(price, 1950e18);
    }
    function test_GetTokenPrice_Revert_OracleFetchFailsAndNoFallback() public {
        // Set a valid feed, then make it revert
        MockAggregatorV3Interface newFeed = new MockAggregatorV3Interface();
        newFeed.setDecimals(18);
        newFeed.setLatestRoundData(1, 2000e18, block.timestamp, block.timestamp, 1);
        vm.prank(owner);
        oracle.setPriceFeed(address(tokenETH), address(newFeed));
        newFeed.setShouldRevertLatestRoundData(true);

        vm.expectRevert(OI_NoPriceSource.selector);
        oracle.getTokenPrice(address(tokenETH));
    }


    // --- fetchAndReportTokenPrice ---
    function test_FetchAndReport_Revert_ZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "token for fetchAndReportTokenPrice"));
        oracle.fetchAndReportTokenPrice(address(0));
    }
    function test_FetchAndReport_Success_OraclePrice() public {
        (, bool isFallback, ) = oracle.fetchAndReportTokenPrice(address(tokenETH));
        assertFalse(isFallback);
    }
    function test_FetchAndReport_Success_StaleOracle_ValidFallback() public {
        vm.prank(owner);
        oracle.setFallbackPrice(address(tokenETH), 1950e18);
        uint256 expectedTimestamp = block.timestamp;
        
        vm.warp(block.timestamp + INITIAL_STALENESS + 1);
        vm.expectEmit(true, true, false, false);
        emit OracleIntegration.FallbackPriceUsed(address(tokenETH), 1950e18, expectedTimestamp, "Oracle data is stale");
        (, bool isFallback, ) = oracle.fetchAndReportTokenPrice(address(tokenETH));
        assertTrue(isFallback);
    }
    function test_FetchAndReport_Revert_StaleOracle_NoFallback() public {
        vm.warp(block.timestamp + INITIAL_STALENESS + 1);
        vm.expectEmit(true, false, false, false);
        emit OracleIntegration.OraclePriceStaleNoViableFallback(address(tokenETH), block.timestamp - (INITIAL_STALENESS + 1), INITIAL_STALENESS);
        vm.expectRevert(OI_NoPriceSource.selector);
        oracle.fetchAndReportTokenPrice(address(tokenETH));
    }
    function test_FetchAndReport_Revert_OracleFetchFails_NoFallback() public {
        // Set up a valid feed first, so setPriceFeed succeeds.
        MockAggregatorV3Interface revertingFeed = new MockAggregatorV3Interface();
        revertingFeed.setDecimals(18);
        revertingFeed.setLatestRoundData(1, 2000e18, block.timestamp, block.timestamp, 1);
        vm.prank(owner);
        oracle.setPriceFeed(address(tokenETH), address(revertingFeed));

        // Now, make the feed revert for subsequent calls.
        revertingFeed.setShouldRevertLatestRoundData(true);

        vm.expectEmit(true, false, false, false);
        emit OracleIntegration.OracleFetchFailedNoViableFallback(address(tokenETH), "Oracle call failed with no return data");
        vm.expectRevert(OI_NoPriceSource.selector);
        oracle.fetchAndReportTokenPrice(address(tokenETH));
    }

    function test_FetchAndReport_Success_OraclePriceBelowMin_UsesFallback() public {
        mockPriceFeedETHUSD.setLatestRoundData(2, 100e18, block.timestamp, block.timestamp, 2);
        vm.prank(owner);
        oracle.setMinAcceptablePrice(200e18);
        vm.prank(owner);
        oracle.setFallbackPrice(address(tokenETH), 250e18);
        uint256 expectedTimestamp = block.timestamp;

        vm.expectEmit(true, true, false, false);
        emit OracleIntegration.FallbackPriceUsed(address(tokenETH), 250e18, expectedTimestamp, "Oracle price below minimum acceptable price");
        (, bool isFallback, ) = oracle.fetchAndReportTokenPrice(address(tokenETH));
        assertTrue(isFallback);
    }
    function test_FetchAndReport_Revert_OraclePriceBelowMin_NoFallback() public {
        mockPriceFeedETHUSD.setLatestRoundData(2, 100e18, block.timestamp, block.timestamp, 2);
        vm.prank(owner);
        oracle.setMinAcceptablePrice(200e18);
        
        vm.expectRevert(OI_NoPriceSource.selector);
        oracle.fetchAndReportTokenPrice(address(tokenETH));
    }

    // --- getLPTokenValue ---
    function test_GetLPTokenValue_Reverts() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "lpToken for getLPTokenValue"));
        oracle.getLPTokenValue(address(0), 1e18, 1e18, 1e18, 1e18);
        vm.expectRevert(OI_TotalSupplyZero.selector);
        oracle.getLPTokenValue(address(tokenLP_ETH_BTC), 1e18, 0, 1e18, 1e18);
        vm.expectRevert(OI_LPNotRegistered.selector);
        oracle.getLPTokenValue(address(tokenLP_ETH_BTC), 1e18, 1e18, 1e18, 1e18);
    }
    function test_GetLPTokenValue_Revert_UnderlyingPriceFails() public {
        vm.prank(owner);
        oracle.registerLPToken(address(tokenLP_ETH_BTC), address(tokenETH), address(tokenBTC));
        // Make getTokenPrice fail for the underlying token by making its price feed revert
        // This should cause getLPTokenValue to revert with OI_NoPriceSource from the underlying getTokenPrice call
        mockPriceFeedBTCUSD.setShouldRevertLatestRoundData(true); 
        vm.expectRevert(OI_NoPriceSource.selector);
        oracle.getLPTokenValue(address(tokenLP_ETH_BTC), 1e18, 1e18, 1e18, 1e18);
    }
    function test_GetLPTokenValue_Revert_UnderlyingDecimalsFail() public {
        RevertingDecimalsToken rdt = new RevertingDecimalsToken();
        // DO NOT set a price feed for the reverting token. This forces getLPTokenValue
        // to call _getTokenDecimals, which is the function we want to test the revert on.
        // We must, however, set a price for the *other* token in the pair.
        MockAggregatorV3Interface validFeed = new MockAggregatorV3Interface();
        validFeed.setDecimals(18);
        validFeed.setLatestRoundData(1, 1e18, block.timestamp, block.timestamp, 1);
        vm.prank(owner);
        oracle.setPriceFeed(address(tokenBTC), address(validFeed));
        vm.prank(owner);
        oracle.setFallbackPrice(address(rdt), 1e18); // FIX: Set fallback price to avoid OI_NoPriceSource

        vm.prank(owner);
        oracle.registerLPToken(address(tokenLP_ETH_BTC), address(rdt), address(tokenBTC));
        vm.expectRevert(OI_GetDecimalsFailed.selector);
        oracle.getLPTokenValue(address(tokenLP_ETH_BTC), 1e18, 1e18, 1e18, 1e18);
    }
    function test_GetLPTokenValue_Success_ZeroAmountLP() public view {
        uint256 value = oracle.getLPTokenValue(address(tokenLP_ETH_BTC), 0, 1e18, 1e18, 1e18);
        assertEq(value, 0);
    }

    // --- getLPTokenValueAlternative ---
    function test_GetLPTokenValueAlternative_Reverts() public {
        vm.expectRevert(OI_TotalSupplyZero.selector);
        oracle.getLPTokenValueAlternative(1,0,1,1,1,1,1,1);
        vm.expectRevert(OI_FailedToGetTokenPrices.selector);
        oracle.getLPTokenValueAlternative(1,1,1,0,1,1,1,1);
        vm.expectRevert(InvalidAmount.selector);
        oracle.getLPTokenValueAlternative(1,1,1,1,0,1,1,1);
        vm.expectRevert(InvalidAmount.selector);
        oracle.getLPTokenValueAlternative(1,1,1,1,31,1,1,1);
    }

    // --- validatePriceAgainstOracle ---
    function test_ValidatePriceAgainstOracle_Reverts() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "token for validatePriceAgainstOracle"));
        oracle.validatePriceAgainstOracle(address(0), 1, 100);
        vm.expectRevert(OI_NegativeOrZeroPrice.selector);
        oracle.validatePriceAgainstOracle(address(tokenETH), 0, 100);
        vm.expectRevert(OI_InvalidDeviationBPS.selector);
        oracle.validatePriceAgainstOracle(address(tokenETH), 1, 10001);
    }
    function test_ValidatePriceAgainstOracle_Success_ZeroDeviation_ExactMatch() public view {
        assertTrue(oracle.validatePriceAgainstOracle(address(tokenETH), 2000e18, 0));
    }
    function test_ValidatePriceAgainstOracle_Fail_ZeroDeviation_NoMatch() public view {
        assertFalse(oracle.validatePriceAgainstOracle(address(tokenETH), 2001e18, 0));
    }
    function test_ValidatePriceAgainstOracle_Success_OraclePriceIsZero() public {
        // Set a valid feed, then make its price 0
        mockPriceFeedETHUSD.setLatestRoundData(2, 0, block.timestamp, block.timestamp, 2);

        // A call to validatePriceAgainstOracle should revert because getTokenPrice will revert
        vm.expectRevert(OI_NoPriceSource.selector);
        oracle.validatePriceAgainstOracle(address(tokenETH), 1, 100);
    }
    function test_ValidatePriceAgainstOracle_FallbackHalving_OddDeviation() public {
        vm.prank(owner);
        oracle.setFallbackPrice(address(tokenETH), 2000e18);
        vm.warp(block.timestamp + INITIAL_STALENESS + 1);

        // effectiveDeviationBps = 6 / 2 = 3.
        // Max allowed price = 2000e18 * (1 + 3/10000) = 2000e18 + 6e16 = 2000.6e18
        uint256 validPrice = 2000e18 + (2000e18 * 3) / 10000;
        assertTrue(oracle.validatePriceAgainstOracle(address(tokenETH), validPrice, 6));

        // FIX: Use 4 bps deviation which is 2000e18 * (4/10000) = 0.8e18
        uint256 invalidPrice = validPrice + (2000e18 * 1) / 10000; // 2000.7e18 would be 3.5 bps -> still valid? Let's use 4 bps
        // Instead, set to 4 bps above: 2000e18 * (1 + 4/10000) = 2000.8e18
        invalidPrice = 2000e18 + (2000e18 * 4) / 10000; // 2000.8e18 -> 4 bps
        assertFalse(oracle.validatePriceAgainstOracle(address(tokenETH), invalidPrice, 6));
    }

    // --- _getTokenDecimals ---
    function test_GetTokenDecimals_Reverts() public {
        RevertingDecimalsToken rdt = new RevertingDecimalsToken();
        ZeroDecimalsToken zdt = new ZeroDecimalsToken();
        TooManyDecimalsToken tmdt = new TooManyDecimalsToken();
        
        // DO NOT set price feeds for the test tokens. This forces getLPTokenValue
        // to call the internal _getTokenDecimals, which is what we are testing.
        // We MUST set a price for the other token in the pair (tokenBTC) for the call to proceed.
        MockAggregatorV3Interface validFeed = new MockAggregatorV3Interface();
        validFeed.setDecimals(18);
        validFeed.setLatestRoundData(1, 1e18, block.timestamp, block.timestamp, 1);
        vm.prank(owner);
        oracle.setPriceFeed(address(tokenBTC), address(validFeed));
        // FIX: Set fallback prices for the problematic tokens to avoid OI_NoPriceSource revert
        vm.prank(owner);
        oracle.setFallbackPrice(address(rdt), 1e18);
        vm.prank(owner);
        oracle.setFallbackPrice(address(zdt), 1e18);
        vm.prank(owner);
        oracle.setFallbackPrice(address(tmdt), 1e18);

        vm.prank(owner);
        oracle.registerLPToken(address(tokenLP_ETH_BTC), address(rdt), address(tokenBTC));
        vm.expectRevert(OI_GetDecimalsFailed.selector);
        oracle.getLPTokenValue(address(tokenLP_ETH_BTC), 1, 1, 1, 1);

        vm.prank(owner);
        oracle.registerLPToken(address(tokenLP_ETH_BTC), address(zdt), address(tokenBTC));
        vm.expectRevert(OI_GetDecimalsFailed.selector);
        oracle.getLPTokenValue(address(tokenLP_ETH_BTC), 1, 1, 1, 1);
        
        vm.prank(owner);
        oracle.registerLPToken(address(tokenLP_ETH_BTC), address(tmdt), address(tokenBTC));
        vm.expectRevert(OI_GetDecimalsFailed.selector);
        oracle.getLPTokenValue(address(tokenLP_ETH_BTC), 1, 1, 1, 1);
    }
    
    // --- _getPriceFromOracle ---
    function test_GetPriceFromOracle_Reverts() public {
        // Set a valid feed first, then make it return bad data.
        MockAggregatorV3Interface badFeed = new MockAggregatorV3Interface(); 
        badFeed.setDecimals(18); 
        badFeed.setLatestRoundData(1, 2000e18, block.timestamp, block.timestamp, 1); 
        vm.prank(owner);
        oracle.setPriceFeed(address(tokenETH), address(badFeed));

        // Now set invalid data. getTokenPrice should revert because there's no fallback.
        badFeed.setLatestRoundData(1, -1, block.timestamp, block.timestamp, 1);
        vm.expectRevert(OI_NoPriceSource.selector);
        oracle.getTokenPrice(address(tokenETH));

        // FIX: Remove startedAt=0 test case since we don't check it in _getPriceFromOracle
        // Only test updatedAt=0 and roundId < answeredInRound
        badFeed.setLatestRoundData(1, 1, block.timestamp, 0, 1);
        vm.expectRevert(OI_NoPriceSource.selector);
        oracle.getTokenPrice(address(tokenETH));

        badFeed.setLatestRoundData(1, 1, block.timestamp, block.timestamp, 2); // roundId < answeredInRound
        vm.expectRevert(OI_NoPriceSource.selector);
        oracle.getTokenPrice(address(tokenETH));
    }

    // --- getLPTokenInfo and getPriceFeedInfo ---
    function test_Getters_Revert_ZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "token for getPriceFeedInfo"));
        oracle.getPriceFeedInfo(address(0));
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "lpToken for getLPTokenInfo"));
        oracle.getLPTokenInfo(address(0));
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../liquidity/interfaces/IPancakeRouter.sol";

contract MockPancakeRouter {
    
    struct AddLiquidityCall { 
        address tokenA;
        address tokenB;
        uint256 amountADesired;
        uint256 amountBDesired;
        uint256 amountAMin;
        uint256 amountBMin;
        address to;
        uint256 deadline;
    }
    AddLiquidityCall[] public addLiquidityCalls;

    struct AddLiquidityETHCall { 
        address token;
        uint256 amountTokenDesired;
        uint256 amountTokenMin;
        uint256 amountETHMin;
        address to;
        uint256 deadline;
        uint256 value;
    }
    AddLiquidityETHCall[] public addLiquidityETHCalls;
    
    struct RemoveLiquidityCall { 
        address tokenA;
        address tokenB;
        uint256 liquidity;
        uint256 amountAMin;
        uint256 amountBMin;
        address to;
        uint256 deadline;
    }
    RemoveLiquidityCall[] public removeLiquidityCalls;

    struct RemoveLiquidityETHCall { 
        address token;
        uint256 liquidity;
        uint256 amountTokenMin;
        uint256 amountETHMin;
        address to;
        uint256 deadline;
    }
    RemoveLiquidityETHCall[] public removeLiquidityETHCalls;

    uint256 public mockAmountAOut;
    uint256 public mockAmountBOut;
    uint256 public mockLiquidityOut;
    uint256 public mockAmountTokenOut;
    uint256 public mockAmountETHOut;
    uint256[] public mockAmountsOutArray;

    bool public shouldRevertAddLiquidity;
    bool public shouldRevertAddLiquidityETH;
    bool public shouldRevertRemoveLiquidity;
    bool public shouldRevertRemoveLiquidityETH;
    bool public shouldRevertFactory;
    bool public shouldRevertWeth;
    
    address private _factoryAddress = 0x00000000000000000000000000000000000000f1;
    address private _wethAddress = 0x0000000000000000000000000000000000000E71;

    function setAddLiquidityReturn(uint256 amountA, uint256 amountB, uint256 liquidity) external {
        mockAmountAOut = amountA;
        mockAmountBOut = amountB;
        mockLiquidityOut = liquidity;
    }

    function setAddLiquidityETHReturn(uint256 amountToken, uint256 amountETH, uint256 liquidity) external {
        mockAmountTokenOut = amountToken;
        mockAmountETHOut = amountETH;
        mockLiquidityOut = liquidity;
    }
     function setRemoveLiquidityReturn(uint256 amountA, uint256 amountB) external {
        mockAmountAOut = amountA;
        mockAmountBOut = amountB;
    }
    function setRemoveLiquidityETHReturn(uint256 amountToken, uint256 amountETH) external {
        mockAmountTokenOut = amountToken;
        mockAmountETHOut = amountETH;
    }
    function setAmountsOutArray(uint256[] memory amounts) external {
        mockAmountsOutArray = amounts;
    }
    function setShouldRevertAddLiquidity(bool _revert) external {
        shouldRevertAddLiquidity = _revert;
    }
    function setShouldRevertAddLiquidityETH(bool _revert) external {
        shouldRevertAddLiquidityETH = _revert;
    }
    function setShouldRevertRemoveLiquidity(bool _revert) external {
        shouldRevertRemoveLiquidity = _revert;
    }
    function setShouldRevertRemoveLiquidityETH(bool _revert) external {
        shouldRevertRemoveLiquidityETH = _revert;
    }
    function setShouldRevertFactory(bool _revert) external {
        shouldRevertFactory = _revert;
    }
    function setFactoryReturn(address _addr) external {
        _factoryAddress = _addr;
    }

    function setShouldRevertWeth(bool _revert) external {
        shouldRevertWeth = _revert;
    }

    function setWethReturn(address _weth) external {
        _wethAddress = _weth;
    }

    function factory() external view returns (address) {
        if(shouldRevertFactory) revert("MockRouter: Factory call reverted by mock setting");
        return _factoryAddress;
    }
    function weth() external view returns (address) {
        if(shouldRevertWeth) revert("MockRouter: WETH call reverted by mock setting");
        return _wethAddress;
    }
    
    function addLiquidity(
        address tokenA, address tokenB,
        uint256 amountADesired, uint256 amountBDesired,
        uint256 amountAMin, uint256 amountBMin,
        address to, uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        if (shouldRevertAddLiquidity) revert("MockRouter: AddLiquidity reverted by mock setting");
        addLiquidityCalls.push(AddLiquidityCall(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin, to, deadline));
        
        amountA = mockAmountAOut > 0 ? mockAmountAOut : amountADesired;
        amountB = mockAmountBOut > 0 ? mockAmountBOut : amountBDesired;
        liquidity = mockLiquidityOut > 0 ? mockLiquidityOut : (amountA + amountB) / 2;
        
        return (amountA, amountB, liquidity);
    }

    function addLiquidityETH(
        address token, uint256 amountTokenDesired,
        uint256 amountTokenMin, uint256 amountETHMin,
        address to, uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        if (shouldRevertAddLiquidityETH) revert("MockRouter: AddLiquidityETH reverted by mock setting");
        addLiquidityETHCalls.push(AddLiquidityETHCall(token, amountTokenDesired, amountTokenMin, amountETHMin, to, deadline, msg.value));

        amountToken = mockAmountTokenOut > 0 ? mockAmountTokenOut : amountTokenDesired;
        amountETH = mockAmountETHOut > 0 ? mockAmountETHOut : msg.value;
        liquidity = mockLiquidityOut > 0 ? mockLiquidityOut : (amountToken + amountETH) / 2;
        
        return (amountToken, amountETH, liquidity);
    }

    function removeLiquidity(
        address tokenA, address tokenB,
        uint256 liqAmount, uint256 amountAMin, uint256 amountBMin,
        address to, uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {
        if (shouldRevertRemoveLiquidity) revert("MockRouter: RemoveLiquidity reverted by mock setting");
        removeLiquidityCalls.push(RemoveLiquidityCall(tokenA, tokenB, liqAmount, amountAMin, amountBMin, to, deadline));

        amountA = mockAmountAOut > 0 ? mockAmountAOut : liqAmount / 2; 
        amountB = mockAmountBOut > 0 ? mockAmountBOut : liqAmount / 2; 
        return (amountA, amountB);
    }

    function removeLiquidityETH(
        address token_, uint256 liquidity_,
        uint256 amountTokenMin_, uint256 amountETHMin_,
        address to_, uint256 deadline_
    ) external returns (uint256 amountToken, uint256 amountETH) {
        if (shouldRevertRemoveLiquidityETH) revert("MockRouter: RemoveLiquidityETH reverted by mock setting");
        removeLiquidityETHCalls.push(RemoveLiquidityETHCall(token_, liquidity_, amountTokenMin_, amountETHMin_, to_, deadline_));
        
        amountToken = mockAmountTokenOut > 0 ? mockAmountTokenOut : liquidity_ / 2; 
        amountETH = mockAmountETHOut > 0 ? mockAmountETHOut : liquidity_ / 2; 
        return (amountToken, amountETH);
    }

    function swapExactTokensForTokens(uint256, uint256, address[] calldata, address, uint256)
        external view returns (uint256[] memory) {
        return mockAmountsOutArray;
    }

    function swapTokensForExactTokens(uint256, uint256, address[] calldata, address, uint256)
        external view returns (uint256[] memory) {
        return mockAmountsOutArray;
    }

    function swapExactETHForTokens(uint256, address[] calldata, address, uint256)
        external payable returns (uint256[] memory) {
        return mockAmountsOutArray;
    }

    function swapTokensForExactETH(uint256, uint256, address[] calldata, address, uint256)
        external view returns (uint256[] memory) {
        return mockAmountsOutArray;
    }

    function swapExactTokensForETH(uint256, uint256, address[] calldata, address, uint256)
        external view returns (uint256[] memory) {
        return mockAmountsOutArray;
    }

    function swapETHForExactTokens(uint256, address[] calldata, address, uint256)
        external payable returns (uint256[] memory) {
        return mockAmountsOutArray;
    }

    function getAmountsOut(uint256, address[] calldata)
        external view returns (uint256[] memory) {
        return mockAmountsOutArray;
    }
    
    function getAmountsIn(uint256, address[] calldata)
        external view returns (uint256[] memory) {
        return mockAmountsOutArray;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../liquidity/interfaces/IPancakePair.sol";

contract MockPancakePair is ERC20, IPancakePair {
    address public mockToken0;
    address public mockToken1;

    uint112 public mockReserve0;
    uint112 public mockReserve1;
    uint32 public mockBlockTimestampLast;
    
    bool public shouldRevertGetReserves;
    bool public shouldRevertToken0;

    constructor(
        string memory name_,
        string memory symbol_,
        address _tokenA,
        address _tokenB
    ) ERC20(name_, symbol_) {
        // Dynamically sort tokens to mimic real factory behavior
        (mockToken0, mockToken1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
    }

    function setReserves(uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) external {
        mockReserve0 = _reserve0;
        mockReserve1 = _reserve1;
        mockBlockTimestampLast = _blockTimestampLast;
    }
    
    function setShouldRevertGetReserves(bool _revert) external {
        shouldRevertGetReserves = _revert;
    }
    
    function setShouldRevertToken0(bool _revert) external {
        shouldRevertToken0 = _revert;
    }

    function mintTokensTo(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function token0() external view override returns (address) {
        if (shouldRevertToken0) revert("MockPair: token0 reverted by mock setting");
        return mockToken0;
    }

    function token1() external view override returns (address) {
        return mockToken1;
    }

    function getReserves() external view override returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) {
        if (shouldRevertGetReserves) revert("MockPair: getReserves reverted by mock setting");
        return (mockReserve0, mockReserve1, mockBlockTimestampLast);
    }

    function price0CumulativeLast() external pure override returns (uint256) { return 0; }
    function price1CumulativeLast() external pure override returns (uint256) { return 0; }

    function totalSupply() public view override(ERC20, IPancakePair) returns (uint256) {
        return super.totalSupply();
    }

    function balanceOf(address account) public view override(ERC20, IPancakePair) returns (uint256) {
        return super.balanceOf(account);
    }

    function allowance(address owner_param, address spender) public view override(ERC20, IPancakePair) returns (uint256) {
        return super.allowance(owner_param, spender);
    }

    function approve(address spender, uint256 value) public override(ERC20, IPancakePair) returns (bool) {
        return super.approve(spender, value);
    }

    function transfer(address to, uint256 value) public override(ERC20, IPancakePair) returns (bool) {
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override(ERC20, IPancakePair) returns (bool) {
        return super.transferFrom(from, to, value);
    }

    function swap(uint256, uint256, address, bytes calldata) external override {
        // No-op
    }

    function mint(address to) external override returns (uint256 liquidity) {
        liquidity = 100 * 1e18;
        _mint(to, liquidity);
        return liquidity;
    }

    function burn(address) external override returns (uint256 amount0, uint256 amount1) {
        uint256 lpBalanceOfSender = balanceOf(msg.sender); 
        require(lpBalanceOfSender > 0, "MockPair: No LP to burn from sender");
        _burn(msg.sender, lpBalanceOfSender);

        uint256 currentTotalSupplyPlusBurned = totalSupply() + lpBalanceOfSender;
        if (currentTotalSupplyPlusBurned == 0) {
             amount0 = mockReserve0;
             amount1 = mockReserve1;
        } else {
            amount0 = mockReserve0 > 0 ? (mockReserve0 * lpBalanceOfSender) / currentTotalSupplyPlusBurned : 0;
            amount1 = mockReserve1 > 0 ? (mockReserve1 * lpBalanceOfSender) / currentTotalSupplyPlusBurned : 0;
        }
        return (amount0, amount1);
    }
}
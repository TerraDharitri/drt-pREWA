pragma solidity ^0.8.28;

import "../liquidity/interfaces/IPancakeFactory.sol";

contract MockPancakeFactory is IPancakeFactory {
    mapping(address => mapping(address => address)) public mockPairs;
    address[] public allMockPairsArray;

    address public mockFeeTo;
    address public mockFeeToSetter;
    
    bool public shouldRevertGetPair;
    bool public shouldRevertCreatePair;
    address public getPairReturnAddress = address(0);
    address public createPairReturnAddress = address(0);
    string public revertReason;
    string public revertType;

    event MockPairCreated(address tokenA, address tokenB, address pair, uint allPairsLength);

    function setPair(address tokenA, address tokenB, address pairAddress) external {
        require(tokenA != tokenB, "MockFactory: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        
        address currentPair = mockPairs[token0][token1];
        if (currentPair != address(0) && currentPair != pairAddress) {
            // Remove from array if replacing
            for (uint i = 0; i < allMockPairsArray.length; i++) {
                if (allMockPairsArray[i] == currentPair) {
                    allMockPairsArray[i] = allMockPairsArray[allMockPairsArray.length - 1];
                    allMockPairsArray.pop();
                    break;
                }
            }
        }
        
        mockPairs[token0][token1] = pairAddress;
        
        bool exists = false;
        for(uint i=0; i < allMockPairsArray.length; i++){
            if(allMockPairsArray[i] == pairAddress) {
                exists = true;
                break;
            }
        }
        if(!exists && pairAddress != address(0)) {
            allMockPairsArray.push(pairAddress);
        }
    }
    
    function setFeeTo(address _feeTo) external override {
        mockFeeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external override {
        mockFeeToSetter = _feeToSetter;
    }

    function setShouldRevertGetPair(bool _revert) external {
        shouldRevertGetPair = _revert;
    }

    function setShouldRevertCreatePair(bool _revert) external {
        shouldRevertCreatePair = _revert;
    }
    
    function setCreatePairReturnAddress(address _addr) external {
        createPairReturnAddress = _addr;
    }
    
    function setCreatePairRevertDetails(string memory _revertType, string memory _revertReason) external {
        shouldRevertCreatePair = true;
        revertType = _revertType;
        revertReason = _revertReason;
    }

    function setGetPairReturn(address _addr) external {
        getPairReturnAddress = _addr;
    }

    function getPair(address tokenA, address tokenB) external view override returns (address pair) {
        if(shouldRevertGetPair) revert("MockFactory: getPair reverted by mock setting");
        if (getPairReturnAddress != address(0)) return getPairReturnAddress;
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return mockPairs[token0][token1];
    }

    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        if(shouldRevertCreatePair) {
            if (bytes(revertType).length > 0) {
                if (keccak256(bytes(revertType)) == keccak256(bytes("Error(string)"))) {
                    revert(revertReason);
                } else if (keccak256(bytes(revertType)) == keccak256(bytes("Panic(uint256)"))) {
                    revert(revertReason); // Simplified for mock; actual panic is harder to trigger
                }
            }
            revert("MockFactory: createPair reverted by mock setting");
        }
        require(tokenA != tokenB, "MockFactory: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(mockPairs[token0][token1] == address(0), "MockFactory: PAIR_EXISTS");

        if (createPairReturnAddress != address(0)) {
            pair = createPairReturnAddress;
        } else {
            pair = address(uint160(uint256(keccak256(abi.encodePacked(token0, token1)))));
        }

        mockPairs[token0][token1] = pair;
        allMockPairsArray.push(pair);
        emit MockPairCreated(tokenA, tokenB, pair, allMockPairsArray.length);
        return pair;
    }
    
    function feeTo() external view override returns (address) {
        return mockFeeTo;
    }

    function feeToSetter() external view override returns (address) {
        return mockFeeToSetter;
    }

    function allPairsLength() external view override returns (uint) {
        return allMockPairsArray.length;
    }

    function allPairs(uint index) external view override returns (address pair) {
        require(index < allMockPairsArray.length, "MockFactory: Index out of bounds");
        return allMockPairsArray[index];
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../core/interfaces/IpREWAToken.sol"; 
import "../interfaces/IEmergencyAware.sol";   

contract MockERC20 is Initializable, ERC20Upgradeable, OwnableUpgradeable, IpREWAToken {
    bool private _isPausedInternal;
    mapping(address => bool) private _isBlacklistedAccount;
    address private _emergencyControllerAddress;
    uint256 private _capAmount;
    mapping(address => bool) private _isMinterAccount;

    struct MockBlacklistProposal {
        bool pending;
        uint256 executeAfterTimestamp;
        uint256 timeRemainingSec;
    }
    mapping(address => MockBlacklistProposal) public mockBlacklistProposals;
    uint256 public mockBlacklistTimelockDuration;

    uint8 private _forcedMockDecimals;
    bool private _decimalsForced;
    bool public shouldRevert = false;
    bool public shouldRevertDecimals = false;
    
    // The initializer modifier in mockInitialize is sufficient.

    function mockInitialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_, 
        address initialOwner_
    ) public initializer {
        __ERC20_init(name_, symbol_);
        __Ownable_init(); 
        if (initialOwner_ != address(0)) { 
            transferOwnership(initialOwner_);
        }
        _forcedMockDecimals = decimals_; 
        _decimalsForced = true;
    }

    function name() public view virtual override(ERC20Upgradeable, IpREWAToken) returns (string memory) {
        return super.name();
    }

    function symbol() public view virtual override(ERC20Upgradeable, IpREWAToken) returns (string memory) {
        return super.symbol();
    }

    function decimals() public view virtual override(ERC20Upgradeable, IpREWAToken) returns (uint8) {
        if (shouldRevertDecimals) {
            revert("MockERC20: decimals call reverted");
        }
        if (_decimalsForced) {
            return _forcedMockDecimals;
        }
        return super.decimals();
    }

    function totalSupply() public view virtual override(ERC20Upgradeable, IERC20Upgradeable) returns (uint256) {
        return super.totalSupply();
    }

    function balanceOf(address account) public view virtual override(ERC20Upgradeable, IERC20Upgradeable) returns (uint256) {
        if (shouldRevert) {
            revert("MockERC20: Forced revert");
        }
        return super.balanceOf(account);
    }

    function transfer(address recipient, uint256 amount) public virtual override(ERC20Upgradeable, IERC20Upgradeable) returns (bool) {
        _checkPausedAndBlacklisted(msg.sender, recipient);
        return super.transfer(recipient, amount);
    }

    function allowance(address ownerAccount, address spender) public view virtual override(ERC20Upgradeable, IERC20Upgradeable) returns (uint256) {
        return super.allowance(ownerAccount, spender);
    }

    function approve(address spender, uint256 amount) public virtual override(ERC20Upgradeable, IERC20Upgradeable) returns (bool) {
        _checkPausedAndBlacklisted(msg.sender, spender);
        return super.approve(spender, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override(ERC20Upgradeable, IERC20Upgradeable) returns (bool) {
        _checkPausedAndBlacklisted(sender, recipient);
        _spendAllowance(sender, msg.sender, amount);
        _transfer(sender, recipient, amount);
        return true;
    }

    function _checkPausedAndBlacklisted(address fromToCheck, address toToCheck) internal view {
        require(!paused(), "MockERC20: Paused");
        if (fromToCheck != address(0)) {
            require(!isBlacklisted(fromToCheck), "MockERC20: 'From' account blacklisted");
        }
        if (toToCheck != address(0)) {
            require(!isBlacklisted(toToCheck), "MockERC20: 'To' account blacklisted");
        }
    }

    function mint(address to, uint256 amount) public virtual override(IpREWAToken) returns (bool) {
        require(_isMinterAccount[msg.sender] || msg.sender == owner(), "MockERC20: Caller is not a minter or owner for mint");
        _checkPausedAndBlacklisted(address(0), to);
        if (_capAmount > 0 && totalSupply() + amount > _capAmount) {
            revert("MockERC20: Cap exceeded");
        }
        _mint(to, amount);
        return true;
    }

    function burn(uint256 amount) public virtual override(IpREWAToken) returns (bool) {
        _checkPausedAndBlacklisted(msg.sender, address(0));
        _burn(msg.sender, amount);
        return true;
    }

    function burnFrom(address account, uint256 amount) public virtual override(IpREWAToken) returns (bool) {
        _checkPausedAndBlacklisted(account, address(0));
        address spender = msg.sender;
        _spendAllowance(account, spender, amount); 
        _burn(account, amount); 
        return true;
    }

    function pause() public virtual override(IpREWAToken) returns (bool) {
        require(msg.sender == owner(), "MockERC20: Not owner");
        _isPausedInternal = true;
        return true;
    }

    function unpause() public virtual override(IpREWAToken) returns (bool) {
        require(msg.sender == owner(), "MockERC20: Not owner");
        _isPausedInternal = false;
        return true;
    }

    function blacklist(address account) public virtual override(IpREWAToken) returns (bool) {
        require(msg.sender == owner(), "MockERC20: Not owner");
        _isBlacklistedAccount[account] = true;
        emit BlacklistStatusChanged(account, true, msg.sender);
        return true;
    }

    function unblacklist(address account) public virtual override(IpREWAToken) returns (bool) {
        require(msg.sender == owner(), "MockERC20: Not owner");
        _isBlacklistedAccount[account] = false;
        emit BlacklistStatusChanged(account, false, msg.sender);
        return true;
    }

    function isBlacklisted(address account) public view virtual override(IpREWAToken) returns (bool) {
        return _isBlacklistedAccount[account];
    }

    function paused() public view virtual override(IpREWAToken) returns (bool isTokenPaused) {
        return _isPausedInternal;
    }

    function cap() external view virtual override(IpREWAToken) returns (uint256) {
        return _capAmount;
    }

    function setCap(uint256 newCapAmount) public virtual override(IpREWAToken) returns (bool) {
        require(msg.sender == owner(), "MockERC20: Not owner");
        if (newCapAmount != 0 && newCapAmount < totalSupply()) {
            revert("MockERC20: new cap less than total supply");
        }
        uint256 oldCap = _capAmount;
        _capAmount = newCapAmount;
        emit CapUpdated(oldCap, newCapAmount, msg.sender);
        return true;
    }

    function recoverTokens(address tokenAddress, uint256 amount) external virtual override(IpREWAToken) returns (bool) {
        require(msg.sender == owner(), "MockERC20: Not owner");
        emit TokenRecovered(tokenAddress, amount, owner());
        return true;
    }

    function addMinter(address minterAddress) external virtual override(IpREWAToken) returns (bool) {
        require(msg.sender == owner(), "MockERC20: Not owner");
        _isMinterAccount[minterAddress] = true;
        emit MinterStatusChanged(minterAddress, true, msg.sender);
        return true;
    }

    function removeMinter(address minterAddress) external virtual override(IpREWAToken) returns (bool) {
        require(msg.sender == owner(), "MockERC20: Not owner");
        _isMinterAccount[minterAddress] = false;
        emit MinterStatusChanged(minterAddress, false, msg.sender);
        return true;
    }

    function isMinter(address account) external view virtual override(IpREWAToken) returns (bool) {
        return _isMinterAccount[account];
    }

    function transferTokenOwnership(address newOwnerAddress) external virtual override(IpREWAToken) returns (bool) {
        address oldOwner = owner(); 
        super.transferOwnership(newOwnerAddress); 
        emit TokenOwnershipTransferred(oldOwner, newOwnerAddress, msg.sender);
        return true;
    }

    function owner() public view virtual override(OwnableUpgradeable, IpREWAToken) returns (address) {
        return super.owner();
    }

    function getBlacklistProposal(address account) external view virtual override(IpREWAToken) returns (
        bool proposalExists, uint256 executeAfterTimestamp, uint256 timeRemainingSec
    ) {
        MockBlacklistProposal storage proposal = mockBlacklistProposals[account];
        return (proposal.pending, proposal.executeAfterTimestamp, proposal.timeRemainingSec);
    }

    function getBlacklistTimelockDuration() external view virtual override(IpREWAToken) returns (uint256) {
        return mockBlacklistTimelockDuration;
    }

    function setBlacklistTimelockDuration(uint256 newDurationSeconds) external virtual override(IpREWAToken) returns (bool success) {
        require(msg.sender == owner(), "MockERC20: Not owner");
        uint256 oldDuration = mockBlacklistTimelockDuration;
        mockBlacklistTimelockDuration = newDurationSeconds;
        emit BlacklistTimelockDurationUpdated(oldDuration, newDurationSeconds, msg.sender);
        return true;
    }

    function executeBlacklist(address account) external virtual override(IpREWAToken) returns (bool) {
        require(msg.sender == owner(), "MockERC20: Not owner");
        require(mockBlacklistProposals[account].pending, "Mock: No proposal");
        require(block.timestamp >= mockBlacklistProposals[account].executeAfterTimestamp, "Mock: Timelock active");
        _isBlacklistedAccount[account] = true;
        mockBlacklistProposals[account].pending = false;
        emit BlacklistStatusChanged(account, true, msg.sender);
        return true;
    }

    function cancelBlacklistProposal(address account) external virtual override(IpREWAToken) returns (bool) {
        require(msg.sender == owner(), "MockERC20: Not owner");
        require(mockBlacklistProposals[account].pending, "Mock: No proposal");
        mockBlacklistProposals[account].pending = false;
        emit BlacklistCancelled(account, msg.sender);
        return true;
    }

    function checkEmergencyStatus(bytes4) external view virtual override(IEmergencyAware) returns (bool allowed) {
        return !paused();
    }

    function emergencyShutdown(uint8 emergencyLevel) external virtual override(IEmergencyAware) returns (bool success) {
        if (emergencyLevel >= 3) { 
            _isPausedInternal = true;
        }
        emit EmergencyShutdownHandled(emergencyLevel, msg.sender); 
        return true;
    }

    function getEmergencyController() external view virtual override(IEmergencyAware) returns (address controller) {
        return _emergencyControllerAddress;
    }

    function setEmergencyController(address controller) external virtual override(IEmergencyAware) returns (bool success) {
        require(msg.sender == owner(), "MockERC20: Not owner to set EC");
        _emergencyControllerAddress = controller;
        return true;
    }
    
    function isEmergencyPaused() external view virtual override(IEmergencyAware) returns (bool isPausedStatus) {
        return paused();
    }

    function mintForTest(address to, uint256 amount) external {
        _checkPausedAndBlacklisted(address(0), to); 
        _mint(to, amount);
    }

    function setPausedByAdmin(bool newPausedState) external {
        require(msg.sender == owner(), "MockERC20: Not owner");
        _isPausedInternal = newPausedState;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setShouldRevertDecimals(bool _shouldRevert) external {
        shouldRevertDecimals = _shouldRevert;
    }
}
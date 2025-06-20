// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol"; 
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./storage/pREWATokenStorage.sol";
import "./interfaces/IpREWAToken.sol";
import "../interfaces/IEmergencyAware.sol";
import "../controllers/EmergencyController.sol";
import "../access/AccessControl.sol";
import "../libraries/Constants.sol";
import "../libraries/Errors.sol";
import "../utils/EmergencyAwareBase.sol";

/**
 * @title PREWAToken
 * @author Rewa
 * @notice The platform's primary ERC20 token, with minting, burning, pausing, and blacklisting capabilities.
 * @dev This is an upgradeable ERC20 token contract. It includes features like a supply cap, role-based minter access,
 * and a timelocked blacklisting mechanism for enhanced security. It integrates with AccessControl and an
 * EmergencyController, and inherits from EmergencyAwareBase.
 */
contract PREWAToken is
    Initializable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable, 
    PREWATokenStorage,
    IpREWAToken,
    EmergencyAwareBase
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice The contract that controls roles and permissions.
    AccessControl public accessControl;

    /**
     * @notice Emitted when the EmergencyController address is changed.
     * @param oldController The previous controller address.
     * @param newController The new controller address.
     * @param setter The address that performed the update.
     */
    event EmergencyControllerSet(address indexed oldController, address indexed newController, address indexed setter);

    /**
     * @dev Disables the regular constructor to make the contract upgradeable.
     */
    constructor() {
        _disableInitializers();
    }
   
    /**
     * @notice Initializes the PREWAToken contract.
     * @dev Sets up the token's properties, initial supply, cap, and administrative contracts.
     * Can only be called once.
     * @param name_ The name of the token.
     * @param symbol_ The symbol of the token.
     * @param decimals_ The number of decimals for the token.
     * @param initialSupply_ The amount of tokens to mint to the admin upon initialization.
     * @param cap_ The maximum total supply for the token. Use 0 for no cap.
     * @param accessControlAddress_ The address of the AccessControl contract.
     * @param emergencyControllerAddress_ The address of the EmergencyController contract.
     * @param admin_ The initial owner and first minter of the token.
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 initialSupply_,
        uint256 cap_,
        address accessControlAddress_,
        address emergencyControllerAddress_,
        address admin_
    ) external initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init(); 

        if (admin_ == address(0)) revert ZeroAddress("admin_");
        if (accessControlAddress_ == address(0)) revert PREWA_ACZero();
        if (emergencyControllerAddress_ == address(0)) revert PREWA_ECZero();
        if (bytes(name_).length == 0) revert PREWA_NameEmpty();
        if (bytes(symbol_).length == 0) revert PREWA_SymbolEmpty();
        if (decimals_ == 0 || decimals_ > 18) revert PREWA_DecimalsZero(); 

        uint256 codeSize;
        assembly { codeSize := extcodesize(accessControlAddress_) }
        if (codeSize == 0) revert NotAContract("accessControl");
        assembly { codeSize := extcodesize(emergencyControllerAddress_) }
        if (codeSize == 0) revert NotAContract("emergencyController");

        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _cap = cap_;
        
        _transferOwnership(admin_); 

        accessControl = AccessControl(accessControlAddress_);
        emergencyController = EmergencyController(emergencyControllerAddress_);

        _minters[admin_] = true;
        _blacklistTimelockDuration = 1 days;

        if (initialSupply_ > 0) {
            _mint(admin_, initialSupply_);
        }
    }

    /**
     * @dev Modifier to restrict access to functions to addresses with the PAUSER_ROLE.
     */
    modifier onlyPauserRole() {
        if (address(accessControl) == address(0)) revert PREWA_ACZero();
        if (!accessControl.hasRole(accessControl.PAUSER_ROLE(), msg.sender)) revert PREWA_MustHavePauserRole();
        _;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function name() external view override returns (string memory) { return _name; }

    /**
     * @inheritdoc IpREWAToken
     */
    function symbol() external view override returns (string memory) { return _symbol; }

    /**
     * @inheritdoc IpREWAToken
     */
    function decimals() external view override returns (uint8) { return _decimals; }

    /**
     * @inheritdoc IERC20Upgradeable
     */
    function totalSupply() external view override returns (uint256) { return _totalSupply; }

    /**
     * @inheritdoc IERC20Upgradeable
     */
    function balanceOf(address account) external view override returns (uint256) {
        if (account == address(0)) return 0;
        return _balances[account];
    }

    /**
     * @inheritdoc IERC20Upgradeable
     */
    function allowance(address ownerAddress, address spenderAddress) external view override returns (uint256) {
        if (ownerAddress == address(0) || spenderAddress == address(0)) return 0;
        return _allowances[ownerAddress][spenderAddress];
    }

    /**
     * @inheritdoc IERC20Upgradeable
     */
    function transfer(address to, uint256 amount) public override nonReentrant whenNotPaused returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /**
     * @inheritdoc IERC20Upgradeable
     */
    function approve(address spender, uint256 amount) public override nonReentrant returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /**
     * @inheritdoc IERC20Upgradeable
     */
    function transferFrom(address from, address to, uint256 amount) public override nonReentrant whenNotPaused returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function mint(address to, uint256 amount) external override nonReentrant whenNotPaused returns (bool) {
        if (!_minters[msg.sender]) revert PREWA_NotMinter();
        _mint(to, amount);
        return true;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function burn(uint256 amount) external override nonReentrant whenNotPaused returns (bool) {
        _burn(msg.sender, amount);
        return true;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function burnFrom(address account, uint256 amount) external override nonReentrant whenNotPaused returns (bool) {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
        return true;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function pause() external override onlyPauserRole nonReentrant returns (bool) {
        _pause();
        return true;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function unpause() external override onlyPauserRole nonReentrant returns (bool) {
        _unpause();
        return true;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function blacklist(address account) external override onlyOwner nonReentrant returns (bool) {
        if (account == address(0)) revert PREWA_AccountBlacklistZero();
        if (_blacklisted[account]) revert PREWA_AccountAlreadyBlacklisted(account);
        uint256 currentTimelockDuration = _blacklistTimelockDuration;
        if (currentTimelockDuration == 0) {
            _blacklisted[account] = true;
            emit BlacklistStatusChanged(account, true, msg.sender);
        } else {
            if (_blacklistProposals[account].pending) revert PREWA_BlacklistPropExists(account);
            uint256 executeTime = block.timestamp + currentTimelockDuration;
            _blacklistProposals[account] = BlacklistProposal(block.timestamp, executeTime, msg.sender, true);
            emit BlacklistProposed(account, executeTime, msg.sender);
        }
        return true;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function executeBlacklist(address account) external override onlyOwner nonReentrant returns (bool successFlag) {
        if (account == address(0)) revert PREWA_AccountBlacklistZero();
        BlacklistProposal storage proposal = _blacklistProposals[account];
        if (!proposal.pending) revert PREWA_NoBlacklistProp(account);
        if (block.timestamp < proposal.executeAfter) revert PREWA_TimelockActive();
        delete _blacklistProposals[account];
        _blacklisted[account] = true;
        emit BlacklistStatusChanged(account, true, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function cancelBlacklistProposal(address account) external override onlyOwner nonReentrant returns (bool successFlag) {
        if (account == address(0)) revert PREWA_AccountBlacklistZero();
        BlacklistProposal storage proposal = _blacklistProposals[account];
        if (!proposal.pending) revert PREWA_NoBlacklistProp(account);
        delete _blacklistProposals[account];
        emit BlacklistCancelled(account, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function unblacklist(address account) external override onlyOwner nonReentrant returns (bool) {
        if (account == address(0)) revert PREWA_AccountBlacklistZero();
        if (!_blacklisted[account]) revert PREWA_AccountNotBlacklisted(account);
        _blacklisted[account] = false;
        if (_blacklistProposals[account].pending) {
            delete _blacklistProposals[account];
            emit BlacklistCancelled(account, msg.sender);
        }
        emit BlacklistStatusChanged(account, false, msg.sender);
        return true;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function isBlacklisted(address account) external view override returns (bool isAccBlacklisted) {
        if (account == address(0)) return false;
        isAccBlacklisted = _blacklisted[account];
        return isAccBlacklisted;
    }

    /**
     * @inheritdoc IpREWAToken
     * @dev Returns true if the token is paused locally or if the global `EmergencyController` has paused the system.
     */
    function paused() public view override(IpREWAToken, PausableUpgradeable) returns (bool isTokenPaused) {
        isTokenPaused = PausableUpgradeable.paused() || _isEffectivelyPaused();
        return isTokenPaused;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function cap() external view override returns (uint256 currentCap) {
        currentCap = _cap;
        return currentCap;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function setCap(uint256 newCapAmount) external override onlyOwner nonReentrant returns (bool) {
        if (_cap != 0 && newCapAmount != 0 && newCapAmount < _totalSupply) {
            revert PREWA_CapLessThanSupply(newCapAmount, _totalSupply);
        }
        uint256 oldCap = _cap;
        _cap = newCapAmount;
        emit CapUpdated(oldCap, newCapAmount, msg.sender);
        return true;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function recoverTokens(address tokenAddr, uint256 amountVal) external override onlyOwner nonReentrant returns (bool) {
        if (tokenAddr == address(0)) revert PREWA_BadTokenRecoveryAddress();
        if (tokenAddr == address(this)) revert PREWA_CannotRecoverSelf();
        if (amountVal == 0) revert AmountIsZero();
        IERC20Upgradeable token = IERC20Upgradeable(tokenAddr);
        uint256 balance = token.balanceOf(address(this));
        if (amountVal > balance) revert InsufficientBalance(balance, amountVal);
        token.safeTransfer(owner(), amountVal);
        emit TokenRecovered(tokenAddr, amountVal, owner());
        return true;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function addMinter(address minterAddress) external override onlyOwner nonReentrant returns (bool) {
        if (minterAddress == address(0)) revert PREWA_MinterAddressZero();
        if (_minters[minterAddress]) revert PREWA_AddressAlreadyMinter(minterAddress);
        _minters[minterAddress] = true;
        emit MinterStatusChanged(minterAddress, true, msg.sender);
        return true;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function removeMinter(address minterAddress) external override onlyOwner nonReentrant returns (bool) {
        if (minterAddress == address(0)) revert PREWA_MinterAddressZero();
        if (!_minters[minterAddress]) revert PREWA_AddressNotMinter(minterAddress);
        _minters[minterAddress] = false;
        emit MinterStatusChanged(minterAddress, false, msg.sender);
        return true;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function isMinter(address account) external view override returns (bool isAccMinter) {
        if (account == address(0)) return false;
        isAccMinter = _minters[account];
        return isAccMinter;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function transferTokenOwnership(address newOwnerAddress) external override nonReentrant returns (bool successFlag) {
        address oldOwner = owner();
        super.transferOwnership(newOwnerAddress);
        emit TokenOwnershipTransferred(oldOwner, newOwnerAddress, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function owner() public view override(OwnableUpgradeable, IpREWAToken) returns (address) {
        return super.owner();
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function getBlacklistProposal(address account) external view override returns (
        bool proposalExists,
        uint256 executeAfterTimestamp,
        uint256 timeRemainingSec
    ) {
        if (account == address(0)) return (false, 0, 0);
        BlacklistProposal storage proposal = _blacklistProposals[account];
        proposalExists = proposal.pending;
        if (!proposalExists) return (false, 0, 0);
        executeAfterTimestamp = proposal.executeAfter;
        timeRemainingSec = (block.timestamp < proposal.executeAfter) ? proposal.executeAfter - block.timestamp : 0;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function getBlacklistTimelockDuration() external view override returns (uint256 durationSeconds) {
        durationSeconds = _blacklistTimelockDuration;
        return durationSeconds;
    }

    /**
     * @inheritdoc IpREWAToken
     */
    function setBlacklistTimelockDuration(uint256 newDurationSeconds) external override onlyOwner nonReentrant returns (bool successFlag) {
        if (newDurationSeconds != 0 && (newDurationSeconds < Constants.MIN_TIMELOCK_DURATION || newDurationSeconds > Constants.MAX_TIMELOCK_DURATION)) {
             revert PREWA_TimelockDurationInvalid(newDurationSeconds);
        }
        uint256 oldDuration = _blacklistTimelockDuration;
        _blacklistTimelockDuration = newDurationSeconds;
        emit BlacklistTimelockDurationUpdated(oldDuration, newDurationSeconds, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Renouncing ownership is disabled for this contract to prevent accidental loss of control.
     * @dev Always reverts. This is a deliberate security design choice.
     */
    function renounceOwnership() public view override onlyOwner {
        revert("pREWAToken: renounceOwnership is permanently disabled for security reasons");
    }

    /**
     * @dev Internal function to handle token transfers, including blacklist checks.
     * @param from The address sending tokens.
     * @param to The address receiving tokens.
     * @param amount The amount of tokens being transferred.
     */
    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0)) revert PREWA_TransferFromZero();
        if (to == address(0)) revert PREWA_TransferToZero();
        if (_blacklisted[from]) revert PREWA_SenderBlacklisted(from);
        if (_blacklisted[to]) revert PREWA_RecipientBlacklisted(to);
        if (amount == 0) {
             emit Transfer(from, to, 0);
             return;
        }
        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) revert InsufficientBalance(fromBalance, amount);
        unchecked { _balances[from] = fromBalance - amount; }
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    /**
     * @dev Internal function to handle approvals, including blacklist checks.
     * @param ownerApproval The address granting the allowance.
     * @param spenderApproval The address being granted the allowance.
     * @param amountApproval The allowance amount.
     */
    function _approve(address ownerApproval, address spenderApproval, uint256 amountApproval) internal {
        if (ownerApproval == address(0)) revert ZeroAddress("ownerApproval");
        if (spenderApproval == address(0)) revert ZeroAddress("spenderApproval");
        if (_blacklisted[ownerApproval]) revert PREWA_OwnerBlacklisted(ownerApproval);
        if (_blacklisted[spenderApproval]) revert PREWA_SpenderBlacklisted(spenderApproval);

        _allowances[ownerApproval][spenderApproval] = amountApproval;
        emit Approval(ownerApproval, spenderApproval, amountApproval);
    }

    /**
     * @dev Internal function to spend an allowance.
     * @param ownerSpend The address of the token owner.
     * @param spenderSpend The address of the spender.
     * @param amountSpend The amount to spend.
     */
    function _spendAllowance(address ownerSpend, address spenderSpend, uint256 amountSpend) internal {
        uint256 currentAllowance = _allowances[ownerSpend][spenderSpend];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amountSpend) revert InsufficientAllowance(currentAllowance, amountSpend);
            unchecked { _allowances[ownerSpend][spenderSpend] = currentAllowance - amountSpend; }
        }
    }

    /**
     * @dev Internal function to mint new tokens, checking cap and blacklist.
     * @param to The recipient of the new tokens.
     * @param amount The amount to mint.
     */
    function _mint(address to, uint256 amount) internal {
        if (to == address(0)) revert PREWA_MintToZero();
        if (_blacklisted[to]) revert PREWA_RecipientBlacklisted(to);
        if (amount == 0) revert AmountIsZero();
        if (_cap > 0) {
            if (_totalSupply + amount > _cap) revert CapExceeded(_totalSupply, amount, _cap);
        }
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    /**
     * @dev Internal function to burn tokens, checking blacklist.
     * @param from The address from which to burn tokens.
     * @param amount The amount to burn.
     */
    function _burn(address from, uint256 amount) internal {
        if (from == address(0)) revert PREWA_BurnFromZero();
        if (_blacklisted[from]) revert PREWA_SenderBlacklisted(from);
        if (amount == 0) revert AmountIsZero();
        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) revert InsufficientBalance(fromBalance, amount);
        unchecked {
            _balances[from] = fromBalance - amount;
            _totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function checkEmergencyStatus(bytes4 ) external view override returns (bool allowed) {
        allowed = !paused();
        return allowed;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function emergencyShutdown(uint8 emergencyLevelInput) external override returns (bool successFlag) {
        if (address(emergencyController) == address(0)) revert PREWA_CallerNotEmergencyController();
        if (msg.sender != address(emergencyController)) revert PREWA_CallerNotEmergencyController();
        if (emergencyLevelInput >= Constants.EMERGENCY_LEVEL_CRITICAL && !PausableUpgradeable.paused()) {
            _pause();
        }
        emit EmergencyShutdownHandled(emergencyLevelInput, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function getEmergencyController() external view override returns (address controllerAddress) {
        controllerAddress = address(emergencyController);
        return controllerAddress;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function setEmergencyController(address controllerAddr) external override onlyOwner returns (bool successFlag) {
        if (controllerAddr == address(0)) revert PREWA_ECZero();
        uint256 codeSize;
        assembly { codeSize := extcodesize(controllerAddr) }
        if (codeSize == 0) revert NotAContract("emergencyController");
        address oldController = address(emergencyController);
        emergencyController = EmergencyController(controllerAddr);
        emit EmergencyControllerSet(oldController, controllerAddr, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @inheritdoc IEmergencyAware
     */
    function isEmergencyPaused() external view override returns (bool isPausedStatus) {
        isPausedStatus = paused();
        return isPausedStatus;
    }
}
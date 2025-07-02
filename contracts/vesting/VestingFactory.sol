// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol"; 
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../proxy/TransparentProxy.sol"; 
import "./interfaces/IVesting.sol"; 
import "./interfaces/IVestingFactory.sol"; 
import "../libraries/Errors.sol"; 
import "../libraries/Constants.sol";

/**
 * @title VestingFactory
 * @author Rewa
 * @notice A factory for creating and tracking token vesting contracts.
 * @dev This contract deploys new `VestingImplementation` contracts behind transparent proxies.
 * It keeps track of all created vesting schedules, indexed by beneficiary and owner.
 * The factory owner can update the implementation address for new deployments.
 */
contract VestingFactory is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IVestingFactory
{
    using SafeERC20Upgradeable for IERC20Upgradeable; 

    /// @notice The pREWA token contract used for all vesting schedules.
    IERC20Upgradeable public pREWAToken; 
    /// @notice The address of the logic contract (`VestingImplementation`) for new proxies.
    address public vestingImplementation;
    /// @notice The address of the admin for all created proxies (typically a `ProxyAdmin` contract).
    address public proxyAdminAddress; 

    /// @dev A mapping from a beneficiary address to an array of their vesting contract addresses.
    mapping(address => address[]) private _vestingsByBeneficiary;
    /// @dev A mapping from an owner address to an array of vesting contracts they created.
    mapping(address => address[]) private _vestingsByOwner;
    /// @dev An array of all vesting contract addresses created by this factory.
    address[] private _allVestingContracts;

    /**
     * @dev A reentrancy lock specific to a `(creator, beneficiary)` pair.
     * This prevents a user from initiating a second vesting creation for the same beneficiary
     * while the first one is still in progress, closing a potential reentrancy attack vector.
     */
    mapping(address => mapping(address => bool)) private _vestingCreationInProgress;

    /**
     * @notice Emitted when the vesting implementation address is updated.
     * @param oldImplementation The previous implementation address.
     * @param newImplementation The new implementation address.
     * @param updater The address that performed the update.
     */
    event ImplementationUpdated(address indexed oldImplementation, address indexed newImplementation, address indexed updater);
    /**
     * @notice Emitted when the proxy admin address is updated.
     * @param oldProxyAdmin The previous proxy admin address.
     * @param newProxyAdmin The new proxy admin address.
     * @param updater The address that performed the update.
     */
    event ProxyAdminUpdated(address indexed oldProxyAdmin, address indexed newProxyAdmin, address indexed updater);

    /**
     * @notice Thrown if the vesting amount exceeds the maximum allowed limit.
     * @param amount The requested amount.
     * @param maxAmount The maximum allowed amount.
     */
    error Vesting_AmountExceedsMax(uint256 amount, uint256 maxAmount);

    /**
     * @dev Disables the regular constructor to make the contract upgradeable.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the VestingFactory contract.
     * @dev Sets the owner, token address, initial implementation, and proxy admin. Can only be called once.
     * @param initialOwner_ The initial owner of the factory.
     * @param pREWATokenAddress_ The address of the pREWA token to be vested.
     * @param initialVestingImplementation_ The initial implementation address for vesting contracts.
     * @param adminForProxies_ The admin address for the created proxies.
     */
    function initialize(
        address initialOwner_,
        address pREWATokenAddress_,
        address initialVestingImplementation_,
        address adminForProxies_
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        if (initialOwner_ == address(0)) revert ZeroAddress("initialOwner_");
        if (pREWATokenAddress_ == address(0)) revert Vesting_TokenZero(); 
        if (initialVestingImplementation_ == address(0)) revert ZeroAddress("initialVestingImplementation_");
        if (adminForProxies_ == address(0)) revert ZeroAddress("adminForProxies_");

        pREWAToken = IERC20Upgradeable(pREWATokenAddress_);
        vestingImplementation = initialVestingImplementation_;
        proxyAdminAddress = adminForProxies_;

        _transferOwnership(initialOwner_); 
    }

    /**
     * @inheritdoc IVestingFactory
     * @dev This function is reentrancy-proof by implementing a specific lock (`_vestingCreationInProgress`).
     * It strictly follows the Checks-Effects-Interactions (CEI) principle to prevent state inconsistencies
     * during external calls.
     */
    function createVesting(
        address beneficiary,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 duration,
        bool revocable,
        uint256 amount
    ) 
        external 
        override 
        returns (address vestingAddress)
    {
        // --- 1. CHECKS ---
        if (vestingImplementation == address(0)) revert ZeroAddress("Vesting implementation not set");
        if (beneficiary == address(0)) revert Vesting_BeneficiaryZero();
        if (amount == 0) revert Vesting_AmountZeroV();
        if (amount > Constants.MAX_VESTING_AMOUNT) revert Vesting_AmountExceedsMax(amount, Constants.MAX_VESTING_AMOUNT);
        if (duration == 0) revert Vesting_DurationZero();
        if (cliffDuration > duration) revert Vesting_CliffLongerThanDuration();
        if (duration < Constants.MIN_VESTING_DURATION || duration > Constants.MAX_VESTING_DURATION) revert InvalidDuration();
        if (startTime != 0 && startTime < block.timestamp) revert Vesting_StartTimeInvalid(); 

        if (_vestingCreationInProgress[msg.sender][beneficiary]) revert("Vesting creation for this beneficiary is already in progress");

        // --- 2. EFFECTS (Phase 1: Set the Lock) ---
        // This lock is set before any external calls to prevent reentrancy.
        _vestingCreationInProgress[msg.sender][beneficiary] = true;

        // --- 3. INTERACTIONS (Phase 1: Create Proxy & Transfer) ---
        // External call to deploy the proxy contract.
        TransparentProxy proxy = new TransparentProxy(
            vestingImplementation,
            proxyAdminAddress, 
            bytes("") 
        );
        vestingAddress = address(proxy);
        
        // External call to transfer tokens to the new proxy.
        pREWAToken.safeTransferFrom(msg.sender, vestingAddress, amount);
        
        // External call to initialize the new proxy.
        uint256 actualStartTime = (startTime == 0) ? block.timestamp : startTime;
        IVesting(vestingAddress).initialize(
            address(pREWAToken),
            beneficiary,
            actualStartTime,
            cliffDuration,
            duration,
            revocable,
            amount,
            msg.sender 
        );

        // --- 4. EFFECTS (Phase 2: Update State) ---
        // All state updates happen after interactions are complete.
        _vestingsByBeneficiary[beneficiary].push(vestingAddress);
        _vestingsByOwner[msg.sender].push(vestingAddress);
        _allVestingContracts.push(vestingAddress);
        
        emit VestingCreated(vestingAddress, beneficiary, amount, msg.sender);
        
        // --- 5. EFFECTS (Phase 3: Clear the Lock) ---
        delete _vestingCreationInProgress[msg.sender][beneficiary];
        
        return vestingAddress;
    }
    
    /**
     * @inheritdoc IVestingFactory
     */
    function getVestingsByBeneficiary(address beneficiary_) external view override returns (address[] memory) {
        if (beneficiary_ == address(0)) revert ZeroAddress("beneficiary");
        return _vestingsByBeneficiary[beneficiary_];
    }
    
    /**
     * @notice Retrieves a paginated list of vesting contracts for a specific beneficiary.
     * @param beneficiary_ The address of the beneficiary.
     * @param offset The starting index for pagination.
     * @param limit The maximum number of addresses to return.
     * @return page A memory array of vesting contract addresses.
     * @return total The total number of vesting contracts for the beneficiary.
     */
    function getVestingsByBeneficiaryPaginated(address beneficiary_, uint256 offset, uint256 limit) external view returns (address[] memory page, uint256 total) {
        if (beneficiary_ == address(0)) revert ZeroAddress("beneficiary");
        if (limit == 0) revert VF_LimitIsZero();

        address[] storage vestings = _vestingsByBeneficiary[beneficiary_];
        total = vestings.length;

        if (offset >= total) {
            return (new address[](0), total);
        }

        uint256 count = total - offset < limit ? total - offset : limit;
        page = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            page[i] = vestings[offset + i];
        }
        return (page, total);
    }

    /**
     * @inheritdoc IVestingFactory
     */
    function getVestingsByOwner(address owner_) external view override returns (address[] memory) {
        if (owner_ == address(0)) revert ZeroAddress("owner_");
        return _vestingsByOwner[owner_];
    }

    /**
     * @notice Retrieves a paginated list of vesting contracts created by a specific owner.
     * @param owner_param The address of the owner.
     * @param offset The starting index for pagination.
     * @param limit The maximum number of addresses to return.
     * @return page A memory array of vesting contract addresses.
     * @return total The total number of vesting contracts for the owner.
     */
    function getVestingsByOwnerPaginated(address owner_param, uint256 offset, uint256 limit) external view returns (address[] memory page, uint256 total) {
        if (owner_param == address(0)) revert ZeroAddress("owner_");
        if (limit == 0) revert VF_LimitIsZero();

        address[] storage vestings = _vestingsByOwner[owner_param];
        total = vestings.length;

        if (offset >= total) {
            return (new address[](0), total);
        }

        uint256 count = total - offset < limit ? total - offset : limit;
        page = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            page[i] = vestings[offset + i];
        }
        return (page, total);
    }

    /**
     * @notice Retrieves a paginated list of all vesting contracts created by this factory.
     * @param offset The starting index for pagination.
     * @param limit The maximum number of addresses to return.
     * @return page A memory array of all vesting contract addresses.
     * @return total The total number of vesting contracts created.
     */
    function getAllVestingContractsPaginated(uint256 offset, uint256 limit) external view returns (address[] memory page, uint256 total) {
        if (limit == 0) revert VF_LimitIsZero();
        
        address[] storage vestings = _allVestingContracts;
        total = vestings.length;

        if (offset >= total) {
            return (new address[](0), total);
        }

        uint256 count = total - offset < limit ? total - offset : limit;
        page = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            page[i] = vestings[offset + i];
        }
        return (page, total);
    }

    /**
     * @inheritdoc IVestingFactory
     */
    function getImplementation() external view override returns (address) {
        return vestingImplementation;
    }

    /**
     * @inheritdoc IVestingFactory
     */
    function setImplementation(address newVestingImplementation) external override onlyOwner returns (bool success) {
        if (newVestingImplementation == address(0)) revert ZeroAddress("newVestingImplementation");
        uint256 codeSize;
        assembly { codeSize := extcodesize(newVestingImplementation) } 
        if (codeSize == 0) revert NotAContract("newVestingImplementation"); 

        address oldImplementation = vestingImplementation;
        vestingImplementation = newVestingImplementation;
        success = true;
        emit ImplementationUpdated(oldImplementation, newVestingImplementation, msg.sender);
        return success;
    }

    /**
     * @notice Sets a new admin address for all future proxy deployments.
     * @param newProxyAdminAddress The address of the new proxy admin contract.
     * @return success A boolean indicating if the operation was successful.
     */
    function setProxyAdmin(address newProxyAdminAddress) external onlyOwner returns (bool success) {
        if (newProxyAdminAddress == address(0)) revert ZeroAddress("newProxyAdminAddress");
        
        address oldProxyAdmin = proxyAdminAddress;
        proxyAdminAddress = newProxyAdminAddress;
        success = true;
        emit ProxyAdminUpdated(oldProxyAdmin, newProxyAdminAddress, msg.sender);
        return success;
    }

    /**
     * @inheritdoc IVestingFactory
     */
    function getTokenAddress() external view override returns (address) {
        return address(pREWAToken);
    }
}
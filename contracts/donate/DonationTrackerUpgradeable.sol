// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// --- UPGRADEABLE IMPORTS ---
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// --- STANDARD IMPORTS (YOUR ARCHITECTURE) ---
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../access/AccessControl.sol";
import "../libraries/Errors.sol";
import "../libraries/DonationMetadataLib.sol"; // <<< ADD THIS IMPORT

/**
 * @title Donation Tracker (Upgradeable)
 * @author drt-pREWA
 * @notice An upgradeable ERC1155 contract to track donations, issue NFT certificates, and manage funds.
 * @dev This contract uses a UUPS proxy pattern for upgradeability. It integrates with an external
 *      AccessControl contract for granular, role-based permissions for all administrative functions.
 *      It is designed to handle donations in both the native chain currency (e.g., ETH/BNB) and
 *      allowlisted ERC20 tokens, forwarding all proceeds to a designated treasury.
 */
contract DonationTrackerUpgradeable is
    Initializable,
    ERC1155Upgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using Strings for uint256;
    using SafeERC20 for IERC20;

    // --- ROLES ---

    /// @notice Role for recovering non-supported, accidentally sent tokens from the contract.
    bytes32 public constant RESCUE_ROLE = keccak256("RESCUE_ROLE");
    /// @notice Role for managing which ERC20 tokens are supported for donations and setting the native symbol.
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");
    /// @notice Role for updating the treasury address where funds are sent.
    bytes32 public constant TREASURY_MANAGER_ROLE = keccak256("TREASURY_MANAGER_ROLE");
    /// @notice Role for performing compliance-related actions, such as verifying a donor.
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");
    /// @notice Role for pausing and unpausing all donation functions.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice Role required to upgrade the contract's implementation via the UUPS proxy pattern.
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // --- STATE VARIABLES ---

    /**
     * @notice Represents the data associated with a single donation, linked to an NFT token ID.
     * @param donor The address of the account that made the donation.
     * @param token The address of the ERC20 token donated, or address(0) for the native currency.
     * @param amount The amount of tokens donated, stored as a uint96.
     * @param timestamp The block timestamp when the donation was made.
     * @param verificationHash A unique hash to prevent replay attacks on donation calls.
     * @param decimals The number of decimals of the donated token.
     * @param symbol The symbol of the donated token (e.g., "ETH", "USDC").
     */
    struct Donation {
        address donor;
        address token;
        uint96 amount;
        uint40 timestamp;
        bytes32 verificationHash;
        uint8 decimals;
        string symbol;
    }

    /// @dev Counter for the next available ERC1155 token ID.
    uint256 private _nextTokenId;
    /// @dev Maps a token ID to the Donation struct containing its metadata.
    mapping(uint256 => Donation) public donations;
    /// @dev Maps a donor's address to their next nonce, used for creating unique donation hashes.
    mapping(address => uint256) public donationNonce;

    /// @notice The address where all donated funds are immediately sent.
    address public treasury;
    /// @notice The configurable symbol for the native chain currency (e.g., "ETH", "BNB", "MATIC").
    string public nativeTokenSymbol;
    /// @notice Donations exceeding this value (in 18-decimal representation) will be rejected.
    uint256 public constant COMPLIANCE_THRESHOLD = 1000 ether;

    /// @dev Maps a token address to a boolean indicating if it is supported for donations.
    mapping(address => bool) public supportedTokens;
    /// @dev Maps a supported token address to its symbol string.
    mapping(address => string) public tokenSymbols;
    /// @dev Maps a supported token address to its decimals value.
    mapping(address => uint8) public tokenDecimals;
    
    /// @notice The external AccessControl contract that manages all roles and permissions.
    AccessControl public accessControl;

    // --- EVENTS ---

    event DonationReceived(address indexed donor, uint256 indexed tokenId, address indexed token, uint256 amount, uint256 timestamp, bytes32 verificationHash);
    event ComplianceVerified(address indexed donor);
    event TokenSupportUpdated(address token, bool isSupported);
    event FundsDrained(address indexed token, uint256 amount);
    event TreasuryUpdated(address newTreasury);
    event NativeSymbolUpdated(string newSymbol);

    // --- ERRORS ---

    error TokenNotSupported();
    error InvalidTreasuryAddress();
    error InvalidDonationHash();
    error ComplianceCheckRequired(uint256 amount);
    error InvalidTokenAddress();
    error ArrayLengthMismatch();
    error UnauthorizedTokenRecovery();
    error InvalidSymbol();
    error InvalidDecimals();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _accessControl,
        address _treasury,
        address[] memory initialSupportedTokens,
        string[] memory symbols,
        uint8[] memory decimalsList
    ) public initializer {
        __ERC1155_init("");
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        if (_treasury == address(0)) revert InvalidTreasuryAddress();
        if (_accessControl == address(0)) revert ZeroAddress("AccessControl");
        treasury = _treasury;
        accessControl = AccessControl(_accessControl);
        nativeTokenSymbol = "ETH";

        if (initialSupportedTokens.length != symbols.length || symbols.length != decimalsList.length) revert ArrayLengthMismatch();
        
        uint256 length = initialSupportedTokens.length;
        for (uint i = 0; i < length; ) {
            _setTokenSupport(initialSupportedTokens[i], symbols[i], decimalsList[i], true);
            unchecked { i++; }
        }
    }

    receive() external payable {
        revert("Direct ETH not allowed");
    }

    function donateBNB(bytes32 donationHash) external payable nonReentrant whenNotPaused {
        if (msg.value == 0) revert InvalidAmount();
        uint256 normalizedAmount = _normalizeAmount(msg.value, 18);
        if (normalizedAmount > COMPLIANCE_THRESHOLD) revert ComplianceCheckRequired(msg.value);
        _processDonation(address(0), msg.value, donationHash, nativeTokenSymbol, 18);
        (bool sent, ) = treasury.call{value: msg.value}("");
        if (!sent) revert TransferFailed();
    }

    function donateERC20(address token, uint256 amount, bytes32 donationHash) external nonReentrant whenNotPaused {
        if (!supportedTokens[token]) revert TokenNotSupported();
        if (amount == 0) revert InvalidAmount();
        uint8 decimals = tokenDecimals[token];
        uint256 normalizedAmount = _normalizeAmount(amount, decimals);
        if (normalizedAmount > COMPLIANCE_THRESHOLD) revert ComplianceCheckRequired(amount);
        uint256 allowance = IERC20(token).allowance(msg.sender, address(this));
        if (allowance < amount) revert InsufficientAllowance(allowance, amount);
        uint256 balanceBefore = IERC20(token).balanceOf(treasury);
        IERC20(token).safeTransferFrom(msg.sender, treasury, amount);
        uint256 actualReceived = IERC20(token).balanceOf(treasury) - balanceBefore;
        if (actualReceived == 0) revert InvalidAmount();
        _processDonation(token, actualReceived, donationHash, tokenSymbols[token], decimals);
    }

    function verifyCompliance(address donor) external {
        if (!accessControl.hasRole(COMPLIANCE_ROLE, msg.sender)) revert NotAuthorized(COMPLIANCE_ROLE);
        emit ComplianceVerified(donor);
    }

    function _processDonation(address token, uint256 amount, bytes32 donationHash, string memory symbol, uint8 decimals) private {
        bytes32 expectedHash = keccak256(abi.encode(block.chainid, msg.sender, token, amount, donationNonce[msg.sender]));
        if (donationHash != expectedHash) revert InvalidDonationHash();
        
        uint256 tokenId = _nextTokenId++;
        donationNonce[msg.sender]++;
        donations[tokenId] = Donation({
            donor: msg.sender,
            token: token,
            amount: uint96(amount),
            timestamp: uint40(block.timestamp),
            verificationHash: donationHash,
            decimals: decimals,
            symbol: symbol
        });

        _mint(msg.sender, tokenId, 1, "");

        emit DonationReceived(msg.sender, tokenId, token, amount, block.timestamp, donationHash);
    }

    /**
     * @notice Returns the URI for a given token ID, containing JSON metadata.
     * @dev Generates the metadata on-chain by calling an external library to save bytecode size.
     * @param tokenId The ID of the token for which to retrieve the URI.
     * @return A data URI containing the token's metadata.
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        // <<< REFACTOR: Delegate URI generation to the library >>>
        return DonationMetadataLib.generateURI(donations[tokenId], tokenId);
    }

    /**
     * @dev Normalizes a token amount to an 18-decimal representation for consistent comparisons.
     */
    function _normalizeAmount(uint256 amount, uint8 decimals) private pure returns (uint256) {
        if (decimals == 18) return amount;
        if (decimals < 18) return amount * (10**(18 - decimals));
        return amount / (10**(decimals - 18));
    }
    
    // <<< REFACTOR: The _formatAmount and _generateSVG functions have been REMOVED from this contract
    // and moved into DonationMetadataLib.sol to reduce contract size. >>>

    function setTokenSupport(address token, string calldata symbol, uint8 decimals, bool isSupported) external {
        if (!accessControl.hasRole(TOKEN_MANAGER_ROLE, msg.sender)) revert NotAuthorized(TOKEN_MANAGER_ROLE);
        if (token == address(0)) revert InvalidTokenAddress();
        if (bytes(symbol).length == 0) revert InvalidSymbol();
        if (decimals > 18) revert InvalidDecimals();
        _setTokenSupport(token, symbol, decimals, isSupported);
    }

    function _setTokenSupport(address token, string memory symbol, uint8 decimals, bool isSupported) private {
        supportedTokens[token] = isSupported;
        if (isSupported) {
            tokenSymbols[token] = symbol;
            tokenDecimals[token] = decimals;
        } else {
            delete tokenSymbols[token];
            delete tokenDecimals[token];
        }
        emit TokenSupportUpdated(token, isSupported);
    }

    function setNativeTokenSymbol(string calldata symbol) external {
        if (!accessControl.hasRole(TOKEN_MANAGER_ROLE, msg.sender)) revert NotAuthorized(TOKEN_MANAGER_ROLE);
        if (bytes(symbol).length == 0) revert InvalidSymbol();
        nativeTokenSymbol = symbol;
        emit NativeSymbolUpdated(symbol);
    }

    function updateTreasury(address newTreasury) external {
        if (!accessControl.hasRole(TREASURY_MANAGER_ROLE, msg.sender)) revert NotAuthorized(TREASURY_MANAGER_ROLE);
        if (newTreasury == address(0)) revert InvalidTreasuryAddress();
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    function rescueFunds(address token) external {
        if (!accessControl.hasRole(RESCUE_ROLE, msg.sender)) revert NotAuthorized(RESCUE_ROLE);
        if (supportedTokens[token]) revert UnauthorizedTokenRecovery();
        uint256 amount;
        if (token == address(0)) {
            amount = address(this).balance;
            (bool sent, ) = payable(msg.sender).call{value: amount}("");
            if (!sent) revert TransferFailed();
        } else {
            amount = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransfer(msg.sender, amount);
        }
        emit FundsDrained(token, amount);
    }
    
    function pause() external {
        if (!accessControl.hasRole(PAUSER_ROLE, msg.sender)) revert NotAuthorized(PAUSER_ROLE);
        _pause();
    }

    function unpause() external {
        if (!accessControl.hasRole(PAUSER_ROLE, msg.sender)) revert NotAuthorized(PAUSER_ROLE);
        _unpause();
    }

    function _authorizeUpgrade(address /* newImplementation */) internal view override {
        if (!accessControl.hasRole(UPGRADER_ROLE, msg.sender)) {
            revert NotAuthorized(UPGRADER_ROLE);
        }
    }

    uint256[49] private __gap;
}
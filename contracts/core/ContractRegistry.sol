// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../access/AccessControl.sol"; 
import "../libraries/Errors.sol";

/**
 * @title ContractRegistry
 * @author Rewa
 * @notice A central on-chain registry for managing and discovering contract addresses within the ecosystem.
 * @dev This contract allows authorized accounts to register, update, and manage contracts by name.
 * It provides a reliable way for other contracts and front-ends to look up the latest address
 * for a given service (e.g., "LPStaking", "SecurityModule"). It is upgradeable and controlled
 * by an owner and an AccessControl contract.
 */
contract ContractRegistry is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    /// @notice The contract that controls roles and permissions.
    AccessControl public accessControl;

    /**
     * @notice Struct to hold information about a registered contract.
     * @param contractAddress The address of the contract.
     * @param contractType A string defining the category of the contract (e.g., "Staking", "Security").
     * @param version The version string of the contract.
     * @param active A flag indicating if the contract is considered active.
     * @param registrationTime The timestamp of the initial registration.
     * @param registrar The address that originally registered the contract.
     */
    struct ContractInfo {
        address contractAddress;
        string contractType;
        string version;
        bool active;
        uint256 registrationTime;
        address registrar;
    }

    /// @dev Maps a contract's unique name to its information.
    mapping(string => ContractInfo) private _contractsByName;
    /// @dev Maps a contract's address to its unique name for reverse lookups.
    mapping(address => string) private _namesByAddress;
    /// @dev An array of all registered contract names for enumeration.
    string[] private _allContractNames;
    /// @dev Maps a contract's name to its index in the `_allContractNames` array for O(1) removal.
    mapping(string => uint256) private _contractNameIndices;
    /// @dev Maps a contract type hash to an array of names belonging to that type.
    mapping(bytes32 => string[]) private _contractNamesByTypeHash;
    /// @dev Maps a type hash and a contract name to the name's index within the type-specific array for O(1) removal.
    mapping(bytes32 => mapping(string => uint256)) private _contractTypeIndicesByName;

    /**
     * @notice Emitted when a new contract is registered.
     * @param name The unique name of the contract.
     * @param contractAddress The address of the registered contract.
     * @param contractType The category of the contract.
     * @param version The version of the contract.
     * @param registrar The address that performed the registration.
     */
    event ContractRegistered(
        string indexed name,
        address indexed contractAddress,
        string contractType,
        string version,
        address indexed registrar
    );
    /**
     * @notice Emitted when a registered contract's address or version is updated.
     * @param name The unique name of the contract.
     * @param oldAddress The previous address of the contract.
     * @param newAddress The new address of the contract.
     * @param newVersion The new version of the contract.
     * @param updater The address that performed the update.
     */
    event ContractUpdated(
        string indexed name,
        address indexed oldAddress,
        address indexed newAddress,
        string newVersion,
        address updater
    );
    /**
     * @notice Emitted when a contract is removed from the registry.
     * @param name The unique name of the removed contract.
     * @param contractAddress The address of the removed contract.
     * @param remover The address that performed the removal.
     */
    event ContractRemoved(
        string indexed name,
        address indexed contractAddress,
        address indexed remover
    );
    /**
     * @notice Emitted when a contract's active status is changed.
     * @param name The unique name of the contract.
     * @param contractAddress The address of the contract.
     * @param active The new active status.
     * @param changer The address that changed the status.
     */
    event ContractActivationChanged(
        string indexed name,
        address indexed contractAddress,
        bool active,
        address indexed changer
    );

    /**
     * @dev Disables the regular constructor to make the contract upgradeable.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the ContractRegistry.
     * @dev Sets the initial owner and the AccessControl contract address. Can only be called once.
     * @param initialOwner_ The initial owner of the registry.
     * @param accessControlAddress_ The address of the AccessControl contract.
     */
    function initialize(
        address initialOwner_,
        address accessControlAddress_
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        if (initialOwner_ == address(0)) revert ZeroAddress("initialOwner");
        if (accessControlAddress_ == address(0)) revert ZeroAddress("accessControlAddress for ContractRegistry");

        accessControl = AccessControl(accessControlAddress_);
        _transferOwnership(initialOwner_);
    }

    /**
     * @dev Modifier to restrict functions to accounts with the PARAMETER_ROLE.
     */
    modifier onlyParameterRole() {
        if (address(accessControl) == address(0)) revert CR_AccessControlZero();
        if (!accessControl.hasRole(accessControl.PARAMETER_ROLE(), msg.sender)) {
            revert NotAuthorized(accessControl.PARAMETER_ROLE());
        }
        _;
    }

    /**
     * @notice Registers a new contract in the registry.
     * @dev The name must be unique, and the address must not already be registered.
     * @param name The unique name to identify the contract.
     * @param contractAddress_ The address of the contract being registered.
     * @param contractType_ The category or type of the contract.
     * @param version_ The version of the contract.
     * @return success A boolean indicating if the operation was successful.
     */
    function registerContract(
        string calldata name,
        address contractAddress_,
        string calldata contractType_,
        string calldata version_
    ) external onlyParameterRole nonReentrant returns (bool success) {
        if (bytes(name).length == 0) revert CR_NameEmpty();
        if (contractAddress_ == address(0)) revert CR_ContractAddressZero("contractAddress_");
        if (bytes(contractType_).length == 0) revert CR_ContractTypeEmpty();
        if (bytes(version_).length == 0) revert CR_VersionEmpty();
        if (_contractsByName[name].contractAddress != address(0)) revert CR_NameAlreadyRegistered(name);
        if (bytes(_namesByAddress[contractAddress_]).length != 0) revert CR_AddressAlreadyRegistered(contractAddress_);

        _contractsByName[name] = ContractInfo({
            contractAddress: contractAddress_,
            contractType: contractType_,
            version: version_,
            active: true,
            registrationTime: block.timestamp,
            registrar: msg.sender
        });

        _namesByAddress[contractAddress_] = name;
        _allContractNames.push(name);
        _contractNameIndices[name] = _allContractNames.length - 1;

        bytes32 typeHash = keccak256(abi.encodePacked(contractType_));
        _contractNamesByTypeHash[typeHash].push(name);
        _contractTypeIndicesByName[typeHash][name] = _contractNamesByTypeHash[typeHash].length - 1;

        emit ContractRegistered(name, contractAddress_, contractType_, version_, msg.sender);
        success = true;
        return success;
    }

    /**
     * @notice Updates the address and version of an existing contract in the registry.
     * @param name The name of the contract to update.
     * @param newContractAddress The new address for the contract.
     * @param newVersion The new version for the contract.
     * @return success A boolean indicating if the operation was successful.
     */
    function updateContract(
        string calldata name,
        address newContractAddress,
        string calldata newVersion
    ) external onlyParameterRole nonReentrant returns (bool success) {
        if (bytes(name).length == 0) revert CR_NameEmpty();
        if (newContractAddress == address(0)) revert CR_ContractAddressZero("newContractAddress");
        if (bytes(newVersion).length == 0) revert CR_VersionEmpty();

        ContractInfo storage contractInfo = _contractsByName[name];
        if (contractInfo.contractAddress == address(0)) revert CR_ContractNotFound(name);

        address oldAddress = contractInfo.contractAddress;
        if (oldAddress != newContractAddress) {
            if (bytes(_namesByAddress[newContractAddress]).length != 0) revert CR_AddressAlreadyRegistered(newContractAddress);
            delete _namesByAddress[oldAddress];
            _namesByAddress[newContractAddress] = name;
        }

        contractInfo.contractAddress = newContractAddress;
        contractInfo.version = newVersion;

        emit ContractUpdated(name, oldAddress, newContractAddress, newVersion, msg.sender);
        success = true;
        return success;
    }

    /**
     * @notice Removes a contract entirely from the registry.
     * @dev This operation removes the contract from all lookups and enumeration arrays. It uses the
     * "swap and pop" technique on all tracking arrays for O(1) gas complexity.
     * @param name The name of the contract to remove.
     * @return success A boolean indicating if the operation was successful.
     */
    function removeContract(
        string calldata name
    ) external onlyParameterRole nonReentrant returns (bool success) {
        if (bytes(name).length == 0) revert CR_NameEmpty();

        ContractInfo storage contractInfo = _contractsByName[name];
        if (contractInfo.contractAddress == address(0)) revert CR_ContractNotFound(name);

        address contractAddress_ = contractInfo.contractAddress;
        string memory contractType_ = contractInfo.contractType;

        delete _namesByAddress[contractAddress_];

        // "Swap and pop" from the global list of all contract names
        uint256 indexToRemove = _contractNameIndices[name];
        string[] storage allNames = _allContractNames;
        uint256 lastIndex = allNames.length - 1;
        if (indexToRemove != lastIndex) {
            string memory lastContractName = allNames[lastIndex];
            allNames[indexToRemove] = lastContractName;
            _contractNameIndices[lastContractName] = indexToRemove;
        }
        allNames.pop();
        delete _contractNameIndices[name];

        // "Swap and pop" from the type-specific list of contract names
        bytes32 typeHash = keccak256(abi.encodePacked(contractType_));
        string[] storage namesForType = _contractNamesByTypeHash[typeHash];
        uint256 typeSpecificIndexToRemove = _contractTypeIndicesByName[typeHash][name];
        uint256 typeSpecificLastIndex = namesForType.length - 1;

        if (typeSpecificIndexToRemove != typeSpecificLastIndex) {
            string memory lastContractNameForType = namesForType[typeSpecificLastIndex];
            namesForType[typeSpecificIndexToRemove] = lastContractNameForType;
            _contractTypeIndicesByName[typeHash][lastContractNameForType] = typeSpecificIndexToRemove;
        }
        namesForType.pop();
        delete _contractTypeIndicesByName[typeHash][name]; 

        delete _contractsByName[name];

        emit ContractRemoved(name, contractAddress_, msg.sender);
        success = true;
        return success;
    }

    /**
     * @notice Sets the active status of a registered contract.
     * @param name The name of the contract.
     * @param active The new active status (true or false).
     * @return success A boolean indicating if the operation was successful.
     */
    function setContractActive(
        string calldata name,
        bool active
    ) external onlyParameterRole nonReentrant returns (bool success) {
        if (bytes(name).length == 0) revert CR_NameEmpty();

        ContractInfo storage contractInfo = _contractsByName[name];
        if (contractInfo.contractAddress == address(0)) revert CR_ContractNotFound(name);

        if (contractInfo.active == active) {
            success = true;
            return success;
        }

        contractInfo.active = active;

        emit ContractActivationChanged(name, contractInfo.contractAddress, active, msg.sender);
        success = true;
        return success;
    }

    /**
     * @notice Retrieves the address of a contract by its registered name.
     * @param name The name of the contract.
     * @return The address of the contract, or address(0) if not found.
     */
    function getContractAddress(string calldata name) external view returns (address) {
        return _contractsByName[name].contractAddress;
    }

    /**
     * @notice Retrieves the registered name of a contract by its address.
     * @param contractAddress_ The address of the contract.
     * @return The name of the contract, or an empty string if not found.
     */
    function getContractName(address contractAddress_) external view returns (string memory) {
        return _namesByAddress[contractAddress_];
    }

    /**
     * @notice Retrieves all information for a contract by its registered name.
     * @param name The name of the contract.
     * @return contractAddress_ The contract's address.
     * @return contractType_ The contract's type.
     * @return version_ The contract's version.
     * @return active_ The contract's active status.
     * @return registrationTime_ The timestamp of registration.
     * @return registrar_ The address that registered the contract.
     */
    function getContractInfo(
        string calldata name
    ) external view returns (
        address contractAddress_,
        string memory contractType_,
        string memory version_,
        bool active_,
        uint256 registrationTime_,
        address registrar_
    ) {
        ContractInfo storage contractInfo_ = _contractsByName[name];
        if (contractInfo_.contractAddress == address(0)) revert CR_ContractNotFound(name);

        contractAddress_ = contractInfo_.contractAddress;
        contractType_ = contractInfo_.contractType;
        version_ = contractInfo_.version;
        active_ = contractInfo_.active;
        registrationTime_ = contractInfo_.registrationTime;
        registrar_ = contractInfo_.registrar;
    }

    /**
     * @notice Lists all registered contract names with pagination.
     * @param offset The starting index for pagination.
     * @param limit The maximum number of names to return.
     * @return page A memory array of contract names.
     * @return totalContracts The total number of registered contracts.
     */
    function listContracts(uint256 offset, uint256 limit) external view returns (string[] memory page, uint256 totalContracts) {
        if (limit == 0) revert CR_LimitIsZero();

        string[] storage allNames = _allContractNames;
        totalContracts = allNames.length;

        if (offset >= totalContracts) {
            page = new string[](0);
            return (page, totalContracts);
        }

        uint256 countRet = totalContracts - offset < limit ? totalContracts - offset : limit;
        page = new string[](countRet);
        for (uint256 i = 0; i < countRet; i++) { 
            page[i] = allNames[offset + i];
        }
        return (page, totalContracts);
    }

    /**
     * @notice Retrieves a paginated list of contracts belonging to a specific type.
     * @param contractType_ The type of contracts to retrieve.
     * @param offset The starting index for pagination.
     * @param limit The maximum number of contracts to return.
     * @return namesPage A memory array of the names of matching contracts.
     * @return addressesPage A memory array of the addresses of matching contracts.
     * @return totalMatchingContracts The total number of contracts of the specified type.
     */
    function getContractsByType(
        string calldata contractType_,
        uint256 offset,
        uint256 limit
    ) external view returns (
        string[] memory namesPage,
        address[] memory addressesPage,
        uint256 totalMatchingContracts
    ) {
        if (limit == 0) revert CR_LimitIsZero();
        bytes32 typeHash = keccak256(abi.encodePacked(contractType_));
        string[] storage matchingNames = _contractNamesByTypeHash[typeHash];
        totalMatchingContracts = matchingNames.length;

        if (offset >= totalMatchingContracts) {
            namesPage = new string[](0);
            addressesPage = new address[](0);
            return (namesPage, addressesPage, totalMatchingContracts);
        }

        uint256 countRet = totalMatchingContracts - offset < limit ? totalMatchingContracts - offset : limit;
        namesPage = new string[](countRet);
        addressesPage = new address[](countRet);

        for (uint256 i = 0; i < countRet; i++) { 
            string memory currentName = matchingNames[offset + i];
            namesPage[i] = currentName;
            addressesPage[i] = _contractsByName[currentName].contractAddress;
        }

        return (namesPage, addressesPage, totalMatchingContracts);
    }

    /**
     * @notice Checks if a contract with a given name exists and is active.
     * @param name The name of the contract.
     * @return exists_ True if a contract with this name is registered.
     * @return isActive_ True if the contract exists and is marked as active.
     */
    function contractExists(
        string calldata name
    ) external view returns (bool exists_, bool isActive_) {
        ContractInfo storage contractInfo_ = _contractsByName[name];
        exists_ = contractInfo_.contractAddress != address(0);
        isActive_ = contractInfo_.active && exists_; 
        return (exists_, isActive_);
    }

    /**
     * @notice Gets the total number of contracts registered.
     * @return count_ The total count.
     */
    function getContractCount() external view returns (uint256 count_) {
        count_ = _allContractNames.length;
        return count_;
    }
}
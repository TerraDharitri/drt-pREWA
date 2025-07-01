// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol"; 
import "../proxy/interfaces/IProxy.sol"; 
import "../access/AccessControl.sol"; 
import "../interfaces/IEmergencyAware.sol";
import "../controllers/EmergencyController.sol"; 
import "../libraries/Errors.sol"; 
import "../libraries/Constants.sol"; 

/**
 * @title ProxyAdmin
 * @author Rewa
 * @notice A contract for managing the administration of upgradeable proxies.
 * @dev This contract is responsible for proposing, executing, and cancelling upgrades for contracts
 * that follow the Transparent Upgradeable Proxy pattern. It includes a timelock mechanism for upgrades
 * and an optional allowlist for approved implementation contracts. It integrates with AccessControl for
 * role-based permissions and is emergency-aware. All administrative actions are governed by roles
 * defined in the AccessControl contract.
 */
contract ProxyAdmin is Initializable, IEmergencyAware { 
    /// @notice The contract that controls roles and permissions.
    AccessControl public accessControl;
    /// @notice The central controller for system-wide emergency states.
    EmergencyController public emergencyController;
    
    /// @notice A mapping of implementation addresses that are approved for upgrades.
    mapping(address => bool) public validImplementations;
    /// @notice The total count of approved implementations. If 0, the approval check is bypassed.
    uint256 public implementationCount;
    
    /**
     * @notice Represents a pending upgrade proposal for a proxy.
     * @param implementation The address of the new implementation contract.
     * @param proposalTime The timestamp when the proposal was made.
     * @param data The calldata for the `upgradeToAndCall` function, if applicable.
     * @param useData A flag indicating whether `upgradeToAndCall` should be used.
     * @param verified A flag indicating if the implementation was on the `validImplementations` list at proposal time.
     * @param proposer The address that proposed the upgrade.
     */
    struct UpgradeProposal {
        address implementation;
        uint256 proposalTime;
        bytes data;
        bool useData; 
        bool verified; 
        address proposer;
    }
    
    /// @notice A mapping from a proxy address to its pending upgrade proposal.
    mapping(address => UpgradeProposal) public upgradeProposals;
    /// @notice The duration in seconds that must pass after a proposal before it can be executed.
    uint256 public upgradeTimelock;

    /**
     * @notice Emitted when a new upgrade is proposed for a proxy.
     * @param proxy The address of the proxy being upgraded.
     * @param newImplementation The address of the proposed new implementation.
     * @param executeAfter The timestamp after which the upgrade can be executed.
     * @param proposer The address that proposed the upgrade.
     */
    event UpgradeProposed(address indexed proxy, address indexed newImplementation, uint256 executeAfter, address indexed proposer); 
    /**
     * @notice Emitted when a proposed upgrade is successfully executed.
     * @param proxy The address of the upgraded proxy.
     * @param newImplementation The address of the new implementation.
     * @param executor The address that executed the upgrade.
     */
    event UpgradeExecuted(address indexed proxy, address indexed newImplementation, address indexed executor); 
    /**
     * @notice Emitted when a pending upgrade proposal is cancelled.
     * @param proxy The address of the proxy whose proposal was cancelled.
     * @param implementation The implementation address of the cancelled proposal.
     * @param canceller The address that cancelled the proposal.
     */
    event UpgradeCancelled(address indexed proxy, address indexed implementation, address indexed canceller); 
    /**
     * @notice Emitted when the upgrade timelock duration is updated.
     * @param oldTimelock The previous timelock duration.
     * @param newTimelock The new timelock duration.
     * @param updater The address that performed the update.
     */
    event TimelockUpdated(uint256 oldTimelock, uint256 newTimelock, address indexed updater);
    /**
     * @notice Emitted when a new implementation address is added to the allowlist.
     * @param implementation The address added to the allowlist.
     * @param adder The address that performed the addition.
     */
    event ValidImplementationAdded(address indexed implementation, address indexed adder);
    /**
     * @notice Emitted when an implementation address is removed from the allowlist.
     * @param implementation The address removed from the allowlist.
     * @param remover The address that performed the removal.
     */
    event ValidImplementationRemoved(address indexed implementation, address indexed remover);
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
     * @notice Initializes the ProxyAdmin contract.
     * @dev Sets up initial contract addresses and the upgrade timelock. Can only be called once.
     * @param accessControlAddress_ The address of the AccessControl contract.
     * @param emergencyControllerAddress_ The address of the EmergencyController contract.
     * @param timelockDuration_ The initial timelock duration for upgrades, in seconds.
     * @param initialAdmin_ The address to be granted the initial PROXY_ADMIN_ROLE.
     */
    function initialize(
        address accessControlAddress_,
        address emergencyControllerAddress_,
        uint256 timelockDuration_,
        address initialAdmin_ 
    ) external initializer { 
        if (accessControlAddress_ == address(0)) revert PA_AccessControlZero(); 
        if (emergencyControllerAddress_ == address(0)) revert PA_EmergencyControllerZero();
        if (initialAdmin_ == address(0)) revert ZeroAddress("initialAdmin_"); 
        if (timelockDuration_ < Constants.MIN_TIMELOCK_DURATION || timelockDuration_ > Constants.MAX_TIMELOCK_DURATION) {
             revert PA_InvalidTimelockDuration();
        }

        uint256 codeSize;
        assembly { codeSize := extcodesize(accessControlAddress_) }
        if (codeSize == 0) revert NotAContract("accessControl");
        assembly { codeSize := extcodesize(emergencyControllerAddress_) }
        if (codeSize == 0) revert NotAContract("emergencyController");
        
        accessControl = AccessControl(accessControlAddress_);
        emergencyController = EmergencyController(emergencyControllerAddress_);
        upgradeTimelock = timelockDuration_;
        
        // Grant the initial admin role via the AccessControl contract
        accessControl.grantRole(accessControl.PROXY_ADMIN_ROLE(), initialAdmin_);
    }

    /**
     * @dev Modifier to restrict functions to accounts with the PROXY_ADMIN_ROLE.
     * This role is for high-level administrative actions on this contract.
     */
    modifier onlyProxyAdminRole() {
        if (address(accessControl) == address(0)) revert PA_AccessControlZero();
        if (!accessControl.hasRole(accessControl.PROXY_ADMIN_ROLE(), msg.sender)) revert NotAuthorized(accessControl.PROXY_ADMIN_ROLE());
        _;
    }

    /**
     * @dev Modifier to restrict access to functions to addresses with the UPGRADER_ROLE.
     * This role is for managing the lifecycle of upgrade proposals.
     */
    modifier onlyUpgrader() {
        if (address(accessControl) == address(0)) revert PA_AccessControlZero();
        if (!accessControl.hasRole(accessControl.UPGRADER_ROLE(), msg.sender)) revert NotAuthorized(accessControl.UPGRADER_ROLE());
        _;
    }
    
    /**
     * @dev Modifier that reverts if the system is in an emergency state.
     */
    modifier whenNotEmergency() {
        if (isEmergencyPaused()) revert SystemInEmergencyMode();
        _;
    }

    /**
     * @dev Internal function to check if an address has code.
     * @param account The address to check.
     * @return A boolean indicating if the address is a contract.
     */
    function _isContract(address account) internal view returns (bool) {
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(account)
        }
        return codeSize > 0;
    }

    /**
     * @notice Gets the current implementation address for a given proxy.
     * @param proxy The address of the proxy contract.
     * @return implementationAddress The address of the logic contract.
     */
    function getProxyImplementation(address proxy) external view returns (address implementationAddress) { 
        if (proxy == address(0)) revert PA_ProxyZero();
        try IProxy(proxy).implementation() returns (address impl) {
            implementationAddress = impl;
        } catch { 
            revert PA_GetImplFailed(); 
        }
        return implementationAddress;
    }

    /**
     * @notice Gets the current admin address for a given proxy.
     * @param proxy The address of the proxy contract.
     * @return adminAddress The address of the admin (should be this contract).
     */
    function getProxyAdmin(address proxy) external view returns (address adminAddress) { 
        if (proxy == address(0)) revert PA_ProxyZero();
        try IProxy(proxy).admin() returns (address pAdmin) { 
            adminAddress = pAdmin;
        } catch { 
            revert PA_GetAdminFailed(); 
        }
        return adminAddress;
    }

    /**
     * @notice Changes the admin of a proxy contract.
     * @dev This should be used with extreme caution, as it transfers control of the proxy away from this ProxyAdmin.
     * Only callable by an account with the `PROXY_ADMIN_ROLE`.
     * @param proxy The address of the proxy contract.
     * @param newAdmin The address of the new admin.
     */
    function changeProxyAdmin(address proxy, address newAdmin) external onlyProxyAdminRole whenNotEmergency { 
        if (proxy == address(0)) revert PA_ProxyZero();
        if (newAdmin == address(0)) revert PA_NewAdminZero();
        
        try IProxy(proxy).changeAdmin(newAdmin) {} 
        catch Error(string memory reason) { revert PA_AdminChangeFailed(reason); } 
        catch { revert PA_AdminChangeFailed("Proxy admin change failed"); } 
    }

    /**
     * @notice Adds an implementation contract address to the allowlist of valid upgrade targets.
     * @param implementationToAdd The address of the implementation contract to add.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function addValidImplementation(address implementationToAdd) external onlyUpgrader returns (bool successFlag) { 
        if (implementationToAdd == address(0)) revert PA_ImplZero();
        if (validImplementations[implementationToAdd]) revert PA_ImplAlreadyAdded();
        if (!_isContract(implementationToAdd)) revert PA_ImplNotAContract(); 
        
        validImplementations[implementationToAdd] = true;
        implementationCount++;
        emit ValidImplementationAdded(implementationToAdd, msg.sender);
        successFlag = true;
        return successFlag;
    }
    
    /**
     * @notice Removes an implementation contract address from the allowlist.
     * @param implementationToRemove The address of the implementation contract to remove.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function removeValidImplementation(address implementationToRemove) external onlyUpgrader returns (bool successFlag) { 
        if (implementationToRemove == address(0)) revert PA_ImplZero();
        if (!validImplementations[implementationToRemove]) revert PA_ImplNotAdded();
        
        validImplementations[implementationToRemove] = false;
        if (implementationCount > 0) { 
            implementationCount--;
        }
        emit ValidImplementationRemoved(implementationToRemove, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Proposes a simple upgrade for a proxy to a new implementation.
     * @dev Creates a timelocked proposal. If an implementation allowlist is active, the target must be on it.
     * @param proxy The address of the proxy to upgrade.
     * @param newImplementationProposed The address of the new implementation contract.
     */
    function proposeUpgrade(address proxy, address newImplementationProposed) external onlyUpgrader whenNotEmergency { 
        if (proxy == address(0)) revert PA_ProxyZero();
        if (newImplementationProposed == address(0)) revert PA_ImplZero();
        if (upgradeProposals[proxy].implementation != address(0)) revert PA_UpgradePropExists();
        
        if (!_isContract(newImplementationProposed)) revert PA_ImplNotAContract(); 
        
        bool isVerifiedFlag = false; 
        if (implementationCount > 0) { 
            if (!validImplementations[newImplementationProposed]) revert PA_ImplNotApproved();
            isVerifiedFlag = true; 
        } 
        upgradeProposals[proxy] = UpgradeProposal(
            newImplementationProposed, 
            block.timestamp, 
            bytes(""), 
            false,    
            isVerifiedFlag, 
            msg.sender
        );
        emit UpgradeProposed(proxy, newImplementationProposed, block.timestamp + upgradeTimelock, msg.sender);
    }

    /**
     * @notice Proposes an upgrade for a proxy that also calls an initialization function on the new implementation.
     * @dev Creates a timelocked proposal. `data` typically contains the function selector and arguments for an initializer.
     * @param proxy The address of the proxy to upgrade.
     * @param newImplementationProposed The address of the new implementation contract.
     * @param data The calldata to be executed in the context of the proxy after the upgrade.
     */
    function proposeUpgradeAndCall(address proxy, address newImplementationProposed, bytes calldata data) external onlyUpgrader whenNotEmergency { 
        if (proxy == address(0)) revert PA_ProxyZero();
        if (newImplementationProposed == address(0)) revert PA_ImplZero();
        if (data.length == 0) revert PA_DataEmptyForCall(); 
        if (upgradeProposals[proxy].implementation != address(0)) revert PA_UpgradePropExists();
        
        if (!_isContract(newImplementationProposed)) revert PA_ImplNotAContract(); 
        
        bool isVerifiedFlag = false;
        if (implementationCount > 0) {
            if(!validImplementations[newImplementationProposed]) revert PA_ImplNotApproved();
            isVerifiedFlag = true;
        } 

        upgradeProposals[proxy] = UpgradeProposal(
            newImplementationProposed, 
            block.timestamp, 
            data, 
            true, 
            isVerifiedFlag, 
            msg.sender
        );
        emit UpgradeProposed(proxy, newImplementationProposed, block.timestamp + upgradeTimelock, msg.sender);
    }

    /**
     * @notice Executes a pending upgrade proposal for a proxy after the timelock has passed.
     * @param proxy The address of the proxy to upgrade.
     */
    function executeUpgrade(address proxy) external payable onlyUpgrader whenNotEmergency { 
        if (proxy == address(0)) revert PA_ProxyZero();
        UpgradeProposal storage currentProposal = upgradeProposals[proxy]; 
        
        _validateProposalForExecution(currentProposal); 
        
        address implAddress = currentProposal.implementation; 
        bool shouldUseData = currentProposal.useData; 
        bytes memory callData = currentProposal.data; 
        
        if (!shouldUseData && msg.value != 0) {
            revert PA_UpgradeFailed("Value sent to non-payable upgradeTo");
        }
        
        delete upgradeProposals[proxy]; 
        
        emit UpgradeExecuted(proxy, implAddress, msg.sender); 
        
        _executeProxyUpgradeInternal(proxy, implAddress, shouldUseData, callData); 
    }
    
    /**
     * @dev Internal function to validate if a proposal is ready for execution.
     * @param proposal The proposal to validate.
     */
    function _validateProposalForExecution(UpgradeProposal storage proposal) private view { 
        if (proposal.implementation == address(0)) revert PA_NoProposalExists();
        if (block.timestamp < (proposal.proposalTime + upgradeTimelock)) revert PA_TimelockNotYetExpired(); 
        
        if (proposal.verified && !validImplementations[proposal.implementation]) { 
             revert PA_ImplementationNoLongerValidAtExecution(); 
        }
        if (!_isContract(proposal.implementation)) revert PA_ExecImplNotAContract(); 
    }
    
    /**
     * @dev Internal function to perform the actual proxy upgrade via an external call.
     * @param proxy The address of the proxy contract.
     * @param newImplementation The address of the new implementation.
     * @param useData True if `upgradeToAndCall` should be used.
     * @param data The calldata for the call, if applicable.
     */
    function _executeProxyUpgradeInternal(address proxy, address newImplementation, bool useData, bytes memory data) private {
        // This function executes low-level calls to the proxy contract (`upgradeTo` or `upgradeToAndCall`).
        // This is a standard and necessary part of the transparent proxy upgrade pattern.
        // The calling function, `executeUpgrade`, provides robust security checks including role-based access control,
        // a mandatory timelock, and an optional implementation allowlist, which mitigates the risks associated
        // with this privileged operation.
        if (useData) {
            try IProxy(proxy).upgradeToAndCall{value: msg.value}(newImplementation, data) {} 
            catch Error(string memory reason) { revert PA_UpgradeFailed(reason); } 
            catch { revert PA_UpgradeFailed("Proxy upgradeToAndCall failed"); } 
        } else {
            try IProxy(proxy).upgradeTo(newImplementation) {} 
            catch Error(string memory reason) { revert PA_UpgradeFailed(reason); } 
            catch { revert PA_UpgradeFailed("Proxy upgradeTo failed"); } 
        }
    }
    
    /**
     * @notice Cancels a pending upgrade proposal for a proxy.
     * @dev Can be called by the original proposer or any account with `UPGRADER_ROLE` or `PROXY_ADMIN_ROLE`.
     * @param proxy The address of the proxy whose upgrade proposal should be cancelled.
     * @return successFlag A boolean indicating if the operation was successful.
     */
    function cancelUpgrade(address proxy) external returns (bool successFlag) { 
        if (proxy == address(0)) revert PA_ProxyZero();
        UpgradeProposal storage proposalToCancel = upgradeProposals[proxy]; 
        if (proposalToCancel.implementation == address(0)) revert PA_NoProposalExists();
        
        bool isAuthorizedToCancel = (proposalToCancel.proposer == msg.sender) ||
                                   (accessControl.hasRole(accessControl.PROXY_ADMIN_ROLE(), msg.sender)) ||
                                   (accessControl.hasRole(accessControl.UPGRADER_ROLE(), msg.sender));
            
        if (!isAuthorizedToCancel) revert PA_NotAuthorizedToCancel();

        address cancelledImpl = proposalToCancel.implementation; 
        delete upgradeProposals[proxy];
        emit UpgradeCancelled(proxy, cancelledImpl, msg.sender);
        successFlag = true;
        return successFlag;
    }

    /**
     * @notice Updates the timelock duration for all future upgrade proposals.
     * @dev Only callable by an account with the `PROXY_ADMIN_ROLE`.
     * @param newTimelock The new timelock duration in seconds.
     */
    function updateTimelock(uint256 newTimelock) external onlyProxyAdminRole { 
        if (newTimelock < Constants.MIN_TIMELOCK_DURATION || newTimelock > Constants.MAX_TIMELOCK_DURATION) {
             revert PA_InvalidTimelockDuration();
        }
        uint256 oldTimelockDuration = upgradeTimelock; 
        upgradeTimelock = newTimelock;
        emit TimelockUpdated(oldTimelockDuration, newTimelock, msg.sender);
    }

    /**
     * @notice Retrieves details about a pending upgrade proposal for a proxy.
     * @param proxy The address of the proxy.
     * @return implOut The address of the proposed new implementation.
     * @return propTimeOut The timestamp of the proposal.
     * @return timeRemOut The remaining time in seconds until the timelock expires.
     * @return canExecOut A boolean indicating if the proposal can be executed now.
     * @return verifiedOut A boolean indicating if the implementation was on the allowlist at proposal time.
     * @return proposerOut The address of the proposer.
     */
    function getUpgradeProposal(address proxy) external view returns (
        address implOut, uint256 propTimeOut, uint256 timeRemOut, 
        bool canExecOut, bool verifiedOut, address proposerOut 
    ) {
        if (proxy == address(0)) revert PA_ProxyZero();
        UpgradeProposal storage proposalRef = upgradeProposals[proxy]; 
        if (proposalRef.implementation == address(0)) {
            return (address(0), 0, 0, false, false, address(0));
        }
        
        implOut = proposalRef.implementation;
        propTimeOut = proposalRef.proposalTime;
        proposerOut = proposalRef.proposer;
        verifiedOut = proposalRef.verified;

        uint256 unlockAtTime = proposalRef.proposalTime + upgradeTimelock; 
        uint256 currentTime = block.timestamp; 
        timeRemOut = (currentTime < unlockAtTime) ? unlockAtTime - currentTime : 0;
        
        bool isTimelockExpired = currentTime >= unlockAtTime;
        bool isStillVerified = !proposalRef.verified || validImplementations[proposalRef.implementation]; 
        
        bool implementationHasCode = _isContract(implOut); 
        
        canExecOut = isTimelockExpired && isStillVerified && implementationHasCode;
    }
    
    /**
     * @inheritdoc IEmergencyAware
     * @dev Only callable by an account with the `PROXY_ADMIN_ROLE`.
     */
    function setEmergencyController(address controllerAddr) external override onlyProxyAdminRole returns (bool successFlag) { 
        if (controllerAddr == address(0)) revert PA_ECNotSet(); 
        if(!_isContract(controllerAddr)) revert NotAContract("EmergencyController"); 

        address oldController = address(emergencyController);
        emergencyController = EmergencyController(controllerAddr);
        emit EmergencyControllerSet(oldController, controllerAddr, msg.sender);
        successFlag = true;
        return successFlag;
    }
    
    /**
     * @notice Gets the current count of allowlisted implementation addresses.
     * @return countValue The number of implementations on the allowlist.
     */
    function getImplementationCount() external view returns (uint256 countValue) { 
        countValue = implementationCount;
        return countValue;
    }
    
    /**
     * @inheritdoc IEmergencyAware
     */
    function checkEmergencyStatus(bytes4 operation) external view override returns (bool finalOperationAllowed) {
        if (address(emergencyController) == address(0)) { return true; } 
        bool opIsRestrictedByEC = false; 
        bool sysIsPausedByEC = false; 
        uint8 ecLevelForCheck = Constants.EMERGENCY_LEVEL_NORMAL; 
        try emergencyController.isFunctionRestricted(operation) returns (bool r) { opIsRestrictedByEC = r; } catch { } 
        try emergencyController.isSystemPaused() returns (bool p) { sysIsPausedByEC = p; } catch { } 
        try emergencyController.getEmergencyLevel() returns (uint8 l) { 
            ecLevelForCheck = l; 
            if (l >= Constants.EMERGENCY_LEVEL_CRITICAL) sysIsPausedByEC = true;
        } catch { }
        finalOperationAllowed = !opIsRestrictedByEC && !sysIsPausedByEC;
        return finalOperationAllowed;
    }
    
    /**
     * @inheritdoc IEmergencyAware
     */
    function emergencyShutdown(uint8 emergencyLevelInput) external override returns (bool successFlag) { 
        if (address(emergencyController) == address(0)) revert PA_ECNotSet();
        if (msg.sender != address(emergencyController)) revert PA_CallerNotEC();
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
    function isEmergencyPaused() public view override returns (bool isEffectivelyPaused) { 
        if (address(emergencyController) == address(0)) { return false; } 
        bool ecSystemIsPaused = false; 
        uint8 ecCurrentSystemLevel = Constants.EMERGENCY_LEVEL_NORMAL; 
        try emergencyController.isSystemPaused() returns (bool sP) { ecSystemIsPaused = sP; } catch {}
        try emergencyController.getEmergencyLevel() returns (uint8 cL) { ecCurrentSystemLevel = cL; } catch {}
        isEffectivelyPaused = ecSystemIsPaused || (ecCurrentSystemLevel >= Constants.EMERGENCY_LEVEL_CRITICAL); 
        return isEffectivelyPaused;
    }
}
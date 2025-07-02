// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../../interfaces/IEmergencyAware.sol";

/**
 * @title IpREWAToken Interface
 * @notice Defines the extended interface for the pREWA token, including all standard ERC20 functions
 * as well as custom administrative and security features.
 */
interface IpREWAToken is IERC20Upgradeable, IEmergencyAware {
    /**
     * @notice Returns the name of the token.
     * @return The token name string.
     */
    function name() external view returns (string memory);

    /**
     * @notice Returns the symbol of the token.
     * @return The token symbol string.
     */
    function symbol() external view returns (string memory);

    /**
     * @notice Returns the decimals of the token.
     * @return The number of decimals.
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Emitted when an account's blacklist status is changed.
     * @param account The address of the account.
     * @param blacklisted True if the account was blacklisted, false if unblacklisted.
     * @param operator The address that performed the action.
     */
    event BlacklistStatusChanged(address indexed account, bool blacklisted, address indexed operator);

    /**
     * @notice Emitted when the ownership of the token contract is transferred.
     * @param previousOwner The address of the previous owner.
     * @param newOwner The address of the new owner.
     * @param operator The address that initiated the transfer.
     */
    event TokenOwnershipTransferred(address indexed previousOwner, address indexed newOwner, address indexed operator);

    /**
     * @notice Emitted when an account's minter status is changed.
     * @param minter The address of the account.
     * @param status True if the account was granted minter rights, false if revoked.
     * @param operator The address that performed the action.
     */
    event MinterStatusChanged(address indexed minter, bool status, address indexed operator);

    /**
     * @notice Emitted when non-pREWA tokens are recovered from the contract.
     * @param token The address of the recovered token.
     * @param amount The amount recovered.
     * @param recipient The address that received the tokens.
     */
    event TokenRecovered(address indexed token, uint256 amount, address indexed recipient);

    /**
     * @notice Emitted when the token's supply cap is updated.
     * @param oldCap The previous supply cap.
     * @param newCap The new supply cap.
     * @param updater The address that updated the cap.
     */
    event CapUpdated(uint256 oldCap, uint256 newCap, address indexed updater);

    /**
     * @notice Emitted when a proposal to blacklist an account is created.
     * @param account The address of the account proposed for blacklisting.
     * @param executeAfter The timestamp after which the blacklisting can be executed.
     * @param proposer The address that created the proposal.
     */
    event BlacklistProposed(address indexed account, uint256 executeAfter, address indexed proposer);

    /**
     * @notice Emitted when a blacklist proposal is cancelled.
     * @param account The account whose blacklist proposal was cancelled.
     * @param canceller The address that cancelled the proposal.
     */
    event BlacklistCancelled(address indexed account, address indexed canceller);

    /**
     * @notice Emitted when the blacklist timelock duration is updated.
     * @param oldDuration The previous timelock duration in seconds.
     * @param newDuration The new timelock duration in seconds.
     * @param updater The address that updated the duration.
     */
    event BlacklistTimelockDurationUpdated(uint256 oldDuration, uint256 newDuration, address indexed updater);

    /**
     * @notice Creates new tokens and assigns them to an account.
     * @dev Callable only by accounts with the minter role.
     * @param to The address to receive the new tokens.
     * @param amount The amount of tokens to mint.
     * @return success True if the operation was successful.
     */
    function mint(address to, uint256 amount) external returns (bool success);

    /**
     * @notice Destroys a specified amount of tokens from the caller's balance.
     * @param amount The amount of tokens to burn.
     * @return success True if the operation was successful.
     */
    function burn(uint256 amount) external returns (bool success);

    /**
     * @notice Destroys a specified amount of tokens from a specific account, using the caller's allowance.
     * @param account The address whose tokens will be burned.
     * @param amount The amount of tokens to burn.
     * @return success True if the operation was successful.
     */
    function burnFrom(address account, uint256 amount) external returns (bool success);

    /**
     * @notice Pauses all token transfers, minting, and burning.
     * @dev Callable only by accounts with the pauser role.
     * @return success True if the operation was successful.
     */
    function pause() external returns (bool success);

    /**
     * @notice Resumes token transfers, minting, and burning.
     * @dev Callable only by accounts with the pauser role.
     * @return success True if the operation was successful.
     */
    function unpause() external returns (bool success);

    /**
     * @notice Adds an account to the blacklist, preventing it from sending or receiving tokens.
     * @dev This action may be subject to a timelock. Callable only by the owner.
     * @param account The address to blacklist.
     * @return success True if the operation was successful.
     */
    function blacklist(address account) external returns (bool success);

    /**
     * @notice Removes an account from the blacklist.
     * @dev Callable only by the owner.
     * @param account The address to unblacklist.
     * @return success True if the operation was successful.
     */
    function unblacklist(address account) external returns (bool success);

    /**
     * @notice Checks if an account is on the blacklist.
     * @param account The address to check.
     * @return isAccBlacklisted True if the account is blacklisted.
     */
    function isBlacklisted(address account) external view returns (bool isAccBlacklisted);

    /**
     * @notice Checks if the token is currently paused.
     * @return isTokenPaused True if the token is paused.
     */
    function paused() external view returns (bool isTokenPaused); 

    /**
     * @notice Returns the maximum total supply of the token.
     * @return currentCap The supply cap.
     */
    function cap() external view returns (uint256 currentCap);

    /**
     * @notice Sets a new maximum total supply for the token.
     * @dev Callable only by the owner.
     * @param newCapAmount The new supply cap.
     * @return success True if the operation was successful.
     */
    function setCap(uint256 newCapAmount) external returns (bool success);

    /**
     * @notice Recovers other ERC20 tokens mistakenly sent to this contract.
     * @dev Cannot be used to recover pREWA tokens. Callable only by the owner.
     * @param tokenAddress The address of the token to recover.
     * @param amount The amount to recover.
     * @return success True if the operation was successful.
     */
    function recoverTokens(address tokenAddress, uint256 amount) external returns (bool success);

    /**
     * @notice Grants the minter role to an account.
     * @dev Callable only by the owner.
     * @param minterAddress The address to grant the minter role.
     * @return success True if the operation was successful.
     */
    function addMinter(address minterAddress) external returns (bool success);

    /**
     * @notice Revokes the minter role from an account.
     * @dev Callable only by the owner.
     * @param minterAddress The address to revoke the minter role from.
     * @return success True if the operation was successful.
     */
    function removeMinter(address minterAddress) external returns (bool success);

    /**
     * @notice Checks if an account has the minter role.
     * @param account The address to check.
     * @return isAccMinter True if the account is a minter.
     */
    function isMinter(address account) external view returns (bool isAccMinter);

    /**
     * @notice Transfers ownership of the token contract.
     * @dev Callable only by the current owner.
     * @param newOwnerAddress The address of the new owner.
     * @return success True if the operation was successful.
     */
    function transferTokenOwnership(address newOwnerAddress) external returns (bool success);

    /**
     * @notice Retrieves details of a pending blacklist proposal.
     * @param account The account for which the proposal was made.
     * @return proposalExists True if a proposal exists.
     * @return executeAfterTimestamp The timestamp after which the blacklist can be executed.
     * @return timeRemainingSec The remaining time in seconds until execution is possible.
     */
    function getBlacklistProposal(address account) external view returns (
        bool proposalExists,
        uint256 executeAfterTimestamp,
        uint256 timeRemainingSec
    );

    /**
     * @notice Gets the current duration of the blacklist timelock.
     * @return durationSeconds The timelock duration in seconds.
     */
    function getBlacklistTimelockDuration() external view returns (uint256 durationSeconds);

    /**
     * @notice Sets a new duration for the blacklist timelock.
     * @dev Callable only by the owner.
     * @param newDurationSeconds The new timelock duration in seconds.
     * @return success True if the operation was successful.
     */
    function setBlacklistTimelockDuration(uint256 newDurationSeconds) external returns (bool success);

    /**
     * @notice Executes a pending blacklist proposal after the timelock has passed.
     * @dev Callable only by the owner.
     * @param account The account to blacklist.
     * @return success True if the operation was successful.
     */
    function executeBlacklist(address account) external returns (bool success);

    /**
     * @notice Cancels a pending blacklist proposal.
     * @dev Callable only by the owner.
     * @param account The account whose proposal is to be cancelled.
     * @return success True if the operation was successful.
     */
    function cancelBlacklistProposal(address account) external returns (bool success);

    /**
     * @notice Returns the address of the current owner.
     * @return ownerAddress The address of the owner.
     */
    function owner() external view returns (address ownerAddress);
}
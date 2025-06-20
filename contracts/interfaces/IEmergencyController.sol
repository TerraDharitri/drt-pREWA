// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IEmergencyController Interface
 * @notice Defines the external interface for the EmergencyController contract, which manages system-wide states.
 */
interface IEmergencyController {
    /**
     * @notice Emitted when the system-wide emergency level is changed.
     * @param level The new emergency level.
     * @param activator The address that triggered the change.
     */
    event EmergencyLevelSet(uint8 level, address indexed activator);

    /**
     * @notice Emitted when the global emergency withdrawal settings are updated.
     * @param enabled True if emergency withdrawal is enabled across the system.
     * @param penalty The penalty to be applied during emergency withdrawals, in basis points.
     */
    event EmergencyWithdrawalSet(bool enabled, uint256 penalty);

    /**
     * @notice Emitted when the entire system is paused.
     * @param pauser The address that initiated the pause.
     */
    event SystemPaused(address indexed pauser);

    /**
     * @notice Emitted when the entire system is unpaused.
     * @param unpauser The address that initiated the unpause.
     */
    event SystemUnpaused(address indexed unpauser);

    /**
     * @notice Emitted when tokens are recovered from the controller contract.
     * @param token The address of the recovered token.
     * @param amount The amount recovered.
     * @param recipient The address that received the recovered tokens.
     */
    event TokensRecovered(address indexed token, uint256 amount, address indexed recipient);

    /**
     * @notice Sets the system-wide emergency level.
     * @param level The new emergency level (0-3).
     * @return success True if the operation was successful.
     */
    function setEmergencyLevel(uint8 level) external returns (bool success);

    /**
     * @notice Enables or disables emergency withdrawal functionality across all integrated contracts.
     * @param enabled True to enable, false to disable.
     * @param penalty The penalty to apply during emergency withdrawals, in basis points.
     * @return success True if the operation was successful.
     */
    function enableEmergencyWithdrawal(bool enabled, uint256 penalty) external returns (bool success);

    /**
     * @notice Pauses the entire system, restricting most operations in integrated contracts.
     * @return success True if the operation was successful.
     */
    function pauseSystem() external returns (bool success);

    /**
     * @notice Unpauses the entire system, resuming normal operations.
     * @return success True if the operation was successful.
     */
    function unpauseSystem() external returns (bool success);

    /**
     * @notice Recovers ERC20 tokens mistakenly sent to the EmergencyController contract.
     * @param tokenAddress The address of the token to recover.
     * @param amount The amount to recover.
     * @return success True if the operation was successful.
     */
    function recoverTokens(address tokenAddress, uint256 amount) external returns (bool success);

    /**
     * @notice Gets the current system-wide emergency level.
     * @return level The current emergency level.
     */
    function getEmergencyLevel() external view returns (uint8 level);

    /**
     * @notice Gets the current global emergency withdrawal settings.
     * @return enabled True if emergency withdrawal is enabled.
     * @return penalty The penalty in basis points.
     */
    function getEmergencyWithdrawalSettings() external view returns (bool enabled, uint256 penalty);

    /**
     * @notice Checks if the system is currently paused.
     * @return isPaused True if the system is paused.
     */
    function isSystemPaused() external view returns (bool isPaused);

    /**
     * @notice Retrieves a paginated list of all registered emergency-aware contracts.
     * @param offset The starting index for pagination.
     * @param limit The maximum number of addresses to return.
     * @return page A memory array of contract addresses.
     * @return totalContracts The total number of registered contracts.
     */
    function getEmergencyAwareContractsPaginated(uint256 offset, uint256 limit) external view returns (address[] memory page, uint256 totalContracts);
}
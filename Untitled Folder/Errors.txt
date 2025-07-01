// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// --- Generic / Common Errors ---
/// @dev Thrown when an address parameter is the zero address where it is not allowed.
/// @param context A string describing the context of the error (e.g., "initialOwner_").
error ZeroAddress(string context);
/// @dev Thrown when a function is called by an account that is not the owner.
error NotOwner();
/// @dev Thrown when a function is called by an account that does not have the required role.
/// @param requiredRole The `bytes32` identifier of the role that is required.
error NotAuthorized(bytes32 requiredRole);
/// @dev Thrown for generic invalid amount errors, typically when an amount is illogical in its context.
error InvalidAmount();
/// @dev Thrown when a required amount is zero where it should not be.
error AmountIsZero();
/// @dev Thrown when a transaction deadline has passed.
error DeadlineExpired();
/// @dev Thrown when a transaction deadline is set too far in the future.
error DeadlineTooFar();
/// @dev Thrown when a contract's local pause, inherited from Pausable, is active.
error ContractPaused();
/// @dev Thrown when the global emergency system is active, preventing operations.
error SystemInEmergencyMode();
/// @dev Thrown when a contract is used before it is properly initialized.
error NotInitialized();
/// @dev Thrown when an initializer function is called more than once.
error AlreadyInitialized();
/// @dev Thrown when a duration parameter is outside the allowed range.
error InvalidDuration();
/// @dev Thrown on a failed reentrancy check, indicating a potential reentrancy attack.
error ReentrancyGuardFailure();
/// @dev Thrown when an account has an insufficient token balance for an operation.
/// @param available The available balance.
/// @param required The required balance.
error InsufficientBalance(uint256 available, uint256 required);
/// @dev Thrown when a spender has an insufficient token allowance.
/// @param available The available allowance.
/// @param required The required allowance.
error InsufficientAllowance(uint256 available, uint256 required);
/// @dev Thrown on a failed low-level token transfer, often from `safeTransfer`.
error TransferFailed();
/// @dev Thrown when an action is attempted by or on a blacklisted account.
/// @param account The blacklisted account.
error AddressBlacklisted(address account);
/// @dev Thrown when a mint operation would exceed the token's total supply cap.
/// @param currentSupply The current total supply.
/// @param amount The amount being minted.
/// @param cap The maximum total supply.
error CapExceeded(uint256 currentSupply, uint256 amount, uint256 cap);
/// @dev Thrown when an address is expected to be a contract but is an External-Owned Account (EOA).
/// @param context A string describing the context of the error.
error NotAContract(string context);

// --- AccessControl Errors ---
/// @dev Thrown when attempting to grant or revoke the zero role (bytes32(0)), which is reserved.
error AC_RoleCannotBeZero();
/// @dev Thrown when granting a role to the zero address.
error AC_AccountInvalid();
/// @dev Thrown when trying to access a role member at an out-of-bounds index.
/// @param index The requested index.
/// @param length The current number of members in the role.
error AC_IndexOutOfBounds(uint256 index, uint256 length);
/// @dev Thrown when attempting to remove the last member of the admin role, which would lock the contract.
error AC_CannotRemoveLastAdmin();
/// @dev Thrown when the caller is missing the required admin role to manage another role.
/// @param adminRole The `bytes32` identifier of the required admin role.
error AC_SenderMissingAdminRole(bytes32 adminRole);

// --- LiquidityManager Errors ---
/// @dev Thrown if the pREWA token address is zero during initialization.
error LM_PTokenZero();
/// @dev Thrown if the DEX router address is zero during initialization.
error LM_RouterZero();
/// @dev Thrown if the AccessControl address is zero during initialization.
error LM_AccessControlZero();
/// @dev Thrown if the EmergencyController address is zero during initialization.
error LM_EmergencyControllerZero();
/// @dev Thrown if the OracleIntegration address is zero during initialization.
error LM_OracleIntegrationZero();
/// @dev Thrown if the PriceGuard address is zero during initialization.
error LM_PriceGuardZero();
/// @dev Thrown if the initial owner address is zero during initialization.
error LM_InitialOwnerZero();
/// @dev Thrown if the call to the router's `factory()` function fails.
error LM_FactoryFail();
/// @dev Thrown if the router returns a zero address for its factory.
error LM_InvalidFactory();
/// @dev Thrown if the call to the router's `weth()` function fails.
error LM_WETHFail();
/// @dev Thrown if the router returns a zero address for WETH.
error LM_WETHZero();
/// @dev Thrown when trying to interact with a pair that is not active.
/// @param pairName A string identifier for the pair.
error LM_PairNotActive(string pairName);
/// @dev Thrown when trying to interact with a pair that is not registered.
/// @param pairName A string identifier for the pair.
error LM_PairDoesNotExist(string pairName);
/// @dev A specific error for when the BNB pair is not active.
error LM_BNBPairNotActive();
/// @dev A specific error for when the BNB pair is not registered.
error LM_BNBPairDoesNotExist();
/// @dev Thrown when a swap's price impact exceeds the configured threshold.
error LM_PriceImpactTooHigh();
/// @dev Thrown if the amount of liquidity received is less than the minimum specified.
/// @param received The amount of LP tokens received.
/// @param expectedMin The minimum amount of LP tokens expected.
error LM_InsufficientLiquidityReceived(uint256 received, uint256 expectedMin);
/// @dev Thrown when a required name parameter (e.g., for a pair) is empty.
error LM_NameEmpty();
/// @dev Thrown when attempting to register a pair that is already registered.
/// @param pairName A string identifier for the pair.
error LM_PairAlreadyRegistered(string pairName);
/// @dev Thrown when the DEX factory returns a zero address upon pair creation.
/// @param name A string identifier for the pair.
/// @param tokenAddress The address of the token for which pair creation was attempted.
error LM_CreatePairReturnedZero(string name, address tokenAddress);
/// @dev Thrown when the DEX factory's `createPair` function reverts.
/// @param name A string identifier for the pair.
/// @param tokenAddress The address of the token for which pair creation was attempted.
/// @param reason The revert reason from the factory call.
error LM_CreatePairReverted(string name, address tokenAddress, string reason);
/// @dev Thrown when the slippage tolerance is set to an invalid value (e.g., >100%).
/// @param tolerance The invalid tolerance value provided.
error LM_SlippageInvalid(uint256 tolerance);
/// @dev Thrown when the deadline offset is set to an invalid value (e.g., zero or too large).
/// @param offset The invalid offset value provided.
error LM_DeadlineOffsetInvalid(uint256 offset);
/// @dev Thrown when a liquidity percentage parameter is invalid.
/// @param percentage The invalid percentage value provided.
error LM_LiquidityPercentageInvalid(uint256 percentage);
/// @dev Thrown if a new router address fails the `factory()` call check during an update.
error LM_RouterUpdateFactoryFail();
/// @dev Thrown if a new router address returns a zero address for its factory.
error LM_RouterUpdateInvalidFactory();
/// @dev Thrown when trying to recover the native pREWA token, which is not allowed.
error LM_CannotRecoverPToken();
/// @dev Thrown when trying to recover an active LP token, which is not allowed.
error LM_CannotRecoverActiveLP();
/// @dev Thrown when trying to recover a zero amount of tokens.
error LM_RecoverAmountZero();
/// @dev Thrown when the contract does not have a sufficient balance of the token to be recovered.
error LM_InsufficientBalanceForRecovery();
/// @dev Thrown when a required controller (e.g., EmergencyController) is not set.
/// @param context A string describing which controller is missing.
error LM_ControllerNotSet(string context);
/// @dev Thrown when a function is called by an account other than the EmergencyController.
error LM_CallerNotEmergencyController();
/// @dev Thrown when the PriceGuard address is expected to be a contract but is not.
error LM_PriceGuardNotContract();
/// @dev Thrown when registering an LP token with the OracleIntegration contract fails.
/// @param lpToken The address of the LP token.
/// @param token0 The address of the first underlying token.
/// @param token1 The address of the second underlying token.
error LM_OracleRegistrationFailed(address lpToken, address token0, address token1);
/// @dev Thrown when a DEX router returns a zero address for a required contract (e.g., WETH, factory).
/// @param context A string describing what address was expected.
error LM_RouterReturnedZeroAddress(string context);
/// @dev Thrown if a user has no pending BNB refund to recover.
error LM_NoPendingRefund();

// --- ContractRegistry Errors ---
/// @dev Thrown when a contract is registered with an empty name.
error CR_NameEmpty();
/// @dev Thrown when a contract is registered with a zero address.
/// @param context A string describing the context of the error.
error CR_ContractAddressZero(string context);
/// @dev Thrown when a contract is registered with an empty type string.
error CR_ContractTypeEmpty();
/// @dev Thrown when a contract is registered with an empty version string.
error CR_VersionEmpty();
/// @dev Thrown when attempting to register a contract with a name that is already in use.
/// @param name The duplicate name.
error CR_NameAlreadyRegistered(string name);
/// @dev Thrown when attempting to register a contract with an address that is already registered under a different name.
/// @param addr The duplicate address.
error CR_AddressAlreadyRegistered(address addr);
/// @dev Thrown when trying to look up a contract by a name that is not registered.
/// @param name The name that was not found.
error CR_ContractNotFound(string name);
/// @dev Thrown when a pagination query is made with a limit of zero.
error CR_LimitIsZero();
/// @dev Thrown when a pagination query is made with an index that is out of bounds.
error CR_IndexOutOfBounds();
/// @dev Thrown when AccessControl has not been set, but a function requiring it is called.
error CR_AccessControlZero();

// --- LPStaking Errors ---
/// @dev Thrown if the reward token address is zero during initialization.
error LPS_PTokenZero();
/// @dev Thrown if the LiquidityManager address is zero during initialization.
error LPS_LMZero();
/// @dev Thrown when a user tries to stake zero LP tokens.
error LPS_StakeAmountZero();
/// @dev Thrown when a user tries to stake into a tier that does not exist.
/// @param tierId The non-existent tier ID.
error LPS_TierDoesNotExist(uint256 tierId);
/// @dev Thrown when a user tries to stake into a pool that is not active or does not exist.
/// @param lpToken The address of the inactive or non-existent LP token pool.
error LPS_PoolNotActive(address lpToken);
/// @dev Thrown when a user has reached the maximum number of active staking positions.
/// @param current The user's current number of positions.
/// @param max The maximum allowed number of positions.
error LPS_MaxPositionsReached(uint256 current, uint256 max);
/// @dev Thrown when a user tries to stake into a tier that is not active.
/// @param tierId The ID of the inactive tier.
error LPS_TierNotActive(uint256 tierId);
/// @dev Thrown if the provided LP token address is invalid (e.g., zero address).
error LPS_InvalidLPTokenAddress();
/// @dev Thrown when a user attempts to create more than one stake in the same block.
error LPS_MultiStakeInBlock();
/// @dev Thrown when trying to interact with a staking position that does not exist for the user.
/// @param positionId The non-existent position ID.
error LPS_PositionDoesNotExist(uint256 positionId);
/// @dev Thrown when trying to interact with a staking position that is no longer active (e.g., already unstaked).
/// @param positionId The ID of the inactive position.
error LPS_PositionNotActive(uint256 positionId);
/// @dev Thrown when a user tries to claim rewards but there are none to claim.
error LPS_NoRewardsToClaim();
/// @dev Thrown when a user tries to perform an emergency withdrawal when the feature is not enabled.
error LPS_EMGWDNotEnabled();
/// @dev Thrown when trying to add a liquidity pool that already exists.
/// @param lpToken The address of the LP token for the existing pool.
error LPS_PoolAlreadyExists(address lpToken);
/// @dev Thrown when setting a pool's APR to an invalid value.
error LPS_RewardRateZero();
/// @dev Thrown when a tier's duration is less than the contract's minimum allowed duration.
/// @param duration The provided duration.
/// @param min The minimum allowed duration.
error LPS_DurationLessThanMin(uint256 duration, uint256 min);
/// @dev Thrown when a tier's duration exceeds the contract's maximum allowed duration.
/// @param duration The provided duration.
/// @param max The maximum allowed duration.
error LPS_DurationExceedsMax(uint256 duration, uint256 max);
/// @dev Thrown when a tier's reward multiplier is below the minimum allowed value.
/// @param multiplier The provided multiplier.
/// @param min The minimum allowed multiplier.
error LPS_MultiplierTooLow(uint256 multiplier, uint256 min);
/// @dev Thrown when a tier's reward multiplier exceeds the maximum allowed value.
/// @param multiplier The provided multiplier.
/// @param max The maximum allowed multiplier.
error LPS_MultiplierTooHigh(uint256 multiplier, uint256 max);
/// @dev Thrown when a tier's early withdrawal penalty exceeds the maximum allowed value.
/// @param penalty The provided penalty.
/// @param max The maximum allowed penalty.
error LPS_PenaltyTooHigh(uint256 penalty, uint256 max);
/// @dev Thrown when the maximum positions per user is set to zero.
error LPS_MaxPositionsMustBePositive();
/// @dev Thrown when trying to recover the main reward token, which is not allowed.
error LPS_CannotRecoverStakingToken();
/// @dev Thrown when trying to recover an LP token that is actively part of a staking pool.
/// @param lpToken The address of the staked LP token.
error LPS_CannotRecoverStakedLP(address lpToken);
/// @dev Thrown when a function is called by an account other than the EmergencyController.
error LPS_CallerNotEmergencyController();

// --- pREWAToken Errors ---
/// @dev Thrown if the AccessControl address is zero during initialization.
error PREWA_ACZero();
/// @dev Thrown if the EmergencyController address is zero during initialization.
error PREWA_ECZero();
/// @dev Thrown if the token name is empty during initialization.
error PREWA_NameEmpty();
/// @dev Thrown if the token symbol is empty during initialization.
error PREWA_SymbolEmpty();
/// @dev Thrown if the token decimals are invalid (0 or >18) during initialization.
error PREWA_DecimalsZero();
/// @dev Thrown when transferring from the zero address.
error PREWA_TransferFromZero();
/// @dev Thrown when transferring to the zero address.
error PREWA_TransferToZero();
/// @dev Thrown when the sender of a transfer is blacklisted.
/// @param account The blacklisted sender account.
error PREWA_SenderBlacklisted(address account);
/// @dev Thrown when the recipient of a transfer is blacklisted.
/// @param account The blacklisted recipient account.
error PREWA_RecipientBlacklisted(address account);
/// @dev Thrown when the owner in an `approve` call is blacklisted.
/// @param account The blacklisted owner account.
error PREWA_OwnerBlacklisted(address account);
/// @dev Thrown when the spender in an `approve` call is blacklisted.
/// @param account The blacklisted spender account.
error PREWA_SpenderBlacklisted(address account);
/// @dev Thrown when attempting to mint tokens without the minter role.
error PREWA_NotMinter();
/// @dev Thrown when attempting to mint tokens to the zero address.
error PREWA_MintToZero();
/// @dev Thrown when attempting to burn tokens from the zero address.
error PREWA_BurnFromZero();
/// @dev Thrown when trying to blacklist the zero address.
error PREWA_AccountBlacklistZero();
/// @dev Thrown when trying to blacklist an account that is already blacklisted.
/// @param account The account that is already blacklisted.
error PREWA_AccountAlreadyBlacklisted(address account);
/// @dev Thrown when a blacklist proposal already exists for an account.
/// @param account The account with an existing proposal.
error PREWA_BlacklistPropExists(address account);
/// @dev Thrown when trying to act on a blacklist proposal that does not exist.
/// @param account The account without a proposal.
error PREWA_NoBlacklistProp(address account);
/// @dev Thrown when trying to execute a blacklist proposal before its timelock has expired.
error PREWA_TimelockActive();
/// @dev Thrown when setting the blacklist timelock to an invalid duration.
/// @param duration The invalid duration.
error PREWA_TimelockDurationInvalid(uint256 duration);
/// @dev Thrown when trying to unblacklist an account that is not blacklisted.
/// @param account The account that is not blacklisted.
error PREWA_AccountNotBlacklisted(address account);
/// @dev Thrown when setting a new cap that is less than the current total supply.
/// @param cap The proposed new cap.
/// @param supply The current total supply.
error PREWA_CapLessThanSupply(uint256 cap, uint256 supply);
/// @dev Thrown when attempting to recover the token contract's own address.
error PREWA_CannotRecoverSelf();
/// @dev Thrown when the token recovery address is invalid.
error PREWA_BadTokenRecoveryAddress();
/// @dev Thrown when adding the zero address as a minter.
error PREWA_MinterAddressZero();
/// @dev Thrown when trying to add an account that already has the minter role.
/// @param minter The address that is already a minter.
error PREWA_AddressAlreadyMinter(address minter);
/// @dev Thrown when trying to remove the minter role from an account that does not have it.
/// @param minter The address that is not a minter.
error PREWA_AddressNotMinter(address minter);
/// @dev Thrown when an emergency function is called by an address other than the EmergencyController.
error PREWA_CallerNotEmergencyController();
/// @dev Thrown when an account without the pauser role tries to pause or unpause.
error PREWA_MustHavePauserRole();

// --- TokenStaking Errors ---
/// @dev Thrown if the staking token address is zero during initialization.
error TS_TokenZero();
/// @dev Thrown if the AccessControl address is zero during initialization.
error TS_ACZero();
/// @dev Thrown if the EmergencyController address is zero during initialization.
error TS_ECZero();
/// @dev Thrown if the initial admin address is zero during initialization.
error TS_AdminZero();
/// @dev Thrown if the base reward rate is zero during initialization.
error TS_RateZero();
/// @dev Thrown if the minimum stake duration is too short during initialization.
error TS_MinDurShort();
/// @dev Thrown if the minimum stake duration is too long during initialization.
error TS_MinDurLong();
/// @dev Thrown if the base APR is set to a value that is too high.
/// @param rate The invalid rate provided.
error TS_AnnualRateTooHigh(uint256 rate);
/// @dev Thrown if the daily penalty rate is set to a value that is too high.
/// @param rate The invalid rate provided.
error TS_DailyPenaltyTooHigh(uint256 rate);
/// @dev Thrown when the oracle provides an invalid price.
error TS_InvalidOraclePrice();
/// @dev Thrown when the oracle price data is stale.
error TS_StaleOraclePrice();
/// @dev Thrown when attempting to recover the main staking token, which is not allowed.
error TS_CannotUnprotectStakingToken();
/// @dev Thrown when a function is called by an account other than the EmergencyController.
error TS_CallerNotEmergencyController();

// --- EmergencyController Errors ---
/// @dev Thrown if the AccessControl address is zero during initialization.
error EC_AccessControlZero();
/// @dev Thrown if the EmergencyTimelockController address is zero during initialization.
error EC_TimelockControllerZero();
/// @dev Thrown if the required approvals for a Level 3 emergency is set to zero.
error EC_RequiredApprovalsZero();
/// @dev Thrown if the Level 3 timelock duration is set to a value that is too short.
error EC_TimelockTooShort();
/// @dev Thrown if the Level 3 timelock duration is set to a value that is too long.
error EC_TimelockTooLong();
/// @dev Thrown when trying to approve a Level 3 emergency when the system is already at that level.
error EC_AlreadyAtLevel3();
/// @dev Thrown when trying to cancel a Level 3 escalation when none is in progress.
error EC_NoLevel3EscalationInProgress();
/// @dev Thrown when setting an invalid emergency level (e.g., > 3).
/// @param level The invalid level provided.
error EC_InvalidEmergencyLevel(uint8 level);
/// @dev Thrown when trying to set the emergency level to 3 directly, which requires the approval process.
error EC_UseApproveForLevel3();
/// @dev Thrown when providing a zero address for a contract parameter.
error EC_ContractAddressZero();
/// @dev Thrown when trying to process a notification for a level that is not currently active.
/// @param level The requested, non-active emergency level.
error EC_LevelNotInEmergency(uint8 level);
/// @dev Thrown when trying to re-process an emergency notification for a contract that has already processed it recently.
/// @param contractAddress The address of the contract.
/// @param level The emergency level.
error EC_AlreadyProcessed(address contractAddress, uint8 level);
/// @dev Thrown when trying to interact with a contract that is not registered as emergency-aware.
/// @param contractAddress The address of the unregistered contract.
error EC_ContractNotRegistered(address contractAddress);
/// @dev Thrown when trying to unpause the system while it is at a critical emergency level.
error EC_CannotUnpauseAtLevel3();
/// @dev Thrown when setting a function restriction threshold to an invalid value.
/// @param threshold The invalid threshold provided.
error EC_ThresholdInvalid(uint8 threshold);
/// @dev Thrown when an admin address is not found or set.
error EC_AdminNotFound();
/// @dev Thrown when trying to pause a system that is already paused.
error EC_SystemAlreadyPaused();
/// @dev Thrown when trying to unpause a system that is not paused.
error EC_SystemNotPaused();
/// @dev Thrown when a penalty value exceeds the maximum allowed.
/// @param penalty The invalid penalty provided.
error EC_PenaltyTooHigh(uint256 penalty);
/// @dev Thrown when trying to execute a Level 3 emergency before its timelock has expired.
error EC_Level3TimelockNotExpired();
/// @dev Thrown when a caller lacks the EMERGENCY_ROLE.
error EC_MustHaveEmergencyRole();
/// @dev Thrown when a caller lacks the PAUSER_ROLE.
error EC_MustHavePauserRole();
/// @dev Thrown when a caller lacks the DEFAULT_ADMIN_ROLE.
error EC_MustHaveAdminRole();
/// @dev Thrown when the contract has an insufficient balance of a token to be recovered.
error EC_InsufficientBalanceToRecover();
/// @dev Thrown when setting the required approvals to a value that is too high.
/// @param requested The requested number of approvals.
/// @param maxAllowed The maximum allowed number of approvals.
error EC_RequiredApprovalsTooHigh(uint256 requested, uint256 maxAllowed);
/// @dev Thrown when trying to recover tokens but the recovery admin address is not set.
error EC_RecoveryAdminNotSet();
/// @dev Thrown when a pagination query is made with a limit of zero.
error EC_LimitIsZero();
/// @dev Thrown when a call to an emergency-aware contract's `emergencyShutdown` function fails.
error EC_EmergencyShutdownCallFailed();

// --- ProxyAdmin Errors ---
/// @dev Thrown if the AccessControl address is zero during initialization.
error PA_AccessControlZero();
/// @dev Thrown if the EmergencyController address is zero during initialization.
error PA_EmergencyControllerZero();
/// @dev Thrown if the upgrade timelock duration is set to an invalid value.
error PA_InvalidTimelockDuration();
/// @dev Thrown when a proxy address parameter is the zero address.
error PA_ProxyZero();
/// @dev Thrown on a failed call to get a proxy's implementation address.
error PA_GetImplFailed();
/// @dev Thrown on a failed call to get a proxy's admin address.
error PA_GetAdminFailed();
/// @dev Thrown when trying to change a proxy's admin to the zero address.
error PA_NewAdminZero();
/// @dev Thrown when a proxy's `changeAdmin` call fails.
/// @param reason The revert reason from the proxy call.
error PA_AdminChangeFailed(string reason);
/// @dev Thrown when an implementation address parameter is the zero address.
error PA_ImplZero();
/// @dev Thrown when trying to add an implementation to the allowlist that is already on it.
error PA_ImplAlreadyAdded();
/// @dev Thrown when trying to add an implementation that is not a contract.
error PA_ImplNotAContract();
/// @dev Thrown when trying to remove an implementation from the allowlist that was not on it.
error PA_ImplNotAdded();
/// @dev Thrown when an upgrade proposal already exists for a proxy.
error PA_UpgradePropExists();
/// @dev Thrown when proposing an upgrade to an implementation that is not on the active allowlist.
error PA_ImplNotApproved();
/// @dev Thrown when proposing an upgrade when no implementations are on the allowlist (and it's required).
error PA_NoValidImplsRegistered();
/// @dev Thrown when proposing an `upgradeToAndCall` with empty calldata.
error PA_DataEmptyForCall();
/// @dev Thrown when trying to act on an upgrade proposal that does not exist.
error PA_NoProposalExists();
/// @dev Thrown when a proposed implementation is no longer approved at the time of execution.
error PA_ImplNoLongerApproved();
/// @dev Thrown when a proposed implementation is no longer a contract at the time of execution.
error PA_ExecImplNotAContract();
/// @dev Thrown when a proxy's `upgradeTo` or `upgradeToAndCall` function fails.
/// @param reason The revert reason from the proxy call.
error PA_UpgradeFailed(string reason);
/// @dev Thrown when trying to cancel an upgrade proposal without the required permissions.
error PA_NotAuthorizedToCancel();
/// @dev Thrown when the EmergencyController address is not set but is required.
error PA_ECNotSet();
/// @dev Thrown when a function is called by an account other than the EmergencyController.
error PA_CallerNotEC();
/// @dev Thrown when trying to execute an upgrade before its timelock has expired.
error PA_TimelockNotYetExpired();
/// @dev Thrown if, at execution, the proposed implementation address is no longer a contract.
error PA_ImplementationNotAContractAtExecution();
/// @dev Thrown if, at execution, the proposed implementation is no longer on the allowlist (if it was verified at proposal time).
error PA_ImplementationNoLongerValidAtExecution();

// --- PriceGuard Errors ---
/// @dev Thrown when `getExpectedPrice` is called but the oracle is using a fallback price, which is disallowed for this function.
error PG_FallbackPriceNotAllowed();

// --- SecurityModule Errors ---
/// @dev Thrown if the EmergencyController address is zero during initialization.
error SM_ControllerZero();
/// @dev Thrown if the OracleIntegration address is zero during initialization.
error SM_OracleZero();
/// @dev Thrown if a token address parameter is the zero address.
error SM_TokenZero();
/// @dev Thrown when setting a threshold (e.g., for price deviation) to a value that is too high.
/// @param thresholdType A string describing the threshold being set.
error SM_ThresholdTooHigh(string thresholdType);
/// @dev Thrown when trying to set a threshold to zero when it should be positive.
/// @param thresholdType A string describing the threshold being set.
error SM_ThresholdNotPositive(string thresholdType);
/// @dev Thrown when the gas limit for external calls is set to an invalid value.
error SM_GasLimitInvalid();
/// @dev Thrown when the transaction cooldown is set to zero when it should be positive.
error SM_CooldownNotPositive();
/// @dev Thrown when the transaction cooldown is set to a value that is too high.
error SM_CooldownTooHigh();
/// @dev Thrown when a function is called while the SecurityModule is manually paused.
error SM_SecurityPaused();
/// @dev Thrown if an account parameter is the zero address.
error SM_AccountZero();
/// @dev Thrown when a commit hash for the commit-reveal scheme is zero.
error SM_CommitHashZero();
/// @dev Thrown when parameters for the commit-reveal scheme are empty where they should not be.
error SM_ParamsEmpty();
/// @dev Thrown when the salt for the commit-reveal scheme is zero.
error SM_SaltZero();
/// @dev Thrown when a price parameter is not positive where it should be.
error SM_PriceNotPositive();
/// @dev Thrown when a call to the OracleIntegration contract fails.
/// @param token The address of the token involved in the failed call.
/// @param reason The revert reason from the oracle call.
error SM_OracleCallFailed(address token, string reason);
/// @dev Thrown when a price deviation BPS parameter is invalid.
error SM_InvalidDeviationBPS();
/// @dev Thrown when a function is called by an account other than the EmergencyController.
error SM_CallerNotEmergencyController();
/// @dev Thrown when trying to resume the SecurityModule when it is not paused.
error SM_SecurityNotPaused();

// --- Vesting Errors ---
/// @dev Thrown if the vesting token address is the zero address.
error Vesting_TokenZero();
/// @dev Thrown if the beneficiary address is the zero address.
error Vesting_BeneficiaryZero();
/// @dev Thrown if the owner address is the zero address.
error Vesting_OwnerZeroV();
/// @dev Thrown if the vesting duration is zero.
error Vesting_DurationZero();
/// @dev Thrown if the vesting amount is zero.
error Vesting_AmountZeroV();
/// @dev Thrown if the cliff duration is longer than the total vesting duration.
error Vesting_CliffLongerThanDuration();
/// @dev Thrown if the vesting start time is set to a past timestamp.
error Vesting_StartTimeInvalid();
/// @dev Thrown when trying to release or revoke a vesting schedule that has already been revoked.
error Vesting_AlreadyRevoked();
/// @dev Thrown when trying to release tokens when none are currently due.
error Vesting_NoTokensDue();
/// @dev Thrown when trying to revoke a vesting schedule that is not revocable.
error Vesting_NotRevocable();
/// @dev Thrown when a function is called by an account other than the EmergencyController or the creating factory.
error Vesting_CallerNotEmergencyController();

// --- VestingFactory Errors ---
/// @dev Thrown when a pagination query is made with a limit of zero.
error VF_LimitIsZero();

// --- OracleIntegration Errors ---
/// @dev Thrown if a price feed address is the zero address.
error OI_PriceFeedZero();
/// @dev Thrown if a price feed aggregator is determined to be invalid during verification.
error OI_InvalidPriceFeed();
/// @dev Thrown on a failed call to get a price feed's decimals.
error OI_GetDecimalsFailed();
/// @dev Thrown when a price is below the minimum acceptable price.
/// @param price The price that was checked.
/// @param min The minimum acceptable price.
error OI_MinPriceNotMet(uint256 price, uint256 min);
/// @dev Thrown when no valid price source (primary or fallback) is available for a token.
error OI_NoPriceSource();
/// @dev Thrown when a price from a primary feed is stale and no valid fallback is available.
error OI_StalePriceData();
/// @dev Thrown when a price from a primary feed is zero or negative.
error OI_NegativeOrZeroPrice();
/// @dev Thrown when a price feed returns incomplete or invalid round data.
error OI_IncompleteRoundData();
/// @dev Thrown during price feed verification if the latest price is too old.
error OI_PriceTooOld();
/// @dev Thrown when a price feed fails and there is no fallback.
error OI_OracleFailedNoFallback();
/// @dev Thrown on an error fetching metadata for an LP token's underlying assets.
error OI_LPMetadataError();
/// @dev Thrown when calculating LP token value and the total supply is zero.
error OI_TotalSupplyZero();
/// @dev Thrown when calculating LP token value and the reserves are zero.
error OI_ReservesZero();
/// @dev Thrown when trying to get the value of an unregistered LP token.
error OI_LPNotRegistered();
/// @dev Thrown when unable to fetch prices for one or both underlying tokens of an LP pair.
error OI_FailedToGetTokenPrices();
/// @dev Thrown when a price deviation exceeds the maximum allowed.
error OI_DeviationExceedsMax();
/// @dev Thrown when the staleness threshold is set to zero.
error OI_StalenessThresholdZero();
/// @dev Thrown when the minimum acceptable price is set to zero.
error OI_MinAcceptablePriceZero();
/// @dev Thrown when the deviation BPS parameter is invalid (e.g., > 100%).
error OI_InvalidDeviationBPS();

// --- Generic & Utility Errors ---
/// @dev Thrown when arrays of different lengths are provided where they should be equal.
error GO_ArrayLengthMismatch();
/// @dev Thrown when arrays are empty where they should not be.
error GO_EmptyArrays();
/// @dev Thrown when an address is expected to be a contract but is not.
error GO_TargetNotAContract();
/// @dev Thrown when an index is out of bounds for an array.
error GO_IndexOutOfBounds();
/// @dev Thrown when a bit size parameter is invalid.
error GO_InvalidBitSize();
/// @dev Thrown when a value is too large to fit into the specified number of bits.
error GO_ValueTooLargeForBitSize();
/// @dev Thrown when the total number of bits for packing exceeds 256.
error GO_TotalBitsExceed256();
/// @dev Thrown when the bit sizes array for packing/unpacking is empty.
error GO_EmptyBitSizesArray();

// --- EmergencyTimelockController Errors ---
/// @dev Thrown when the calldata for a proposed action is too short to contain a function selector.
error ETC_DataTooShortForSelector();
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title Constants
 * @author Rewa
 * @notice A library of system-wide constants for easy access and consistency.
 * @dev This library centralizes frequently used values such as time units, basis points,
 * parameter limits, and emergency level identifiers.
 */
library Constants {
    // --- Time Constants ---
    /// @dev Number of seconds in one day.
    uint256 internal constant SECONDS_PER_DAY = 1 days;
    /// @dev Number of seconds in one week.
    uint256 internal constant SECONDS_PER_WEEK = 7 days;
    /// @dev Number of seconds in a 30-day month.
    uint256 internal constant SECONDS_PER_MONTH = 30 days;
    /// @dev Number of seconds in a 365-day year.
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    // --- Staking Duration Limits ---
    /// @dev The minimum allowed staking duration (1 day).
    uint256 public constant MIN_STAKING_DURATION = 1 days;
    /// @dev The maximum allowed staking duration (365 days).
    uint256 public constant MAX_STAKING_DURATION = 365 days;

    // --- Vesting Duration Limits ---
    /// @dev The minimum allowed vesting duration (7 days).
    uint256 internal constant MIN_VESTING_DURATION = 7 days;
    /// @dev The maximum allowed vesting duration (10 years).
    uint256 internal constant MAX_VESTING_DURATION = 10 * 365 days;

    // --- Vesting Amount Limit ---
    /// @dev A safety limit on the maximum amount for a single vesting schedule (1 billion tokens).
    uint256 public constant MAX_VESTING_AMOUNT = 1_000_000_000 * 1e18;

    // --- Timelock Duration Limits ---
    /// @dev The minimum allowed duration for timelocks (1 hour).
    uint256 internal constant MIN_TIMELOCK_DURATION = 1 hours;
    /// @dev The maximum allowed duration for timelocks (7 days).
    uint256 internal constant MAX_TIMELOCK_DURATION = 7 days;

    // --- Basis Points ---
    /// @dev The maximum value for basis points, representing 100%.
    uint256 internal constant BPS_MAX = 10000;

    // --- Slippage and Penalty Constants ---
    /// @dev The maximum allowed slippage tolerance (50%).
    uint256 internal constant MAX_SLIPPAGE = 5000;
    /// @dev The default slippage tolerance (1%).
    uint256 internal constant DEFAULT_SLIPPAGE = 100;
    /// @dev The default penalty for emergency actions (20%).
    uint256 public constant DEFAULT_PENALTY = 2000;
    /// @dev The maximum allowed penalty (50%).
    uint256 public constant MAX_PENALTY = 5000;

    // --- Reward Multiplier Constants ---
    /// @dev The minimum reward multiplier (0.01x).
    uint256 public constant MIN_REWARD_MULTIPLIER = 100;
    /// @dev The maximum reward multiplier (2.5x).
    uint256 internal constant MAX_REWARD_MULTIPLIER = 25000;
    /// @dev The default reward multiplier (1x).
    uint256 internal constant DEFAULT_REWARD_MULTIPLIER = 10000;

    // --- Precision Constants ---
    /// @dev Standard precision for decimal math (10^18).
    uint256 internal constant PRECISION = 1e18;
    /// @dev Precision for values with 6 decimals.
    uint256 internal constant PRECISION_6 = 1e6;
    /// @dev Precision for values with 8 decimals.
    uint256 internal constant PRECISION_8 = 1e8;
    /// @dev Precision for values with 9 decimals.
    uint256 internal constant PRECISION_9 = 1e9;

    // --- Emergency Levels ---
    /// @dev System is operating normally.
    uint8 internal constant EMERGENCY_LEVEL_NORMAL = 0;
    /// @dev A potential issue has been detected; heightened monitoring is required.
    uint8 internal constant EMERGENCY_LEVEL_CAUTION = 1;
    /// @dev A significant threat is active; some non-critical functions may be disabled, and emergency withdrawals may be enabled.
    uint8 internal constant EMERGENCY_LEVEL_ALERT = 2;
    /// @dev A critical security event is in progress; the system is globally paused.
    uint8 internal constant EMERGENCY_LEVEL_CRITICAL = 3;

    // --- Price Deviation Thresholds (in BPS) ---
    /// @dev The threshold for a warning-level price deviation (3%).
    uint256 internal constant PRICE_DEVIATION_WARNING = 300;
    /// @dev The threshold for an alert-level price deviation (10%).
    uint256 internal constant PRICE_DEVIATION_ALERT = 1000;
    /// @dev The threshold for a critical-level price deviation (20%).
    uint256 internal constant PRICE_DEVIATION_CRITICAL = 2000;

    // --- Oracle Staleness ---
    /// @dev The maximum age of an oracle price reading before it is considered stale (1 hour).
    uint256 internal constant ORACLE_MAX_STALENESS = 1 hours;

    // --- Versioning ---
    /// @dev The semantic version of the contract or system.
    string internal constant VERSION = "1.0.0";
    /// @dev A numerical representation of the version.
    uint256 internal constant VERSION_ID = 10000;

    // --- Common Function Selectors ---
    /// @dev The selector for the standard ERC20 `transfer` function.
    bytes4 internal constant SELECTOR_TRANSFER = bytes4(keccak256("transfer(address,uint256)"));
    /// @dev The selector for the standard ERC20 `approve` function.
    bytes4 internal constant SELECTOR_APPROVE = bytes4(keccak256("approve(address,uint256)"));
    /// @dev The selector for the standard ERC20 `transferFrom` function.
    bytes4 internal constant SELECTOR_TRANSFER_FROM = bytes4(keccak256("transferFrom(address,address,uint256)"));
}
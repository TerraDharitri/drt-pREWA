// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title PREWATokenStorage
 * @author drt-pREWA
 * @notice Defines the storage layout for the PREWAToken contract.
 * @dev This contract is not meant to be deployed directly. It is inherited by PREWAToken to separate
 * storage variables from logic, following the unstructured storage pattern for upgradeability.
 * This separation helps prevent storage layout collisions during contract upgrades.
 */
contract PREWATokenStorage {
    /// @notice Mapping from an account address to its token balance.
    mapping(address => uint256) internal _balances;

    /// @notice Mapping from an owner's address to a spender's address to the approved allowance.
    mapping(address => mapping(address => uint256)) internal _allowances;

    /// @notice The total supply of the token.
    uint256 internal _totalSupply;

    /// @notice The name of the token (e.g., "Dharitri pREWA").
    string internal _name;

    /// @notice The symbol of the token (e.g., "pREWA").
    string internal _symbol;

    /// @notice The number of decimals for the token's representation.
    uint8 internal _decimals;

    /// @notice The maximum total supply of the token. A value of 0 indicates no cap.
    uint256 internal _cap;

    /// @notice Mapping from an account address to its blacklisted status. If true, the address cannot transfer or receive tokens.
    mapping(address => bool) internal _blacklisted;

    /// @notice Mapping from an account address to its minter status. If true, the address can mint new tokens.
    mapping(address => bool) internal _minters;
    
    /**
     * @notice Struct representing a pending proposal to blacklist an account.
     * @param proposalTime The timestamp when the proposal was made.
     * @param executeAfter The timestamp after which the blacklisting can be executed.
     * @param proposer The address that initiated the proposal.
     * @param pending A flag indicating if the proposal is active.
     */
    struct BlacklistProposal {
        uint256 proposalTime;
        uint256 executeAfter;
        address proposer;
        bool pending;
    }

    /// @notice Mapping from an account address to its pending blacklist proposal.
    mapping(address => BlacklistProposal) internal _blacklistProposals;

    /// @notice The duration in seconds of the timelock for blacklisting proposals.
    uint256 internal _blacklistTimelockDuration;

    /// @notice Reserved storage space to allow for future upgrades without storage collisions.
    uint256[49] private __gap;
}
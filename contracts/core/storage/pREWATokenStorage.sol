// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title PREWATokenStorage
 * @author Rewa
 * @notice Defines the storage layout for the PREWAToken contract.
 * @dev This contract is not meant to be deployed. It is inherited by PREWAToken to separate
 * storage variables from logic, which can help in managing upgrades.
 */
contract PREWATokenStorage {
    /// @dev Mapping from an account address to its token balance.
    mapping(address => uint256) internal _balances;
    /// @dev Mapping from an owner's address to a spender's address to the approved allowance.
    mapping(address => mapping(address => uint256)) internal _allowances;
    /// @dev The total supply of the token.
    uint256 internal _totalSupply;

    /// @dev The name of the token.
    string internal _name;
    /// @dev The symbol of the token.
    string internal _symbol;
    /// @dev The number of decimals for the token.
    uint8 internal _decimals;

    /// @dev The maximum total supply of the token. A value of 0 means no cap.
    uint256 internal _cap;

    /// @dev Mapping from an account address to its blacklisted status.
    mapping(address => bool) internal _blacklisted;

    /// @dev Mapping from an account address to its minter status.
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

    /// @dev Mapping from an account address to its pending blacklist proposal.
    mapping(address => BlacklistProposal) internal _blacklistProposals;

    /// @dev The duration in seconds of the timelock for blacklisting proposals.
    uint256 internal _blacklistTimelockDuration;
}
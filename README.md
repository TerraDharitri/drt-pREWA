# pREWA Protocol

## Overview

The pREWA Protocol is a comprehensive, secure, and modular suite of smart contracts designed to power a sophisticated DeFi ecosystem. The architecture emphasizes security, upgradeability, and clear separation of concerns, providing a robust foundation for staking, liquidity management, token vesting, and more.

At its core, the protocol is governed by a multi-layered security framework, including a central `EmergencyController`, role-based `AccessControl`, and a `ProxyAdmin` with timelocked upgrades. This ensures that administrative actions are transparent and system-wide threats can be managed effectively.

## Core Components

The protocol is composed of several key contracts, each with a distinct responsibility:

| Contract | Description |
| :--- | :--- |
| **`AccessControl`** | A robust, enumerable role-based access control contract. It serves as the single source of truth for permissions across the entire protocol. |
| **`EmergencyController`** | A central hub for managing system-wide emergency states. It can broadcast pause signals and other commands to all integrated `IEmergencyAware` contracts. |
| **`ProxyAdmin`** | Manages the administration of all upgradeable proxy contracts. It enforces a timelock on all upgrade proposals for enhanced security. |
| **`pREWAToken`** | The native ERC20 token of the protocol. It is upgradeable and includes features like a supply cap, pausable transfers, and a timelocked blacklisting mechanism. |
| **`TokenStaking`** | A flexible contract for staking the native `pREWAToken`. It supports multiple tiers with different lockup durations, reward multipliers, and early-exit penalties. |
| **`LPStaking`** | A contract for staking Liquidity Provider (LP) tokens from a DEX. It allows for multiple LP token pools and configurable reward rates. |
| **`LiquidityManager`** | Facilitates adding and removing liquidity for `pREWA` pairs on a DEX (e.g., PancakeSwap). It integrates with `PriceGuard` to protect users. |
| **`VestingFactory`** | A factory for deploying and tracking token vesting schedules. It creates new vesting contracts as transparent upgradeable proxies. |
| **`OracleIntegration`** | A reliable price feed aggregator that integrates with Chainlink oracles. It provides standardized price data, handles staleness checks, and can value LP tokens. |
| **`SecurityModule`** | A proactive security contract that monitors on-chain activity for risks like flash loans, price manipulation, and anomalous volume. |
| **`PriceGuard`** | Protects users from high slippage and price impact during swaps by validating trades against oracle prices. |
| **`ContractRegistry`** | An on-chain directory for discovering the addresses of core protocol contracts, ensuring that components can reliably interact with each other. |

## Key Architectural Features

- **Upgradeable by Default**: All core logic contracts are deployed behind transparent upgradeable proxies (`TransparentProxy`), allowing for seamless bug fixes and feature additions without requiring data migration.
- **Centralized & Granular Permissions**: A single `AccessControl` contract manages all roles (`PROXY_ADMIN_ROLE`, `UPGRADER_ROLE`, `PARAMETER_ROLE`, etc.), providing a clear and auditable permissioning system.
- **Multi-Level Emergency System**: The `EmergencyController` defines a tiered emergency system (Normal, Caution, Alert, Critical) that allows for a proportional response to threats, from enabling emergency withdrawals to a full system-wide pause.
- **Timelocked Administrative Actions**: Critical operations, such as contract upgrades via `ProxyAdmin` and account blacklisting via `pREWAToken`, are subject to a mandatory timelock, giving stakeholders time to review and react to proposed changes.
- **Deep Security Integration**: Contracts are "emergency-aware" by implementing the `IEmergencyAware` interface. Security components like `SecurityModule` and `PriceGuard` are deeply integrated to provide proactive risk mitigation.
- **Separation of Concerns**: The codebase is highly modular. Storage variables are separated from logic (`ContractName.sol` vs. `ContractNameStorage.sol`), and distinct functionalities are encapsulated in their own contracts, enhancing readability and maintainability.

## Development Setup

This project uses the [Foundry](https://github.com/foundry-rs/foundry) framework for development, testing, and deployment.

### Prerequisites

- [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Installation

Clone the repository and install the dependencies:

```bash
git clone <repository_url>
cd <repository_directory>
forge install
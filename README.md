# Decentralized Stablecoin Protocol

**Author**: Luke4G1

- [Decentralized Stablecoin Protocol](#decentralized-stablecoin-protocol)
  - [Project Overview](#project-overview)
    - [Key Characteristics](#key-characteristics)
    - [Components of the Protocol](#components-of-the-protocol)
    - [Collateralization and Liquidation](#collateralization-and-liquidation)
  - [DecentralizedStableCoin Contract](#decentralizedstablecoin-contract)
  - [DSCEngine Contract](#dscengine-contract)
    - [Main Features](#main-features)
  - [OracleLib](#oraclelib)
  - [Testing](#testing)
  - [Quickstart](#quickstart)
  - [Installation and Setup](#installation-and-setup)
    - [Prerequisites](#prerequisites)
    - [Cloning the repository](#cloning-the-repository)
    - [Compile Smart Contracts](#compile-smart-contracts)
    - [Run Tests](#run-tests)
  - [License](#license)

## Project Overview

This is a smart contract protocol aimed at providing a stable digital currency pegged to the USD.

The system allows users to deposit cryptocurrencies like WETH and WBTC as collateral to mint DSC tokens, algorithmically stabilized against the USD.

It is similar to **DAI** if it had no governance, no fees and was only backed by WETH and WBTC.

### Key Characteristics

- **Stability**: Anchored to the USD
- **Minting Mechanism**: Algorithmic and decentralized
- **Collateral Types**: Exogenous (WETH & WBTC)
- **Collateralization Requirement**: 200% over-collateralized

### Components of the Protocol

The protocol is comprised of two primary smart contracts:

1. **DSCEngine**: Manages user interactions, including collateral management, token minting, and burning.
2. **DecentralizedStableCoin**: the ERC20 token that will be used as currency.

### Collateralization and Liquidation

To ensure protocol safety and stability, users must maintain a collateralization ratio of at least **200**%.

This means if a user has 500 DSC minted, they need to have collateral worth at least $1000 to avoid liquidation.

The protocol supports both total and partial liquidations.

## DecentralizedStableCoin Contract

This contract contains the logic of the **ERC20 token** that the system will use as currency.

## DSCEngine Contract

DSCEngine is the **heart** of the DSC system, handling collateral, minting, redeeming, and maintaining the overall health of the protocol.

### Main Features

- **Collateral Management**: Users can deposit and redeem collateral.
- **Token Minting and Burning**: Manages the issuance and destruction of DSC based on user actions.
- **Health Factor**: Ensures the system remains over-collateralized; users below a certain health factor threshold can be liquidated.
- **Price Feeds**: Integrates Chainlink Oracles for real-time price data of collateral assets.

## OracleLib

A vital component for the stability and reliability of the DSCEngine, OracleLib interacts with **Chainlink Data Feeds** to obtain up-to-date, accurate price data.

It includes mechanisms to guard against stale data, contributing to the protocol's robustness.

## Testing

The protocol has been tested with unit and stateful fuzz (invariant) testing.

You can find tests in the `/test` folder.

## Quickstart

```
git clone https://github.com/0xLuke4G1/4g1-decentralized-stablecoin
cd 4g1-decentralized-stablecoin
forge build
```

## Installation and Setup

This project is built using the Foundry framework, a fast, portable, and modular toolkit for smart contract development.

### Prerequisites

Before you begin, ensure you have Foundry installed. If not, you can install it by running the following command:

```shell
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Cloning the repository

```shell
git clone https://github.com/0xLuke4G1/4g1-decentralized-stablecoin
cd 4g1-decentralized-stablecoin
```

### Compile Smart Contracts

```shell
forge build
```

### Run Tests

```shell
forge test

# Unit tests

forge test --mt test__invariant

# Stateful Fuzz / Invariant

forge test --mt test__invariant
```

<!-- ## Protection Mechanisms -->

<!-- **⚠️ For this reason, please do not copy and deploy this code on the mainnet without solving and implementing these things first. ⚠️** -->

## License

Copyright © 2023, Luke4G1

This code is provided for portfolio and educational purposes only.

The system does not implement safeguard mechanisms to protect itself from becoming insolvent and drastic price drops.

For this reason, this code should not be used as-is in a live environment and it's **not intended for production** use as it currently stands.

The author takes no responsibility for any issues arising from its use.

Any use, modification, distribution, or deployment in a production environment is strictly at the user's own risk.

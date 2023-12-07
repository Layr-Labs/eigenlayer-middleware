[core-docs-m2]: https://github.com/Layr-Labs/eigenlayer-contracts/tree/m2-mainnet/docs

# EigenLayer Middleware

EigenLayer is a set of smart contracts deployed on Ethereum that enable restaking of assets to secure new services called AVSs (actively validated services). The core contracts that enable these features can be found in the [`eigenlayer-contracts` repo](https://github.com/Layr-Labs/eigenlayer-contracts).

This repo contains smart contracts used to create an AVS that interacts with the EigenLayer core contracts.

## Getting Started

* [Technical Documentation](#technical-documentation)
* [Building and Running Tests](#building-and-running-tests)
* [Deployments]()

## Technical Documentation

Technical documentation for this repo is in [the `/docs` folder](./docs).

It might be helpful to explore the EigenLayer core technical documentation as well, which you can find [here][core-docs-m2].

## Building and Running Tests

This repository uses Foundry. See the [Foundry docs](https://book.getfoundry.sh/) for more info on installation and usage. If you already have foundry, you can build this project with these commands:

```
foundryup

forge build
```

You can run all tests using this command:

```
forge test
```

## Deployments

TODO
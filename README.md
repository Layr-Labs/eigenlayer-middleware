[core-docs-m2]: https://github.com/Layr-Labs/eigenlayer-contracts/tree/m2-mainnet/docs
[core-repo]: https://github.com/Layr-Labs/eigenlayer-contracts

# EigenLayer Middleware

EigenLayer is a set of smart contracts deployed on Ethereum that enable restaking of assets to secure new services called AVSs (actively validated services). The core contracts that enable these features can be found in the [`eigenlayer-contracts` repo][core-repo].

This repo contains smart contracts used to create an AVS that interacts with the EigenLayer core contracts.

## Getting Started

* [Documentation](#documentation)
* [Building and Running Tests](#building-and-running-tests)
* [Deployments](#deployments)

## Documentation

### Basics

To get a basic understanding of EigenLayer, check out [You Could've Invented EigenLayer](https://www.blog.eigenlayer.xyz/ycie/). Note that some of the document's content describes features that do not exist yet (like the Slasher). To understand more about how restakers and operators interact with EigenLayer, check out these guides:
* [Restaking User Guide](https://docs.eigenlayer.xyz/restaking-guides/restaking-user-guide)
* [Operator Guide](https://docs.eigenlayer.xyz/operator-guides/operator-introduction)

Most of this content is intro-level and describes user interactions with the EigenLayer core contracts, but it should give you a good enough starting point.

### Deep Dive

The most up-to-date and technical documentation can be found in [/docs](/docs). If you're a shadowy super coder, this is a great place to get an overview of the contracts before diving into the code.

It might be helpful to explore the EigenLayer core technical documentation as well, which you can find [here][core-docs-m2].

## Building and Running Tests

This repository uses Foundry. See the [Foundry docs](https://book.getfoundry.sh/) for more info on installation and usage. If you already have foundry, you can build this project and run tests with these commands:

```
foundryup

forge build
forge test
```

## Deployments

### Current Mainnet Deployment

No contracts have been deployed to mainnet yet.

### Current Testnet Deployment

TODO
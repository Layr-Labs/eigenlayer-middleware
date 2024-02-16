[core-docs-dev]: https://github.com/Layr-Labs/eigenlayer-contracts/tree/dev/docs
[core-repo]: https://github.com/Layr-Labs/eigenlayer-contracts

# EigenLayer Middleware

EigenLayer is a set of smart contracts deployed on Ethereum that enable restaking of assets to secure new services called AVSs (actively validated services). The core contracts that enable these features can be found in the [`eigenlayer-contracts` repo][core-repo].

This repo contains smart contracts used to create an AVS that interacts with the EigenLayer core contracts. Because these contracts are meant to be used by any AVS, there is no single deployment. However, you can see EigenDA's deployment info on our [docs site](https://docs.eigenlayer.xyz/eigenda/deployed-contracts).

## Getting Started

* [Documentation](#documentation)
* [Building and Running Tests](#building-and-running-tests)

## Documentation

### Basics

To get a basic understanding of EigenLayer, check out [You Could've Invented EigenLayer](https://www.blog.eigenlayer.xyz/ycie/). Note that some of the document's content describes features that do not exist yet (like the Slasher). To understand more about how restakers and operators interact with EigenLayer, check out these guides:
* [Restaking User Guide](https://docs.eigenlayer.xyz/restaking-guides/restaking-user-guide)
* [Operator Guide](https://docs.eigenlayer.xyz/operator-guides/operator-introduction)

Most of this content is intro-level and describes user interactions with the EigenLayer core contracts, but it should give you a good enough starting point.

### Deep Dive

For shadowy super-coders:
* The most up-to-date technical documentation can be found in [/docs](/docs).
* To get an idea of how users interact with these contracts, check out the integration tests: [/test/integration](./test/integration)
* To explore the EigenLayer core contracts, check out the core repo technical docs [here][core-docs-dev].

## Building and Running Tests

This repository uses Foundry. See the [Foundry docs](https://book.getfoundry.sh/) for more info on installation and usage. If you already have foundry, you can build this project and run tests with these commands:

```sh
foundryup

forge build
forge test
```
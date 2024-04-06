[core-docs-dev]: https://github.com/Layr-Labs/eigenlayer-contracts/tree/dev/docs
[core-repo]: https://github.com/Layr-Labs/eigenlayer-contracts

# EigenLayer Middleware

EigenLayer is a set of smart contracts deployed on Ethereum that enable restaking of assets to secure new services called AVSs (actively validated services). The core contracts that enable these features can be found in the [`eigenlayer-contracts` repo][core-repo].

## Getting Started

* [Branching](#branching)
* [Documentation](#documentation)
* [Building and Running Tests](#building-and-running-tests)
* [Deployments](#deployments)

## Branching

The main branches we use are:
* [`dev (default)`](https://github.com/Layr-Labs/eigenlayer-middleware/tree/dev): The most up-to-date branch, containing the work-in-progress code for upcoming releases
* [`testnet-holesky`](https://github.com/Layr-Labs/eigenlayer-middleware/tree/testnet-holesky): Our current testnet deployment

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

## Deployments

The contracts in this repo are meant to be deployed by each AVS that wants to use them. The addresses listed below refer to EigenDA's deployment, and are included as an example.

### Current Mainnet Deployment

No contracts have been deployed to mainnet yet.

### Current Testnet Deployment

The current testnet deployment is on holesky, is from our M2 beta release. You can view the deployed contract addresses below, or check out the code itself on the [`testnet-holesky`](https://github.com/Layr-Labs/eigenlayer-middleware/tree/testnet-holesky) branch.

| Name | Solidity | Proxy | Implementation | Notes |
| -------- | -------- | -------- | -------- | -------- | 
| RegistryCoordinator | [`RegistryCoordinator.sol`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/testnet-holesky/src/RegistryCoordinator.sol) | [`0x5301...3490`](https://holesky.etherscan.io/address/0x53012C69A189cfA2D9d29eb6F19B32e0A2EA3490) | [`0xC908...bfa0`](https://holesky.etherscan.io/address/0xC908fAFAE29B5C9F0b5E0Da1d3025b8d6D42bfa0) | Proxy: [OpenZeppelin TUP@4.7.1](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
| StakeRegistry | [`StakeRegistry.sol`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/testnet-holesky/src/StakeRegistry.sol) | [`0xBDAC...a270`](https://holesky.etherscan.io/address/0xBDACD5998989Eec814ac7A0f0f6596088AA2a270) | [`0xa8d2...98E5`](https://holesky.etherscan.io/address/0xa8d25410c3e3347d93647f10FB6961069BEc98E5) | Proxy: [OpenZeppelin TUP@4.7.1](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
| IndexRegistry | [`IndexRegistry.sol`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/testnet-holesky/src/IndexRegistry.sol) | [`0x2E3D...7a5D`](https://holesky.etherscan.io/address/0x2E3D6c0744b10eb0A4e6F679F71554a39Ec47a5D) | [`0x889B...420d`](https://holesky.etherscan.io/address/0x889B040116f453D89e9d6d692Ad70Edd7357420d) | Proxy: [OpenZeppelin TUP@4.7.1](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
| BLSApkRegistry | [`BLSApkRegistry.sol`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/testnet-holesky/src/BLSApkRegistry.sol) | [`0x066c...730D`](https://holesky.etherscan.io/address/0x066cF95c1bf0927124DFB8B02B401bc23A79730D) | [`0x885C...e064`](https://holesky.etherscan.io/address/0x885C0CC8118E428a2C04de58A93eB15Ed4F0e064) | Proxy: [OpenZeppelin TUP@4.7.1](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
| OperatorStateRetriever | [`OperatorStateRetriever.sol`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/testnet-holesky/src/OperatorStateRetriever.sol) | - | [`0xB4ba...6C67`](https://holesky.etherscan.io/address/0xB4baAfee917fb4449f5ec64804217bccE9f46C67) | |
| ProxyAdmin | [OpenZeppelin ProxyAdmin@4.7.1](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/ProxyAdmin.sol) | - | [`0xB043...5c15`](https://holesky.etherscan.io/address/0xB043055dd967A382577c2f5261fA6428f2905c15) | |
| EigenDAServiceManager | [`eigenda/EigenDAServiceManager.sol`](https://github.com/Layr-Labs/eigenda/blob/a33b41561cc3fb4cd6d50a8738e4c5dca43ec0a5/contracts/src/core/EigenDAServiceManager.sol) | [`0xD4A7...e84b`](https://holesky.etherscan.io/address/0xD4A7E1Bd8015057293f0D0A557088c286942e84b) | [`0xa722...67f3`](https://holesky.etherscan.io/address/0xa7227485e6C693AC4566fe168C5E3647c5c267f3) | Proxy: [OpenZeppelin TUP@4.7.1](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
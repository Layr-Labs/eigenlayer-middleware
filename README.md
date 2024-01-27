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

For shadowy super-coders:
* The most up-to-date technical documentation can be found in [/docs](/docs).
* To get an idea of how users interact with these contracts, check out the integration tests: [/test/integration](./test/integration)
* To explore the EigenLayer core contracts, check out the core repo technical docs [here][core-docs-m2].

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

The current testnet deployment is from our M2 beta release, which is a slightly older version of this repo. You can view the deployed contract addresses below, or check out the [`v0.1.0`](https://github.com/Layr-Labs/eigenlayer-middleware/tree/v0.1.0-m2-goerli) branch in "Releases".


| Name | Solidity | Proxy | Implementation | Notes |
| -------- | -------- | -------- | -------- | -------- | 
| RegistryCoordinator | [`BLSRegistryCoordinatorWithIndices.sol`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/v0.1.0-m2-goerli/src/BLSRegistryCoordinatorWithIndices.sol) | [`0x0b30...4C0B`](https://goerli.etherscan.io/address/0x0b30a3427765f136754368a4500bAca8d2a54C0B) | [`0x9A70...a0e4`](https://goerli.etherscan.io/address/0x9A70ED111FaFEC41856202536AFAA38841a9a0e4) | Proxy: [OpenZeppelin TUP@4.7.1](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
| StakeRegistry | [`StakeRegistry.sol`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/v0.1.0-m2-goerli/src/StakeRegistry.sol) | [`0x5a83...A206`](https://goerli.etherscan.io/address/0x5a834d58D22742503D8f92dd2f28c866C166A206) | [`0x8741...5B98`](https://goerli.etherscan.io/address/0x8741e3a24d9517Aa19E63122A34680a9A85F5B98) | Proxy: [OpenZeppelin TUP@4.7.1](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
| IndexRegistry | [`IndexRegistry.sol`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/v0.1.0-m2-goerli/src/IndexRegistry.sol) | [`0xa8A1...BDF7`](https://goerli.etherscan.io/address/0xa8A14B97d556cEc3f4384C186fB99d72F015BDF7) | [`0x8cd4...8117`](https://goerli.etherscan.io/address/0x8cd4c39B713B026319e35f20B7f19baE28648117) | Proxy: [OpenZeppelin TUP@4.7.1](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
| BLSApkRegistry | [`BLSPubkeyRegistry.sol`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/v0.1.0-m2-goerli/src/BLSPubkeyRegistry.sol) | [`0xD8fC...BEcA`](https://goerli.etherscan.io/address/0xD8fCD5c9103962DE37E375EF9dB62cCf39D5BEcA) | [`0x4C9D...aFb8`](https://goerli.etherscan.io/address/0x4C9D23fd901d3d98e75BdcC6a8AC9bA81d8DaFb8) | Proxy: [OpenZeppelin TUP@4.7.1](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
| BLSPubkeyCompendium <br />(deprecated) | [`BLSPublicKeyCompendium.sol`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/v0.1.0-m2-goerli/src/BLSPublicKeyCompendium.sol) | - | [`0xc81d...1b19`](https://goerli.etherscan.io/address/0xc81d3963087fe09316cd1e032457989c7ac91b19) | |
| OperatorStateRetriever | [`BLSOperatorStateRetriever.sol`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/v0.1.0-m2-goerli/src/BLSOperatorStateRetriever.sol) | - | [`0x737d...a3a3`](https://goerli.etherscan.io/address/0x737dd62816a9392e84fa21c531af77c00816a3a3) | |
| ProxyAdmin | [OpenZeppelin ProxyAdmin@4.7.1](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/ProxyAdmin.sol) | - | [`0xbe85...aF3e`](https://goerli.etherscan.io/address/0xbe85B38b6086A45350947DD6dA6d78cc2E4BaF3e) | |
| EigenDAServiceManager | [`eigenda/EigenDAServiceManager.sol`](https://github.com/Layr-Labs/eigenda/blob/f599513723a17ad7bd5693287f75325007deec19/contracts/EigenDAServiceManager.sol#L4831) | [`0x9FcE...0010`](https://goerli.etherscan.io/address/0x9FcE30E01a740660189bD8CbEaA48Abd36040010) | [`0x1261...9606`](https://goerli.etherscan.io/address/0x12612f42bc1f09680c3d0c8dae72d5cd534c9606) | Proxy: [OpenZeppelin TUP@4.7.1](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
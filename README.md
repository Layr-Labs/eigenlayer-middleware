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
* [`mainnet`](https://github.com/Layr-Labs/eigenlayer-middleware/tree/mainnet): Our current mainnet deployment

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

The current mainnet deployment is from our M2 mainnet release. You can view the deployed contract addresses below, or check out the code itself on the [`mainnet`](https://github.com/Layr-Labs/eigenlayer-middleware/tree/mainnet) branch.

| Name | Proxy | Implementation | Notes |
| -------- | -------- | -------- | -------- |
[`RegistryCoordinator`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/mainnet/src/RegistryCoordinator.sol) | [`0x0baac79acd45a023e19345c352d8a7a83c4e5656`](https://etherscan.io/address/0x0baac79acd45a023e19345c352d8a7a83c4e5656#readProxyContract) | [`0xd3e0...EECF`](https://etherscan.io/address/0xd3e09a0c2a9a6fdf5e92ae65d3cc090a4df8eecf#code) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
[`StakeRegistry`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/mainnet/src/StakeRegistry.sol) | [`0x006124ae7976137266feebfb3f4d2be4c073139d`](https://etherscan.io/address/0x006124ae7976137266feebfb3f4d2be4c073139d#readProxyContract) | [`0x1C46...dd96`](https://etherscan.io/address/0x1c468cf7089d263c2f53e2579b329b16abc4dd96#code) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
[`IndexRegistry`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/mainnet/src/IndexRegistry.sol) | [`0xbd35a7a1cdef403a6a99e4e8ba0974d198455030`](https://etherscan.io/address/0xbd35a7a1cdef403a6a99e4e8ba0974d198455030#readProxyContract) | [`0x1ae0...a14c`](https://etherscan.io/address/0x1ae0b73118906f39d5ed30ae4a484ce2f479a14c#code) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
[`BLSApkRegistry`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/mainnet/src/BLSApkRegistry.sol) | [`0x00a5fd09f6cee6ae9c8b0e5e33287f7c82880505`](https://etherscan.io/address/0x00a5fd09f6cee6ae9c8b0e5e33287f7c82880505#readProxyContract) | [`0x5d0B...eD2b`](https://etherscan.io/address/0x5d0b9ce2e277daf508528e9f6bf6314e79e4ed2b#code) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
[`OperatorStateRetriever`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/mainnet/src/OperatorStateRetriever.sol) | - | [`0xD5D7...8C31`](https://etherscan.io/address/0xd5d7fb4647ce79740e6e83819efdf43fa74f8c31#code) | |
[`ServiceManagerRouter`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/mainnet/src/ServiceManagerRouter.sol) | - | [`0x518D...09eA`](https://etherscan.io/address/0x518d5140b5c935fe094f00f2dd64f2f95c4f09ea#code) | |
[`ProxyAdmin`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/ProxyAdmin.sol) | - | [`0x8247...2E99`](https://etherscan.io/address/0x8247ef5705d3345516286b72bfe6d690197c2e99#code) | |
[`eigenda/EigenDAServiceManager`](https://github.com/Layr-Labs/eigenda/blob/08d8781a2165c159ac9bb502dd61ed6ed340601c/contracts/src/core/EigenDAServiceManager.sol) | [`0x870679e138bcdf293b7ff14dd44b70fc97e12fc0`](https://etherscan.io/address/0x870679e138bcdf293b7ff14dd44b70fc97e12fc0#readProxyContract) | [`0xF5fD...899e`](https://etherscan.io/address/0xf5fd25a90902c27068cf5ebe53be8da693ac899e#code) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |

### Current Testnet Deployment

The current testnet deployment is on holesky, is from our M2 beta release. You can view the deployed contract addresses below, or check out the code itself on the [`testnet-holesky`](https://github.com/Layr-Labs/eigenlayer-middleware/tree/testnet-holesky) branch.

| Name | Proxy | Implementation | Notes |
| -------- | -------- | -------- | -------- |
[`RegistryCoordinator`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/testnet-holesky/src/RegistryCoordinator.sol) | [`0x53012C69A189cfA2D9d29eb6F19B32e0A2EA3490`](https://holesky.etherscan.io/address/0x53012C69A189cfA2D9d29eb6F19B32e0A2EA3490) | [`0xC908...bfa0`](https://holesky.etherscan.io/address/0xC908fAFAE29B5C9F0b5E0Da1d3025b8d6D42bfa0) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
[`StakeRegistry`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/testnet-holesky/src/StakeRegistry.sol) | [`0xBDACD5998989Eec814ac7A0f0f6596088AA2a270`](https://holesky.etherscan.io/address/0xBDACD5998989Eec814ac7A0f0f6596088AA2a270) | [`0xa8d2...98E5`](https://holesky.etherscan.io/address/0xa8d25410c3e3347d93647f10FB6961069BEc98E5) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
[`IndexRegistry`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/testnet-holesky/src/IndexRegistry.sol) | [`0x2E3D6c0744b10eb0A4e6F679F71554a39Ec47a5D`](https://holesky.etherscan.io/address/0x2E3D6c0744b10eb0A4e6F679F71554a39Ec47a5D) | [`0x889B...420d`](https://holesky.etherscan.io/address/0x889B040116f453D89e9d6d692Ad70Edd7357420d) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
[`BLSApkRegistry`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/testnet-holesky/src/BLSApkRegistry.sol) | [`0x066cF95c1bf0927124DFB8B02B401bc23A79730D`](https://holesky.etherscan.io/address/0x066cF95c1bf0927124DFB8B02B401bc23A79730D) | [`0x885C...e064`](https://holesky.etherscan.io/address/0x885C0CC8118E428a2C04de58A93eB15Ed4F0e064) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
[`OperatorStateRetriever`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/testnet-holesky/src/OperatorStateRetriever.sol) | - | [`0xB4ba...6C67`](https://holesky.etherscan.io/address/0xB4baAfee917fb4449f5ec64804217bccE9f46C67) | |
[`ServiceManagerRouter`](https://github.com/Layr-Labs/eigenlayer-middleware/blob/testnet-holesky/src/ServiceManagerRouter.sol) | - | [`0x4463...5a37`](https://holesky.etherscan.io/address/0x44632dfBdCb6D3E21EF613B0ca8A6A0c618F5a37#code) | |
[`ProxyAdmin`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/ProxyAdmin.sol) | - | [`0xB043...5c15`](https://holesky.etherscan.io/address/0xB043055dd967A382577c2f5261fA6428f2905c15) | |
[`eigenda/EigenDAServiceManager`](https://github.com/Layr-Labs/eigenda/blob/a33b41561cc3fb4cd6d50a8738e4c5dca43ec0a5/contracts/src/core/EigenDAServiceManager.sol) | [`0xD4A7E1Bd8015057293f0D0A557088c286942e84b`](https://holesky.etherscan.io/address/0xD4A7E1Bd8015057293f0D0A557088c286942e84b) | [`0xa722...67f3`](https://holesky.etherscan.io/address/0xa7227485e6C693AC4566fe168C5E3647c5c267f3) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |


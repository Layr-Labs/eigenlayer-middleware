# v1.5.0 Multichain/MiddlewareV2/Hourglass

These are the combined release notes of multichain and hourglass. 

# v1.4.0 MultiChain/MiddlewareV2

The multichain/middlewareV2 release enables AVSs to launch their services and make verified Operator outputs available on any EVM chain, meeting their customers where they are. AVSs can specify custom operator weights to be transported to any destination chain. The release has 3 components:

1. Core Contracts
2. AVS Contracts
3. Offchain Infrastructure

The below release notes cover AVS Contracts. For more information on the end to end protocol, see our [docs](../docs/middlewareV2/README.md), [core contract docs](https://github.com/Layr-Labs/eigenlayer-contracts/tree/main/docs/multichain), and [ELIP-008](https://github.com/eigenfoundation/ELIPs/blob/main/ELIPs/ELIP-008.md).

## Release Manager

@ypatil12 @eigenmikem

## Highlights

This multichain release only introduces new standards and contracts. As a result, there are **no breaking changes or deprecations**. All new contracts are in the [middlewareV2 folder](../src/middlewareV2/). 

🚀 New Features – Highlight major new functionality

- `AVSRegistrar`: The primary interface for managing operator registration and deregistration within an AVS. It integrates with core EigenLayer contracts to ensure operators have valid keys and are properly registered in operator sets
- `OperatorTableCalculator`: Responsible for calculating stake weights of operator. These stake weights are aggregated and transported using the [Eigenlayer Multichain Protocol](https://github.com/eigenfoundation/ELIPs/blob/main/ELIPs/ELIP-008.md). In order to utilize the multichain protocol, an AVS *MUST* deploy an `OperatorTableCalculator` and register it in the `CrossChainRegistry` in EigenLayer core. See our [core documentation](https://github.com/Layr-Labs/eigenlayer-contracts/tree/main/docs/multichain#common-user-flows) for this process. 

🔧 Improvements – Enhancements to existing features.

- The multichain protocol has protocol-ized several AVS-deployed contracts, enabling an simpler AVS developer experience. These include:
    - `KeyRegistrar`: Manages BLS and ECDSA signing keys. AVSs no longer have to deploy a `BLSAPKRegistry`
    - `CertificateVerifier`: Handles signature verification for BLS and ECDSA keys. AVSs no longer have to deploy a `BLSSignatureChecker`
    - Offchain Multichain Transport: AVSs no longer have to maintain [avs-sync](https://github.com/Layr-Labs/avs-sync) to keep operator stakes fresh

# v1.5.0 Hourglass

The Hourglass release consists of a framework that supports the creation of task-based AVSs. The task-based AVSs are enabled through a `TaskMailbox` core contract deployed to all chains that support a `CertificateVerifier`. Additionally AVSs deploy their `TaskAVSRegistrar`. The release has 3 components:

1. Core Contracts
2. AVS Contracts
3. Offchain Infrastructure

The below release notes cover AVS Contracts. For more information on the end to end protocol, see our [docs](https://github.com/Layr-Labs/hourglass-monorepo/blob/master/README.md) and [ELIP-010](https://github.com/eigenfoundation/ELIPs/blob/main/ELIPs/ELIP-010.md).

## Release Manager

@0xrajath

## Highlights

This hourglass release only introduces new contracts. As a result, there are no breaking changes or deprecations.

🚀 New Features

- `TaskAVSRegistrar`: An instanced (per-AVS) eigenlayer middleware contract on L1 that is responsible for handling operator registration for specific operator sets of your AVS and providing the offchain components with socket endpoints for the Aggregator and Executor operators. It also keeps track of which operator sets are the aggregator and executors. It works by default, but can be extended to include additional onchain logic for your AVS.

# Changelog
* fix: bls sig operator state retriever sorting by @RonTuretzky in https://github.com/Layr-Labs/eigenlayer-middleware/pull/480
* chore: update core submodule by @ypatil12 in https://github.com/Layr-Labs/eigenlayer-middleware/pull/497
* test: table calc by @ypatil12 in https://github.com/Layr-Labs/eigenlayer-middleware/pull/499
* test: ecdsa stake reg/bls sig checker utils by @ypatil12 in https://github.com/Layr-Labs/eigenlayer-middleware/pull/500
* release: middlewareV2/multichain by @ypatil12 in https://github.com/Layr-Labs/eigenlayer-middleware/pull/496
* fix: broken link by @ypatil12 in https://github.com/Layr-Labs/eigenlayer-middleware/pull/501
* chore: update `AVSRegistrar` for new `KeyRegistrar` interface by @ypatil12 in https://github.com/Layr-Labs/eigenlayer-middleware/pull/502
* chore: update submodule by @ypatil12 in https://github.com/Layr-Labs/eigenlayer-middleware/pull/503
* feat(redistribution): update slashers by @0xClandestine in https://github.com/Layr-Labs/eigenlayer-middleware/pull/492
* docs: format table in `OperatorTableCalculator` by @ypatil12 in https://github.com/Layr-Labs/eigenlayer-middleware/pull/505
* docs: add new table calculators by @ypatil12 in https://github.com/Layr-Labs/eigenlayer-middleware/pull/508
* fix(H-1): correct array indexing for BN254TableCalculatorBase._calculateOperatorTable by @nadir-akhtar in https://github.com/Layr-Labs/eigenlayer-middleware/pull/504
* feat: hourglass by @0xrajath in https://github.com/Layr-Labs/eigenlayer-middleware/pull/515
* fix: multichain pt1 audit fixes by @ypatil12 in https://github.com/Layr-Labs/eigenlayer-middleware/pull/520
* fix: make storage variable internal due to existing getter by @nadir-akhtar in https://github.com/Layr-Labs/eigenlayer-middleware/pull/524
* fix(I-07): add onlyInitializing modifier to initializing function by @nadir-akhtar in https://github.com/Layr-Labs/eigenlayer-middleware/pull/525
* feat: tablecalc modules by @eigenmikem in https://github.com/Layr-Labs/eigenlayer-middleware/pull/514
* fix(I-05): remove unused import by @ypatil12 in https://github.com/Layr-Labs/eigenlayer-middleware/pull/529
* fix: multichain pt2 audit fixes by @ypatil12 in https://github.com/Layr-Labs/eigenlayer-middleware/pull/528
* chore: bump core submodule by @ypatil12 in https://github.com/Layr-Labs/eigenlayer-middleware/pull/531
* feat: add UAM to `SocketRegistry` by @ypatil12 in https://github.com/Layr-Labs/eigenlayer-middleware/pull/532
* fix: add allowlist to TaskAVSRegistarBase by @nadir-akhtar in https://github.com/Layr-Labs/eigenlayer-middleware/pull/533
* chore: update core submodule + ReadME by @ypatil12 in https://github.com/Layr-Labs/eigenlayer-middleware/pull/534
* fix: task replay directed at same operator set by @0xrajath in https://github.com/Layr-Labs/eigenlayer-middleware/pull/535
* chore: update core bindings by @0xrajath in https://github.com/Layr-Labs/eigenlayer-middleware/pull/536
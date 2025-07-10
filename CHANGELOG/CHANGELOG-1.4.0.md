# v1.4.0 MultiChain/MiddlewareV2

The multichain/middlewareV2 release enables AVSs to launch their services and make verified Operator outputs available on any EVM chain, meeting their customers where they are. AVSs can specify custom operator weights to be transported to any destination chain. The release has 3 components:

1. Core Contracts
2. AVS Contracts
3. Offchain Infrastructure

The below release notes cover AVS Contracts. For more information on the end to end protocol, see our [docs](../docs/middlewareV2/README.md), [core contract docs](https://github.com/Layr-Labs/eigenlayer-contracts/tree/main/docs/multichain), and [ELIP-008](https://github.com/eigenfoundation/ELIPs/blob/elip-008v1/ELIPs/ELIP-008.md).

## Release Manager

@ypatil12 @eigenmikem

## Highlights

This multichain release only introduces new standards and contracts. As a result, there are **no breaking changes or deprecations**. All new contracts are in the [middlewareV2 folder](../src/middlewareV2/). 

🚀 New Features – Highlight major new functionality

- `AVSRegistrar`: The primary interface for managing operator registration and deregistration within an AVS. It integrates with core EigenLayer contracts to ensure operators have valid keys and are properly registered in operator sets
- `OperatorTableCalculator`: Responsible for calculating stake weights of operator. These stake weights are aggregated and transported using the [Eigenlayer Multichain Protocol](https://github.com/eigenfoundation/ELIPs/blob/elip-008v1/ELIPs/ELIP-008.md). In order to utilize the multichain protocol, an AVS *MUST* deploy an `OperatorTableCalculator` and register it in the `CrossChainRegistry` in EigenLayer core. See our [core documentation](https://github.com/Layr-Labs/eigenlayer-contracts/tree/main/docs/multichain#common-user-flows) for this process. 

🔧 Improvements – Enhancements to existing features.

- The multichain protocol has protocol-ized several AVS-deployed contracts, enabling an simpler AVS developer experience. These include:
    - `KeyRegistrar`: Manages BLS and ECDSA signing keys. AVSs no longer have to deploy a `BLSAPKRegistry`
    - `CertificateVerifier`: Handles signature verification for BLS and ECDSA keys. AVSs no longer have to deploy a `BLSSignatureChecker`
    - Offchain Multichain Transport: AVSs no longer have to maintain [avs-sync](https://github.com/Layr-Labs/avs-sync) to keep operator stakes fresh

## Changelog

- fix: avs registrar as identifier [PR #494](https://github.com/layr-labs/eigenlayer-middleware/pull/494)
- fix: table calc interface [PR #493](https://github.com/layr-labs/eigenlayer-middleware/pull/493)
- docs: middlewareV2/multichain [PR #489](https://github.com/layr-labs/eigenlayer-middleware/pull/489)
- chore: add avs registrar interfaces [PR #491](https://github.com/layr-labs/eigenlayer-middleware/pull/491)
- chore: remove unused imports [PR #490](https://github.com/layr-labs/eigenlayer-middleware/pull/490)
- feat: add table calculators  [PR #488](https://github.com/layr-labs/eigenlayer-middleware/pull/488)
- chore: remove interfaces [PR #485](https://github.com/layr-labs/eigenlayer-middleware/pull/485)
- chore: bump up ecdsa dependency [PR #487](https://github.com/layr-labs/eigenlayer-middleware/pull/487)
- chore: bump up `eigenlayer-contracts` dependency [PR #486](https://github.com/layr-labs/eigenlayer-middleware/pull/486)
- feat: avs registrar [PR #484](https://github.com/layr-labs/eigenlayer-middleware/pull/484)
- refactor: singleton cv combining ECDSA and BN254 [PR #479](https://github.com/layr-labs/eigenlayer-middleware/pull/479)
- feat: multichain interfaces [PR #477](https://github.com/layr-labs/eigenlayer-middleware/pull/477)
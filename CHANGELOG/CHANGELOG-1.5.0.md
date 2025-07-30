# v1.5.0 Hourglass

The Hourglass release consists of a framework that supports the creation of task-based AVSs. The task-based AVSs are enabled through a `TaskMailbox` core contract deployed to all chains that support a `CertificateVerifier`. Additionally AVSs deploy their `TaskAVSRegistrar`. The release has 3 components:

1. Core Contracts
2. AVS Contracts
3. Offchain Infrastructure

The below release notes cover AVS Contracts. For more information on the end to end protocol, see our [docs](https://github.com/Layr-Labs/hourglass-monorepo/blob/master/README.md).

## Release Manager

@0xrajath

## Highlights

This hourglass release only introduces new contracts. As a result, there are no breaking changes or deprecations.

🚀 New Features

- `TaskAVSRegistrar`: An instanced (per-AVS) eigenlayer middleware contract on L1 that is responsible for handling operator registration for specific operator sets of your AVS and providing the offchain components with socket endpoints for the Aggregator and Executor operators. It also keeps track of which operator sets are the aggregator and executors. It works by default, but can be extended to include additional onchain logic for your AVS.

## Changelog

- chore: bump up core deps
- feat: hourglass [PR #507](https://github.com/layr-labs/eigenlayer-middleware/pull/507)

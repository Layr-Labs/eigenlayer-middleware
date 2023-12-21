<!-- 
Reference Links:
 -->
[core-contracts-repo]: https://github.com/Layr-Labs/eigenlayer-contracts
[core-docs-m2]: https://github.com/Layr-Labs/eigenlayer-contracts/tree/m2-mainnet/docs
[eigenda-repo]: https://github.com/Layr-Labs/eigenda/
[bitmaputils-lib]: ../src/libraries/BitmapUtils.sol

[core-registerToAVS]: https://github.com/Layr-Labs/eigenlayer-contracts/blob/m2-mainnet/docs/core/DelegationManager.md#registeroperatortoavs
[core-deregisterFromAVS]: https://github.com/Layr-Labs/eigenlayer-contracts/blob/m2-mainnet/docs/core/DelegationManager.md#deregisteroperatorfromavs

## EigenLayer Middleware Docs

EigenLayer AVSs ("actively validated services") are protocols that make use of EigenLayer's restaking primitives. AVSs are validated by EigenLayer operators, who are backed by delegated restaked assets via the [EigenLayer core contracts][core-contracts-repo]. Each AVS will deploy or modify instances of the contracts in this repo to hook into the EigenLayer core contracts and ensure their service has an up-to-date view of its currently-registered operators.

**Currently, each AVS needs to implement one thing on-chain:** registration/deregistration conditions that define how an operator registers for/deregisters from the AVS. This repo provides building blocks to support these functions.

*Eventually,* the core contracts and this repo will be extended to cover other conditions, including:
* payment conditions that define how an operator is paid for the services it provides
* slashing conditions that define "malicious behavior" in the context of the AVS, and the punishments for this behavior

*... however, the design for these conditions is still in progress.*

**Additional Note**: Although the goal of this repo is to eventually provide general-purpose building blocks for all kinds of AVSs, many of the contracts and design considerations were made to support EigenDA. When these docs provide examples, they will often cite EigenDA.

For more information on EigenDA, check out the repo: [Layr-Labs/eigenda][eigenda-repo].

### Contents

* [Important Concepts](#important-concepts)
    * [Quorums](#quorums)
    * [Strategies and Stake](#strategies-and-stake)
    * [Operator Sets and Churn](#operator-sets-and-churn)
    * [State Histories](#state-histories)
    * [Hooking Into EigenLayer Core](#hooking-into-eigenlayer-core)
* [System Components](#system-components)
    * [Service Manager](#service-manager)
    * [Registries](#registries)
    * [BLSSignatureChecker](#blssignaturechecker)

---

### Important Concepts

##### Quorums

A quorum is a grouping and configuration of specific kinds of stake that an AVS considers when interacting with operators. When operators register for an AVS, they select one or more quorums within the AVS to register for. Depending on its configuration, each quorum evaluates a specific subset of the operator's restaked tokens and uses this to determine a specific weight for the operator for that quorum. This weight is ultimately used to determine when an AVS has reached consensus.

The purpose of having a quorum is that an AVS can customize the makeup of its security offering by choosing which kinds of stake/security it would like to utilize.

As an example, an AVS might want to support primarily native ETH stakers. It would do so by configuring a quorum to only weigh operators that control shares belonging to the native eth strategy (defined in the core contracts).

The Owner initializes quorums in the `RegistryCoordinator`, and may configure them further in both the `RegistryCoordinator` and `StakeRegistry` contracts. When quorums are initialized, they are assigned a unique, sequential quorum number.

*Note:* For the most part, quorum numbers are passed between contracts as `bytes` arrays containing an ordered list of quorum numbers. However, when storing lists of quorums in state (and for other operations), these `bytes` arrays are converted to bitmaps using the [`BitmapUtils` library][bitmaputils-lib].

##### Strategies and Stake

Each quorum has an associated list of `StrategyParams`, which the Owner can configure via the `StakeRegistry`.

`StrategyParams` define pairs of strategies and multipliers for the quorum:
* Strategies refer to the `DelegationManager` in the EigenLayer core contracts, which tracks shares delegated to each operator for each supported strategy. Basically, a strategy is a wrapper around an underlying token - either an LST or Native ETH.
* Multipliers determine the relative weight given to shares belonging to the corresponding strategy.

When the `StakeRegistry` updates its view of an operator's stake for a given quorum, it queries the `DelegationManager` to get the operator's shares in each of the quorum's strategies and applies the multiplier to the returned share count.

For more information on the `DelegationManager`, see the [EigenLayer core docs][core-docs-m2].

##### Operator Sets and Churn

Quorums define a maximum operator count as well as parameters that determine when a new operator can replace an existing operator when this max count is reached. The process of replacing an existing operator when the max count is reached is called "churn," and requires a signature from the Churn Approver.

These definitions are contained in a quorum's `OperatorSetParam`, which the Owner can configure via the `RegistryCoordinator`. A quorum's `OperatorSetParam` defines both a max operator count, as well as stake thresholds that the incoming and existing operators need to meet to qualify for churn.

*Additional context*:

Currently for EigenDA, the max operator count is 200. This maximum exists because EigenDA requires that completed "jobs" validate a signature by the aggregate BLS pubkey of the operator set over some job parameters. Although an aggregate BLS pubkey's signature should have a fixed cost no matter the number of operators, it may be the case that not all operators sign off on a job.

When this happens, EigenDA needs to provide a list of the pubkeys of the non-signers to subtract them out from the quorum's aggregate pubkey ("Apk"). The limit of 200 operators keeps the gas costs reasonable in a worst case scenario. See `BLSSignatureChecker.checkSignatures` for this part of the implementation.

In order to prevent the operator set from getting calcified, the churn mechanism was introduced to allow operators to be replaced in some cases. Future work is being done to increase the max operator count and refine the churn mechanism.

##### State Histories

Many of the contracts in this repo keep histories of states over time. Generally, you'll see structs that look like this:

```solidity
struct ValueUpdate {
    Value value;
    uint32 updateBlockNumber;     // when the value started being valid
    uint32 nextUpdateBlockNumber; // when the value stopped being valid (or 0, if the value is still valid)
}
```

These histories are used by offchain code to query state at particular blocks, and are ultimately used to validate specific actions on-chain. See the [`BLSSignatureChecker` section](#blssignaturechecker) below.

##### Hooking Into EigenLayer Core

The main thing that links an AVS to the EigenLayer core contracts is that when EigenLayer operators register/deregister with an AVS, the AVS calls these functions in EigenLayer core:
* [`DelegationManager.registerOperatorToAVS`][core-registerToAVS]
* [`DelegationManager.deregisterOperatorFromAVS`][core-deregisterFromAVS]

These methods ensure that the operator registering with the AVS is also registered as an operator in EigenLayer core. In this repo, these methods are called by the `ServiceManagerBase`.

Eventually, operator slashing and payment for services will be part of the middleware/core relationship, but these features aren't implemented yet and their design is a work in progress.

### System Components

#### Service Manager

| Code | Type | Proxy |
| -------- | -------- | -------- |
| [`ServiceManagerBase.sol`](../src/ServiceManagerBase.sol) | Singleton | Transparent proxy |

The Service Manager contract serves as the AVS's address relative to EigenLayer core contracts. When operators register for/deregister from the AVS, the Service Manager forwards this request to the DelegationManager (see [Hooking Into EigenLayer Core](#hooking-into-eigenlayer-core) above).

It also contains a few convenience methods used to query operator information by the frontend.

See full documentation in [`ServiceManagerBase.md`](./ServiceManagerBase.md).

#### Registries

| Code | Type | Proxy |
| -------- | -------- | -------- |
| [`RegistryCoordinator.sol`](../src/RegistryCoordinator.sol) | Singleton | Transparent proxy |
| [`BLSApkRegistry.sol`](../src/BLSApkRegistry.sol) | Singleton | Transparent proxy |
| [`StakeRegistry.sol`](../src/StakeRegistry.sol) | Singleton | Transparent proxy |
| [`IndexRegistry.sol`](../src/IndexRegistry.sol) | Singleton | Transparent proxy |

The `RegistryCoordinator` keeps track of which quorums exist and have been initialized. It is also the primary entry point for operators as they register for and deregister from an AVS's quorums.

When operators register or deregister, the registry coordinator updates that operator's currently-registered quorums, and pushes the registration/deregistration to each of the three registries it controls:
* `BLSApkRegistry`: tracks the aggregate BLS pubkey hash for the operators registered to each quorum. Also maintains a history of these aggregate pubkey hashes.
* `StakeRegistry`: interfaces with the EigenLayer core contracts to determine the weight of operators according to their stake and each quorum's configuration. Also maintains a history of these weights.
* `IndexRegistry`: assigns indices to operators within each quorum, and tracks historical indices and operators per quorum. Used primarily by offchain infrastructure to fetch ordered lists of operators in quorums.

Both the registry coordinator and each of the registries maintain historical state for the specific information they track. This historical state tracking can be used to query state at a particular block, which is primarily used in offchain infrastructure.

See full documentation for the registry coordinator in [`RegistryCoordinator.md`](./RegistryCoordinator.md), and for each registry in [`registries/`](./registries/).

#### BLSSignatureChecker

| Code | Type | Proxy |
| -------- | -------- | -------- |
| [`BLSSignatureChecker.sol`](../src/BLSSignatureChecker.sol) | Singleton | Transparent proxy |
| [`OperatorStateRetriever.sol`](../src/OperatorStateRetriever.sol) | Singleton | Transparent proxy |

The BLSSignatureChecker verifies signatures made by the aggregate pubkeys ("Apk") of operators in one or more quorums. The primary function, `checkSignatures`, is called by an AVS when confirming that a given message hash is signed by operators belonging to one or more quorums.

The `OperatorStateRetriever` is used by offchain code to query the `RegistryCoordinator` (and its registries) for information that will ultimately be passed into `BLSSignatureChecker.checkSignatures`.

See full documentation for both of these contracts in [`BLSSignatureChecker.md`](./BLSSignatureChecker.md).
<!-- 
Reference Links:
 -->
[core-contracts-repo]: https://github.com/Layr-Labs/eigenlayer-contracts
[core-docs-m2]: https://github.com/Layr-Labs/eigenlayer-contracts/tree/m2-mainnet/docs

## EigenLayer Middleware Docs

EigenLayer AVSs ("actively validated services") are protocols that make use of EigenLayer's restaking primitives. AVSs are validated by EigenLayer operators, who are backed by delegated restaked assets via the [EigenLayer core contracts][core-contracts-repo]. AVSs deploy or modify instances of the contracts in this repo to hook into the core contracts and ensure their service has an up-to-date view of its currently-registered operators.

**Currently, each AVS needs to implement one thing on-chain:** registration/deregistration conditions that define how an operator registers for/deregisters from the AVS. This repo provides building blocks to support these functions.

*Eventually,* the core contracts and this repo will be extended to cover other conditions, including:
* payment conditions that define how an operator is paid for the services it provides
* slashing conditions that define "malicious behavior" in the context of the AVS, and the punishments for this behavior

*... however, the design for these conditions is still in progress.*

TODO - also missing the servicemanagerbase and maybe other contracts?

### Contents

* [Important Concepts](#important-concepts)
    * [Quorums](#quorums)
    * [Strategies and Stake](#strategies-and-stake)
    * [Operator Sets and Churn](#operator-sets-and-churn)
* [System Components](#system-components)
    * [Registries](#registries)

---

### Important Concepts

##### Quorums

A quorum is a grouping and configuration of specific kinds of stake that an AVS considers when interacting with operators. When operators register for an AVS, they select one or more quorums within the AVS to regsiter for. The purpose of having a quorum is that an AVS can customize the makeup of its security offering by choosing which kinds of stake/security it would like to utilize.

As an example, an AVS might want to support primarily native ETH stakers. It would do so by configuring a quorum to only weigh operators that control shares belonging to the native eth strategy (defined in the core contracts).

The Service Manager Owner initializes quorums in `BLSRegistryCoordinatorWithIndices`, and may configure them further in both the `BLSRegistryCoordinatorWithIndices` and `StakeRegistry` contracts.

##### Strategies and Stake

Each quorum has an associated list of `StrategyParams`, which the Service Manager Owner can configure via the `StakeRegistry`.

`StrategyParams` define pairs of strategies and multipliers for the quorum:
* Strategies refer to the `DelegationManager` in the EigenLayer core contracts, which tracks shares delegated to each operator for each supported strategy. Basically, a strategy is a wrapper around an underlying token - either an LST or Native ETH.
* Multipliers determine the relative weight given to shares belonging to the corresponding strategy.

When the `StakeRegistry` updates its view of an operator's stake for a given quorum, it queries the `DelegationManager` to get the operator's shares in each of the quorum's strategies and applies the multiplier to the returned share count.

For more information on the `DelegationManager`, see the [EigenLayer core docs][core-docs-m2].

##### Operator Sets and Churn

Quorums define a maximum operator count as well as parameters that determine when a new operator can replace an existing operator when this max count is reached. The process of replacing an existing operator when the max count is reached is called "churn," and requires a signature from the Churn Approver.

These definitions are contained in a quorum's `OperatorSetParam`, which the Service Manager Owner can configure via the `BLSRegistryCoordinatorWithIndices`. A quorum's `OperatorSetParam` defines both a max operator count, as well as stake thresholds that the incoming and existing operators need to meet to qualify for churn.

### System Components

#### Registries

| File | Type | Proxy |
| -------- | -------- | -------- |
| [`BLSRegistryCoordinatorWithIndices.sol`](../src/BLSRegistryCoordinatorWithIndices.sol) | Singleton | Transparent proxy |
| [`BLSPubkeyRegistry.sol`](../src/BLSPubkeyRegistry.sol) | Singleton | Transparent proxy |
| [`StakeRegistry.sol`](../src/StakeRegistry.sol) | Singleton | Transparent proxy |
| [`IndexRegistry.sol`](../src/IndexRegistry.sol) | Singleton | Transparent proxy |

The `BLSRegistryCoordinatorWithIndices` is the primary entry point for operators as they register for and deregister from an AVS's quorums. When operators register or deregister, the registry coordinator updates that operator's currently-registered quorums, and pushes the registration/deregistration to each of the three registries it controls:
* `BLSPubkeyRegistry`: tracks the aggregate BLS pubkey hash for the operators registered to each quorum. Also maintains a history of these aggregate pubkey hashes.
* `StakeRegistry`: interfaces with the EigenLayer core contracts to track historical state of operators per quorum.
* `IndexRegistry`: assigns indices to operators within each quorum, and tracks historical indices and operators per quorum. Used primarily by offchain infrastructure to fetch ordered lists of operators in quorums.

Both the registry coordinator and each of the registries maintain historical state for the specific information they track. This historical state tracking can be used to query state at a particular block, which is primarily used in offchain infrastructure.

See full documentation for the registry coordinator in [`BLSRegistryCoordinatorWithIndices.md`](./BLSRegistryCoordinatorWithIndices.md), and for each registry in [`registries/`](./registries/).
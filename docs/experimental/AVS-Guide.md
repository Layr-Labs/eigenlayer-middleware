[middleware-guide-link]: #quick-start-guide-to-build-avs-contracts
[operator-set-guide-link]: #https://www.blog.eigenlayer.xyz/introducing-the-eigenlayer-security-model
[uam-link]: #https://github.com/eigenfoundation/ELIPs/blob/main/ELIPs/ELIP-003.md
# Purpose
This document aims to describe and summarize how autonomous verifiable services (AVSs) building on EigenLayer interact with the core EigenLayer protocol. Currently, this doc explains how AVS developers can use the APIs for:
- enabling operators to opt-in to the AVS,
- enabling operators to opt-out (withdraw stake) from the AVS,
- enabling operators to continuously update their commitments to middlewares,
- enabling AVSs to create operator sets,
- enabling AVSs to submit rewards for operators and stakers, and
- enabling AVSs to slash operators for malicious behaviour.

# Introduction
In designing EigenLayer, the EigenLabs team aspired to make minimal assumptions about the structure of AVSs built on top of it. This repo contains code that can be extended, used directly, or consulted as a reference in building an AVS on top of EigenLayer. All the middleware contracts are AVS-specific and need to be deployed separately by AVS teams which interface with the EigenLayer core contracts, deployed by EigenLabs.

## Important Terminology
- **Tasks** - A task in EigenLayer is the smallest unit of work that operators commit to perform when serving an AVS. These tasks may be associated with one or more operator sets within the AVS.
- **Strategies** - A strategy in EigenLayer is a contract that holds staker deposits, i.e. it controls one or more asset(s) that can be restaked. EigenLayer's strategy design is flexible and open, meaning anyone can permissionlessly deploy a strategy using the `StrategyManager` in the core contracts.
- **Operator Sets** - An operator set in EigenLayer is a way to distinguish different classes of operators within an AVS. Operators may be seperated on the basis of the tasks they perform, supported strategies, rewards they recieve or, the slashing conditions operators are subject to. There are two types of operator sets that an AVS may create, total delegated stake and unique stake. See [this][operator-set-guide-link] blog post for further information on the different types of operator sets.

# Key Design Considerations
1. *Decomposition into "Tasks"*: <br/>
    EigenLayer assumes that an AVS manages tasks that are executed over time by a registered operator. Each task is associated with the time period during which the AVS's operators' stakes are placed "at stake", i.e. potentially subject to slashing. Examples of tasks could be:
    - Hosting and serving a “DataStore” in the context of EigenDA
    - Posting a state root of another blockchain for a bridge service

2. *Stake is "At Stake" on Tasks for a Finite Duration*: <br/>
    It is assumed that every task (eventually) resolves. Each operator places their stake in EigenLayer “at stake” on the tasks that they perform. In order to “release” the stake (e.g. so the operator can withdraw their funds), these tasks need to eventually resolve. It is RECOMMENDED, but not required that a predefined duration is specified in the AVS contract for each task. As a guideline, the EigenLabs team believes that the duration of a task should be aligned with the longest reasonable duration that would be acceptable for an operator to keep funds “at stake”. An AVS builder should recognize that extending the duration of a task may impose significant negative externalities on the stakers of EigenLayer, and may disincentivize operators from opting-in to serving their application (so that they can attract more delegated stake). At the time of writing, the `DEALLOCATION_DELAY` which is the time it takes for stake to be deallocated from an AVS is 14 days.

3. *Services Slash Only Objectively Attributable Behavior*: <br/>
    EigenLayer is built to support slashing as a result of an on-chain-checkable, objectively attributable action. An AVS SHOULD slash in EigenLayer only for such provable and attributable behavior. It is expected that operators will be very hesitant to opt-in to services that slash for other types of behavior, and other services may even choose to exclude operators who have opted-in to serving one or more AVSs with such “subjective slashing conditions”, as these slashing conditions present a significant challenge for risk modeling, and may be perceived as more dangerous in general. Some examples of on-chain-checkable, objectively attributable behavior: 
    - double-signing a block in Ethereum, but NOT inactivity leak; 
    - proofs-of-custody in EigenDA, but NOT a node ceasing to serve data; 
    - a node in a light-node-bridge AVS signing an invalid block from another chain.

    Intersubjective slashing will be supported in the future through the Eigen token.

4. *Contract Interactions for Services and EigenLayer*: <br/>
    It is assumed that services have a two contracts that coordinate the service’s communications sent to EigenLayer. The first contract – referred to as the `ServiceManager` – informs EigenLayer when an operator should be slashed, evicted or jailed, when rewards are submitted, setting AVS metadata and, managing UAM (refer to [here][uam-link] for further information on UAM). The second contract is the `SlashingRegistryCoordinator` which calls into EigenLayer to create operator sets and, force ejection of operators. AVSs can choose deviate from this pattern, but this will result in a worse developer and operator experience and is not reccomended.

## Integration with EigenLayer Contracts:
In this section, we will explain various API interfaces that EigenLayer provides which are essential for AVSs to integrate with EigenLayer. 

### *Operators Opting into AVS*
An operator opts into an AVS by allocating stake to an AVS then register for the operator set. The flow is as follows:
1. The operator calls `modifyAllocations(..)`, supplying the operator set of the AVS, the strategies and the magnitudes to allocate. After the transaction is successful, the allocation delay is triggered, which is the time it takes for the stake to become active or slashable. Operators configure this value and can be set to 0.
2. After the allocation delay has elapsed, the operator can then register for the operator set they allocated to, by calling `registerForOperatorSets(..)`, supplying the address of the `SlashingRegistryCoordinator` which implements the `IAVSRegistrar` interface, operator set IDs and, any extra data needed for registration.

The following figure illustrates the above flow:

<p align="center">
  <img src="../images/operator_registration.png" alt="Operator opting-in" width="500">
</p>

### *Recording Stake Updates*
EigenLayer is a dynamic system where stakers and operators are constantly adjusting amounts of stake delegated via the system. It is therefore imperative for an AVS to be aware of any changes to stake delegated to its operators. In order to facilitate this, EigenLayer offers the `Slasher.recordStakeUpdate(..)`.

Let us illustrate the usage of this facility with an example: A staker has delegated to an operator, who has opted-in to serving an AVS. Whenever the staker withdraws some or all of its stake from EigenLayer, this withdrawal affects all the AVSs uniformly that the staker's delegated operator is participating in. The series of steps for withdrawing stake is as follows:
 - The staker queues their withdrawal request with EigenLayer. The staker can place this request by calling  `StrategyManager.queueWithdrawal(..)`.
 - The operator, noticing an upcoming change in their delegated stake, notifies the AVS about this change. To do this, the operator triggers the AVS to call the `ServiceManager.recordStakeUpdate(..)` which in turn accesses `Slasher.recordStakeUpdate(..)`.  On successful execution of this call, the event `MiddlewareTimesAdded(..)` is emitted.
- The AVS provider now is aware of the change in stake, and the staker can eventually complete their withdrawal.  Refer [here](https://github.com/Layr-Labs/eigenlayer-contracts/blob/master/docs/EigenLayer-withdrawal-flow.md) for more details

The following figure illustrates the above flow: 
![Stake update](../images/staker_withdrawing.png)

### *Deregistering from AVS*
In order for any EigenLayer operator to be able to de-register from an AVS, EigenLayer provides the interface `Slasher.recordLastStakeUpdateAndRevokeSlashingAbility(..)`. Essentially, in order for an operator to deregister from an AVS, the operator has to call `Slasher.recordLastStakeUpdateAndRevokeSlashingAbility(..)`  via the AVS's ServiceManager contract. It is important to note that the latest block number until which the operator is required to serve tasks for the service must be known by the service and included in the ServiceManager's call to `Slasher.recordLastStakeUpdateAndRevokeSlashingAbility`.

The following figure illustrates the above flow in which the operator calls the `deregister(..)` function in a sample Registry contract.
![Operator deregistering](../images/operator_deregister.png)

### *Slashing*
As mentioned above, EigenLayer is built to support slashing as a result of an on-chain-checkable, objectively attributable action. In order for an AVS to be able to slash an operator in an objective manner, the AVS needs to deploy a DisputeResolution contract which anyone can call to raise a challenge against an EigenLayer operator for its adversarial action. On successful challenge, the DisputeResolution contract calls `ServiceManager.freezeOperator(..)`; the ServiceManager in turn calls `Slasher.freezeOperator(..)` to freeze the operator in EigenLayer. EigenLayer's Slasher contract emits a `OperatorFrozen(..)` event whenever an operator is (successfully) frozen


## Quick Start Guide to Build AVS Contracts:
The EigenLayer team has built this repo as a set of reusable and extensible contracts for use in AVSs built on top of EigenLayer, which comprises code that can be extended, used directly, or consulted as a reference in building AVS on top of EigenLayer. There are several basic contracts that all AVS-specific contracts can be built on:
- The *VoteWeigherBase contract* tracks an operator’s “weight” in a given quorum, across all strategies that are associated with that quorum.  This contract also manages which strategies are in each quorum - this includes functionalities for both adding and removing strategies, as well as changing strategy weights.  
- The *RegistryBase contract* is a basic registry contract that can be used to track operators opted-into running an AVS.  Importantly, this base registry contract assumes a maximum of two quorums, where each quorum represents an aggregation of a certain type of stake. 

Furthermore, it’s expected that many AVSs will require a quorum of registered operators to sign on commitments.  To this end, the EigenLabs team has developed a set of contracts designed to optimize the cost of checking signatures through the use of a BLS aggregate signature scheme:
### BLSPublicKeyCompendium
This contract allows each Ethereum address to register a unique BLS public key; a single BLSPublicKeyCompendium contract can be shared amongst all AVSs using BLS signatures. <br/>
### BLSRegistry
This contract builds upon lower-level (RegistryBase and VoteWeigherBase) contracts, to allow users of EigenLayer to register as operators for a single AVS. Each AVS’s BLSRegistry keeps a historic record of the Aggregate Public Key (APK) of all operators of the AVS. To allow proper encoding of data and aggregation of signatures while avoiding race conditions (e.g. from operators registering or deregistering, causing the current APK to change), each task defines a referenceBlockNumber, which may be briefly in the past. The BLSRegistry defines an optional whitelister role, which controls whether or not the whitelist is enabled and can edit the whitelist. If the whitelist is enabled, then only addresses that have been whitelisted may opt-in to serving the AVS. <br/>   

In addition, the BLSRegistry (technically the lower-level RegistryBase which the BLSRegistry inherits from) defines a “minimum stake” for the quorum(s). An operator can only register for the AVS if they meet the minimum requirement for at least one quorum. By default the `ServiceManager.owner()` has the ability to change the minimum stake requirement(s). Each BLSRegistry defines one or two “quorums”; each operator for the AVS may have stake in EigenLayer that falls into either (or both) quorum(s). Each quorum is essentially defined by two vectors: a vector of “Strategies” of interest (in practice this ends up being tokens of interest) and a vector of “weights” or “multipliers”, which define whether certain strategies are weighed more heavily than others within the quorum (e.g. if the AVS desires to give 2x power to a specific token over another token). In the contract code these vectors are condensed into a single array of `StrategyAndWeightingMultiplier` structs. The `ServiceManager.owner()` has the ability to edit these arrays at will.

### BLSSignatureChecker
When signatures have been aggregated, they can be submitted to the BLSSignatureChecker, an optimized contract designed expressly for verifying quorums of BLS signers. The caller MUST provide a small amount of data corresponding to the task to be confirmed, the aggregate signature itself, and a bit of data for each non-signer, that is, the caller MUST provide data for each operator registered for the service for whom their signature has not been aggregated. The BLSSignatureChecker ultimately returns both the total stake that was present at the specified block number (i.e. the sum of all operator’s stakes) and the total stake that signed; these amounts can then be checked against a quorum condition (e.g. requiring ⅔ stake to sign) before the task is ultimately confirmed.



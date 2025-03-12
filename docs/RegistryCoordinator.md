[core-dmgr-docs]: https://github.com/Layr-Labs/eigenlayer-contracts/blob/dev/docs/core/DelegationManager.md
[core-dmgr-register]: https://github.com/Layr-Labs/eigenlayer-contracts/blob/dev/docs/core/DelegationManager.md#registeroperatortoavs
[core-dmgr-deregister]: https://github.com/Layr-Labs/eigenlayer-contracts/blob/dev/docs/core/DelegationManager.md#deregisteroperatorfromavs

## RegistryCoordinator

| File | Type | Proxy? |
| -------- | -------- | -------- |
| [`RegistryCoordinator.sol`](../src/RegistryCoordinator.sol) | Singleton | Transparent proxy |

The `RegistryCoordinator` is a contract that exisiting AVSs using M2 quorums who wish to enable operator sets should upgrade to. New AVSs should deploy the `SlashingRegistryCoordinator` to use operator sets. The `RegistryCoordinator` inherits the `SlashingRegistryCoordinator` to expose the operator set functionality.

The `RegistryCoordinator` has four primary functions:
1. It is the primary entry and exit point for operators as they register for and deregister from quorums, and manages registration and deregistration in the `BLSApkRegistry`, `StakeRegistry`, and `IndexRegistry`. It also hooks into the EigenLayer core contracts, updating the core `AVSDirectory` for M2 quorums and `AllocationManager` in the case of ejection and operator set quorums
2. It allows anyone to update the current stake of any registered operator
3. It allows the Owner to initialize and configure new quorums
4. Disabling M2 quorum registration to upgrade to operator sets

Refer to the [`SlashingRegistryCoordinator`](./SlashingRegistryCoordinator) for operator set functionality.

#### Migration
Existing AVSs upgrading to this version `RegistryCoordinator` will be in a state where both M2 quorum registration and operator set registration will be enabled. AVSs must be aware of this. Operator sets will be enabled on upon the first call to either `createDelegatedStakeQuorum` or `createSlashableStakeQuorum` which are inherited from the `SlashingRegistryCoordinator`. The suggested flow for this migration is as follows:
1. Upgrade `RegistryCoordinator`
2. Create delegated or slashable stake quorums via `createDelegatedStakeQuorum` or `createSlashableStakeQuorum`
3. Allow time for operators to register for the new quorums using the `AllocationManager`
4. After adequate stake has been migrated (e.g. for the sake of securing new tasks of operator sets), disable M2 registration by calling `disableM2QuorumRegistration`, note that operators can still deregister from the legacy quorums

#### High-level Concepts

This document organizes methods according to the following themes (click each to be taken to the relevant section):
* [Registering and Deregistering](#registering-and-deregistering)
* [Updating Registered Operators](#updating-registered-operators)
* [System Configuration](#system-configuration)

#### Roles

* Owner: a permissioned role that can create and configure quorums as well as manage other roles
* Ejector: a permissioned role that can forcibly eject an operator from a quorum via `RegistryCoordinator.ejectOperator`
* Churn Approver: a permissioned role that signs off on operator churn in `RegistryCoordinator.registerOperatorWithChurn`

---    

### Registering and Deregistering

These methods allow operators to register for/deregister from one or more quorums, and are the primary entry points to the middleware contracts as a whole:
* [`registerOperator`](#registeroperator)
* [`registerOperatorWithChurn`](#registeroperatorwithchurn)
* [`deregisterOperator`](#deregisteroperator)
* [`ejectOperator`](#ejectoperator)

#### `registerOperator`

```solidity
function registerOperator(
    bytes calldata quorumNumbers,
    string calldata socket,
    IBLSApkRegistryTypes.PubkeyRegistrationParams calldata params,
    SignatureWithSaltAndExpiry memory operatorSignature
) 
    external 
    onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR)
```

Registers the caller as an Operator for one or more quorums, as long as registration doesn't place any quorum's operator count above the configured cap. This method updates the Operator's current and historical bitmap of registered quorums, and forwards a call to each of the registry contracts:
* `BLSApkRegistry.registerOperator`
* `StakeRegistry.registerOperator`
* `IndexRegistry.registerOperator`

If the Operator has never registered for any of this AVS's quorums before, they need to register a BLS public key to participate in AVS signing events. In this case, this method will automatically pass `params` to the `BLSApkRegistry` to perform public key registration. The registered pubkey hash becomes the Operator's unique operator id, used to identify them in many places in the middleware contracts.

If the Operator was not currently registered for any quorums, this method will register the Operator to the AVS in the EigenLayer core contracts via the `ServiceManagerBase`.

*Effects*:
* If the Operator has never registered for the AVS before:
    * Registers their BLS pubkey in the `BLSApkRegistry` (see [`BLSApkRegistry.registerBLSPublicKey`](./registries/BLSApkRegistry.md#registerblspublickey))
* If the Operator was not currently registered for any quorums: 
    * Updates their status to `REGISTERED`
    * Registers them in the core contracts (see [`ServiceManagerBase.registerOperatorToAVS`](./ServiceManagerBase.md#registeroperatortoavs))
* Adds the new quorums to the Operator's current registered quorums, and updates the Operator's bitmap history
* See [`BLSApkRegistry.registerOperator`](./registries/BLSApkRegistry.md#registeroperator)
* See [`StakeRegistry.registerOperator`](./registries/StakeRegistry.md#registeroperator)
* See [`IndexRegistry.registerOperator`](./registries/IndexRegistry.md#registeroperator)

*Requirements*:
* Pause status MUST NOT be set: `PAUSED_REGISTER_OPERATOR`
* Caller MUST have a valid operator ID in the `BLSApkRegistry`
* `quorumNumbers` MUST be an ordered array of quorum numbers, with no entry exceeding the current `quorumCount`
* `quorumNumbers` MUST contain at least one valid quorum
* `quorumNumbers` MUST NOT contain any quorums the Operator is already registered for
* If the Operator was not currently registered for any quorums:
    * See [`ServiceManagerBase.registerOperatorToAVS`](./ServiceManagerBase.md#registeroperatortoavs)
* See [`BLSApkRegistry.registerOperator`](./registries/BLSApkRegistry.md#registeroperator)
* See [`StakeRegistry.registerOperator`](./registries/StakeRegistry.md#registeroperator)
* See [`IndexRegistry.registerOperator`](./registries/IndexRegistry.md#registeroperator)
* For each quorum being registered for, the Operator's addition MUST NOT put the total number of operators registered for the quorum above the quorum's configured `maxOperatorCount`

#### `registerOperatorWithChurn`

```solidity
function registerOperatorWithChurn(
    bytes calldata quorumNumbers, 
    string calldata socket,
    IBLSApkRegistryTypes.PubkeyRegistrationParams calldata params,
    OperatorKickParam[] calldata operatorKickParams,
    SignatureWithSaltAndExpiry memory churnApproverSignature,
    SignatureWithSaltAndExpiry memory operatorSignature
) 
    external 
    onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR)
```

This method performs similar steps to `registerOperator` above, except that for each quorum where the new Operator total exceeds the `maxOperatorCount`, the `operatorKickParams` are used to deregister a current Operator to make room for the new one.

This operation requires a valid signature from the Churn Approver. Additionally, the incoming and outgoing Operators must meet these requirements:
* The new Operator's stake must be greater than the old Operator's stake by a factor given by the quorum's configured `kickBIPsOfOperatorStake`
* The old Operator's stake must be lower than the total stake for the quorum by a factor given by the quorum's configured `kickBIPsOfTotalStake`

*Effects*:
* The new Operator is registered for one or more quorums (see `registerOperator` above)
* For any quorum where registration causes the operator count to exceed `maxOperatorCount`, the Operator selected to be replaced is deregistered (see `deregisterOperator` below)

*Requirements*:
* Pause status MUST NOT be set: `PAUSED_REGISTER_OPERATOR`
* The `churnApproverSignature` MUST be a valid, unexpired signature from the Churn Approver over the Operator's id and the `operatorKickParams`
* The old and new Operators MUST meet the stake requirements described above
* See `registerOperator` above
* See `deregisterOperator` below

#### `deregisterOperator`

```solidity
function deregisterOperator(
    bytes calldata quorumNumbers
) 
    external 
    onlyWhenNotPaused(PAUSED_DEREGISTER_OPERATOR)
```

Allows an Operator to deregister themselves from one or more quorums.

*Effects*:
* If the Operator is no longer registered for any quorums:
    * Updates their status to `DEREGISTERED`
    * Deregisters them in the core contracts (see [`ServiceManagerBase.deregisterOperatorFromAVS`](./ServiceManagerBase.md#deregisteroperatorfromavs))
* Removes the new quorums from the Operator's current registered quorums, and updates the Operator's bitmap history
* See [`BLSApkRegistry.deregisterOperator`](./registries/BLSApkRegistry.md#deregisteroperator)
* See [`StakeRegistry.deregisterOperator`](./registries/StakeRegistry.md#deregisteroperator)
* See [`IndexRegistry.deregisterOperator`](./registries/IndexRegistry.md#deregisteroperator)

*Requirements*:
* Pause status MUST NOT be set: `PAUSED_DEREGISTER_OPERATOR`
* The Operator MUST currently be in the `REGISTERED` status (i.e. registered for at least one quorum)
* `quorumNumbers` MUST be an ordered array of quorum numbers, with no entry exceeding the current `quorumCount`
* `quorumNumbers` MUST contain at least one valid quorum
* `quorumNumbers` MUST ONLY contain bits that are also set in the Operator's current registered quorum bitmap
* See [`ServiceManagerBase.deregisterOperatorFromAVS`](./ServiceManagerBase.md#deregisteroperatorfromavs)
* See [`BLSApkRegistry.deregisterOperator`](./registries/BLSApkRegistry.md#deregisteroperator)
* See [`StakeRegistry.deregisterOperator`](./registries/StakeRegistry.md#deregisteroperator)
* See [`IndexRegistry.deregisterOperator`](./registries/IndexRegistry.md#deregisteroperator)

### System Configuration

These methods are used by the Owner to configure the `RegistryCoordinator`:

#### `disableM2QuorumRegistration`

```solidity
function disableM2QuorumRegistration() external onlyOwner
```

Allows the Owner to disable M2 quorum registration. This disables the M2 legacy quorum registration. Operators can still deregister once M2 registration is disabled. Note that this is a one way function, meaning once M2 is disabled it cannot be re-enabled.

*Effects*
* Disables M2 quourum registration

*Requirements*
* Caller MUST be the Owner
* M2 registration must be enabled
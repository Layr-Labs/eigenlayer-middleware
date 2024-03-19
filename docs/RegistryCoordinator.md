[core-dmgr-docs]: https://github.com/Layr-Labs/eigenlayer-contracts/blob/dev/docs/core/DelegationManager.md
[core-dmgr-register]: https://github.com/Layr-Labs/eigenlayer-contracts/blob/dev/docs/core/DelegationManager.md#registeroperatortoavs
[core-dmgr-deregister]: https://github.com/Layr-Labs/eigenlayer-contracts/blob/dev/docs/core/DelegationManager.md#deregisteroperatorfromavs

## RegistryCoordinator

| File | Type | Proxy? |
| -------- | -------- | -------- |
| [`RegistryCoordinator.sol`](../src/RegistryCoordinator.sol) | Singleton | Transparent proxy |

The `RegistryCoordinator` has three primary functions:
1. It is the primary entry and exit point for operators as they register for and deregister from quorums, and manages registration and deregistration in the `BLSApkRegistry`, `StakeRegistry`, and `IndexRegistry`. It also hooks into the EigenLayer core contracts, updating the core `DelegationManager` when an Operator registers/deregisters.
2. It allows anyone to update the current stake of any registered operator
3. It allows the Owner to initialize and configure new quorums

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
    IBLSApkRegistry.PubkeyRegistrationParams calldata params,
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
    IBLSApkRegistry.PubkeyRegistrationParams calldata params,
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

#### `ejectOperator`

```solidity
function ejectOperator(
    address operator, 
    bytes calldata quorumNumbers
) 
    external 
    onlyEjector
```

Allows the Ejector to forcibly deregister an Operator from one or more quorums.

*Effects*:
* See `deregisterOperator` above

*Requirements*:
* Caller MUST be the Ejector
* See `deregisterOperator` above

---

### Updating Registered Operators

These methods concern Operators that are currently registered for at least one quorum:
* [`updateOperators`](#updateoperators)
* [`updateOperatorsForQuorum`](#updateoperatorsforquorum)
* [`updateSocket`](#updatesocket)

#### `updateOperators`

```solidity
function updateOperators(
    address[] calldata operators
) 
    external 
    onlyWhenNotPaused(PAUSED_UPDATE_OPERATOR)
```

Allows anyone to update the contracts' view of one or more Operators' stakes. For each currently-registered `operator`, this method calls `StakeRegistry.updateOperatorStake`, triggering an update of that Operator's stake. 

The `StakeRegistry` returns a bitmap of quorums where the Operator no longer meets the minimum stake required for registration. The Operator is then deregistered from those quorums.

*Effects*:
* See [`StakeRegistry.updateOperatorStake`](./registries/StakeRegistry.md#updateoperatorstake)
* For any quorums where the Operator no longer meets the minimum stake, they are deregistered (see `deregisterOperator` above).

*Requirements*:
* Pause status MUST NOT be set: `PAUSED_UPDATE_OPERATOR`
* See [`StakeRegistry.updateOperatorStake`](./registries/StakeRegistry.md#updateoperatorstake)

#### `updateOperatorsForQuorum`

```solidity
function updateOperatorsForQuorum(
    address[][] calldata operatorsPerQuorum,
    bytes calldata quorumNumbers
) 
    external 
    onlyWhenNotPaused(PAUSED_UPDATE_OPERATOR)
```

Can be called by anyone to update the stake of ALL Operators in one or more quorums simultaneously. This method works similarly to `updateOperators` above, but with the requirement that, for each quorum being updated, the respective `operatorsPerQuorum` passed in is the complete set of Operators currently registered for that quorum.

This method also updates each quorum's `quorumUpdateBlockNumber`, signifying that the quorum's entire Operator set was updated at the current block number. (This is used by the `BLSSignatureChecker` to ensure that signature and stake validation is performed on up-to-date stake.)

*Effects*:
* See `updateOperators` above
* Updates each quorum's `quorumUpdateBlockNumber` to the current block
* For any quorums where the Operator no longer meets the minimum stake, they are deregistered (see `deregisterOperator` above).

*Requirements*:
* Pause status MUST NOT be set: `PAUSED_UPDATE_OPERATOR`
* See `updateOperators` above
* `quorumNumbers` MUST be an ordered array of quorum numbers, with no entry exceeding the current `quorumCount`
* All `quorumNumbers` MUST correspond to valid, initialized quorums
* `operatorsPerQuorum` and `quorumNumbers` MUST have the same lengths
* Each entry in `operatorsPerQuorum` MUST contain an order list of the currently-registered Operator addresses in the corresponding quorum
* See [`StakeRegistry.updateOperatorStake`](./registries/StakeRegistry.md#updateoperatorstake)

#### `updateSocket`

```solidity
function updateSocket(string memory socket) external
```

Allows a registered Operator to emit an event, updating their socket.

*Effects*:
* Emits an `OperatorSocketUpdate` event

*Requirements*:
* Caller MUST be a registered Operator

---

### System Configuration

These methods are used by the Owner to configure the `RegistryCoordinator`:
* [`createQuorum`](#createquorum)
* [`setOperatorSetParams`](#setoperatorsetparams)
* [`setChurnApprover`](#setchurnapprover)
* [`setEjector`](#setejector)

#### `createQuorum`

```solidity
function createQuorum(
    OperatorSetParam memory operatorSetParams,
    uint96 minimumStake,
    IStakeRegistry.StrategyParams[] memory strategyParams
) 
    external
    virtual 
    onlyOwner
```

Allows the Owner to initialize a new quorum with the given configuration. The new quorum is assigned a sequential quorum number.

The new quorum is also initialized in each of the registry contracts.

*Effects*:
* `quorumCount` is incremented by 1
* The new quorum's `OperatorSetParams` are initialized (see `setOperatorSetParams` below)
* See [`BLSApkRegistry.initializeQuorum`](./registries/BLSApkRegistry.md#initializequorum)
* See [`StakeRegistry.initializeQuorum`](./registries/StakeRegistry.md#initializequorum)
* See [`IndexRegistry.initializeQuorum`](./registries/IndexRegistry.md#initializequorum)

*Requirements*:
* Caller MUST be the Owner
* Quorum count before creation MUST be less than `MAX_QUORUM_COUNT`
* See [`BLSApkRegistry.initializeQuorum`](./registries/BLSApkRegistry.md#initializequorum)
* See [`StakeRegistry.initializeQuorum`](./registries/StakeRegistry.md#initializequorum)
* See [`IndexRegistry.initializeQuorum`](./registries/IndexRegistry.md#initializequorum)

#### `setOperatorSetParams`

```solidity
function setOperatorSetParams(
    uint8 quorumNumber, 
    OperatorSetParam memory operatorSetParams
) 
    external 
    onlyOwner 
    quorumExists(quorumNumber)
```

Allows the Owner to update an existing quorum's `OperatorSetParams`, which determine:
* `maxOperatorCount`: The max number of operators that can be in this quorum
* `kickBIPsOfOperatorStake`: The basis points a new Operator needs over an old Operator's stake to replace them in `registerOperatorWithChurn`
* `kickBIPsOfTotalStake`: The basis points a replaced Operator needs under the quorum's total stake to be replaced in `registerOperatorWithChurn`

*Effects*:
* Updates the quorum's `OperatorSetParams`

*Requirements*:
* Caller MUST be the Owner
* `quorumNumber` MUST correspond to an existing, initialized quorum

#### `setChurnApprover`

```solidity
function setChurnApprover(address _churnApprover) external onlyOwner
```

Allows the Owner to update the Churn Approver address.

*Effects*:
* Updates the Churn Approver address

*Requirements*:
* Caller MUST be the Owner

#### `setEjector`

```solidity
function setEjector(address _ejector) external onlyOwner
```

Allows the Owner to update the Ejector address.

*Effects*:
* Updates the Ejector address

*Requirements*:
* Caller MUST be the Owner
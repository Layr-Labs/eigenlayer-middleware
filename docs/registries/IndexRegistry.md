## IndexRegistry

| File | Type | Proxy? |
| -------- | -------- | -------- |
| [`IndexRegistry.sol`](../../src/IndexRegistry.sol) | Singleton | Transparent proxy |

The `IndexRegistry` provides an `operatorIndex` for every registered Operator in every quorum. For example, if a quorum has `n` Operators, every Operator registered for that quorum will have an `operatorIndex` in the range `[0:n-1]`. The role of this contract is to provide an AVS with a common, on-chain ordering of Operators within a quorum.

*In EigenDA*, the Operator ordering properties of the `IndexRegistry` will eventually be used in proofs of custody, though this feature is not implemented yet.

#### Important State Variables

```solidity
/// @notice maps quorumNumber => operator id => current operatorIndex
/// NOTE: This mapping is NOT updated when an operator is deregistered,
/// so it's possible that an index retrieved from this mapping is inaccurate.
/// If you're querying for an operator that might be deregistered, ALWAYS 
/// check this index against the latest `_operatorIndexHistory` entry
mapping(uint8 => mapping(bytes32 => uint32)) public currentOperatorIndex;

/// @notice maps quorumNumber => operatorIndex => historical operator ids at that index
mapping(uint8 => mapping(uint32 => OperatorUpdate[])) internal _operatorIndexHistory;

/// @notice maps quorumNumber => historical number of unique registered operators
mapping(uint8 => QuorumUpdate[]) internal _operatorCountHistory;
 
struct OperatorUpdate {
    uint32 fromBlockNumber;
    bytes32 operatorId;
}

struct QuorumUpdate {
    uint32 fromBlockNumber;
    uint32 numOperators;
}
```

Operators are assigned a unique `operatorIndex` in each quorum they're registered for. If a quorum has `n` registered Operators, every Operator in that quorum will have an `operatorIndex` in the range `[0:n-1]`. To accomplish this, the `IndexRegistry` uses the three mappings listed above:
* `currentOperatorIndex` is a straightforward mapping of an Operator's current `operatorIndex` in a specific quorum. It is updated when an Operator registers for a quorum.
* `_operatorIndexHistory` keeps track of the `operatorIds` assigned to an `operatorIndex` at various points in time. This is used by offchain code to determine what `operatorId` belonged to an `operatorIndex` at a specific block.
* `_operatorCountHistory` keeps track of the number of Operators registered to each quorum over time. Note that a quorum's Operator count is also its "max `operatorIndex` + 1". Paired with `_operatorIndexHistory`, this allows offchain code to query the entire Operator set registered for a quorum at a given block number. For an example of this in the code, see `IndexRegistry.getOperatorListAtBlockNumber`.

*Note*: `currentOperatorIndex` is ONLY updated when an Operator is *assigned* to an `operatorIndex`. When an Operator deregisters and is removed, we don't update `currentOperatorIndex` because their `operatorIndex` is not "0" - that's held by another Operator. Their `operatorIndex` is also not the `operatorIndex` they currently have. There's not really a "right answer" for this - see https://github.com/Layr-Labs/eigenlayer-middleware/issues/126 for more details.

#### High-level Concepts

This document organizes methods according to the following themes (click each to be taken to the relevant section):
* [Registering and Deregistering](#registering-and-deregistering)
* [System Configuration](#system-configuration)

---    

### Registering and Deregistering

These methods are ONLY called through the `RegistryCoordinator` - when an Operator registers for or deregisters from one or more quorums:
* [`registerOperator`](#registeroperator)
* [`deregisterOperator`](#deregisteroperator)

#### `registerOperator`

```solidity
function registerOperator(
    bytes32 operatorId, 
    bytes calldata quorumNumbers
) 
    public 
    virtual 
    onlyRegistryCoordinator 
    returns(uint32[] memory)
```

When an Operator registers for a quorum, the following things happen:
1. The current Operator count for the quorum is increased. 
    * This updates `_operatorCountHistory[quorum]`. The quorum's new "max `operatorIndex`" is equal to the quorum Operator count - 1.
    * Additionally, if the `_operatorIndexHistory` for the quorum indicates that this is the first time the quorum has reached a given Operator count, an initial `OperatorUpdate` is pushed to `_operatorIndexHistory` for the new operator count. This is to maintain an invariant: that existing quorum indices have nonzero history.
2. The quorum's max index (Operator count - 1) is assigned to the registering Operator as their current `operatorIndex`.
    * This updates `currentOperatorIndex[quorum][operatorId]`
    * This also updates `_operatorIndexHistory[quorum][prevOperatorCount]`, recording the `operatorId` as the latest holder of the `operatorIndex` in question.

This method is ONLY callable by the `RegistryCoordinator`, and is called when an Operator registers for one or more quorums. This method *assumes* that the `operatorId` is not already registered for any of `quorumNumbers`, and that there are no duplicates in `quorumNumbers`. These properties are enforced by the `RegistryCoordinator`.

*Entry Points*:
* `RegistryCoordinator.registerOperator`
* `RegistryCoordinator.registerOperatorWithChurn`

*Effects*:
* For each `quorum` in `quorumNumbers`:
    * Updates `_operatorCountHistory[quorum]`, increasing the quorum's `numOperators` by 1. 
        * Note that if the most recent update for the quorum is from the current block number, the entry is updated. Otherwise, a new entry is pushed.
    * Updates `_operatorIndexHistory[quorum][newOperatorCount - 1]`, recording the `operatorId` as the latest holder of the new max `operatorIndex`. 
        * Note that if the most recent update for the quorum's index is from the current block number, the entry is updated. Otherwise, a new entry is pushed.
    * Updates `currentOperatorIndex[quorum][operatorId]`, assigning the `operatorId` to the new max `operatorIndex`.

*Requirements*:
* Caller MUST be the `RegistryCoordinator`
* Each quorum in `quorumNumbers` MUST be initialized (see `initializeQuorum` below)

#### `deregisterOperator`

```solidity
function deregisterOperator(
    bytes32 operatorId, 
    bytes calldata quorumNumbers
) 
    public 
    virtual 
    onlyRegistryCoordinator
```

When an Operator deregisters from a quorum, the following things happen:
1. The current Operator count for the quorum is decreased, updating `_operatorCountHistory[quorum]`. The new "max `operatorIndex`" is equal to the new Operator count (minus 1).
2. The Operator currently assigned to the now-invalid `operatorIndex` is "popped".
    * This updates `_operatorIndexHistory[quorum][newOperatorCount]`, recording that the Operator assigned to this `operatorIndex` is `OPERATOR_DOES_NOT_EXIST_ID`
3. If the deregistering Operator and the popped Operator are not the same, the popped Operator is assigned a new `operatorIndex`: the deregistering Operator's previous `operatorIndex`.
    * This updates `_operatorIndexHistory[quorum][removedOperatorIndex]`, recording that the popped Operator is assigned to this `operatorIndex`.
    * This also updates `currentOperatorIndex[quorum][removedOperator]`, assigning the popped Operator to the old Operator's `operatorIndex`.

This method is ONLY callable by the `RegistryCoordinator`, and is called when an Operator deregisters from one or more quorums. This method *assumes* that the `operatorId` is currently registered for each quorum in `quorumNumbers`, and that there are no duplicates in `quorumNumbers`. These properties are enforced by the `RegistryCoordinator`.

*Entry Points*:
* `RegistryCoordinator.registerOperatorWithChurn`
* `RegistryCoordinator.deregisterOperator`
* `RegistryCoordinator.ejectOperator`
* `RegistryCoordinator.updateOperators`
* `RegistryCoordinator.updateOperatorsForQuorum`

*Effects*:
* For each `quorum` in `quorumNumbers`:
    * Updates `_operatorCountHistory[quorum]`, decreasing the quorum's `numOperators` by 1. 
        * Note that if the most recent update for the quorum is from the current block number, the entry is updated. Otherwise, a new entry is pushed.
    * Updates `_operatorIndexHistory[quorum][newOperatorCount]`, "popping" the Operator that currently holds this `operatorIndex`, and marking it as assigned to `OPERATOR_DOES_NOT_EXIST_ID`. 
        * Note that if the most recent update for the quorum's `operatorIndex` is from the current block number, the entry is updated. Otherwise, a new entry is pushed.
    * If `operatorId` is NOT the popped Operator, the popped Operator is assigned to `operatorId's` current `operatorIndex`. (Updates `_operatorIndexHistory` and `currentOperatorIndex`)

*Requirements*:
* Caller MUST be the `RegistryCoordinator`
* Each quorum in `quorumNumbers` MUST be initialized (see `initializeQuorum` below)

---

### System Configuration

#### `initializeQuorum`

```solidity
function initializeQuorum(
    uint8 quorumNumber
) 
    public 
    virtual 
    onlyRegistryCoordinator
```

This method is ONLY callable by the `RegistryCoordinator`. It is called when the `RegistryCoordinator` Owner creates a new quorum.

`initializeQuorum` initializes a new quorum by pushing an initial `QuorumUpdate` to `_operatorCountHistory[quorumNumber]`, setting the initial `numOperators` for the quorum to 0. 

Other methods can validate that a quorum exists by checking whether `_operatorCountHistory[quorumNumber]` has a nonzero length.

*Entry Points*:
* `RegistryCoordinator.createQuorum`

*Effects*:
* Pushes a `QuorumUpdate` to `_operatorCountHistory[quorumNumber]`. The update's `updateBlockNumber` is set to the current block, and `numOperators` is set to 0.

*Requirements*:
* Caller MUST be the `RegistryCoordinator`
* `_operatorCountHistory[quorumNumber].length` MUST be zero

---
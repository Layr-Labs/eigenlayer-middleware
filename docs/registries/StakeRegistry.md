[core-docs-dev]: https://github.com/Layr-Labs/eigenlayer-contracts/tree/dev/docs

## StakeRegistry

| File | Type | Proxy |
| -------- | -------- | -------- |
| [`StakeRegistry.sol`](../src/StakeRegistry.sol) | Singleton | Transparent proxy |

The `StakeRegistry` interfaces with the EigenLayer core contracts to determine the individual and collective stake weight of each Operator registered for each quorum. These weights are used to determine an Operator's relative weight for each of an AVS's quorums. And in the `RegistryCoordinator` specifically, they play an important role in *churn*: determining whether an Operator is eligible to replace another Operator in a quorum.

#### Calculating Stake Weight

Stake weight is primarily a function of the number of shares an Operator has been delegated within the EigenLayer core contracts, along with a per-quorum configuration maintained by the `RegistryCoordinator` Owner (see [System Configuration](#system-configuration) below). This configuration determines, for a given quorum, which Strategies "count" towards an Operator's total stake weight, as well as "how much" each Strategy counts for:

```solidity
/// @notice maps quorumNumber => list of strategies considered (and each strategy's multiplier)
mapping(uint8 => StrategyParams[]) public strategyParams;

struct StrategyParams {
    IStrategy strategy;
    uint96 multiplier;
}
```

For a given quorum, an Operator's stake weight is determined by iterating over the quorum's list of `StrategyParams` and querying `DelegationManager.operatorShares(operator, strategy)`. The result is multiplied by the corresponding `multiplier` (and divided by the `WEIGHTING_DIVISOR`) to calculate the Operator's weight for that strategy. Then, this result is added to a growing sum of stake weights -- and after the quorum's `StrategyParams` have all been considered, the Operator's total stake weight is calculated.

Note that the `RegistryCoordinator` Owner also configures a "minimum stake" for each quorum, which an Operator must meet in order to register for (or remain registered for) a quorum.

For more information on the `DelegationManager`, strategies, and shares, see the [EigenLayer core docs][core-docs-dev].

#### High-level Concepts

This document organizes methods according to the following themes (click each to be taken to the relevant section):
* [Registering and Deregistering](#registering-and-deregistering)
* [Updating Registered Operators](#updating-registered-operators)
* [System Configuration](#system-configuration)

---    

### Registering and Deregistering

These methods are ONLY called through the `RegistryCoordinator` - when an Operator registers for or deregisters from one or more quorums:
* [`registerOperator`](#registeroperator)
* [`deregisterOperator`](#deregisteroperator)

#### `registerOperator`

```solidity
function registerOperator(
    address operator,
    bytes32 operatorId,
    bytes calldata quorumNumbers
) 
    public 
    virtual 
    onlyRegistryCoordinator 
    returns (uint96[] memory, uint96[] memory)
```

When an Operator registers for a quorum, the `StakeRegistry` first calculates the Operator's current weighted stake. If the Operator meets the quorum's configured minimum stake, the Operator's `operatorStakeHistory` is updated to reflect the Operator's current stake.

Additionally, the Operator's stake is added to the `_totalStakeHistory` for that quorum.

This method is ONLY callable by the `RegistryCoordinator`, and is called when an Operator registers for one or more quorums. This method *assumes* that:
* `operatorId` belongs to the `operator`
* `operatorId` is not already registered for any of `quorumNumbers`
* There are no duplicates in `quorumNumbers`

These properties are enforced by the `RegistryCoordinator`.

*Entry Points*:
* `RegistryCoordinator.registerOperator`
* `RegistryCoordinator.registerOperatorWithChurn`

*Effects*:
* For each `quorum` in `quorumNumbers`:
    * The Operator's total stake weight is calculated, and the result is recorded in `operatorStakeHistory[operatorId][quorum]`.
        * Note that if the most recent update is from the current block number, the entry is updated. Otherwise, a new entry is pushed.
    * The Operator's total stake weight is added to the quorum's total stake weight in `_totalStakeHistory[quorum]`.
        * Note that if the most recent update is from the current block number, the entry is updated. Otherwise, a new entry is pushed.

*Requirements*:
* Caller MUST be the `RegistryCoordinator`
* Each quorum in `quorumNumbers` MUST be initialized (see `initializeQuorum` below)
* For each `quorum` in `quorumNumbers`:
    * The calculated total stake weight for the Operator MUST NOT be less than that quorum's minimum stake

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

When an Operator deregisters from a quorum, the `StakeRegistry` sets their stake to 0 and subtracts their stake from the quorum's total stake, updating `operatorStakeHistory` and `_totalStakeHistory`, respectively.

This method is ONLY callable by the `RegistryCoordinator`, and is called when an Operator deregisters from one or more quorums. This method *assumes* that:
* `operatorId` is currently registered for each quorum in `quorumNumbers`
* There are no duplicates in `quorumNumbers`

These properties are enforced by the `RegistryCoordinator`.

*Entry Points*:
* `RegistryCoordinator.registerOperatorWithChurn`
* `RegistryCoordinator.deregisterOperator`
* `RegistryCoordinator.ejectOperator`
* `RegistryCoordinator.updateOperators`
* `RegistryCoordinator.updateOperatorsForQuorum`

*Effects*:
* For each `quorum` in `quorumNumbers`:
    * The Operator's stake weight in `operatorStakeHistory[operatorId][quorum]` is set to 0.
        * Note that if the most recent update is from the current block number, the entry is updated. Otherwise, a new entry is pushed.
    * The Operator's stake weight is removed from the quorum's total stake weight in `_totalStakeHistory[quorum]`.
        * Note that if the most recent update is from the current block number, the entry is updated. Otherwise, a new entry is pushed.

*Requirements*:
* Caller MUST be the `RegistryCoordinator`
* Each quorum in `quorumNumbers` MUST be initialized (see `initializeQuorum` below)

---

### Updating Registered Operators

#### `updateOperatorStake`

```solidity
function updateOperatorStake(
    address operator, 
    bytes32 operatorId, 
    bytes calldata quorumNumbers
) 
    external 
    onlyRegistryCoordinator 
    returns (uint192)
```

AVSs will require up-to-date views on an Operator's stake. When an Operator's shares change in the EigenLayer core contracts (due to additional delegation, undelegation, withdrawals, etc), this change is not automatically pushed to middleware contracts. This is because middleware contracts are unique to each AVS, and core contract share updates would become prohibitively expensive if they needed to update each AVS every time an Operator's shares changed.

Rather than *pushing* updates, `RegistryCoordinator.updateOperators` and `updateOperatorsForQuorum` can be called by anyone to *pull* updates from the core contracts. Those `RegistryCoordinator` methods act as entry points for this method, which performs the same stake weight calculation as `registerOperator`, updating the Operator's `operatorStakeHistory` and the quorum's `_totalStakeHistory`.

*Note*: there is one major difference between `updateOperatorStake` and `registerOperator` - if an Operator does NOT meet the minimum stake for a quorum, their stake weight is set to 0 and removed from the quorum's total stake weight, mimicing the behavior of `deregisterOperator`. For each quorum where this occurs, that quorum's number is added to a bitmap, `uint192 quorumsToRemove`, which is returned to the `RegistryCoordinator`. The `RegistryCoordinator` uses this returned bitmap to completely deregister Operators, maintaining an invariant that if an Operator's stake weight for a quorum is 0, they are NOT registered for that quorum.

This method is ONLY callable by the `RegistryCoordinator`, and is called when an Operator registers for one or more quorums. This method *assumes* that:
* `operatorId` belongs to the `operator`
* `operatorId` is currently registered for each quorum in `quorumNumbers`
* There are no duplicates in `quorumNumbers`

These properties are enforced by the `RegistryCoordinator`.

*Entry Points*:
* `RegistryCoordinator.updateOperators`
* `RegistryCoordinator.updateOperatorsForQuorum`

*Effects*:
* For each `quorum` in `quorumNumbers`:
    * The Operator's total stake weight is calculated, and the result is recorded in `operatorStakeHistory[operatorId][quorum]`. If the Operator does NOT meet the quorum's configured minimum stake, their stake weight is set to 0 instead.
        * Note that if the most recent update is from the current block number, the entry is updated. Otherwise, a new entry is pushed.
    * The Operator's stake weight delta is applied to the quorum's total stake weight in `_totalStakeHistory[quorum]`.
        * Note that if the most recent update is from the current block number, the entry is updated. Otherwise, a new entry is pushed.

*Requirements*:
* Caller MUST be the `RegistryCoordinator`
* Each quorum in `quorumNumbers` MUST be initialized (see `initializeQuorum` below)

---

### System Configuration

Two methods are used by the `RegistryCoordinator` to initialize new quorums in the `StakeRegistry`:
* [`initializeDelegatedStakeQuorum`](#initializedelegatedstakequorum)
* [`initializeSlashableStakeQuorum`](#initializeslashablestakequorum)


These methods are used by the `RegistryCoordinator's` Owner to configure initialized quorums in the `StakeRegistry`. They are not expected to be called very often, and will require updating Operator stakes via `RegistryCoordinator.updateOperatorsForQuorum` to maintain up-to-date views on Operator stake weights. Methods follow:
* [`setMinimumStakeForQuorum`](#setminimumstakeforquorum)
* [`addStrategies`](#addstrategies)
* [`setSlashableLookAhead`](#setslashablelookahead)
* [`removeStrategies`](#removestrategies)
* [`modifyStrategyParams`](#modifystrategyparams)

#### `initializeDelegatedStakeQuorum`

```solidity
function initializeDelegatedStakeQuorum(
    uint8 quorumNumber,
    uint96 minimumStake,
    StrategyParams[] memory _strategyParams
) 
    public 
    virtual 
    onlyRegistryCoordinator

struct StrategyParams {
    IStrategy strategy;
    uint96 multiplier;
}
```

This method is ONLY callable by the `RegistryCoordinator`, and is called when the `RegistryCoordinator` Owner creates a new delegated stake quorum.

`initializeDelegatedStakeQuorum` initializes a new delegated stake quorum by pushing an initial `StakeUpdate` to `_totalStakeHistory[quorumNumber]`, with an initial stake of 0. Other methods can validate that a quorum exists by checking whether `_totalStakeHistory[quorumNumber]` has a nonzero length.

Additionally, this method configures a `minimumStake` for the quorum, as well as the `StrategyParams` it considers when calculating stake weight.

*Entry Points*:
* `RegistryCoordinator.createDelegatedStakeQuorum`

*Effects*:
* See `addStrategies` below
* See `setMinimumStakeForQuorum` below
* Pushes a `StakeUpdate` to `_totalStakeHistory[quorumNumber]`. The update's `updateBlockNumber` is set to the current block, and `stake` is set to 0.

*Requirements*:
* Caller MUST be the `RegistryCoordinator`
* `quorumNumber` MUST NOT belong to an existing, initialized quorum
* See `addStrategies` below
* See `setMinimumStakeForQuorum` below

#### `initializeSlashableStakeQuorum`

```solidity
function initializeSlashableStakeQuorum(
    uint8 quorumNumber,
    uint96 minimumStake,
    uint32 lookAheadPeriod,
    StrategyParams[] memory _strategyParams
)
    public
    virtual
    onlyRegistryCoordinator

struct StrategyParams {
    IStrategy strategy;
    uint96 multiplier;
}
```

This method is ONLY callable by the `RegistryCoordinator`, and is called when the `RegistryCoordinator` Owner creates a new slashable stake quorum.

`initializeSlashableStakeQuorum` initializes a new quorum by pushing an initial `StakeUpdate` to `_totalStakeHistory[quorumNumber]`, with an initial stake of 0. Other methods can validate that a quorum exists by checking whether `_totalStakeHistory[quorumNumber]` has a nonzero length.

This method configures a `minimumStake` for the quorum, defines the `StrategyParams` used when calculating stake weight and sets the `lookAheadPeriod` which defines how many blocks ahead to when considering the minimum amount of slahable stake. Note that `lookAheadPeriod` should be less than the `DEALLOCATION_DELAY` (14 days within the `AllocationManager`) blocks in the future, to avoid calculating stake values that may not reflect the operators true allocated stake.

*Entry Points*:
* `RegistryCoordinator.createSlashableStakeQuorum`

*Effects*:
* See `addStrategies` below
* See `setMinimumStakeForQuorum` below
* See `setSlashableLookAhead` below
* Pushes a `StakeUpdate` to `_totalStakeHistory[quorumNumber]`. The update's `updateBlockNumber` is set to the current block, and `stake` is set to 0.


*Requirements*:
* Caller MUST be the `RegistryCoordinator`
* `quorumNumber` MUST NOT belong to an existing, initialized quorum
* See `addStrategies` below
* See `setMinimumStakeForQuorum` below

#### `setMinimumStakeForQuorum`

```solidity
function setMinimumStakeForQuorum(
    uint8 quorumNumber, 
    uint96 minimumStake
) 
    public 
    virtual 
    onlyCoordinatorOwner 
    quorumExists(quorumNumber)
```

Allows the `RegistryCoordinator` Owner to configure the `minimumStake` for an existing quorum. This value is used to determine whether an Operator has sufficient stake to register for (or stay registered for) a quorum.

There is no lower or upper bound on a quorum's minimum stake.

*Effects*:
* Set `minimumStakeForQuorum[quorum]` to `minimumStake`

*Requirements*:
* Caller MUST be `RegistryCoordinator.owner()`
* `quorumNumber` MUST belong to an existing, initialized quorum

#### `addStrategies`

```solidity
function addStrategies(
    uint8 quorumNumber, 
    StrategyParams[] memory _strategyParams
) 
    public 
    virtual 
    onlyCoordinatorOwner 
    quorumExists(quorumNumber)

struct StrategyParams {
    IStrategy strategy;
    uint96 multiplier;
}
```

Allows the `RegistryCoordinator` Owner to add `StrategyParams` to a quorum, which effect how Operators' stake weights are calculated.

For each `StrategyParams` added, this method checks that the incoming `strategy` has not already been added to the quorum. This is done via a relatively expensive loop over storage, but this function isn't expected to be called very often.

*Effects*:
* Each added `_strategyParams` is pushed to the quorum's stored `strategyParams[quorumNumber]`

*Requirements*:
* Caller MUST be `RegistryCoordinator.owner()`
* `quorumNumber` MUST belong to an existing, initialized quorum
* `_strategyParams` MUST NOT be empty
* The quorum's current `StrategyParams` count plus the new `_strategyParams` MUST NOT exceed `MAX_WEIGHING_FUNCTION_LENGTH`
* `_strategyParams` MUST NOT contain duplicates, and MUST NOT contain strategies that are already being considered by the quorum
* For each `_strategyParams` being added, the `multiplier` MUST NOT be 0

#### `removeStrategies`

```solidity
function removeStrategies(
    uint8 quorumNumber,
    uint256[] memory indicesToRemove
) 
    public 
    virtual 
    onlyCoordinatorOwner 
    quorumExists(quorumNumber)

struct StrategyParams {
    IStrategy strategy;
    uint96 multiplier;
}
```

Allows the `RegistryCoordinator` Owner to remove `StrategyParams` from a quorum, which effect how Operators' stake weights are calculated. Removals are processed by removing specific indices passed in by the caller.

For each `StrategyParams` removed, this method replaces `strategyParams[quorumNumber][indicesToRemove[i]]` with the last item in `strategyParams[quorumNumber]`, then pops the last element of `strategyParams[quorumNumber]`.

*Effects*:
* Removes the specified `StrategyParams` according to their index in the quorum's `strategyParams` list.

*Requirements*:
* Caller MUST be `RegistryCoordinator.owner()`
* `quorumNumber` MUST belong to an existing, initialized quorum
* `indicesToRemove` MUST NOT be empty

#### `modifyStrategyParams`

```solidity
function modifyStrategyParams(
    uint8 quorumNumber,
    uint256[] calldata strategyIndices,
    uint96[] calldata newMultipliers
) 
    public 
    virtual 
    onlyCoordinatorOwner 
    quorumExists(quorumNumber)

struct StrategyParams {
    IStrategy strategy;
    uint96 multiplier;
}
```

Allows the `RegistryCoordinator` Owner to modify the multipliers specified in a quorum's configured `StrategyParams`.

*Effects*:
* The quorum's `StrategyParams` at the specified `strategyIndices` are given a new multiplier

*Requirements*:
* Caller MUST be `RegistryCoordinator.owner()`
* `quorumNumber` MUST belong to an existing, initialized quorum
* `strategyIndices` MUST NOT be empty
* `strategyIndices` and `newMultipliers` MUST have equal lengths


#### `setSlashableLookAhead`

```solidity
function setSlashableStakeLookahead(
    uint8 quorumNumber,
    uint32 _lookAheadBlocks
)
    external
    onlyCoordinatorOwner
    quorumExists(quorumNumber)
```

Allows the `RegistryCoordinator` Owner to modify the slashable lookahead for a slashable stake quorum.

*Effects*
* The quorum's `SlashablableStakeLookAhead` is updated to `_lookAheadBlocks`

*Requirements*
* Caller MUST be `RegistryCoordinator.owner()`
* `quorumNumber` MUST belong to an existing initialized quorum
* `quorumNumber` MUST map to a slashable stake quorum

---
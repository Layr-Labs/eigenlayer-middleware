## StakeRegistry

| File | Type | Proxy? |
| -------- | -------- | -------- |
| [`StakeRegistry.sol`](../src/StakeRegistry.sol) | Singleton | Transparent proxy |

<!-- This contract is deployed for every AVS and keeps track of the AVS's operators' stakes over time and the total stakes for each quorum. In addition, this contract also handles the adding and modification of quorum. -->

TODO

The StakeRegistry manages the historical stake of operators for each quorum.

<!-- ## Upstream Dependencies

The main integration with the StakeRegistry is used by the AVSs [BLSSignatureChecker](./BLSSignatureChecker.md). An offchain actor provides an operator id, a quorum id, and an index in the array of the operator's stake updates to verify the stake of an operator at a particular block number. They also provide a quorum id and an index in the array of total stake updates to verify the stake of the entire quorum at a particular block number. -->

#### High-level Concepts

This document organizes methods according to the following themes (click each to be taken to the relevant section):
* [`Operator Lifecycle`](#operator-lifecycle)
* [`Quorums and Configuration`](#quorums-and-configuration)

#### Important State Variables

* `StakeUpdate[][256] internal _totalStakeHistory`: TODO - explain history update pattern
* `mapping(bytes32 => mapping(uint8 => StakeUpdate[])) internal operatorStakeHistory`: TODO - explain history update pattern
* `uint96[256] public minimumStakeForQuorum`: TODO

#### Helpful Definitions

TODO

```solidity
struct StakeUpdate {
    // the block number at which the stake amounts were updated and stored
    uint32 updateBlockNumber;
    // the block number at which the *next update* occurred.
    /// @notice This entry has the value **0** until another update takes place.
    uint32 nextUpdateBlockNumber;
    // stake weight for the quorum
    uint96 stake;
}
```

```solidity
struct StrategyParams {
    IStrategy strategy;
    uint96 multiplier;
}
```

* `_weightOfOperatorForQuorum(uint8 quorumNumber, address operator) -> (uint96 weight, bool hasMinimumStake)`: Uses the quorum's configured `StrategyParams` to calculate the weight of an `operator` across each strategy they have shares in. 
    * For each `strategy` and `multiplier` configured for the quorum, the `operator's` raw share count is queried from the core `DelegationManager` contract (see [`eigenlayer-contracts/docs`](https://github.com/Layr-Labs/eigenlayer-contracts/tree/master/docs)) and multiplied with the corresponding `multiplier`. These results are summed to determine the total weight of the `operator` for the quorum.
    * If the sum is less than the `minimumStakeForQuorum`, `hasMinimumStake` will be false.

---

### Operator Lifecycle

These methods are callable ONLY by the `BLSRegistryCoordinatorWithIndices`, and are used when operators register, deregister, or are updated:

* [`StakeRegistry.registerOperator`](#registeroperator)
* [`StakeRegistry.deregisterOperator`](#deregisteroperator)
* [`StakeRegistry.updateOperatorStake`](#updateoperatorstake)

See [`BLSRegistryCoordinatorWithIndices.md`](./BLSRegistryCoordinatorWithIndices.md) for more context on how these methods are used.

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
    returns (uint96[] memory currentStakes, uint96[] memory totalStakes)
```

The `BLSRegistryCoordinatorWithIndices` calls this method when an operator registers for one or more quorums. 

For each quorum, the `operator's` weight is calculating according to that quorum's `StrategyParams` (see `_weightOfOperatorForQuorum` in [Helpful Definitions](#helpful-definitions)). If the `operator's` weight is below the minimum stake for the quorum, the method fails.

Otherwise, the `operator's` stake history is updated with the new stake. See `operatorStakeHistory` in [Important State Variables](#important-state-variables) for specifics.

The quorum's total stake history is also updated, adding the `operator's` new stake to the quorum's current stake. See `_totalStakeHistory` in [Important State Variables](#important-state-variables) for specifics.

This method returns two things to the `BLSRegistryCoordinatorWithIndices`:
* `uint96[] memory currentStakes`: A list of the `operator's` current stake for each of the passed-in `quorumNumbers`
* `uint96[] memory totalStakes`: A list of the current total stakes for each quorum in the passed-in `quorumNumbers`

*Entry Points*:
* `BLSRegistryCoordinatorWithIndices.registerOperator`
* `BLSRegistryCoordinatorWithIndices.registerOperatorWithChurn`

*Effects*:
* For each quorum in `quorumNumbers`:
    * Updates the `operator's` current stake for the quorum given by that quorum's `StrategyParams` and the `operator's` shares in the core `DelegationManager` contract.
    * Updates the quorum's total stake to account for the `operator's` change in stake.

*Requirements*:
* Caller MUST be the `BLSRegistryCoordinatorWithIndices`
* For each quorum in `quorumNumbers`:
    * The quorum MUST exist
    * `operator` MUST have at least the minimum weight required for the quorum

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

<!-- The RegistryCoordinator for the AVS calls the StakeRegistry to deregister an operator for a certain set of quorums. For each of the quorums being registered for, the StakeRegistry ends the block range of the current `OperatorStakeUpdate` for the operator for the quorum.

Note that the contract does not check that the quorums that the operator is being deregistered from are a subset of the quorums the operator is registered for, that logic is expected to be done in the RegistryCoordinator. -->

(TODO) description

*Entry Points*:
* `BLSRegistryCoordinatorWithIndices.registerOperatorWithChurn`
* `BLSRegistryCoordinatorWithIndices.updateOperators`
* `BLSRegistryCoordinatorWithIndices.deregisterOperator`
* `BLSRegistryCoordinatorWithIndices.ejectOperator`

*Effects*:
* 

*Requirements*:
* 

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

<!-- An offchain actor can provide a list of operator ids, their corresponding addresses, and a few other witnesses in order to recalculate the stakes of the provided operators for all of the quorums each operator is registered for. This ends block range of the current `OperatorStakeUpdate`s for each of the quorums for each of the provided operators and pushes a new update for each of them.

This has more implications after slashing is enabled... TODO -->

(TODO) description

*Entry Points*:
* `BLSRegistryCoordinatorWithIndices.updateOperators`

*Effects*:
* 

*Requirements*:
* 

---

### Quorums and Configuration

(TODO) Brief description, here are the functions:

* [`StakeRegistry.initializeQuorum`](#TODO)
* [`StakeRegistry.setMinimumStakeForQuorum`](#TODO)
* [`StakeRegistry.addStrategies`](#TODO)
* [`StakeRegistry.removeStrategies`](#TODO)
* [`StakeRegistry.modifyStrategyParams`](#TODO)

#### `initializeQuorum`

```solidity
TODO
```

<!-- ### createQuorum

The owner of the StakeRegistry can create a quorum by providing the list of `StrategyAndWeightingMultiplier`s. Quorums cannot be removed. -->

(TODO) description

*Entry Points*:
* `ContractName.functionName`

*Effects*:
* 

*Requirements*:
* 

#### `setMinimumStakeForQuorum`

```solidity
TODO
```

(TODO) description

*Entry Points*:
* `ContractName.functionName`

*Effects*:
* 

*Requirements*:
* 

#### `addStrategies`

```solidity
TODO
```

(TODO) description

*Entry Points*:
* `ContractName.functionName`

*Effects*:
* 

*Requirements*:
* 

#### `removeStrategies`

```solidity
TODO
```

(TODO) description

*Entry Points*:
* `ContractName.functionName`

*Effects*:
* 

*Requirements*:
* 

#### `modifyStrategyParams`

```solidity
TODO
```

<!-- ### modifyQuorum

The owner of the StakeRegistry can modify the set of strategies and they multipliers for a certain quorum. -->

(TODO) description

*Entry Points*:
* `ContractName.functionName`

*Effects*:
* 

*Requirements*:
* 

---
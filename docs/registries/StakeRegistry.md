## StakeRegistry

| File | Type | Proxy |
| -------- | -------- | -------- |
| [`StakeRegistry.sol`](../src/StakeRegistry.sol) | Singleton | Transparent proxy |

TODO

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

TODO

*Entry Points*:
* `RegistryCoordinator.registerOperator`
* `RegistryCoordinator.registerOperatorWithChurn`

*Effects*:
*

*Requirements*:
* 

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

TODO

*Entry Points*:
* `RegistryCoordinator.registerOperatorWithChurn`
* `RegistryCoordinator.deregisterOperator`
* `RegistryCoordinator.ejectOperator`
* `RegistryCoordinator.updateOperators`
* `RegistryCoordinator.updateOperatorsForQuorum`

*Effects*:
*

*Requirements*:
* 

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

TODO

*Entry Points*:
* `RegistryCoordinator.updateOperators`
* `RegistryCoordinator.updateOperatorsForQuorum`

*Effects*:
*

*Requirements*:
* 

### System Configuration

This method is used by the `RegistryCoordinator` to initialize new quorums in the `StakeRegistry`:
* [`initializeQuorum`](#initializequorum)

These methods are used by the `RegistryCoordinator's` Owner to configure initialized quorums in the `StakeRegistry`:
* [`setMinimumStakeForQuorum`](#setminimumstakeforquorum)
* [`addStrategies`](#addstrategies)
* [`removeStrategies`](#removestrategies)
* [`modifyStrategyParams`](#modifystrategyparams)

#### `initializeQuorum`

```solidity
function initializeQuorum(
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

<!-- This method is ONLY callable by the `RegistryCoordinator`, and is called when the `RegistryCoordinator` Owner creates a new quorum.

`initializeQuorum` initializes a new quorum by pushing an initial `StakeUpdate` to `_totalStakeHistory[quorumNumber]`. Other methods can validate that a quorum exists by checking whether `_totalStakeHistory[quorumNumber]` has a nonzero length.

*Entry Points*:
* `RegistryCoordinator.createQuorum`

*Effects*:
* 
* Pushes a `StakeUpdate` to `_totalStakeHistory[quorumNumber]`. The update's `updateBlockNumber` is set to the current block, and `stake` is set to 0.

*Requirements*:
* Caller MUST be the `RegistryCoordinator`
* `quorumNumber` MUST NOT belong to an existing, initialized quorum -->

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

TODO

*Effects*:
*

*Requirements*:
* 

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

TODO

*Effects*:
*

*Requirements*:
* 

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
```

TODO

*Effects*:
*

*Requirements*:
* 

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
```

TODO

*Effects*:
*

*Requirements*:
* 

---
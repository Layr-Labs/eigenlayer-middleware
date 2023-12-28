## IndexRegistry

| File | Type | Proxy? |
| -------- | -------- | -------- |
| [`IndexRegistry.sol`](../../src/IndexRegistry.sol) | Singleton | Transparent proxy |

TODO

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

TODO

*Entry Points*:
* `RegistryCoordinator.registerOperator`
* `RegistryCoordinator.registerOperatorWithChurn`

*Effects*:
* 

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

`initializeQuorum` initializes a new quorum by pushing an initial `QuorumUpdate` to `_operatorCountHistory[quorumNumber]`. Other methods can validate that a quorum exists by checking whether `_operatorCountHistory[quorumNumber]` has a nonzero length.

*Entry Points*:
* `RegistryCoordinator.createQuorum`

*Effects*:
* Pushes a `QuorumUpdate` to `_operatorCountHistory[quorumNumber]`. The update's `updateBlockNumber` is set to the current block, and `numOperators` is set to 0.

*Requirements*:
* Caller MUST be the `RegistryCoordinator`
* `_operatorCountHistory[quorumNumber].length` MUST be zero

---
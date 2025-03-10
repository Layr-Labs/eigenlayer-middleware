## SlasherBase

| File | Type | Proxy |
| -------- | -------- | -------- |
| [`SlasherBase.sol`](../src/base/SlasherBase.sol) | Abstract | No |

The `SlasherBase` is an abstract contract that provides core slashing functionality intended for AVSs to inherit. It serves as the foundation for implementing slashing mechanisms that interact with EigenLayer's `AllocationManager`. There are two implementations of this contract which are the [`VetoableSlasher`](./VetoableSlasher.md) and the [`InstantSlasher`](./InstantSlasher.md).

*As of current implementation*:
* This contract provides the base functionality for slashing operators in EigenLayer based on certain conditions
* Concrete implementations will determine when and how slashing is performed
* The contract maintains a connection to the registry coordinator and the allocation manager

---    

### Core Functionality

#### `constructor`
```solidity
constructor(
    IAllocationManager _allocationManager,
    ISlashingRegistryCoordinator _registryCoordinator,
    address _slasher
)
```
Initializes the base slasher contract with essential components.

*Effects*:
* Initializes the contract with references to the allocation manager, registry coordinator, and the authorized slasher address

*Requirements*:
* Valid addresses must be provided for all parameters

#### `_fulfillSlashingRequest`
```solidity
function _fulfillSlashingRequest(
    uint256 _requestId,
    IAllocationManager.SlashingParams memory _params
) 
    internal 
    virtual
```
Internal function that executes a slashing request by calling the `AllocationManager.slashOperator` method.

*Effects*:
* Calls the allocation manager to slash the specified operator
* Emits an `OperatorSlashed` event with details about the slashing action

*Requirements*:
* The allocation manager must be properly set up
* The slashing parameters must be valid

#### `_checkSlasher`
```solidity
function _checkSlasher(
    address account
) 
    internal 
    view 
    virtual
```
Internal function that verifies if an account is the authorized slasher.

*Effects*:
* Reverts with an `OnlySlasher` error if the provided account is not the authorized slasher

*Requirements*:
* The account must match the stored slasher address

### Modifiers

#### `onlySlasher`
```solidity
modifier onlySlasher()
```
Ensures that only the authorized slasher can call certain functions. This will commonly be set as the address of the AVS `ServiceManager` which would expose a permissioned or permissionless external function to call the slashing contract. Keeping the contracts decoupled allows for easier upgrade paths.

*Effects*:
* Calls `_checkSlasher` to verify that the caller is the authorized slasher
* Allows the function execution to proceed if the check passes
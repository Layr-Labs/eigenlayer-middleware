[core-registerToAVS]: https://github.com/Layr-Labs/eigenlayer-contracts/blob/dev/docs/core/AVSDirectory.md#registeroperatortoavs
[core-deregisterFromAVS]: https://github.com/Layr-Labs/eigenlayer-contracts/blob/dev/docs/core/AVSDirectory.md#deregisteroperatorfromavs

## ServiceManagerBase

| File | Type | Proxy |
| -------- | -------- | -------- |
| [`ServiceManagerBase.sol`](../src/ServiceManagerBase.sol) | Singleton | Transparent proxy |

The `ServiceManagerBase` represents the AVS's address relative to EigenLayer core. When registering or deregistering an operator from an AVS, the AVS's `ServiceManagerBase` communicates this change to the core contracts, allowing the core contracts to maintain an up-to-date view on operator registration status with various AVSs.

*As of M2*:
* Currently, this contract is used by the `AVSDirectory` to keep track of operator registration and deregistration. Eventually, this relationship will be expanded to allow operators to opt in to slashing and payments for services.

---    

#### `registerOperatorToAVS`

```solidity
function registerOperatorToAVS(
    address operator,
    ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
) 
    public 
    virtual 
    onlyRegistryCoordinator
```

When the `RegistryCoordinator` registers an operator for an AVS and they were not previously registered, it calls this method on `ServiceManagerBase`, which forwards the call to the EigenLayer core contract, the `AVSDirectory`.

*Entry Points*:
* `RegistryCoordinator.registerOperator`
* `RegistryCoordinator.registerOperatorWithChurn`

*Effects*:
* See EigenLayer core: [`AVSDirectory.registerOperatorToAVS`][core-registerToAVS]

*Requirements*:
* Caller MUST be the `RegistryCoordinator`
* See EigenLayer core: [`AVSDirectory.registerOperatorToAVS`][core-registerToAVS]

#### `deregisterOperatorFromAVS`

```solidity
function deregisterOperatorFromAVS(
    address operator
) 
    public 
    virtual 
    onlyRegistryCoordinator
```

When the `RegistryCoordinator` deregisters an operator from an AVS, it calls this method on `ServiceManagerBase`, which forwards the call to the EigenLayer core contract, the `AVSDirectory`.

*Entry Points*:
* `RegistryCoordinator.registerOperatorWithChurn`
* `RegistryCoordinator.deregisterOperator`
* `RegistryCoordinator.ejectOperator`
* `RegistryCoordinator.updateOperators`
* `RegistryCoordinator.updateOperatorsForQuorum`

*Effects*:
* See EigenLayer core: [`AVSDirectory.deregisterOperatorFromAVS`][core-deregisterFromAVS]

*Requirements*:
* Caller MUST be the `RegistryCoordinator`
* See EigenLayer core: [`AVSDirectory.deregisterOperatorFromAVS`][core-dmgr-deregister]
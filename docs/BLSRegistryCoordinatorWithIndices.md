## BLSRegistryCoordinatorWithIndices

| File | Type | Proxy? |
| -------- | -------- | -------- |
| [`BLSRegistryCoordinatorWithIndices.sol`](../src/BLSRegistryCoordinatorWithIndices.sol) | Singleton | Transparent proxy |

TODO

<!-- The `BLSRegistryCoordinatorWithIndices` is the primary entry point for operators as they register for and deregister from an AVS's quorums. When operators register or deregister, the registry coordinator updates that operator's currently-registered quorums, and pushes the registration/deregistration to each of the three registries it controls:
* `BLSPubkeyRegistry`: tracks the aggregate BLS pubkey hash for the operators registered to each quorum. Also maintains a history of these aggregate pubkey hashes.
* `StakeRegistry`: interfaces with the EigenLayer core contracts to track historical state of operators per quorum.
* `IndexRegistry`: assigns indices to operators within each quorum, and tracks historical indices and operators per quorum. Used primarily by offchain infrastructure to fetch ordered lists of operators in quorums.

Both the registry coordinator and each of the registries maintain historical state for the specific information they track. This historical state tracking can be used to query state at a particular block, which is primarily used in offchain infrastructure. -->

#### High-level Concepts

This document organizes methods according to the following themes (click each to be taken to the relevant section):
* [Registering and Deregistering](#registering-and-deregistering)
* [Updating Registered Operators](#updating-registered-operators)
* [System Configuration](#system-configuration)

#### Important State Variables

TODO

<!-- * `EigenPodManager`:
    * `mapping(address => IEigenPod) public ownerToPod`: Tracks the deployed `EigenPod` for each Staker
    * `mapping(address => int256) public podOwnerShares`: Keeps track of the actively restaked beacon chain ETH for each Staker. 
        * In some cases, a beacon chain balance update may cause a Staker's balance to drop below zero. This is because when queueing for a withdrawal in the `DelegationManager`, the Staker's current shares are fully removed. If the Staker's beacon chain balance drops after this occurs, their `podOwnerShares` may go negative. This is a temporary change to account for the drop in balance, and is ultimately corrected when the withdrawal is finally processed.
        * Since balances on the consensus layer are stored only in Gwei amounts, the EigenPodManager enforces the invariant that `podOwnerShares` is always a whole Gwei amount for every staker, i.e. `podOwnerShares[staker] % 1e9 == 0` always. -->

#### Important Definitions

TODO

<!-- * "Pod Owner": A Staker who has deployed an `EigenPod` is a Pod Owner. The terms are used interchangeably in this document.
    * Pod Owners can only deploy a single `EigenPod`, but can restake any number of beacon chain validators from the same `EigenPod`.
    * Pod Owners can delegate their `EigenPodManager` shares to Operators (via `DelegationManager`).
    * These shares correspond to the amount of provably-restaked beacon chain ETH held by the Pod Owner via their `EigenPod`. -->

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
    string calldata socket
) 
    external 
    onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR)
```

Allows an operator to register for one or more quorums, if they 

*Effects*:
* 

*Requirements*:
* 

#### `registerOperatorWithChurn`

```solidity
function registerOperatorWithChurn(
    bytes calldata quorumNumbers, 
    string calldata socket,
    OperatorKickParam[] calldata operatorKickParams,
    SignatureWithSaltAndExpiry memory churnApproverSignature
) 
    external 
    onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR)
```

TODO

*Effects*:
*

*Requirements*:
* 

#### `deregisterOperator`

```solidity
function deregisterOperator(
    bytes calldata quorumNumbers
) 
    external 
    onlyWhenNotPaused(PAUSED_DEREGISTER_OPERATOR)
```

TODO

*Effects*:
*

*Requirements*:
* 

#### `ejectOperator`

```solidity
function ejectOperator(
    address operator, 
    bytes calldata quorumNumbers
) 
    external 
    onlyEjector
```

TODO

*Effects*:
*

*Requirements*:
* 

---

### Updating Registered Operators

TODO

#### `updateOperators`

```solidity
function updateOperators(
    address[] calldata operators
) 
    external 
    onlyWhenNotPaused(PAUSED_UPDATE_OPERATOR)
```

TODO

*Effects*:
*

*Requirements*:
* 

#### `updateSocket`

```solidity
function updateSocket(string memory socket) external
```

TODO

*Effects*:
*

*Requirements*:
* 

---

### System Configuration

TODO

#### `createQuorum`

```solidity
function createQuorum(
    OperatorSetParam memory operatorSetParams,
    uint96 minimumStake,
    IStakeRegistry.StrategyParams[] memory strategyParams
) 
    external
    virtual 
    onlyServiceManagerOwner
```

TODO

*Effects*:
*

*Requirements*:
* 

#### `setOperatorSetParams`

```solidity
function setOperatorSetParams(
    uint8 quorumNumber, 
    OperatorSetParam memory operatorSetParams
) 
    external 
    onlyServiceManagerOwner 
    quorumExists(quorumNumber)
```

TODO

*Effects*:
*

*Requirements*:
* 

#### `setChurnApprover`

```solidity
function setChurnApprover(address _churnApprover) external onlyServiceManagerOwner
```

TODO

*Effects*:
*

*Requirements*:
* 

#### `setEjector`

```solidity
function setEjector(address _ejector) external onlyServiceManagerOwner
```

TODO

*Effects*:
*

*Requirements*:
* 
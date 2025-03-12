## SlashingRegistryCoordinator

| File | Notes |
| -------- | -------- |
| [`SlashingRegistryCoordinator.sol`](../../src/contracts/SlashingRegistryCoordinator.sol) |  |
| [`SlashingRegistryCoordinatorStorage.sol`](../../src/contracts/SlashingRegistryCoordinatorStorage.sol) | state variables |
| [`ISlashingRegistryCoordinator.sol`](../../src/contracts/interfaces/ISlashingRegistryCoordinator.sol) | interface |

Libraries and Mixins:

| File | Notes |
| -------- | -------- |
| [`BitmapUtils.sol`](../../src/contracts/libraries/BitmapUtils.sol) | bitmap manipulation |
| [`BN254.sol`](../../src/contracts/libraries/BN254.sol) | elliptic curve operations |
| [`SignatureCheckerLib.sol`](../../src/contracts/libraries/SignatureCheckerLib.sol) | signature verification |
| [`QuorumBitmapHistoryLib.sol`](../../src/contracts/libraries/QuorumBitmapHistoryLib.sol) | managing quorum registrations |
| [`Pausable.sol`](../../src/contracts/permissions/Pausable.sol) | pausable functionality |

## Prior Reading

* [EigenLayer Slashing ELIP-002](https://github.com/eigenfoundation/ELIPs/blob/main/ELIPs/ELIP-002.md)

## Overview

The `SlashingRegistryCoordinator` manages the registry contracts and integrates with the `AllocationManager` to manage quorum creation, registration and deregistration. The contract's responsibilities include:

* [Quorum Management](#quorum-management)
* [Operator Registration](#operator-registration)
* [Stake Management](#stake-management)
* [Operator Churn](#operator-churn)
* [AVS Integration](#avs-integration)



## Parameterization

* `MAX_QUORUM_COUNT`: The maximum number of quorums that can be created (hardcoded to `192`).
* `BIPS_DENOMINATOR`: Used for calculating percentages in basis points (hardcoded to `10000`).
* `ejectionCooldown`: The cooldown period an operator must wait after being ejected before they can re-register.
  * Default: Can be set by the contract owner.

---

## Quorum Management

Quorums are logical groupings of operators that share a common purpose within an AVS. Each quorum tracks operator registrations, stakes, and has its own configuration for operator management. The `SlashingRegistryCoordinator` supports two types of quorums:

1. **Total Delegated Stake Quorums**: Track the total delegated stake for operators
2. **Slashable Stake Quorums**: Track the slashable stake for operators, which is used for slashing

Each quorum is identified by a unique `quorumNumber` and has its own set of parameters defined in the `OperatorSetParam` struct:

```solidity
struct OperatorSetParam {
    uint32 maxOperatorCount;
    uint16 kickBIPsOfOperatorStake;
    uint16 kickBIPsOfTotalStake;
}
```

**Methods:**
* [`createTotalDelegatedStakeQuorum`](#createtotaldelegatedstakequorum)
* [`createSlashableStakeQuorum`](#createslashablestakequorum)
* [`setOperatorSetParams`](#setoperatorsetparams)

#### `createTotalDelegatedStakeQuorum`

```solidity
function createTotalDelegatedStakeQuorum(
    OperatorSetParam memory operatorSetParams,
    uint96 minimumStake,
    IStakeRegistryTypes.StrategyParams[] memory strategyParams
) 
    external
```

This function creates a new quorum that tracks the total delegated stake for operators. The quorum is initialized with the provided parameters and integrated with the underlying registry contracts.

*Effects:*
* Increments the `quorumCount` by 1
* Sets the operator set parameters for the new quorum
* Creates an operator set in the `AllocationManager`
* Initializes the quorum in all registry contracts:
  * `StakeRegistry`: Sets minimum stake and strategy parameters
  * `IndexRegistry`: Prepares the quorum for tracking operator indices
  * `BLSApkRegistry`: Prepares the quorum for tracking BLS public keys
* Emits an `OperatorSetParamsUpdated` event for the new quorum

*Requirements:*
* Caller MUST be the contract owner
* The quorum count MUST NOT exceed `MAX_QUORUM_COUNT` (192)

#### `createSlashableStakeQuorum`

```solidity
function createSlashableStakeQuorum(
    OperatorSetParam memory operatorSetParams,
    uint96 minimumStake,
    IStakeRegistryTypes.StrategyParams[] memory strategyParams,
    uint32 lookAheadPeriod
) 
    external
```

This function creates a new quorum that specifically tracks slashable stake for operators. This type of quorum provides slashing enforcement through the `AllocationManager`.

*Effects:*
* Same as `createTotalDelegatedStakeQuorum`, but initializes the quorum with slashable stake type
* Additionally configures the `lookAheadPeriod` for slashable stake calculation

*Requirements:*
* Same as `createTotalDelegatedStakeQuorum`

#### `setOperatorSetParams`

```solidity
function setOperatorSetParams(
    uint8 quorumNumber,
    OperatorSetParam memory operatorSetParams
) 
    external
```

This function updates the parameters for an existing quorum, allowing the owner to modify the maximum operator count and churn thresholds.

*Effects:*
* Updates the operator set parameters for the specified quorum
* Emits an `OperatorSetParamsUpdated` event

*Requirements:*
* Caller MUST be the contract owner
* The specified quorum MUST exist

---

## Operator Registration

Operators need to register with the `SlashingRegistryCoordinator` to participate in quorums. Registration involves providing BLS public keys, sockets, and allocating stake to specific quorums. The contract tracks an operator's registration status and history of quorum memberships. The `AllocationManager` calls these functions when an operator registers for a quorum.

**Methods:**
* [`registerOperator`](#registeroperator)
* [`deregisterOperator`](#deregisteroperator)
* [`updateSocket`](#updatesocket)
* [`ejectOperator`](#ejectoperator)

#### `registerOperator`

```solidity
function registerOperator(
    address operator,
    address avs,
    uint32[] calldata operatorSetIds,
    bytes calldata data
) 
    external
    onlyAllocationManager
    onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR)
```

This function is called by the `AllocationManager` when an operator wants to register for one or more quorums. It supports two registration types: normal registration and registration with churn.

*Effects:*
* Registers operator's BLS public key if not already registered
* Updates operator's quorum bitmap to include the new quorums
* Updates operator's socket information
* Updates operator's registration status to `REGISTERED`
* Registers the operator with all registry contracts
* If registering with churn, may deregister another operator to make room
* Emits an `OperatorRegistered` event

*Requirements:*
* Caller MUST be the Allocation Manager
* Contract MUST NOT be paused for operator registration
* Provided AVS address MUST match the contract's configured AVS
* Operator MUST NOT be already registered for the specified quorums
* Operator MUST be past their ejection cooldown if they were previously ejected
* For normal registration, quorums MUST NOT exceed their maximum operator count
* For registration with churn, the churn approver's signature MUST be valid

#### `deregisterOperator`

```solidity
function deregisterOperator(
    address operator,
    address avs,
    uint32[] calldata operatorSetIds
) 
    external
    onlyAllocationManager
    onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR)
```

This function is called by the `AllocationManager` when an operator wants to deregister from one or more quorums.

*Effects:*
* Updates operator's quorum bitmap to remove the specified quorums
* If the operator is no longer registered for any quorums, updates their status to `DEREGISTERED`
* Deregisters the operator from all registry contracts
* Emits an `OperatorDeregistered` event if the operator's status changes to `DEREGISTERED`

*Requirements:*
* Caller MUST be the Allocation Manager
* Contract MUST NOT be paused for operator deregistration
* Provided AVS address MUST match the contract's configured AVS
* Operator MUST be currently registered
* Operator MUST be registered for the specified quorums

#### `updateSocket`

```solidity
function updateSocket(
    string memory socket
) 
    external
```

This function allows a registered operator to update their socket information.

*Effects:*
* Updates the operator's socket in the SocketRegistry
* Emits an `OperatorSocketUpdate` event

*Requirements:*
* Caller MUST be a registered operator

#### `ejectOperator`

```solidity
function ejectOperator(
    address operator,
    bytes memory quorumNumbers
) 
    external
    onlyEjector
```

This function allows the designated ejector to forcibly remove an operator from specified quorums.

*Effects:*
* Sets the operator's `lastEjectionTimestamp` to the current timestamp
* Deregisters the operator from the specified quorums
* Forces deregistration from the AllocationManager
* The operator will be unable to re-register until the `ejectionCooldown` period passes

*Requirements:*
* Caller MUST be the designated ejector address
* Operator MUST be registered for the specified quorums

---

## Stake Management

The `SlashingRegistryCoordinator` manages operator stakes through the `StakeRegistry`. It enforces minimum stake requirements and provides mechanisms to update stake values and deregister operators who fall below the threshold.

**Methods:**
* [`updateOperatorsForQuorum`](#updateoperatorsforquorum)

#### `updateOperatorsForQuorum`

```solidity
function updateOperatorsForQuorum(
    address[][] memory operatorsPerQuorum,
    bytes calldata quorumNumbers
) 
    external
```

This function updates the stakes of all operators in specified quorums at once. This is more efficient than calling `updateOperators` for multiple operators individually.

*Effects:*
* Updates stake values for all operators in the specified quorums
* Updates each quorum's `quorumUpdateBlockNumber` to the current block number
* May deregister operators from quorums if their stake falls below the minimum
* Emits a `QuorumBlockNumberUpdated` event for each updated quorum

*Requirements:*
* Contract MUST NOT be paused for operator updates
* The number of operator lists MUST match the number of quorums
* Each operator list MUST contain the exact set of registered operators for the corresponding quorum
* Each operator list MUST be sorted in ascending order by operator address
* Operators MUST be registered for their respective quorums

---

## Operator Churn

Operator churn is the process of replacing an existing operator with a new one when a quorum has reached its maximum capacity. The `SlashingRegistryCoordinator` provides mechanisms for churn based on stake thresholds and authorized approvals.

**Concepts:**
* [Churn Thresholds](#churn-thresholds)
* [Churn Approval](#churn-approval)

**Methods:**
* [`setChurnApprover`](#setchurnapprover)

#### Churn Thresholds

Operator churn is governed by two threshold parameters defined in the `OperatorSetParam` struct:

1. `kickBIPsOfOperatorStake`: The minimum percentage (in basis points) by which a new operator's stake must exceed an existing operator's stake to qualify for churn.
2. `kickBIPsOfTotalStake`: The minimum percentage (in basis points) of total quorum stake that an operator must maintain to avoid being churned out.

These thresholds ensure that operators can only be replaced by meaningfully higher-staked operators, and that operators with significant stake relative to the quorum total are protected from churn.

The contract implements two helper functions to calculate these thresholds:

```solidity
function _individualKickThreshold(
    uint96 operatorStake,
    OperatorSetParam memory setParams
)   
    internal 
    pure 
```

```solidity
function _totalKickThreshold(
    uint96 totalStake,
    OperatorSetParam memory setParams
) 
    internal 
    pure 
```

#### Churn Approval

For security and coordination, operator churn requires approval from a designated churn approver. The churn approver must sign a message authorizing the replacement of specific operators.

The churn approval process uses EIP-712 typed signatures to ensure the integrity and non-reusability of churn approvals. Each approval includes:

1. The registering operator's address and ID
2. The parameters specifying which operators to kick
3. A unique salt to prevent replay attacks
4. An expiration timestamp

```solidity
function calculateOperatorChurnApprovalDigestHash(
    address registeringOperator,
    bytes32 registeringOperatorId,
    OperatorKickParam[] memory operatorKickParams,
    bytes32 salt,
    uint256 expiry
) 
    public
```

#### `setChurnApprover`

```solidity
function setChurnApprover(
    address _churnApprover
) 
    external
```

This function updates the address that is authorized to approve operator churn operations.

*Effects:*
* Updates the `churnApprover` address
* Emits a `ChurnApproverUpdated` event

*Requirements:*
* Caller MUST be the contract owner

---

## AVS Integration

The `SlashingRegistryCoordinator` integrates with `AllocationManager`, and is identified as the `AVSRegistrar` within the `AllocationManager`.

**Methods:**
* [`setAVS`](#setavs)
* [`supportsAVS`](#supportsavs)

#### `setAVS`

```solidity
function setAVS(
    address _avs
) 
    external
```

This function sets the AVS address for the AVS (this identitiy is used for UAM integration). Note: updating this will break existing operator sets, this value should only be set once. 
This value should be the address of the `ServiceManager` contract.

*Effects:*
* Sets the `avs` address

*Requirements:*
* Caller MUST be the contract owner

#### `supportsAVS`

```solidity
function supportsAVS(
    address _avs
)  
    public
```

This function checks whether a given AVS address is supported by this contract. It is used by the `AllocationManager` to verify that the contract is correctly configured for a specific AVS.

*Returns:*
* `true` if the provided address matches the configured AVS address
* `false` otherwise

---

## Configuration Functions

These functions allow the contract owner to configure various parameters and roles within the contract.

**Methods:**
* [`setEjector`](#setejector)
* [`setEjectionCooldown`](#setejectioncooldown)

#### `setEjector`

```solidity
function setEjector(
    address _ejector
) 
    external
```

This function updates the address that is authorized to forcibly eject operators from quorums.

*Effects:*
* Updates the `ejector` address
* Emits an `EjectorUpdated` event

*Requirements:*
* Caller MUST be the contract owner

#### `setEjectionCooldown`

```solidity
function setEjectionCooldown(
    uint256 _ejectionCooldown
) 
    external
```

This function updates the cooldown period that ejected operators must wait before they can re-register.

*Effects:*
* Updates the `ejectionCooldown` value

*Requirements:*
* Caller MUST be the contract owner

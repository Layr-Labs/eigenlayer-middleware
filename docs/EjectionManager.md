## EjectionManager

| File | Type | Proxy? |
| -------- | -------- | -------- |
| [`EjectionManager.sol`](../src/EjectionManager.sol) | Singleton | Transparent proxy |

The `EjectionManager` facilitates automated ejection of operators from the `SlashingRegistryCoordinator` under a configurable rate limit. It allows authorized ejectors to remove operators from quorums.

#### High-level Concepts

This document or:
* [Ejection Rate Limiting](#ejection-rate-limiting)
* [Ejector Management](#ejector-management)
* [Operator Ejection](#operator-ejection)

#### Roles

* Owner: a permissioned role that can configure quorum ejection parameters, manage ejectors, and eject operators without rate limiting
* Ejector: a permissioned role that can eject operators under the configured rate limits

---    

### Ejection Rate Limiting

The ejection rate limit system prevents too many operators from being ejected in a short time period, which could potentially destabilize the system. Rate limits are configured per quorum.

* [`setQuorumEjectionParams`](#setquorumejectparams)
* [`amountEjectableForQuorum`](#amountejectableforquorum)

#### `setQuorumEjectionParams`

```solidity
function setQuorumEjectionParams(
    uint8 quorumNumber,
    QuorumEjectionParams memory _quorumEjectionParams
) external onlyOwner
```

Allows the Owner to set the rate limit parameters for a specific quorum.

*Effects*:
* Updates the quorum's ejection parameters, including the rate limit window and the percentage of stake that can be ejected within that window

*Requirements*:
* Caller MUST be the Owner
* `quorumNumber` MUST be less than `MAX_QUORUM_COUNT`

#### `amountEjectableForQuorum`

```solidity
function amountEjectableForQuorum(
    uint8 quorumNumber
) public view returns (uint256)
```

Calculates the amount of stake that can currently be ejected from a quorum, based on the quorum's ejection parameters and recent ejection history.

*Return Value*:
* The amount of stake that can be ejected at the current `block.timestamp`

*Calculation Logic*:
1. Determines the total ejectable stake as a percentage of the quorum's total stake, using `quorumEjectionParams[quorumNumber].ejectableStakePercent`
2. Calculates the stake already ejected during the current rate limit window
3. Returns the difference between the total ejectable stake and the stake already ejected, or 0 if more stake has been ejected than the limit allows

---

### Ejector Management

These methods are used to manage which addresses have the ability to eject operators under the rate limits:

* [`setEjector`](#setejector)

#### `setEjector`

```solidity
function setEjector(address ejector, bool status) external onlyOwner
```

Allows the Owner to add or remove an address from the list of authorized ejectors.

*Effects*:
* Sets the address' ejector status to the provided value
* Emits an `EjectorUpdated` event

*Requirements*:
* Caller MUST be the Owner

---

### Operator Ejection

These methods allow ejection of operators from quorums:

* [`ejectOperators`](#ejectoperators)

#### `ejectOperators`

```solidity
function ejectOperators(
    bytes32[][] memory operatorIds
) external
```

Ejects operators from quorums, respecting the rate limits if called by an ejector (not the owner).

The method processes operators for each quorum sequentially. For each quorum, it attempts to eject operators in the order provided, stopping if the rate limit is reached. The owner can bypass rate limits.

*Effects*:
* For each quorum, ejects as many operators as possible prioritizing operators at lower indexes
* If called by an ejector (not the owner), records the stake ejected to keep track of rate limits
* Emits an `OperatorEjected` event for each ejected operator
* Emits a `QuorumEjection` event for each quorum with the number of ejected operators and whether the rate limit was hit

*Requirements*:
* Caller MUST be either an ejector or the owner

*Implementation Details*:
* If called by the owner, rate limits are not enforced, allowing emergency ejections
* If called by an ejector, operators are ejected until the rate limit is hit

---

### Initialization

The contract is initialized with the following parameters:

```solidity
function initialize(
    address _owner,
    address[] memory _ejectors,
    QuorumEjectionParams[] memory _quorumEjectionParams
) external initializer
```

*Effects*:
* Sets the contract owner
* Configures the initial set of ejectors
* Sets up the ejection parameters for quorums

*Requirements*:
* Can only be called once due to the `initializer` modifier

---

## ServiceManagerBase

| File | Type | Proxy |
| -------- | -------- | -------- |
| [`ServiceManagerBase.sol`](../src/ServiceManagerBase.sol) | Singleton | Transparent proxy |

Libraries and Mixins:

| File | Notes |
| -------- | -------- |
| [`BitmapUtils.sol`](../src/libraries/BitmapUtils.sol) | bitmap manipulation |
| [`LibMergeSort.sol`](../src/libraries/LibMergeSort.sol) | sorting utilities |

## Prior Reading

* [ELIP-002: Slashing via Unique Stake and Operator Sets](https://github.com/eigenfoundation/ELIPs/blob/main/ELIPs/ELIP-002.md)
* [ELIP-003: User Access Management (UAM)](https://github.com/eigenfoundation/ELIPs/blob/main/ELIPs/ELIP-003.md)

## Overview

The `ServiceManagerBase` contract is an abstract contract that serves as a minimal implementation for a `ServiceManager` contract that AVSs will deploy. This document will view this contract through the lens of an implementation of the `ServiceManagerBase`. AVSs are encouraged to extend this contract to meet their own functionality, such as implementing allowlisting for operator sets.

The `ServiceManager` is the AVS's identity within EigenLayer and is responsible for:

* Manages callbacks from the `SlashingRegsitryCoordinator` for operator registration for the AVS and operator sets. Calls will be forwarded to the `AVSDirectory`
* Handling rewards submissions to EigenLayer's `RewardsCoordinator`
* Managing access permissions via the `PermissionController`

## Concepts

* [User Access Management](#user-access-management)
* [Operator Registration](#operator-registration)
* [Rewards Management](#rewards-management)
* [Operator Sets](#operator-sets)

## User Access Management

The `ServiceManagerBase` implements User Access Management (UAM) as defined in [ELIP-003](https://github.com/eigenfoundation/ELIPs/blob/main/ELIPs/ELIP-003.md), allowing fine-grained control over which addresses can perform various actions on behalf of the AVS. UAM functions are primarily used by the contract owner to delegate permissions. For further information on the suggested UAM patterns, refer to the AVS [quick start](./quick-start.md) guide.

**Methods:**
* [`addPendingAdmin`](#addpendingadmin)
* [`removePendingAdmin`](#removependingadmin)
* [`removeAdmin`](#removeadmin)
* [`setAppointee`](#setappointee)
* [`removeAppointee`](#removeappointee)

#### `addPendingAdmin`

```solidity
function addPendingAdmin(
    address admin
) external onlyOwner
```

This function allows the contract owner to add a pending admin for the AVS. The new admin must accept adminhood via the `PermissionController` contract to become active.

*Effects:*
* Calls `addPendingAdmin` on the `PermissionController` contract to set `admin` as a pending admin for this AVS

*Requirements:*
* Caller MUST be the owner of the contract

#### `removePendingAdmin`

```solidity
function removePendingAdmin(
    address pendingAdmin
) external onlyOwner
```

This function allows the contract owner to remove an address from the list of pending admins.

*Effects:*
* Calls `removePendingAdmin` on the `PermissionController` contract to remove `pendingAdmin` from the list of pending admins

*Requirements:*
* Caller MUST be the owner of the contract

#### `removeAdmin`

```solidity
function removeAdmin(
    address admin
) external onlyOwner
```

This function allows the contract owner to remove an admin from the AVS.

*Effects:*
* Calls `removeAdmin` on the `PermissionController` contract to remove `admin` from the list of admins

*Requirements:*
* Caller MUST be the owner of the contract
* There MUST be at least one admin remaining after removal

#### `setAppointee`

```solidity
function setAppointee(
    address appointee,
    address target,`
    bytes4 selector
) external onlyOwner
```

This function allows the contract owner to delegate specific function permissions to an appointee.

*Effects:*
* Calls `setAppointee` on the `PermissionController` contract to grant `appointee` permission to call the function identified by `target` and `selector`

*Requirements:*
* Caller MUST be the owner of the contract

#### `removeAppointee`

```solidity
function removeAppointee(
    address appointee,
    address target,
    bytes4 selector
) external onlyOwner
```

This function allows the contract owner to revoke delegated permissions from an appointee.

*Effects:*
* Calls `removeAppointee` on the `PermissionController` contract to revoke `appointee`'s permission to call the function identified by `target` and `selector`

*Requirements:*
* Caller MUST be the owner of the contract

## Operator Registration

The `ServiceManagerBase` propagates state updates to the `AVSDirectory` (for backward compatibility).

**Methods:**
* [`registerOperatorToAVS`](#registeroperatortoavs)
* [`deregisterOperatorFromAVS`](#deregisteroperatorfromavs)
* [`deregisterOperatorFromOperatorSets`](#deregisteroperatorfromoperatorsets)

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

This function is called by the `SlashingRegistryCoordinator` when an operator registers for the AVS. It forwards the call to the EigenLayer core `AVSDirectory`.

*Effects:*
* Forwards the call to `AVSDirectory.registerOperatorToAVS` with the operator's address and signature

*Requirements:*
* Caller MUST be the `SlashingRegistryCoordinator`

#### `deregisterOperatorFromAVS`

```solidity
function deregisterOperatorFromAVS(
    address operator
) 
    public 
    virtual 
    onlyRegistryCoordinator
```

This function is called by the `SlashingRegistryCoordinator` when an operator deregisters from the AVS. It forwards the call to the EigenLayer core `AVSDirectory` contract to maintain backward compatibility.

*Effects:*
* Forwards the call to `AVSDirectory.deregisterOperatorFromAVS` with the operator's address

*Requirements:*
* Caller MUST be the `SlashingRegistryCoordinator`

#### `deregisterOperatorFromOperatorSets`

```solidity
function deregisterOperatorFromOperatorSets(
    address operator,
    uint32[] memory operatorSetIds
)
    public
    virtual
    onlyRegistryCoordinator
```

This function is called by the `SlashingRegistryCoordinator` to deregister an operator from specific operator.

*Effects:*
* Creates a `DeregisterParams` struct with the operator's address, the AVS address, and the operator set IDs
* Calls `AllocationManager.deregisterFromOperatorSets` with the constructed parameters

*Requirements:*
* Caller MUST be the `SlashingRegistryCoordinator`

## Rewards Management

The `ServiceManagerBase` allows the AVS to submit rewards to EigenLayer's `RewardsCoordinator` contract.

**Methods:**
* [`createAVSRewardsSubmission`](#createavsrewardssubmission)
* [`createOperatorDirectedAVSRewardsSubmission`](#createoperatordirectedavsrewardssubmission)
* [`setClaimerFor`](#setclaimerfor)
* [`setRewardsInitiator`](#setrewardsinitiator)

#### `createAVSRewardsSubmission`

```solidity
function createAVSRewardsSubmission(
    IRewardsCoordinator.RewardsSubmission[] calldata rewardsSubmissions
)
    public
    virtual
    onlyRewardsInitiator
```

This function allows the rewards initiator to create rewards submissions for the AVS. This submission will send rewards to all eligible operators according to stake weight.

*Effects:*
* For each `RewardsSubmission`:
  * Transfers tokens from caller to the ServiceManager
  * Approves the `RewardsCoordinator` to spend these tokens
* Calls `RewardsCoordinator.createAVSRewardsSubmission` with the provided submissions

*Requirements:*
* Caller MUST be the designated rewards initiator
* Token transfers and approvals MUST succeed

#### `createOperatorDirectedAVSRewardsSubmission`

```solidity
function createOperatorDirectedAVSRewardsSubmission(
    IRewardsCoordinator.OperatorDirectedRewardsSubmission[] calldata
        operatorDirectedRewardsSubmissions
) 
    public
    virtual
    onlyRewardsInitiator
```

This function allows the rewards initiator to create operator-directed rewards submissions, which provide more control over how rewards are distributed to specific operators.

*Effects:*
* For each `OperatorDirectedRewardsSubmission`:
  * Calculates the total token amount across all operator rewards
  * Transfers tokens from caller to the ServiceManager
  * Approves the `RewardsCoordinator` to spend these tokens
* Calls `RewardsCoordinator.createOperatorDirectedAVSRewardsSubmission` with the provided submissions

*Requirements:*
* Caller MUST be the designated rewards initiator
* Token transfers and approvals MUST succeed

#### `setClaimerFor`

```solidity
function setClaimerFor(
    address claimer
) 
    public
    virtual
    onlyOwner
```

This function allows the owner to set an address that can claim rewards on behalf of the AVS.

*Effects:*
* Calls `RewardsCoordinator.setClaimerFor` to set the claimer address

*Requirements:*
* Caller MUST be the owner

#### `setRewardsInitiator`

```solidity
function setRewardsInitiator(
    address newRewardsInitiator
)
    external
    onlyOwner
```

This function allows the owner to update the address that is permitted to submit rewards submissions on behalf of the AVS.

*Effects:*
* Updates the `rewardsInitiator` storage variable
* Emits a `RewardsInitiatorUpdated` event

*Requirements:*
* Caller MUST be the owner

## Metadata Management

**Methods:**
* [`updateAVSMetadataURI`](#updateavsmetadatauri)

#### `updateAVSMetadataURI`

```solidity
function updateAVSMetadataURI(
    string memory _metadataURI
)
    public
    virtual
    onlyOwner
```

This function allows the owner to update the metadata URI associated with the AVS.

*Effects:*
* Calls `AVSDirectory.updateAVSMetadataURI` with the provided URI

*Requirements:*
* Caller MUST be the owner

## View Functions

**Methods:**
* [`getRestakeableStrategies`](#getrestakeablestrategies)
* [`getOperatorRestakedStrategies`](#getoperatorrestakedstrategies)
* [`avsDirectory`](#avsdirectory)

#### `getRestakeableStrategies`

```solidity
function getRestakeableStrategies()
    external
    view
    virtual
    returns (address[] memory)
```

This function returns a list of strategy addresses that the AVS supports for restaking. This is intended to be called off-chain by the rewards calculation system.

*Returns:*
* An array of strategy addresses that the AVS supports for restaking across all quorums

#### `getOperatorRestakedStrategies`

```solidity
function getOperatorRestakedStrategies(
    address operator
)
    external
    view
    virtual
    returns (address[] memory)
```

This function returns a list of strategy addresses that a specific operator has potentially restaked with the AVS. This is intended to be called off-chain by the rewards calculation system.

*Returns:*
* An array of strategy addresses that the operator has potentially restaked with the AVS across all quorums they are registered for

#### `avsDirectory`

```solidity
function avsDirectory()
    external
    view
    override
    returns (address)
```

This function returns the address of the EigenLayer AVSDirectory contract.

*Returns:*
* The address of the EigenLayer AVSDirectory contract

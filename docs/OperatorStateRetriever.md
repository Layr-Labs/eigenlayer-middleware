# OperatorStateRetriever 

| File | Type | Proxy |
| -------- | -------- | -------- |
| [`OperatorStateRetriever.sol`](../src/OperatorStateRetriever.sol) | Singleton | None |

The `OperatorStateRetriever` contract provides view methods that compose view calls from the registry contracts to surface enriched state information. These methods are intended to be called offchain to prepare calldata for BLS signature validation through the `BLSSignatureChecker.checkSignatures` method.

The contract traverses historical state records in the registry contracts ([`IndexRegistry`](./registries/IndexRegistry.md), [`StakeRegistry`](./registries/StakeRegistry.md), and [`BLSApkRegistry`](./registries/BLSApkRegistry.md)) to retrieve information about operators and quorums at specific block numbers. This historical data is essential for validating signatures against a fixed point in time, as operators may register for or deregister from quorums after signing data.

#### High-level Concepts

This document organizes methods according to the following themes:
* [Offchain Methods](#offchain-methods)
* [Utility Functions](#utility-functions)

---

### Offchain Methods

These methods traverse various registry histories to retrieve information needed for BLS signature validation:
* [`getOperatorState (operatorId)`](#getoperatorstate-operatorid)
* [`getOperatorState (quorumNumbers)`](#getoperatorstate-quorumnumbers)
* [`getCheckSignaturesIndices`](#getchecksignaturesindices)

#### `getOperatorState (operatorId)`

```solidity
function getOperatorState(
    ISlashingRegistryCoordinator registryCoordinator,
    bytes32 operatorId,
    uint32 blockNumber
) external view returns (uint256, Operator[][] memory)

struct Operator {
    address operator;
    bytes32 operatorId;
    uint96 stake;
}
```

This method is designed for AVS operators to retrieve their state and responsibilities when a new task is created by the AVS coordinator. It returns information about an Operator and the quorums they were registered for at a specific block number.

The method performs the following operations:
1. Retrieves the quorum bitmap for the Operator at the specified block number
2. Converts the bitmap to an array of quorum numbers
3. For each quorum the Operator was registered for, retrieves the complete list of registered Operators in that quorum

This eliminates the need for operators to run indexers to fetch on-chain data.

*Returns*:
* `uint256`: A bitmap representation of the quorums the Operator was registered for at the given block number
* `Operator[][]`: For each quorum the Operator was registered for, an ordered list of all Operators in that quorum, including their addresses, IDs, and stakes

#### `getOperatorState (quorumNumbers)`

```solidity
function getOperatorState(
    ISlashingRegistryCoordinator registryCoordinator,
    bytes memory quorumNumbers,
    uint32 blockNumber
) public view returns (Operator[][] memory)
```

This method returns comprehensive information about all Operators registered for specified quorums at a given block number. It traverses multiple registry contracts to compile complete operator data.

The method performs the following operations for each quorum:
1. Retrieves the list of operator IDs from the `IndexRegistry`
2. Fetches each operator's address from the `BLSApkRegistry`
3. Obtains stake amounts from the `StakeRegistry`
4. Compiles this information into an ordered list of Operators for each quorum

*Returns*:
* `Operator[][]`: For each quorum in `quorumNumbers`, an ordered list of all Operators registered for that quorum at the specified block number, including their addresses, IDs, and stakes

#### `getCheckSignaturesIndices`

```solidity
function getCheckSignaturesIndices(
    ISlashingRegistryCoordinator registryCoordinator,
    uint32 referenceBlockNumber,
    bytes calldata quorumNumbers,
    bytes32[] calldata nonSignerOperatorIds
) external view returns (CheckSignaturesIndices memory)

struct CheckSignaturesIndices {
    uint32[] nonSignerQuorumBitmapIndices;
    uint32[] quorumApkIndices;
    uint32[] totalStakeIndices;
    uint32[][] nonSignerStakeIndices; // nonSignerStakeIndices[quorumNumberIndex][nonSignerIndex]
}
```

This method is critical for BLS signature validation, as it retrieves indices into historical state that can be used for efficient lookups in `BLSSignatureChecker.checkSignatures`. The non-signer operator IDs are required here as signature verification is done against negation of the BLS aggregate public key. That is, negate the aggregate key then add the weight of each signer. 

The method generates the following indices:
1. Indices of quorum bitmap updates for each non-signing operator
2. Indices of total stake updates for each quorum
3. For each quorum, indices of stake updates for non-signing operators registered for that quorum
4. Indices of aggregate public key (APK) updates for each quorum

By pre-computing these indices offchain, the `BLSSignatureChecker.checkSignatures` method can perform cheap lookups rather than traversing over historical state during an expensive onchain operation.

*Returns*:
* `CheckSignaturesIndices`: A struct containing all indices needed for signature validation:
* `nonSignerQuorumBitmapIndices`: For each non-signer, the index in `RegistryCoordinator._operatorBitmapHistory` where their quorum bitmap can be found
* `quorumApkIndices`: For each quorum, the index in `BLSApkRegistry.apkHistory` where the quorum's APK can be found
* `totalStakeIndices`: For each quorum, the index in `StakeRegistry._totalStakeHistory` where the quorum's total stake can be found
* `nonSignerStakeIndices`: For each quorum, indices in `StakeRegistry.operatorStakeHistory` for each non-signer registered for that quorum

*Requirements*:
* Non-signer operator IDs must be registered (have non-zero quorum bitmaps)

---

### Utility Functions

These methods provide additional utilities for retrieving historical state and operator information:
* [`getQuorumBitmapsAtBlockNumber`](#getquorumbitmapsatblocknumber)
* [`getBatchOperatorId`](#getbatchoperatorid)
* [`getBatchOperatorFromId`](#getbatchoperatorfromid)

#### `getQuorumBitmapsAtBlockNumber`

```solidity
function getQuorumBitmapsAtBlockNumber(
    ISlashingRegistryCoordinator registryCoordinator,
    bytes32[] memory operatorIds,
    uint32 blockNumber
) external view returns (uint256[] memory)
```

This method retrieves quorum bitmaps for multiple operators at a specific block number, providing an efficient way to determine which quorums each operator was registered for at that point in time.

*Returns*:
* `uint256[]`: An array of quorum bitmaps, one for each operator ID provided, representing the quorums each operator was registered for at the given block number

#### `getBatchOperatorId`

```solidity
function getBatchOperatorId(
    ISlashingRegistryCoordinator registryCoordinator,
    address[] memory operators
) external view returns (bytes32[] memory operatorIds)
```

This utility function converts multiple operator addresses to their corresponding operator IDs in a single call, improving gas efficiency for batch operations.

*Returns*:
* `bytes32[]`: An array of operator IDs corresponding to the provided addresses
* If an operator is not registered, its ID will be 0

#### `getBatchOperatorFromId`

```solidity
function getBatchOperatorFromId(
    ISlashingRegistryCoordinator registryCoordinator,
    bytes32[] memory operatorIds
) external view returns (address[] memory operators)
```

This utility function converts multiple operator IDs to their corresponding operator addresses in a single call, improving gas efficiency for batch operations.

*Returns*:
* `address[]`: An array of operator addresses corresponding to the provided IDs
* If an operator ID is not registered, its address will be 0x0

---
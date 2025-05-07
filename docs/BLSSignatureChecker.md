[core-docs-dev]: https://github.com/Layr-Labs/eigenlayer-contracts/tree/dev/docs
[core-dmgr-docs]: https://github.com/Layr-Labs/eigenlayer-contracts/blob/dev/docs/core/DelegationManager.md

[eigenda-service-manager]: https://github.com/Layr-Labs/eigenda/blob/dev-contracts/contracts/src/core/EigenDAServiceManager.sol

## BLSSignatureChecker

| File | Type | Proxy |
| -------- | -------- | -------- |
| [`BLSSignatureChecker.sol`](../src/BLSSignatureChecker.sol) | Singleton | Transparent proxy |
| [`OperatorStateRetriever.sol`](../src/OperatorStateRetriever.sol) | Singleton | None |

`BLSSignatureChecker` and `OperatorStateRetriever` perform (respectively) the onchain and offchain portions of BLS signature validation for the aggregate of a quorum's registered Operators.

The `OperatorStateRetriever` has various view methods intended to be called by offchain infrastructure in order to prepare a call to `BLSSignatureChecker.checkSignatures`. These methods traverse the state histories kept by the various registry contracts (see [./RegistryCoordinator.md](./RegistryCoordinator.md)) to query states at specific block numbers.

These historical states are then used within `BLSSignatureChecker` to validate a BLS signature formed from an aggregated subset of the Operators registered for one or more quorums at some specific block number.

#### High-level Concepts

This document organizes methods according to the following themes (click each to be taken to the relevant section):
* [Onchain](#onchain)
* [Offchain](#offchain)
* [System Configuration](#system-configuration)

---

### Onchain

#### `BLSSignatureChecker.checkSignatures`

```solidity
function checkSignatures(
    bytes32 msgHash, 
    bytes calldata quorumNumbers,
    uint32 referenceBlockNumber, 
    NonSignerStakesAndSignature memory params
)
    public 
    view
    returns (QuorumStakeTotals memory, bytes32)

struct NonSignerStakesAndSignature {
    uint32[] nonSignerQuorumBitmapIndices;
    BN254.G1Point[] nonSignerPubkeys;
    BN254.G1Point[] quorumApks;
    BN254.G2Point apkG2;
    BN254.G1Point sigma;
    uint32[] quorumApkIndices;
    uint32[] totalStakeIndices;
    uint32[][] nonSignerStakeIndices;
}

struct QuorumStakeTotals {
    uint96[] signedStakeForQuorum;
    uint96[] totalStakeForQuorum;
}
```

The goal of this method is to allow an AVS to validate a BLS signature formed from the aggregate pubkey ("apk") of Operators registered in one or more quorums at some `referenceBlockNumber`.

Some notes on method parameters:
* `msgHash` is the hash being signed by the apk. Note that the caller is responsible for ensuring `msgHash` is a hash! If someone can provide arbitrary input, it may be possible to tamper with signature verification.
* `referenceBlockNumber` is the reason each registry contract keeps historical states: so that lookups can be performed on each registry's info at a particular block. This is important because Operators may sign some data on behalf of an AVS, then deregister from one or more of the AVS's quorums. Historical states allow signature validation to be performed against a "fixed point" in AVS/quorum history.
* `quorumNumbers` is used to perform signature validation across one *or more* quorums. Also, Operators may be registered for more than one quorum - and for each quorum an Operator is registered for, that Operator's pubkey is included in that quorum's apk within the `BLSApkRegistry`. This means that, when calculating an apk across multiple `quorumNumbers`, Operators registered for more than one of these quorums will have their pubkey included more than once in the total apk.
* `params` contains both a signature from all signing Operators, as well as several fields that identify registered, non-signing Operators. While non-signing Operators haven't contributed to the signature, but need to be accounted for because, as Operators registered for one or more signing quorums, their public keys are included in that quorum's apk. Essentially, in order to validate the signature, nonsigners' public keys need to be subtracted out from the total apk to derive the apk that actually signed the message.

This method performs the following steps. Note that each step involves lookups of historical state from `referenceBlockNumber`, but the writing in this section will use the present tense because adding "at the `referenceBlockNumber`" everywhere gets confusing. Steps follow:
1. Calculate the *total nonsigner apk*, an aggregate pubkey composed of all nonsigner pubkeys. For each nonsigner:
    * Query the `RegistryCoordinator` to get the nonsigner's registered quorums.
    * Multiply the nonsigner's pubkey by the number of quorums in `quorumNumbers` the nonsigner is registered for.
    * Add the result to the *total nonsigner apk*.
2. Calculate the negative of the *total nonsigner apk*.
3. For each quorum:
    * Query the `BLSApkRegistry` to get the *quorum apk*: the aggregate pubkey of all Operators registered for that quorum.
    * Add the *quorum apk* to the *total nonsigner apk*. This effectively subtracts out any pubkeys belonging to nonsigning Operators in the quorum, leaving only pubkeys of signing Operators. We'll call the result the *total signing apk*.
    * Query the `StakeRegistry` to get the total stake for the quorum.
    * For each nonsigner, if the nonsigner is registered for the quorum, query the `StakeRegistry` for their stake and subtract it from the total. This leaves only stake belonging to signing Operators.
4. Use the `msgHash`, the *total signing apk*, `params.apkG2`, and `params.sigma` to validate the BLS signature.
5. Return the total stake and signing stakes for each quorum, along with a hash identifying the `referenceBlockNumber` and non-signers 

*Entry Points* (EigenDA):
* Called by [`EigenDAServiceManager.confirmBatch`][eigenda-service-manager]

*Requirements*:
* Input validation:
    * Quorum-related fields MUST have equal lengths: `quorumNumbers`, `params.quorumApks`, `params.quorumApkIndices`, `params.totalStakeIndices`, `params.nonSignerStakeIndices`
    * Nonsigner-related fields MUST have equal lengths: `params.nonSignerPubkeys`, `params.nonSignerQuorumBitmapIndices`
    * `referenceBlockNumber` MUST be less than `block.number`
    * `quorumNumbers` MUST be an ordered list of valid, initialized quorums
    * `params.nonSignerPubkeys` MUST ONLY contain unique pubkeys, in ascending order of their pubkey hash
* For each quorum:
    * Validate that each `params.quorumApks` corresponds to the quorum's apk at the `referenceBlockNumber`
* For each historical state lookup, the `referenceBlockNumber` and provided index MUST point to a valid historical entry: 
    * `referenceBlockNumber` MUST come after the entry's `updateBlockNumber`
    * The entry's `nextUpdateBlockNumber` MUST EITHER be 0, OR greater than `referenceBlockNumber`

---

### Offchain

These methods perform very gas-heavy lookups through various registry states, and are called by offchain infrastructure to construct calldata for a call to `BLSSignatureChecker.checkSignatures`:
* [`OperatorStateRetriever.getOperatorState (operatorId)`](#operatorstateretrievergetoperatorstate-operatorid)
* [`OperatorStateRetriever.getOperatorState (quorumNumbers)`](#operatorstateretrievergetoperatorstate-quorumnumbers)
* [`OperatorStateRetriever.getCheckSignaturesIndices`](#operatorstateretrievergetchecksignaturesindices)

#### `OperatorStateRetriever.getOperatorState (operatorId)`

```solidity
function getOperatorState(
    IRegistryCoordinator registryCoordinator, 
    bytes32 operatorId, 
    uint32 blockNumber
) 
    external 
    view 
    returns (uint256, Operator[][] memory)

struct Operator {
    bytes32 operatorId;
    uint96 stake;
}
```

Traverses history in the `RegistryCoordinator`, `IndexRegistry`, and `StakeRegistry` to retrieve information on an Operator (given by `operatorId`) and the quorums they are registered for at a specific `blockNumber`. Returns:
* `uint256`: a bitmap of the quorums the Operator was registered for at `blockNumber`
* `Operator[][]`: For each of the quorums mentioned above, this is a list of the Operators registered for that quorum at `blockNumber`, containing each Operator's `operatorId` and `stake`.

#### `OperatorStateRetriever.getOperatorState (quorumNumbers)`

```solidity
function getOperatorState(
    IRegistryCoordinator registryCoordinator, 
    bytes memory quorumNumbers, 
    uint32 blockNumber
) 
    public 
    view 
    returns(Operator[][] memory)
```

Traverses history in the `RegistryCoordinator`, `IndexRegistry`, and `StakeRegistry` to retrieve information on the Operator set registered for each quorum in `quorumNumbers` at `blockNumber`. Returns:
* `Operator[][]`: For each quorum in `quorumNumbers`, this is a list of the Operators registered for that quorum at `blockNumber`, containing each Operator's `operatorId` and `stake`.

#### `OperatorStateRetriever.getCheckSignaturesIndices`

```solidity
function getCheckSignaturesIndices(
    IRegistryCoordinator registryCoordinator,
    uint32 referenceBlockNumber, 
    bytes calldata quorumNumbers, 
    bytes32[] calldata nonSignerOperatorIds
)
    external 
    view 
    returns (CheckSignaturesIndices memory)

struct CheckSignaturesIndices {
    uint32[] nonSignerQuorumBitmapIndices;
    uint32[] quorumApkIndices;
    uint32[] totalStakeIndices;  
    uint32[][] nonSignerStakeIndices; // nonSignerStakeIndices[quorumNumberIndex][nonSignerIndex]
}
```

Traverses histories in the `RegistryCoordinator`, `IndexRegistry`, `StakeRegistry`, and `BLSApkRegistry` to retrieve information on one or more quorums' Operator sets and nonsigning Operators at a given `referenceBlockNumber`.

The return values are all "indices," because of the linear historical state each registry keeps. Offchain code calls this method to compute indices into historical state, which later is leveraged for cheap lookups in `BLSSignatureChecker.checkSignatures` (rather than traversing over the history during an onchain operation).

For each quorum, this returns:
* `uint32[] nonSignerQuorumBitmapIndices`: The indices in `RegistryCoordinator._operatorBitmapHistory` where each nonsigner's registered quorum bitmap can be found at `referenceBlockNumber`. Length is equal to the number of nonsigners included in `nonSignerOperatorIds`
* `uint32[] quorumApkIndices`: The indices in `BLSApkRegistry.apkHistory` where the quorum's apk can be found at `referenceBlockNumber`. Length is equal to the number of quorums in `quorumNumbers`.
* `uint32[] totalStakeIndices`: The indices in `StakeRegistry._totalStakeHistory` where each quorum's total stake can be found at `referenceBlockNumber`. Length is equal to the number of quorums in `quorumNumbers`.
* `uint32[][] nonSignerStakeIndices`: For each quorum, a list of the indices of each nonsigner's `StakeRegistry.operatorStakeHistory` entry at `referenceBlockNumber`. Length is equal to the number of quorums in `quorumNumbers`, and each sub-list is equal in length to the number of nonsigners in `nonSignerOperatorIds` registered for that quorum at `referenceBlockNumber`
## BLSApkRegistry

| File | Type | Proxy |
| -------- | -------- | -------- |
| [`BLSApkRegistry.sol`](../../src/BLSApkRegistry.sol) | Singleton | Transparent proxy |

The `BLSApkRegistry` tracks the current aggregate BLS pubkey for all Operators registered to each quorum, and keeps a historical record of each quorum's aggregate BLS pubkey hash. This contract makes heavy use of the `BN254` library to perform various operations on the BN254 elliptic curve (see [`BN254.sol`](../../src/libraries/BN254.sol)).

Each time an Operator registers for a quorum, its BLS pubkey is added to that quorum's `currentApk`. Each time an Operator deregisters from a quorum, its BLS pubkey is subtracted from that quorum's `currentApk`. This contract maintains a history of the hash of each quorum's apk over time, which is used by the `BLSSignatureChecker` to fetch the "total signing key" for a quorum at a specific block number.

#### High-level Concepts

This document organizes methods according to the following themes (click each to be taken to the relevant section):
* [Registering and Deregistering](#registering-and-deregistering)
* [System Configuration](#system-configuration)

---    

### Registering and Deregistering

These methods are ONLY called through the `RegistryCoordinator` - when an Operator registers for or deregisters from one or more quorums:
* [`registerBLSPublicKey`](#registerblspublickey)
* [`registerOperator`](#registeroperator)
* [`deregisterOperator`](#deregisteroperator)

#### `registerBLSPublicKey`

```solidity
function registerBLSPublicKey(
    address operator,
    PubkeyRegistrationParams calldata params,
    BN254.G1Point calldata pubkeyRegistrationMessageHash
) 
    external 
    onlyRegistryCoordinator 
    returns (bytes32 operatorId)

struct PubkeyRegistrationParams {
    BN254.G1Point pubkeyRegistrationSignature;
    BN254.G1Point pubkeyG1;
    BN254.G2Point pubkeyG2;
}
```

This method is ONLY callable by the `RegistryCoordinator`. It is called when an Operator registers for the AVS for the first time.

This method validates a BLS signature over the `pubkeyRegistrationMessageHash`, then permanently assigns the pubkey to the Operator. The hash of `params.pubkeyG1` becomes the Operator's unique `operatorId`, which identifies the Operator throughout the registry contracts.

*Entry Points*:
* `RegistryCoordinator.registerOperator`
* `RegistryCoordinator.registerOperatorWithChurn`

*Effects*:
* Registers the Operator's BLS pubkey for the first time, updating the following mappings:
    * `operatorToPubkey[operator]`
    * `operatorToPubkeyHash[operator]`
    * `operatorToPubKeyG2[operator]`
    * `pubkeyHashToOperator[pubkeyHash]`

*Requirements*:
* Caller MUST be the `RegistryCoordinator`
* `params.pubkeyG1` MUST NOT hash to the `ZERO_PK_HASH`
* `operator` MUST NOT have already registered a pubkey:
    * `operatorToPubkeyHash[operator]` MUST be zero
    * `pubkeyHashToOperator[pubkeyHash]` MUST be zero
* `params.pubkeyRegistrationSignature` MUST be a valid signature over `pubkeyRegistrationMessageHash`

#### `registerOperator`

```solidity
function registerOperator(
    address operator,
    bytes memory quorumNumbers
) 
    public 
    virtual 
    onlyRegistryCoordinator
```

`registerOperator` fetches the Operator's registered BLS pubkey (see `registerBLSPublicKey` above). Then, for each quorum in `quorumNumbers`, the Operator's pubkey is added to that quorum's `currentApk`. The `apkHistory` for the `quorumNumber` is also updated to reflect this change.

This method is ONLY callable by the `RegistryCoordinator`, and is called when an Operator registers for one or more quorums. This method *assumes* that `operator` is not already registered for any of `quorumNumbers`, and that there are no duplicates in `quorumNumbers`. These properties are enforced by the `RegistryCoordinator`.

*Entry Points*:
* `RegistryCoordinator.registerOperator`
* `RegistryCoordinator.registerOperatorWithChurn`

*Effects*:
* For each `quorum` in `quorumNumbers`:
    * Add the Operator's pubkey to the quorum's apk in `currentApk[quorum]`
    * Updates the quorum's `apkHistory`, pushing a new `ApkUpdate` for the current block number and setting its `apkHash` to the new hash of `currentApk[quorum]`.
        * *Note:* If the most recent entry in `apkHistory[quorum]` was made during the current block, this method updates the most recent entry rather than pushing a new one.

*Requirements*:
* Caller MUST be the `RegistryCoordinator`
* `operator` MUST already have a registered BLS pubkey (see `registerBLSPublicKey` above) 
* Each quorum in `quorumNumbers` MUST be initialized (see `initializeQuorum` below)

#### `deregisterOperator`

```solidity
function deregisterOperator(
    address operator,
    bytes memory quorumNumbers
) 
    public 
    virtual 
    onlyRegistryCoordinator
```

`deregisterOperator` fetches the Operator's registered BLS pubkey (see `registerBLSPublicKey` above). For each quorum in `quorumNumbers`, `deregisterOperator` performs the same steps as `registerOperator` above - except that the Operator's pubkey is negated. Whereas `registerOperator` "adds" a pubkey to each quorum's apk, `deregisterOperator` "subtracts" a pubkey from each quorum's apk.

This method is ONLY callable by the `RegistryCoordinator`, and is called when an Operator deregisters from one or more quorums. This method *assumes* that `operator` is registered for all quorums in `quorumNumbers`, and that there are no duplicates in `quorumNumbers`. These properties are enforced by the `RegistryCoordinator`.

*Entry Points*:
* `RegistryCoordinator.registerOperatorWithChurn`
* `RegistryCoordinator.deregisterOperator`
* `RegistryCoordinator.ejectOperator`
* `RegistryCoordinator.updateOperators`
* `RegistryCoordinator.updateOperatorsForQuorum`

*Effects*:
* For each `quorum` in `quorumNumbers`:
    * Negate the Operator's pubkey, then subtract it from the quorum's apk in `currentApk[quorum]`
    * Updates the quorum's `apkHistory`, pushing a new `ApkUpdate` for the current block number and setting its `apkHash` to the new hash of `currentApk[quorum]`.
        * *Note:* If the most recent entry in `apkHistory[quorum]` was made during the current block, this method updates the most recent entry rather than pushing a new one.

*Requirements*:
* Caller MUST be the `RegistryCoordinator`
* `operator` MUST already have a registered BLS pubkey (see `registerBLSPublicKey` above)
* Each quorum in `quorumNumbers` MUST be initialized (see `initializeQuorum` below)

#### `verifyAndRegisterG2PubkeyForOperator`

```solidity
function verifyAndRegisterG2PubkeyForOperator(
    address operator,
    BN254.G2Point calldata pubkeyG2
)
    external
    onlyRegistryCoordinatorOwner
```
`verifyAndRegisterG2PubkeyForOperator` verifies and registers a G2 public key for an operator that already has a G1 key. This method is used to retrieve all information for the `checkSignatures` entry point from a view function, avoiding the need to index this information offchain. The method ensures that the BLS key pair is derived from the same secret key and stores the G2 key for the operator.

This method is only callable by the `RegistryCoordinatorOwner`, which is the account that has the `owner` role inside the `RegistryCoordinator`.

*Effects*
* Stores the corresponding G2 public key of an operator's BLS keypair, based on their G1 public key, updating `operatorToPubkeyG2[operator]`.

*Requirements*
* Caller MUST be the `RegistryCoordinatorOwner`
* Operator must not have a G2 public key set
* The G2 pubic key must form a valid BN254 pairing with the stored G1 key, in effect verifying that the keypair is derived from the same secret key
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

`initializeQuorum` initializes a new quorum by pushing an initial `ApkUpdate` to `apkHistory[quorumNumber]`. Other methods can validate that a quorum exists by checking whether `apkHistory[quorumNumber]` has a nonzero length.

*Entry Points*:
* `RegistryCoordinator.createQuorum`

*Effects*:
* Pushes an `ApkUpdate` to `apkHistory[quorumNumber]`. The update has a zeroed out `apkHash`, and its `updateBlockNumber` is set to the current block.

*Requirements*:
* Caller MUST be the `RegistryCoordinator`
* `apkHistory[quorumNumber].length` MUST be zero

---
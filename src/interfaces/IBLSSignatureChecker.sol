// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ISlashingRegistryCoordinator} from "./ISlashingRegistryCoordinator.sol";
import {IBLSApkRegistry} from "./IBLSApkRegistry.sol";
import {IStakeRegistry, IDelegationManager} from "./IStakeRegistry.sol";

import {BN254} from "../libraries/BN254.sol";

interface IBLSSignatureCheckerErrors {
    /// @notice Thrown when the caller is not the registry coordinator owner.
    error OnlyRegistryCoordinatorOwner();
    /// @notice Thrown when the quorum numbers input in is empty.
    error InputEmptyQuorumNumbers();
    /// @notice Thrown when two array parameters have mismatching lengths.
    error InputArrayLengthMismatch();
    /// @notice Thrown when the non-signer pubkey length does not match non-signer bitmap indices length.
    error InputNonSignerLengthMismatch();
    /// @notice Thrown when the reference block number is invalid.
    error InvalidReferenceBlocknumber();
    /// @notice Thrown when the non signer pubkeys are not sorted.
    error NonSignerPubkeysNotSorted();
    /// @notice Thrown when StakeRegistry updates have not been updated within withdrawalDelayBlocks window
    error StaleStakesForbidden();
    /// @notice Thrown when the quorum apk hash in storage does not match provided quorum apk.
    error InvalidQuorumApkHash();
    /// @notice Thrown when BLS pairing precompile call fails.
    error InvalidBLSPairingKey();
    /// @notice Thrown when BLS signature is invalid.
    error InvalidBLSSignature();
}

interface IBLSSignatureCheckerTypes {
    /// @notice Contains bitmap and pubkey hash information for non-signing operators.
    /// @param quorumBitmaps Array of bitmaps indicating which quorums each non-signer was registered for.
    /// @param pubkeyHashes Array of BLS public key hashes for each non-signer.
    struct NonSignerInfo {
        uint256[] quorumBitmaps;
        bytes32[] pubkeyHashes;
    }

    /// @notice Contains non-signer information and aggregated signature data for BLS verification.
    /// @param nonSignerQuorumBitmapIndices The indices of all non-signer quorum bitmaps.
    /// @param nonSignerPubkeys The G1 public keys of all non-signers.
    /// @param quorumApks The aggregate G1 public key of each quorum.
    /// @param apkG2 The aggregate G2 public key of all signers.
    /// @param sigma The aggregate G1 signature of all signers.
    /// @param quorumApkIndices The indices of each quorum's aggregate public key in the APK registry.
    /// @param totalStakeIndices The indices of each quorum's total stake in the stake registry.
    /// @param nonSignerStakeIndices The indices of each non-signer's stake within each quorum.
    /// @dev Used as input to checkSignatures() to verify BLS signatures.
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

    /// @notice Records the total stake amounts for operators in each quorum.
    /// @param signedStakeForQuorum Array of total stake amounts from operators who signed, per quorum.
    /// @param totalStakeForQuorum Array of total stake amounts from all operators, per quorum.
    /// @dev Used to track stake distribution and calculate quorum thresholds. Array indices correspond to quorum numbers.
    struct QuorumStakeTotals {
        uint96[] signedStakeForQuorum;
        uint96[] totalStakeForQuorum;
    }
}

interface IBLSSignatureCheckerEvents is IBLSSignatureCheckerTypes {
    /// @notice Emitted when `staleStakesForbiddenUpdate` is set.
    event StaleStakesForbiddenUpdate(bool value);
}

interface IBLSSignatureChecker is IBLSSignatureCheckerErrors, IBLSSignatureCheckerEvents {
    /* STATE */

    /*
     * @notice Returns the address of the registry coordinator contract.
     * @return The address of the registry coordinator.
     * @dev This value is immutable and set during contract construction.
     */
    function registryCoordinator() external view returns (ISlashingRegistryCoordinator);

    /*
     * @notice Returns the address of the stake registry contract.
     * @return The address of the stake registry.
     * @dev This value is immutable and set during contract construction.
     */
    function stakeRegistry() external view returns (IStakeRegistry);

    /*
     * @notice Returns the address of the BLS APK registry contract.
     * @return The address of the BLS APK registry.
     * @dev This value is immutable and set during contract construction.
     */
    function blsApkRegistry() external view returns (IBLSApkRegistry);

    /*
     * @notice Returns the address of the delegation manager contract.
     * @return The address of the delegation manager.
     * @dev This value is immutable and set during contract construction.
     */
    function delegation() external view returns (IDelegationManager);

    /*
     * @notice Returns whether stale stakes are forbidden in signature verification.
     * @return True if stale stakes are forbidden, false otherwise.
     */
    function staleStakesForbidden() external view returns (bool);

    /* ACTIONS */

    /*
     * @notice Sets `value` as the new staleStakesForbidden flag.
     * @param value True to forbid stale stakes, false to allow them.
     * @dev Access restricted to the registry coordinator owner.
     */
    function setStaleStakesForbidden(
        bool value
    ) external;

    /* VIEW */

    /*
     * @notice This function is called by disperser when it has aggregated all the signatures of the operators
     * that are part of the quorum for a particular taskNumber and is asserting them into onchain. The function
     * checks that the claim for aggregated signatures are valid.
     *
     * The thesis of this procedure entails:
     * 1. Getting the aggregated pubkey of all registered nodes at the time of pre-commit by the
     * disperser (represented by apk in the parameters)
     * 2. Subtracting the pubkeys of all non-signers (nonSignerPubkeys) and storing
     * the output in apk to get aggregated pubkey of all operators that are part of quorum
     * 3. Using this aggregated pubkey to verify the aggregated signature under BLS scheme
     *
     * @param msgHash The hash of the message that was signed. NOTE: Be careful to ensure msgHash is
     * collision-resistant! This method does not hash msgHash in any way, so if an attacker is able
     * to pass in an arbitrary value, they may be able to tamper with signature verification.
     * @param quorumNumbers The quorum numbers to verify signatures for, where each byte is an 8-bit integer.
     * @param referenceBlockNumber The block number at which the stake information is being verified
     * @param nonSignerStakesAndSignature Contains non-signer information and aggregated signature data.
     * @return quorumStakeTotals The struct containing the total and signed stake for each quorum
     * @return signatoryRecordHash The hash of the signatory record, which is used for fraud proofs
     * @dev Before signature verification, the function verifies operator stake information. This includes
     * ensuring that the provided referenceBlockNumber is valid and recent enough, and that the stake is
     * either the most recent update for the total stake (of the operator) or latest before the referenceBlockNumber.
     */
    function checkSignatures(
        bytes32 msgHash,
        bytes calldata quorumNumbers,
        uint32 referenceBlockNumber,
        NonSignerStakesAndSignature memory nonSignerStakesAndSignature
    ) external view returns (QuorumStakeTotals memory, bytes32);

    /*
     * @notice Attempts to verify signature `sigma` against message hash `msgHash` using aggregate public keys `apk` and `apkG2`.
     * @param msgHash The hash of the message that was signed.
     * @param apk The aggregate public key in G1.
     * @param apkG2 The aggregate public key in G2.
     * @param sigma The signature to verify.
     * @return pairingSuccessful True if the pairing check succeeded.
     * @return siganatureIsValid True if the signature is valid.
     */
    function trySignatureAndApkVerification(
        bytes32 msgHash,
        BN254.G1Point memory apk,
        BN254.G2Point memory apkG2,
        BN254.G1Point memory sigma
    ) external view returns (bool pairingSuccessful, bool siganatureIsValid);
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IBLSApkRegistry} from "../interfaces/IBLSApkRegistry.sol";
import {IBLSSignatureCheckerTypes} from "../interfaces/IBLSSignatureChecker.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {IIndexRegistry} from "../interfaces/IIndexRegistry.sol";
import {ISlashingRegistryCoordinator} from "../interfaces/ISlashingRegistryCoordinator.sol";
import {BitmapUtils} from "../libraries/BitmapUtils.sol";
import {BN254} from "../libraries/BN254.sol";
import {BN256G2} from "./BN256G2.sol";
import {OperatorStateRetriever} from "../OperatorStateRetriever.sol";
import {ECUtils} from "./ECUtils.sol";

/**
 * @title BLSSigCheckOperatorStateRetriever with view functions that allow to retrieve the state of an AVSs registry system.
 * @dev This contract inherits from OperatorStateRetriever and adds the getNonSignerStakesAndSignature function.
 * @author Bread coop
 */
contract BLSSigCheckOperatorStateRetriever is OperatorStateRetriever {
    using ECUtils for BN254.G1Point;
    using BN254 for BN254.G1Point;
    using BitmapUtils for uint256;

    /// @dev Thrown when the signature is not on the curve.
    error InvalidSigma();
    // avoid stack too deep

    struct GetNonSignerStakesAndSignatureMemory {
        BN254.G1Point[] quorumApks;
        BN254.G2Point apkG2;
        IIndexRegistry indexRegistry;
        IBLSApkRegistry blsApkRegistry;
        bytes32[] signingOperatorIds;
    }

    /**
     * @notice Returns the stakes and signature information for non-signing operators in specified quorums
     * @param registryCoordinator The registry coordinator contract to fetch operator information from
     * @param quorumNumbers Array of quorum numbers to check for non-signers
     * @param sigma The aggregate BLS signature to verify
     * @param operators Array of operator addresses that signed the message
     * @param blockNumber Is the block number to get the indices for
     * @return NonSignerStakesAndSignature Struct containing:
     *         - nonSignerQuorumBitmapIndices: Indices for retrieving quorum bitmaps of non-signers
     *         - nonSignerPubkeys: BLS public keys of operators that did not sign
     *         - quorumApks: Aggregate public keys for each quorum
     *         - apkG2: Aggregate public key of all signing operators in G2
     *         - sigma: The provided signature
     *         - quorumApkIndices: Indices for retrieving quorum APKs
     *         - totalStakeIndices: Indices for retrieving total stake info
     *         - nonSignerStakeIndices: Indices for retrieving non-signer stake info
     * @dev Computes the indices of operators that did not sign across all specified quorums
     * @dev This function does not validate the signature matches the provided parameters, only that it's in a valid format
     */
    function getNonSignerStakesAndSignature(
        ISlashingRegistryCoordinator registryCoordinator,
        bytes calldata quorumNumbers,
        BN254.G1Point calldata sigma,
        address[] calldata operators,
        uint32 blockNumber
    ) external view returns (IBLSSignatureCheckerTypes.NonSignerStakesAndSignature memory) {
        GetNonSignerStakesAndSignatureMemory memory m;
        m.quorumApks = new BN254.G1Point[](quorumNumbers.length);
        m.indexRegistry = registryCoordinator.indexRegistry();
        m.blsApkRegistry = registryCoordinator.blsApkRegistry();

        // Safe guard AVSs from generating NonSignerStakesAndSignature with invalid sigma
        require(sigma.isOnCurve(), InvalidSigma());

        // Compute the g2 APK of the signing operator set
        m.signingOperatorIds = new bytes32[](operators.length);
        for (uint256 i = 0; i < operators.length; i++) {
            m.signingOperatorIds[i] = registryCoordinator.getOperatorId(operators[i]);
            BN254.G2Point memory operatorG2Pk = m.blsApkRegistry.getOperatorPubkeyG2(operators[i]);
            (m.apkG2.X[1], m.apkG2.X[0], m.apkG2.Y[1], m.apkG2.Y[0]) = BN256G2.ECTwistAdd(
                m.apkG2.X[1],
                m.apkG2.X[0],
                m.apkG2.Y[1],
                m.apkG2.Y[0],
                operatorG2Pk.X[1],
                operatorG2Pk.X[0],
                operatorG2Pk.Y[1],
                operatorG2Pk.Y[0]
            );
        }

        // Extra scope for stack limit
        {
            uint32[] memory signingOperatorQuorumBitmapIndices = registryCoordinator
                .getQuorumBitmapIndicesAtBlockNumber(blockNumber, m.signingOperatorIds);
            uint256 bitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers);
            // Check that all operators are registered (this is like the check in getCheckSignaturesIndices, but we check against _signing_ operators)
            for (uint256 i = 0; i < operators.length; i++) {
                uint192 signingOperatorQuorumBitmap = registryCoordinator
                    .getQuorumBitmapAtBlockNumberByIndex(
                    m.signingOperatorIds[i], blockNumber, signingOperatorQuorumBitmapIndices[i]
                );
                require(
                    !uint256(signingOperatorQuorumBitmap).noBitsInCommon(bitmap),
                    OperatorNotRegistered()
                );
            }
        }

        // We use this as a dynamic array
        uint256 nonSignerOperatorsCount = 0;
        bytes32[] memory nonSignerOperatorIds = new bytes32[](16);
        // For every quorum
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            bytes32[] memory operatorIdsInQuorum =
                m.indexRegistry.getOperatorListAtBlockNumber(uint8(quorumNumbers[i]), blockNumber);
            // Operator IDs are computed from the hash of the BLS public keys, so an operatorId's public key can't change over time
            // This lets us compute the APK at the given block number
            m.quorumApks[i] = _computeG1Apk(registryCoordinator, operatorIdsInQuorum);
            // We check for every operator in the quorum
            for (uint256 j = 0; j < operatorIdsInQuorum.length; j++) {
                bool isNewNonSigner = true;
                // If it is in the signing operators array
                for (uint256 k = 0; k < m.signingOperatorIds.length; k++) {
                    if (operatorIdsInQuorum[j] == m.signingOperatorIds[k]) {
                        isNewNonSigner = false;
                        break;
                    }
                }
                // Or already in the non-signing operators array
                for (uint256 l = 0; l < nonSignerOperatorsCount; l++) {
                    if (nonSignerOperatorIds[l] == operatorIdsInQuorum[j]) {
                        isNewNonSigner = false;
                        break;
                    }
                }
                // And if not, we add it to the non-signing operators array
                if (isNewNonSigner) {
                    // If we are at the end of the array, we need to resize it
                    if (nonSignerOperatorsCount == nonSignerOperatorIds.length) {
                        uint256 newCapacity = nonSignerOperatorIds.length * 2;
                        bytes32[] memory newNonSignerOperatorIds = new bytes32[](newCapacity);
                        for (uint256 l = 0; l < nonSignerOperatorIds.length; l++) {
                            newNonSignerOperatorIds[l] = nonSignerOperatorIds[l];
                        }
                        nonSignerOperatorIds = newNonSignerOperatorIds;
                    }

                    nonSignerOperatorIds[nonSignerOperatorsCount] = operatorIdsInQuorum[j];
                    nonSignerOperatorsCount++;
                }
            }
        }

        // Trim the nonSignerOperatorIds array to the actual count
        bytes32[] memory trimmedNonSignerOperatorIds = new bytes32[](nonSignerOperatorsCount);
        BN254.G1Point[] memory nonSignerPubkeys = new BN254.G1Point[](nonSignerOperatorsCount);
        for (uint256 i = 0; i < nonSignerOperatorsCount; i++) {
            trimmedNonSignerOperatorIds[i] = nonSignerOperatorIds[i];
            address nonSignerOperator =
                registryCoordinator.getOperatorFromId(trimmedNonSignerOperatorIds[i]);
            (nonSignerPubkeys[i],) = m.blsApkRegistry.getRegisteredPubkey(nonSignerOperator);
        }

        CheckSignaturesIndices memory checkSignaturesIndices = getCheckSignaturesIndices(
            registryCoordinator, blockNumber, quorumNumbers, trimmedNonSignerOperatorIds
        );
        return IBLSSignatureCheckerTypes.NonSignerStakesAndSignature({
            nonSignerQuorumBitmapIndices: checkSignaturesIndices.nonSignerQuorumBitmapIndices,
            nonSignerPubkeys: nonSignerPubkeys,
            quorumApks: m.quorumApks,
            apkG2: m.apkG2,
            sigma: sigma,
            quorumApkIndices: checkSignaturesIndices.quorumApkIndices,
            totalStakeIndices: checkSignaturesIndices.totalStakeIndices,
            nonSignerStakeIndices: checkSignaturesIndices.nonSignerStakeIndices
        });
    }

    /**
     * @notice Computes the aggregate public key (APK) in G1 for a list of operators
     * @dev Aggregates the individual G1 public keys of operators by adding them together
     * @param registryCoordinator The registry coordinator contract to fetch operator info from
     * @param operatorIds Array of operator IDs to compute the aggregate key for
     * @return The aggregate public key as a G1 point, computed by summing individual operator pubkeys
     */
    function _computeG1Apk(
        ISlashingRegistryCoordinator registryCoordinator,
        bytes32[] memory operatorIds
    ) internal view returns (BN254.G1Point memory) {
        BN254.G1Point memory apk = BN254.G1Point(0, 0);
        IBLSApkRegistry blsApkRegistry = registryCoordinator.blsApkRegistry();
        for (uint256 i = 0; i < operatorIds.length; i++) {
            address operator = registryCoordinator.getOperatorFromId(operatorIds[i]);
            BN254.G1Point memory operatorPk;
            (operatorPk.X, operatorPk.Y) = blsApkRegistry.operatorToPubkey(operator);
            apk = apk.plus(operatorPk);
        }
        return apk;
    }
}

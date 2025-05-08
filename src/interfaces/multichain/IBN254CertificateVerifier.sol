// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {BN254} from "../../libraries/BN254.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IBN254TableCalculatorTypes} from "./IBN254TableCalculator.sol";
import {ICertificateVerifier} from "./ICertificateVerifier.sol";

interface IBN254CertificateVerifierTypes is IBN254TableCalculatorTypes {
    /**
     * @notice A witness for an operator
     * @param operatorIndex the index of the nonsigner in the `BN254OperatorInfo` tree
     * @param operatorInfoProofs merkle proofs of the nonsigner at the index. Empty if operator is in cache.
     * @param operatorInfo the `BN254OperatorInfo` for the operator
     */
    struct BN254OperatorInfoWitness {
        uint32 operatorIndex;
        bytes operatorInfoProof;
        BN254OperatorInfo operatorInfo;
    }

    /**
     * @notice A BN254 Certificate
     * @param referenceTimestamp the timestamp at which the certificate was created
     * @param messageHash the hash of the message that was signed by operators and used to verify the aggregated signature
     * @param signature the G1 signature of the message
     * @param apk the G2 aggregate public key
     * @param nonSignerWitnesses an array of witnesses of non-signing operators
     */
    struct BN254Certificate {
        uint32 referenceTimestamp;
        bytes32 messageHash;
        BN254.G1Point signature;
        BN254.G2Point apk;
        BN254OperatorInfoWitness[] nonSignerWitnesses;
    }
}

interface IBN254CertificateVerifierEvents is IBN254CertificateVerifierTypes {
    /// @notice Emitted when a table is updated
    event TableUpdated(uint32 referenceTimestamp, BN254OperatorSetInfo operatorSetInfo);
}

/// @notice A base table manager interface that handles operator table updates
/// @dev We separate out this interface for forwards-compatibility with a future `TableManager` contract that stores all operatorSet's tables on a chain
interface IBN254TableManager is IBN254CertificateVerifierTypes {
    /**
     * @notice updates the operator table
     * @param operatorSet the operatorSet to update the operator table for
     * @param referenceTimestamp the timestamp at which the operatorSetInfo and
     * operatorInfoTreeRoot were sourced
     * @param operatorSetInfo the aggregate information about the operatorSet
     * @dev only callable by the operatorTableUpdater
     * @dev We pass in an `operatorSet` for future-proofing a global `TableManager` contract
     */
    function updateOperatorTable(
        OperatorSet calldata operatorSet,
        uint32 referenceTimestamp,
        BN254OperatorSetInfo memory operatorSetInfo
    ) external;

    /**
     * @notice ejects operators from the operatorSet
     * @param referenceTimestamp the timestamp of the operator tbale against which
     * the ejection is being done
     * @param operatorIndices the indices of the operators to eject
     * @param witnesses for the operators that are not already in storage
     * @dev only callable by the ejector
     * @dev We pass in an `operatorSet` for future-proofing a global `TableManager` contract
     */
    function ejectOperators(
        OperatorSet calldata operatorSet,
        uint32 referenceTimestamp,
        uint32[] calldata operatorIndices,
        BN254OperatorInfoWitness[] calldata witnesses
    ) external;
}

interface IBN254CertificateVerifier is
    ICertificateVerifier,
    IBN254TableManager,
    IBN254CertificateVerifierEvents
{
    /**
     * @notice verifies a certificate
     * @param cert a certificate
     * @return signedStakes amount of stake that signed the certificate for each stake
     * type
     */
    function verifyCertificate(
        BN254Certificate memory cert
    ) external returns (uint96[] memory signedStakes);

    /**
     * @notice verifies a certificate and makes sure that the signed stakes meet
     * provided portions of the total stake on the AVS
     * @param cert a certificate
     * @param totalStakeProportionThresholds the proportion of total stake that
     * the signed stake of the certificate should meet
     * @return whether or not certificate is valid and meets thresholds
     */
    function verifyCertificateProportion(
        BN254Certificate memory cert,
        uint16[] memory totalStakeProportionThresholds
    ) external returns (bool);

    /**
     * @notice verifies a certificate and makes sure that the signed stakes meet
     * provided nominal stake thresholds
     * @param cert a certificate
     * @param totalStakeNominalThresholds the nominal amount of stake that
     * the signed stake of the certificate should meet
     * @return whether or not certificate is valid and meets thresholds
     */
    function verifyCertificateNominal(
        BN254Certificate memory cert,
        uint96[] memory totalStakeNominalThresholds
    ) external returns (bool);
}

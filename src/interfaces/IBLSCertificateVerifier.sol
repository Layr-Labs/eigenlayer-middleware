// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {BN254} from "../libraries/BN254.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IBLSTableCalculatorTypes} from "./IBLSTableCalculator.sol";

interface IBLSCertificateVerifierErrors {
    /// @notice Thrown when the table updater is not caller
    error OnlyTableUpdater();
    /// @notice Thrown when the table is too stale
    error TableStale();
    /// @notice Thrown when certificate verification fails
    error CertVerificationFailed();
}

interface IBLSCertificateVerifierTypes is IBLSTableCalculatorTypes {
    /// @notice A witness for an operator
    /// @param operatorIndex the index of the nonsigner in the `BN254OperatorInfo` tree
    /// @param operatorInfoProofs merkle proofs of the nonsigner at the index. VEmpty if operator is in cache.
    /// @param operatorInfo the `BN254OperatorInfo` for the operator
    struct BN254OperatorInfoWitness {
        uint32 operatorIndex;
        bytes operatorInfoProofs;
        IBLSTableCalculatorTypes.BN254OperatorInfo operatorInfo;
    }

    /// @notice A BN254 Certificate
    /// @param referenceTimestamp the timestamp at which the certificate was created
    /// @param messageHash the hash of the message that was signed by operators and used to verify the aggregated signature
    /// @param signature the G1 signature of the message
    /// @param apk the G2 aggregate public key
    /// @param nonSignerIndices the indices of the non-signing operators
    /// @param nonSignerWitnesses an array of witnesses of operators
    struct BN254Certificate {
        uint32 referenceTimestamp;
        bytes32 messageHash;
        BN254.G1Point signature;
        BN254.G2Point apk;
        uint32[] nonSignerIndices;
        BN254OperatorInfoWitness[] nonSignerWitnesses;
    }
}

interface IBLSCertificateVerifierEvents is IBLSCertificateVerifierTypes {
    /// @notice Emitted when a table is updated
    event TableUpdated(uint32 referenceTimestamp);
}

interface IBLSCertificateVerifier is IBLSCertificateVerifierTypes, IBLSCertificateVerifierEvents {
    /// @notice the operatorSet the CertificateVerifier is for
    function operatorSet() external returns (OperatorSet memory);

    /// @notice the address of the entity that can update the operator table
    function operatorTableUpdater() external returns (address);

    /// @return the maximum amount of seconds that a operator table can be in the past
    function maxOperatorTableStaleness() external returns (uint32);

    /**
     * @notice updates the operator table
     * @param referenceTimestamp the timestamp at which the operatorSetInfo and
     * operatorInfoTreeRoot were sourced
     * @param operatorSetInfo the aggregate information about the operatorSet
     * @dev only callable by the operatorTableUpdater
     */
    function updateOperatorTable(
        uint32 referenceTimestamp,
        BN254OperatorSetInfo memory operatorSetInfo
    ) external;

    /**
     * @notice ejects operators from the operatorSet
     * @param referenceTimestamp the timestamp of the operator tbale against which
     * the ejection is being done
     * @param operatorIndices the indices of the operators to eject
     * @param witnesses for the operators that are not already in storage
     * @dev only callable by the operatorTableUpdater
     */
    function ejectOperators(
        uint32 referenceTimestamp,
        uint32[] calldata operatorIndices,
        BN254OperatorInfoWitness[] calldata witnesses
    ) external;

    /**
     * @notice verifies a certificate
     * @param cert a certificate
     * @return signedStakes amount of stake that signed the certificate for each stake
     * type
     */
    function verifyCertificate(
        BN254Certificate memory cert
    ) external view returns (uint96[] memory signedStakes);

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
    ) external view returns (bool);

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
    ) external view returns (bool);
}

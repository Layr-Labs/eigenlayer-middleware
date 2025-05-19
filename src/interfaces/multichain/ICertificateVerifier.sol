// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

import {BN254} from "../../libraries/BN254.sol";
import {IECDSATableCalculatorTypes} from "./IECDSATableCalculator.sol";
import {IBN254TableCalculatorTypes} from "./IBN254TableCalculator.sol";

interface ICertificateVerifierTypes is IBN254TableCalculatorTypes, IECDSATableCalculatorTypes {
    /**
     * @notice The type of key used by the operatorSet. An OperatorSet can
     * only generate one Operator Table for an OperatorSet for a given OperatorKeyType.
     */
    enum OperatorKeyType {
        ECDSA,
        BN254
    }

    /**
     * @notice A per-operatorSet configuration struct that is transported from the CrossChainRegistry on L1.
     * @param owner the permissioned owner of the OperatorSet on L2 that can call the CertificateVerifier specific setters
     * @param ejector the address of the ejector of the operatorSet
     * @param operatorTableUpdater the address of the operator table updater of the operatorSet
     * @param maxStalenessPeriod the maximum staleness period of the operatorSet
     * @param operatorKeyType the type of key used by the operatorSet
     */
    struct OpSetConfig {
        address owner;
        address ejector;
        address operatorTableUpdater;
        uint32 maxStalenessPeriod;
        OperatorKeyType operatorKeyType;
    }

    /**
     * @notice A ECDSA Certificate
     * @param referenceTimestamp the timestamp at which the certificate was created
     * @param messageHash the hash of the message that was signed by operators
     * @param signature the concatenated signature of each signing operator
     */
    struct ECDSACertificate {
        uint32 referenceTimestamp;
        bytes32 messageHash;
        bytes sig;
    }

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

interface ICertificateVerifierEvents is ICertificateVerifierTypes {
    /// @notice Emitted when an ECDSA table is updated
    event ECDSATableUpdated(uint32 referenceTimestamp, ECDSAOperatorInfo[] operatorInfos);

    /// @notice Emitted when a BN254 table is updated
    event BN254TableUpdated(uint32 referenceTimestamp, BN254OperatorSetInfo operatorSetInfo);
}

interface ICertificateVerifierErrors {
    /// @notice Thrown when the table updater is not caller
    error OnlyTableUpdater();

    /// @notice Thrown when the global root confirmer is not caller
    error OnlyGlobalRootConfirmer();

    /// @notice Thrown when the table is too stale
    error TableStale();
    /// @notice Thrown when certificate verification fails
    error CertVerificationFailed();
}

/// @notice A base interface that verifies certificates for a given operatorSet
/// @notice This is a base interface that all curve certificate verifiers (eg. BN254, ECDSA) must implement
/// @dev A single `CertificateVerifier` can be used for ONLY 1 operatorSet
interface ICertificateVerifier is ICertificateVerifierEvents, ICertificateVerifierErrors {
    /* GLOBAL TABLE ROOT INTERFACE */

    /**
     * @notice Confirms Global operator table root
     * @param globalOperatorTableRootCert certificate of the root
     * @param referenceTimestamp timestamp of the root
     * @param globalOperatorTableRoot merkle root of the table
     * @dev Overrides the previous globalOperatorTableRoot
     * @dev Any entity can submit, since this has been emitted as an event
     *      or is in storage on the L1 `CrossChainRegistry` and validates against
     *      EigenDA
     */
    function confirmGlobalTableRoot(
        BN254Certificate calldata globalOperatorTableRootCert,
        uint32 referenceTimestamp,
        bytes32 globalOperatorTableRoot
    ) external;

    /**
     * @notice Set the operatorSet which certifies against global roots
     */
    function setGlobalRootConfirmerOperatorSet(
        OperatorSet calldata operatorSet
    ) external;

    /* ECDSA CERTIFICATE VERIFIER INTERFACE */

    /**
     * @notice updates the operator table
     * @param operatorSet the operatorSet to update the operator table for
     * @param referenceTimestamp the timestamp at which the operatorInfos were sourced
     * @param operatorInfos the operatorInfos to update the operator table with
     * @param opSetConfig the configuration of the operatorSet
     * @dev only callable by the operatorTableUpdater for the given operatorSet
     * @dev We pass in an `operatorSet` for future-proofing a global `TableManager` contract
     */
    function updateECDSAOperatorTable(
        OperatorSet calldata operatorSet,
        uint32 referenceTimestamp,
        ECDSAOperatorInfo[] calldata operatorInfos,
        OpSetConfig calldata opSetConfig
    ) external;

    /**
     * @notice verifies a certificate
     * @param cert a certificate
     * @return signedStakes amount of stake that signed the certificate for each stake
     * type
     */
    function verifyECDSACertificate(
        ECDSACertificate memory cert
    ) external returns (uint96[] memory signedStakes);

    /**
     * @notice verifies a certificate and makes sure that the signed stakes meet
     * provided portions of the total stake on the AVS
     * @param cert a certificate
     * @param totalStakeProportionThresholds the proportion of total stake that
     * the signed stake of the certificate should meet
     * @return whether or not certificate is valid and meets thresholds
     */
    function verifyECDSACertificateProportion(
        ECDSACertificate memory cert,
        uint16[] memory totalStakeProportionThresholds
    ) external returns (bool);

    /**
     * @notice verifies a certificate and makes sure that the signed stakes meet
     * provided portions of the total stake on the AVS
     * @param cert a certificate
     * @param totalStakeNominalThresholds the proportion of total stake that
     * the signed stake of the certificate should meet
     * @return whether or not certificate is valid and meets thresholds
     */
    function verifyECDSACertificateNominal(
        ECDSACertificate memory cert,
        uint96[] memory totalStakeNominalThresholds
    ) external returns (bool);

    /**
     * @notice Ejects operators from the operatorSet. Operator ejection technically occurs on the L1 but to avoid having
     * to wait until the OperatorTable is updated on L2, we allow for more immediate ejection of operators for a more
     * concurrent operator registration view. This function is specific for operatorSets with OperatorKeyType.ECDSA
     * @param operatorSet the operatorSet to eject operators from
     * @param referenceTimestamp the timestamp of the operator table against which
     * the ejection is being done
     * @param operatorIndices the indices of the operators to eject
     * @dev only callable by the ejector
     * @dev We pass in an `operatorSet` for future-proofing a global `TableManager` contract
     */
    function ejectECDSAOperators(
        OperatorSet calldata operatorSet,
        uint32 referenceTimestamp,
        uint32[] calldata operatorIndices
    ) external;

    /* BN254 CERTIFICATE VERIFIER INTERFACE */

    /**
     * @notice updates the operator table
     * @param operatorSet the operatorSet to update the operator table for
     * @param referenceTimestamp the timestamp at which the operatorSetInfo and
     * operatorInfoTreeRoot were sourced
     * @param operatorSetInfo the aggregate information about the operatorSet
     * @param opSetConfig the configuration of the operatorSet
     * @dev only callable by the operatorTableUpdater for the given operatorSet
     * @dev We pass in an `operatorSet` for future-proofing a global `TableManager` contract
     */
    function updateBN254OperatorTable(
        OperatorSet calldata operatorSet,
        uint32 referenceTimestamp,
        BN254OperatorSetInfo memory operatorSetInfo,
        OpSetConfig calldata opSetConfig
    ) external;

    /**
     * @notice verifies a certificate
     * @param cert a certificate
     * @return signedStakes amount of stake that signed the certificate for each stake
     * type
     */
    function verifyBN254Certificate(
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
    function verifyBN254CertificateProportion(
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
    function verifyBN254CertificateNominal(
        BN254Certificate memory cert,
        uint96[] memory totalStakeNominalThresholds
    ) external returns (bool);

    /**
     * @notice Ejects operators from the operatorSet. Operator ejection technically occurs on the L1 but to avoid having
     * to wait until the OperatorTable is updated on L2, we allow for more immediate ejection of operators for a more
     * concurrent operator registration view. This function is specific for operatorSets with OperatorKeyType.BN254
     * @param operatorSet the operatorSet to eject operators from
     * @param referenceTimestamp the timestamp of the operator tbale against which
     * the ejection is being done
     * @param operatorIndices the indices of the operators to eject
     * @param witnesses for the operators that are not already in storage
     * @dev only callable by the ejector
     * @dev We pass in an `operatorSet` for future-proofing a global `TableManager` contract
     */
    function ejectBN254Operators(
        OperatorSet calldata operatorSet,
        uint32 referenceTimestamp,
        uint32[] calldata operatorIndices,
        BN254OperatorInfoWitness[] calldata witnesses
    ) external;

    /* OPERATOR SET CONFIG INTERFACE */

    /// @notice the address of the owner of the OperatorSet
    function getOperatorSetOwner(
        OperatorSet memory operatorSet
    ) external returns (address);

    /// @notice the address of the entity that can update the OperatorSet's operator table
    function operatorTableUpdater(
        OperatorSet memory operatorSet
    ) external returns (address);

    /// @return the maximum amount of seconds that a operator table can be in the past for a given operatorSet
    function maxOperatorTableStaleness(
        OperatorSet memory operatorSet
    ) external returns (uint32);

    /// @notice The latest reference timestamp of the operator table for a given operatorSet
    function latestReferenceTimestamp(
        OperatorSet memory operatorSet
    ) external returns (uint32);
}

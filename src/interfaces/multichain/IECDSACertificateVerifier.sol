// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {ICertificateVerifier} from "./ICertificateVerifier.sol";
import {IECDSATableCalculatorTypes} from "./IECDSATableCalculator.sol";

interface IECDSCertificateVerifierTypes is IECDSATableCalculatorTypes {
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
}

interface IECDSACertificateVerifierEvents is IECDSCertificateVerifierTypes {
    /// @notice Emitted when a table is updated
    event TableUpdated(uint32 referenceTimestamp, ECDSAOperatorInfo[] operatorInfos);
}

/// @notice A base table manager interface that handles operator table updates
/// @dev We separate out this interface for forwards-compatibility with a future `TableManager` contract that stores all operatorSet's tables on a chain
interface IECDSATableManager is IECDSCertificateVerifierTypes {
    /**
     * @notice updates the operator table
     * @param operatorSet the operatorSet to update the operator table for
     * @param referenceTimestamp the timestamp at which the operatorInfos were sourced
     * @param operatorInfos the operatorInfos to update the operator table with
     * @dev only callable by the operatorTableUpdater
     * @dev We pass in an `operatorSet` for future-proofing a global `TableManager` contract
     */
    function updateOperatorTable(
        OperatorSet calldata operatorSet,
        uint32 referenceTimestamp,
        ECDSAOperatorInfo[] calldata operatorInfos
    ) external;

    /**
     * @notice ejects operators from the operatorSet
     * @param operatorSet the operatorSet to eject operators from
     * @param referenceTimestamp the timestamp of the operator table against which
     * the ejection is being done
     * @param operatorIndices the indices of the operators to eject
     * @dev only callable by the ejector
     * @dev We pass in an `operatorSet` for future-proofing a global `TableManager` contract
     */
    function ejectOperators(
        OperatorSet calldata operatorSet,
        uint32 referenceTimestamp,
        uint32[] calldata operatorIndices
    ) external;
}

interface IECDSACertificateVerifier is
    ICertificateVerifier,
    IECDSATableManager,
    IECDSACertificateVerifierEvents
{
    /**
     * @notice verifies a certificate
     * @param cert a certificate
     * @return signedStakes amount of stake that signed the certificate for each stake
     * type
     */
    function verifyCertificate(
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
    function verifyCertificateProportion(
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
    function verifyCertificateNominal(
        ECDSACertificate memory cert,
        uint96[] memory totalStakeNominalThresholds
    ) external returns (bool);
}

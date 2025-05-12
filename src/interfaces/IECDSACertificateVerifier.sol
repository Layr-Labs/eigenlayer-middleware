// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IECDSATableCalculatorTypes} from "./IECDSATableCalculator.sol";

/**
 * @title IECDSACertificateVerifierTypes
 * @notice Defines the types used by the ECDSA certificate verifier
 */
interface IECDSACertificateVerifierTypes {
    /**
     * @notice Structure for an ECDSA certificate
     * @param referenceTimestamp The timestamp identifying the operator table to verify against
     * @param messageHash The hash of the message which has been signed by operators
     * @param sig The concatenated ECDSA signatures of the signing operators (each 65 bytes)
     */
    struct ECDSACertificate {
        uint32 referenceTimestamp;
        bytes32 messageHash;
        // The concatenated signature of each signing operator
        bytes sig;
    }
}

/**
 * @title IECDSACertificateVerifier
 * @notice Interface for the ECDSA certificate verifier
 */
interface IECDSACertificateVerifier is IECDSACertificateVerifierTypes {
    // Events
    event TableUpdated(uint32 indexed referenceTimestamp, uint256 operatorCount);
    event OperatorEjected(uint32 indexed referenceTimestamp, uint32 indexed operatorIndex);

    // Errors
    error OnlyTableUpdater();
    error TableStale();
    error CertVerificationFailed();

    /**
     * @notice Returns the operator set this verifier is for
     * @return The operator set
     */
    function operatorSet() external view returns(OperatorSet memory);
    
    /**
     * @notice Returns the address that can update the operator table
     * @return The operator table updater address
     */
    function operatorTableUpdater() external view returns(address);
    
    /**
     * @notice Returns the maximum staleness allowed for an operator table
     * @return The maximum staleness in seconds
     */
    function maxOperatorTableStaleness() external view returns(uint32);
    
    /**
     * @notice Updates the operator table
     * @param referenceTimestamp The timestamp at which the operatorInfos were sourced
     * @param operatorInfos The new operator infos
     */
    function updateOperatorTable(
        uint32 referenceTimestamp, 
        IECDSATableCalculatorTypes.ECDSAOperatorInfo[] memory operatorInfos
    ) external;
    
    /**
     * @notice Ejects operators from the operator set
     * @param referenceTimestamp The timestamp of the operator table against which the ejection is being done
     * @param operatorIndices The indices of the operators to eject
     */
    function ejectOperators(
        uint32 referenceTimestamp,
        uint32[] calldata operatorIndices
    ) external;
    
    /**
     * @notice Verifies a certificate
     * @param cert A certificate
     * @return signedStakes The amount of stake that signed the certificate for each stake type
     */
    function verifyCertificate(ECDSACertificate memory cert) 
        external view returns(uint96[] memory signedStakes);
        
    /**
     * @notice Verifies a certificate and makes sure that the signed stakes meet provided portions of the total stake
     * @param cert A certificate
     * @param totalStakeProportionThresholds The proportion of total stake that the signed stake should meet (in basis points)
     * @return Whether or not certificate is valid and meets thresholds
     */
    function verifyCertificateProportion(
        ECDSACertificate memory cert, 
        uint16[] memory totalStakeProportionThresholds
    ) external view returns(bool);
    
    /**
     * @notice Verifies a certificate and makes sure that the signed stakes meet provided nominal stake thresholds
     * @param cert A certificate
     * @param totalStakeNominalThresholds The nominal amount of stake that the signed stake should meet
     * @return Whether or not certificate is valid and meets thresholds
     */
    function verifyCertificateNominal(
        ECDSACertificate memory cert, 
        uint96[] memory totalStakeNominalThresholds
    ) external view returns(bool);
    
    /**
     * @notice Sets the operator table updater
     * @param _newOperatorTableUpdater The new operator table updater
     */
    function setOperatorTableUpdater(address _newOperatorTableUpdater) external;
    
    /**
     * @notice Sets the maximum operator table staleness
     * @param _newMaxOperatorTableStaleness The new maximum staleness in seconds
     */
    function setMaxOperatorTableStaleness(uint32 _newMaxOperatorTableStaleness) external;
}
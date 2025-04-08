// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ECDSACertificate} from "../certificate-verifiers/ECDSACertificateVerifier.sol";
import {BN254Certificate} from "../certificate-verifiers/BN254CertificateVerifier.sol";

/**
 * @title CertificateConsumer
 * @notice Example consumer contract that uses certificate verifiers
 * @dev This contract shows how to consume certificates from different verifiers
 */
contract CertificateConsumer {
    /// @notice ECDSA certificate verifier
    address public ecdsaVerifier;
    
    /// @notice BN254 certificate verifier
    address public bn254Verifier;
    
    /// @notice Proportion thresholds for stake verification (in basis points, e.g. 6600 = 66%)
    uint16[] public proportionThresholds;
    
    /// @notice Nominal stake thresholds for verification
    uint96[] public nominalThresholds;
    
    /// @notice Mapping from message hash to verification status
    mapping(bytes32 => bool) public certifiedMessages;
    
    /**
     * @notice Event emitted when a message is certified
     * @param messageHash The hash of the certified message
     * @param timestamp The timestamp of certification
     */
    event MessageCertified(bytes32 indexed messageHash, uint256 indexed timestamp);
    
    /**
     * @dev Constructor to initialize the consumer
     * @param _ecdsaVerifier The ECDSA certificate verifier address
     * @param _bn254Verifier The BN254 certificate verifier address
     * @param _proportionThresholds The proportion thresholds for stake verification
     * @param _nominalThresholds The nominal stake thresholds for verification
     */
    constructor(
        address _ecdsaVerifier,
        address _bn254Verifier,
        uint16[] memory _proportionThresholds,
        uint96[] memory _nominalThresholds
    ) {
        ecdsaVerifier = _ecdsaVerifier;
        bn254Verifier = _bn254Verifier;
        proportionThresholds = _proportionThresholds;
        nominalThresholds = _nominalThresholds;
    }
    
    /**
     * @notice Verify an ECDSA certificate and record that the message has been certified
     * @param cert The ECDSA certificate
     * @param useProportionVerification Whether to use proportion-based verification
     * @return success Whether the verification was successful
     */
    function verifyECDSACertificate(
        ECDSACertificate calldata cert,
        bool useProportionVerification
    ) external returns (bool success) {
        // Check if this message has already been certified
        require(!certifiedMessages[cert.messageHash], "Already certified");
        
        // Call the appropriate verification method
        if (useProportionVerification) {
            (bool callSuccess,) = ecdsaVerifier.call(
                abi.encodeWithSignature(
                    "verifyCertificateProportion((uint32,bytes32,bytes),uint16[])",
                    cert,
                    proportionThresholds
                )
            );
            require(callSuccess, "Verification failed");
            
            // Read the result from the call
            bool verified;
            assembly {
                verified := mload(0)
            }
            
            require(verified, "Certificate invalid");
        } else {
            (bool callSuccess,) = ecdsaVerifier.call(
                abi.encodeWithSignature(
                    "verifyCertificateNominal((uint32,bytes32,bytes),uint96[])",
                    cert,
                    nominalThresholds
                )
            );
            require(callSuccess, "Verification failed");
            
            // Read the result from the call
            bool verified;
            assembly {
                verified := mload(0)
            }
            
            require(verified, "Certificate invalid");
        }
        
        // Record that this message has been certified
        certifiedMessages[cert.messageHash] = true;
        
        // Emit event
        emit MessageCertified(cert.messageHash, block.timestamp);
        
        return true;
    }
    
    /**
     * @notice Verify a BN254 certificate and record that the message has been certified
     * @param cert The BN254 certificate
     * @param useProportionVerification Whether to use proportion-based verification
     * @return success Whether the verification was successful
     */
    function verifyBN254Certificate(
        BN254Certificate calldata cert,
        bool useProportionVerification
    ) external returns (bool success) {
        // Check if this message has already been certified
        require(!certifiedMessages[cert.messageHash], "Already certified");
        
        // Call the appropriate verification method
        if (useProportionVerification) {
            (bool callSuccess,) = bn254Verifier.call(
                abi.encodeWithSignature(
                    "verifyCertificateProportion((uint32,bytes32,(uint256,uint256),(uint256[2],uint256[2]),uint32[],(uint32,bytes,(uint256,uint256,uint96[]))[]),uint16[])",
                    cert,
                    proportionThresholds
                )
            );
            require(callSuccess, "Verification failed");
            
            // Read the result from the call
            bool verified;
            assembly {
                verified := mload(0)
            }
            
            require(verified, "Certificate invalid");
        } else {
            (bool callSuccess,) = bn254Verifier.call(
                abi.encodeWithSignature(
                    "verifyCertificateNominal((uint32,bytes32,(uint256,uint256),(uint256[2],uint256[2]),uint32[],(uint32,bytes,(uint256,uint256,uint96[]))[]),uint96[])",
                    cert,
                    nominalThresholds
                )
            );
            require(callSuccess, "Verification failed");
            
            // Read the result from the call
            bool verified;
            assembly {
                verified := mload(0)
            }
            
            require(verified, "Certificate invalid");
        }
        
        // Record that this message has been certified
        certifiedMessages[cert.messageHash] = true;
        
        // Emit event
        emit MessageCertified(cert.messageHash, block.timestamp);
        
        return true;
    }
    
    /**
     * @notice Check if a message has been certified
     * @param messageHash The hash of the message to check
     * @return Whether the message has been certified
     */
    function isMessageCertified(bytes32 messageHash) external view returns (bool) {
        return certifiedMessages[messageHash];
    }
    
    /**
     * @notice Update the thresholds used for verification
     * @param _proportionThresholds The new proportion thresholds
     * @param _nominalThresholds The new nominal thresholds
     */
    function updateThresholds(
        uint16[] calldata _proportionThresholds,
        uint96[] calldata _nominalThresholds
    ) external {
        // In a real implementation, this would have access control
        proportionThresholds = _proportionThresholds;
        nominalThresholds = _nominalThresholds;
    }
}
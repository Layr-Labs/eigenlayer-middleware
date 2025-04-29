
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {BN254} from "../libraries/BN254.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IBLSTableCalculator, IBLSTableCalculatorTypes} from "../interfaces/IBLSTableCalculator.sol";
import {IBLSCertificateVerifier, IBLSCertificateVerifierTypes} from "../interfaces/IBLSCertificateVerifier.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BitmapUtils} from "../libraries/BitmapUtils.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title BLSCertificateVerifier
 * @notice Verifies BLS certificates against a given operator table with enhanced security
 * @dev This contract uses BN254 curves for signature verification and
 *      caches operator information for efficient verification
 */
contract BLSCertificateVerifier is IBLSCertificateVerifier, Ownable {

    using BN254 for BN254.G1Point;

    // Gas limit for pairing operations to prevent DoS
    uint256 private constant PAIRING_EQUALITY_CHECK_GAS = 400000;

    // The operator set this verifier is for
    OperatorSet private _operatorSet;

    // The address that can update the operator table
    address private _operatorTableUpdater;

    // The latest reference timestamp of the operator table
    uint32 public latestReferenceTimestamp;

    // Maximum staleness allowed for an operator table (in seconds)
    uint32 private _maxOperatorTableStaleness;

    // Mapping from reference timestamp to operatorInfoTreeRoot
    mapping(uint32 => bytes32) public operatorInfoTreeRoots;

    // Mapping from reference timestamp to operator set info
    mapping(uint32 => IBLSTableCalculatorTypes.BN254OperatorSetInfo) public operatorSetInfos;

    // Mapping from reference timestamp to operator index to operator info
    // This is used to cache operator info that has been proven against a tree root
    mapping(uint32 => mapping(uint256 => IBLSTableCalculatorTypes.BN254OperatorInfo)) public operatorInfos;

    // Modifier to restrict access to the operator table updater
    modifier onlyTableUpdater() {
        if (msg.sender != _operatorTableUpdater) revert OnlyTableUpdater();
        _;
    }

    /**
     * @notice Constructor for the certificate verifier
     * @param __operatorSet The operator set this verifier is for
     * @param __operatorTableUpdater The address that can update the operator table
     * @param __maxOperatorTableStaleness Maximum staleness allowed for an operator table (in seconds)
     */
    constructor(
        OperatorSet memory __operatorSet,
        address __operatorTableUpdater,
        uint32 __maxOperatorTableStaleness
    ) {
        _operatorSet = __operatorSet;
        _operatorTableUpdater = __operatorTableUpdater;
        _maxOperatorTableStaleness = __maxOperatorTableStaleness;
    }

    /**
     * @inheritdoc IBLSCertificateVerifier
     */
    function operatorSet() external view returns (OperatorSet memory) {
        return _operatorSet;
    }

    /**
     * @inheritdoc IBLSCertificateVerifier
     */
    function operatorTableUpdater() external view returns (address) {
        return _operatorTableUpdater;
    }

    /**
     * @inheritdoc IBLSCertificateVerifier
     */
    function maxOperatorTableStaleness() external view returns (uint32) {
        return _maxOperatorTableStaleness;
    }

    /**
     * @inheritdoc IBLSCertificateVerifier
     */
    function updateOperatorTable(
        uint32 referenceTimestamp,
        IBLSTableCalculatorTypes.BN254OperatorSetInfo memory operatorSetInfo,
        bytes32 operatorInfoTreeRoot
    ) external onlyTableUpdater {
        // Require that the new timestamp is greater than the latest reference timestamp
        require(referenceTimestamp > latestReferenceTimestamp, "Invalid timestamp");

        // Store the operator set info and tree root
        operatorSetInfos[referenceTimestamp] = operatorSetInfo;
        operatorInfoTreeRoots[referenceTimestamp] = operatorInfoTreeRoot;
        latestReferenceTimestamp = referenceTimestamp;

        // Emit event
        emit TableUpdated(referenceTimestamp, operatorSetInfo.aggregatePubkey, operatorInfoTreeRoot);
    }

    /**
     * @inheritdoc IBLSCertificateVerifier
     */
    function ejectOperators(
        uint32 referenceTimestamp,
        uint32[] calldata operatorIndices,
        IBLSCertificateVerifierTypes.BN254OperatorInfoWitness[] calldata witnesses
    ) external onlyTableUpdater {
        // Ensure the reference timestamp exists
        bytes32 treeRoot = operatorInfoTreeRoots[referenceTimestamp];
        if (treeRoot == bytes32(0)) {
            revert("Refrence timestamp does not exist");
        }
        
        // Get the operator set info
        IBLSTableCalculatorTypes.BN254OperatorSetInfo memory operatorSetInfo = operatorSetInfos[referenceTimestamp];
        
        // Process each operator to eject
        for (uint256 i = 0; i < operatorIndices.length; i++) {
            uint32 operatorIndex = operatorIndices[i];
            
            // Ensure index is valid
            if (operatorIndex >= operatorSetInfo.numOperators) {
                revert("Operator index not valid");
            }
            
            // Check if we need to verify and cache the operator info
            bool operatorInfoExists = operatorInfos[referenceTimestamp][operatorIndex].pubkey.X != 0 || 
                        operatorInfos[referenceTimestamp][operatorIndex].pubkey.Y != 0;
            
            if (!operatorInfoExists) {
                // Find the matching witness
                IBLSCertificateVerifierTypes.BN254OperatorInfoWitness memory witness;
                bool found = false;
                
                for (uint256 j = 0; j < witnesses.length; j++) {
                    if (witnesses[j].operatorIndex == operatorIndex) {
                        witness = witnesses[j];
                        found = true;
                        break;
                    }
                }
                
                if (!found) {
                    revert("bad witnesses");
                }
                
                // Verify and cache the witness
                bool verified = _verifyOperatorInfoMerkleProof(
                    referenceTimestamp,
                    operatorIndex,
                    witness.operatorInfo,
                    witness.operatorInfoProofs
                );
                
                if (!verified) {
                    revert("merkle verification failed");
                }
                
                // Cache the operator info
                operatorInfos[referenceTimestamp][operatorIndex] = witness.operatorInfo;
            }
            
            // Get the operator info for updating
            IBLSTableCalculatorTypes.BN254OperatorInfo storage operatorInfo = 
                operatorInfos[referenceTimestamp][operatorIndex];
            
            // Zero out the operator's weights - keep track of total to subtract
            uint96[] memory ejectedWeights = new uint96[](operatorInfo.weights.length);
            for (uint256 j = 0; j < operatorInfo.weights.length; j++) {
                ejectedWeights[j] = operatorInfo.weights[j];
                operatorInfo.weights[j] = 0;
            }
            
            // Update the total weights for the operator set
            for (uint256 j = 0; j < operatorSetInfo.totalWeights.length; j++) {
                if (j < ejectedWeights.length) {
                    operatorSetInfo.totalWeights[j] -= ejectedWeights[j];
                }
            }
        }
        
        // Update the operator set info with new total weights
        operatorSetInfos[referenceTimestamp] = operatorSetInfo;
    }

    /**
     * @inheritdoc IBLSCertificateVerifier
     */
    function verifyCertificate(
        IBLSCertificateVerifierTypes.BN254Certificate memory cert
    ) external returns (uint96[] memory signedStakes) {
        return _verifyCertificate(cert);
    }

    /**
     * @inheritdoc IBLSCertificateVerifier
     */
    function verifyCertificateProportion(
        IBLSCertificateVerifierTypes.BN254Certificate memory cert,
        uint16[] memory totalStakeProportionThresholds
    ) external returns (bool) {
        // Get signed stakes
        uint96[] memory signedStakes = _verifyCertificate(cert);
        
        // Get total stakes from the operator set info
        IBLSTableCalculatorTypes.BN254OperatorSetInfo memory operatorSetInfo = operatorSetInfos[cert.referenceTimestamp];
        uint96[] memory totalStakes = operatorSetInfo.totalWeights;
        
        // Verify that each stake meets the threshold
        require(signedStakes.length == totalStakeProportionThresholds.length, "Length mismatch");
        
        for (uint256 i = 0; i < signedStakes.length; i++) {
            // Calculate threshold as proportion of total stake
            // totalStakeProportionThresholds is a percentage with 2 decimal places (e.g. 6600 = 66%)
            uint96 threshold = uint96(uint256(totalStakes[i]) * uint256(totalStakeProportionThresholds[i]) / 10000);
            
            // If signed stake doesn't meet threshold, return false
            if (signedStakes[i] < threshold) {
                return false;
            }
        }
        
        return true;
    }

    /**
     * @inheritdoc IBLSCertificateVerifier
     */
    function verifyCertificateNominal(
        IBLSCertificateVerifierTypes.BN254Certificate memory cert,
        uint96[] memory totalStakeNominalThresholds
    ) external returns (bool) {
        // Get signed stakes
        uint96[] memory signedStakes = _verifyCertificate(cert);
        
        // Verify that each stake meets the threshold
        require(signedStakes.length == totalStakeNominalThresholds.length, "Length mismatch");
        
        for (uint256 i = 0; i < signedStakes.length; i++) {
            // If signed stake doesn't meet nominal threshold, return false
            if (signedStakes[i] < totalStakeNominalThresholds[i]) {
                return false;
            }
        }
        
        return true;
    }

    /**
     * @inheritdoc IBLSCertificateVerifier
     */
    function setOperatorTableUpdater(address _newOperatorTableUpdater) external onlyOwner {
        _operatorTableUpdater = _newOperatorTableUpdater;
    }

    /**
     * @inheritdoc IBLSCertificateVerifier
     */
    function setMaxOperatorTableStaleness(uint32 _newMaxOperatorTableStaleness) external onlyOwner {
        _maxOperatorTableStaleness = _newMaxOperatorTableStaleness;
    }

    /**
     * @notice Try signature verification with gas limit for safety
     * @param msgHash The message hash that was signed
     * @param aggPubkey The aggregate public key of signers
     * @param apkG2 The G2 point representation of the aggregate public key
     * @param signature The BLS signature to verify
     * @return pairingSuccessful Whether the pairing operation completed successfully
     * @return signatureValid Whether the signature is valid
     */
    function trySignatureVerification(
        bytes32 msgHash,
        BN254.G1Point memory aggPubkey,
        BN254.G2Point memory apkG2,
        BN254.G1Point memory signature
    ) internal view returns (bool pairingSuccessful, bool signatureValid) {
        uint256 gamma = uint256(
            keccak256(
                abi.encodePacked(
                    msgHash,
                    aggPubkey.X,
                    aggPubkey.Y,
                    apkG2.X[0],
                    apkG2.X[1],
                    apkG2.Y[0],
                    apkG2.Y[1],
                    signature.X,
                    signature.Y
                )
            )
        ) % BN254.FR_MODULUS;
        
        (pairingSuccessful, signatureValid) = BN254.safePairing(
            signature.plus(aggPubkey.scalar_mul(gamma)),  // sigma + apk*gamma
            BN254.negGeneratorG2(),                       // -G2
            BN254.hashToG1(msgHash).plus(BN254.generatorG1().scalar_mul(gamma)), // H(m) + g1*gamma
            apkG2,                                        // apkG2
            PAIRING_EQUALITY_CHECK_GAS
        );
    }

    /**
     * @notice Internal function to verify a certificate
     * @param cert The certificate to verify
     * @return signedStakes The amount of stake that signed the certificate for each stake type
     */
    function _verifyCertificate(
        IBLSCertificateVerifierTypes.BN254Certificate memory cert
    ) internal returns (uint96[] memory signedStakes) {
        // Check that the reference timestamp is not too stale
        if (block.timestamp > cert.referenceTimestamp + _maxOperatorTableStaleness) {
            revert TableStale();
        }
        
        // Check that this reference timestamp exists
        bytes32 operatorInfoTreeRoot = operatorInfoTreeRoots[cert.referenceTimestamp];
        if (operatorInfoTreeRoot == bytes32(0)) {
            revert("timestamp does not exist");
        }

        // Get operator set info
        IBLSTableCalculatorTypes.BN254OperatorSetInfo memory operatorSetInfo = operatorSetInfos[cert.referenceTimestamp];
        
        // Initialize signed stakes with total stakes
        uint96[] memory totalStakes = operatorSetInfo.totalWeights;
        signedStakes = new uint96[](totalStakes.length);
        
        for (uint256 i = 0; i < totalStakes.length; i++) {
            signedStakes[i] = totalStakes[i];
        }
        
        // Validate non-signer indices are sorted (for efficiency and to prevent duplicates)
        for (uint256 i = 1; i < cert.nonSignerIndices.length; i++) {
            if (cert.nonSignerIndices[i] <= cert.nonSignerIndices[i-1]) {
                revert("non-signers not sorted");
            }
        }
        
        // Cache non-signer operator infos if needed and build the aggregate non-signer public key
        BN254.G1Point memory nonSignerApk = BN254.G1Point(0, 0);
        
        for (uint256 i = 0; i < cert.nonSignerIndices.length; i++) {
            uint32 nonSignerIndex = cert.nonSignerIndices[i];
            
            // Make sure index is valid
            if (nonSignerIndex >= operatorSetInfo.numOperators) {
                revert("non-signer index not valid");
            }
            
            // Check if this operator's info is already cached
            if (keccak256(abi.encode(operatorInfos[cert.referenceTimestamp][nonSignerIndex].pubkey)) == keccak256(abi.encode(BN254.G1Point(0, 0)))) {
                // Find the matching witness
                IBLSCertificateVerifierTypes.BN254OperatorInfoWitness memory witness;
                bool found = false;
                
                for (uint256 j = 0; j < cert.nonSignerWitnesses.length; j++) {
                    if (cert.nonSignerWitnesses[j].operatorIndex == nonSignerIndex) {
                        witness = cert.nonSignerWitnesses[j];
                        found = true;
                        break;
                    }
                }
                
                if (!found) {
                    revert("bad certificate");
                }
                
                // Verify the merkle proof
                bool verified = _verifyOperatorInfoMerkleProof(
                    cert.referenceTimestamp,
                    nonSignerIndex,
                    witness.operatorInfo,
                    witness.operatorInfoProofs
                );
                
                if (!verified) {
                    revert("operator merkle proof failed");
                }
                
                // Cache the operator info
                    operatorInfos[cert.referenceTimestamp][nonSignerIndex] = witness.operatorInfo;
            }
            
            // Get the non-signer info
            IBLSTableCalculatorTypes.BN254OperatorInfo memory nonSignerInfo = 
                operatorInfos[cert.referenceTimestamp][nonSignerIndex];
            
            // Add the non-signer's public key to the aggregate non-signer key
            nonSignerApk = nonSignerApk.plus(nonSignerInfo.pubkey);
            
            // Subtract non-signer weights from the signed stakes
            for (uint256 j = 0; j < nonSignerInfo.weights.length; j++) {
                if (j < signedStakes.length) {
                    signedStakes[j] -= nonSignerInfo.weights[j];
                }
            }
        }
        
        // Calculate the adjusted aggregate public key (signers only) by subtracting non-signers from total
        BN254.G1Point memory signerApk = operatorSetInfo.aggregatePubkey.plus(nonSignerApk.negate());
        
        // Verify the BLS signature
        (bool pairingSuccessful, bool signatureValid) = trySignatureVerification(
            cert.messageHash,
            signerApk,      
            cert.apk,       
            cert.signature  
        );
        
        if (!pairingSuccessful || !signatureValid) {
            revert CertVerificationFailed();
        }
        
        return signedStakes;
    }

    /**
     * @notice Verifies a merkle proof for an operator info
     * @param referenceTimestamp The reference timestamp
     * @param operatorIndex The index of the operator
     * @param operatorInfo The operator info
     * @param proof The merkle proof as bytes32[]
     * @return verified Whether the proof is valid
     */
    function _verifyOperatorInfoMerkleProof(
        uint32 referenceTimestamp,
        uint32 operatorIndex,
        IBLSTableCalculatorTypes.BN254OperatorInfo memory operatorInfo,
        bytes32[] memory proof
    ) internal view returns (bool verified) {
        bytes32 leaf = keccak256(abi.encode(operatorInfo));
        bytes32 root = operatorInfoTreeRoots[referenceTimestamp];
        // Use OpenZeppelin's MerkleProof to verify
        return MerkleProof.verify(proof, root, leaf);
    }

    function getOperatorInfo(uint32 referenceTimestamp, uint256 operatorIndex) public view returns (IBLSTableCalculatorTypes.BN254OperatorInfo memory) {
        return operatorInfos[referenceTimestamp][operatorIndex];
    }

    function getOperatorSetInfo(uint32 referenceTimestamp) public view returns (IBLSTableCalculatorTypes.BN254OperatorSetInfo memory) {
        return operatorSetInfos[referenceTimestamp];
    }
}
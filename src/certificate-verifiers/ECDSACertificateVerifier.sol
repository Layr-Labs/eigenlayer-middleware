// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet, OperatorSetLib} from "lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {ECDSAOperatorInfo} from "../operator-tables/ECDSAOperatorTableCalculator.sol";
import "@openzeppelin-upgrades/contracts/utils/cryptography/SignatureCheckerUpgradeable.sol";
import {IAllocationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

struct ECDSACertificate {
    uint32 referenceTimestamp;
    bytes32 messageHash;
    // the concatenated signature of each signing operator
    bytes sig;
}

/**
 * @title ECDSACertificateVerifier
 * @notice Verifies certificates signed with ECDSA signatures
 * @dev Stores operator infos and verifies certificates against them
 */
contract ECDSACertificateVerifier {
    /// @notice The operator set this verifier is for
    bytes32 public immutable operatorSetKey;
    address public immutable avsAddress;
    uint32 public immutable operatorSetId;
    
    /// @notice The address that can update the operator table
    address public immutable operatorTableUpdater;
    
    /// @notice Maximum staleness allowed for the operator table (in seconds)
    uint32 public immutable maxOperatorTableStaleness;
    
    /// @notice The timestamp of the latest operator table update
    uint32 public latestReferenceTimestamp;
    
    /// @notice Mapping from reference timestamp to operator infos
    mapping(uint32 => ECDSAOperatorInfo[]) internal _operatorInfos;
    
    /**
     * @notice Get the operator info for a reference timestamp and index
     * @param referenceTimestamp The timestamp to get operator info for
     * @param index The operator index
     * @return The operator info
     */
    function operatorInfos(uint32 referenceTimestamp, uint256 index) external view returns (ECDSAOperatorInfo memory) {
        return _operatorInfos[referenceTimestamp][index];
    }
    
    /**
     * @notice Get all operator infos for a reference timestamp
     * @param referenceTimestamp The timestamp to get operator infos for
     * @return Array of all operator infos
     */
    function getOperatorInfos(uint32 referenceTimestamp) external view returns (ECDSAOperatorInfo[] memory) {
        return _operatorInfos[referenceTimestamp];
    }
    
    /// @notice Mapping from reference timestamp to total weights
    mapping(uint32 => uint96[]) internal _totalWeights;
    
    /**
     * @notice Get the total weights for a reference timestamp
     * @param referenceTimestamp The timestamp to get weights for
     * @return The total weights array
     */
    function totalWeights(uint32 referenceTimestamp) external view returns (uint96[] memory) {
        return _totalWeights[referenceTimestamp];
    }
    
    /**
     * @notice Event emitted when the operator table is updated
     * @param referenceTimestamp The timestamp of the operator table
     * @param numOperators The number of operators in the table
     */
    event OperatorTableUpdated(uint32 referenceTimestamp, uint32 numOperators);
    
    /**
     * @notice Event emitted when operators are ejected
     * @param referenceTimestamp The timestamp of the operator table being modified
     * @param operatorIndices The indices of the operators being ejected
     */
    event OperatorsEjected(uint32 referenceTimestamp, uint32[] operatorIndices);
    
    /**
     * @dev Constructor to initialize the verifier
     * @param _operatorSet The operator set this verifier is for
     * @param _operatorTableUpdater The address that can update the operator table
     * @param _maxOperatorTableStaleness Maximum staleness allowed for the operator table (in seconds)
     */
    constructor(
        OperatorSet memory _operatorSet,
        address _operatorTableUpdater,
        uint32 _maxOperatorTableStaleness
    ) {
        operatorSetKey = OperatorSetLib.key(_operatorSet);
        avsAddress = _operatorSet.avs;
        operatorSetId = _operatorSet.id;
        operatorTableUpdater = _operatorTableUpdater;
        maxOperatorTableStaleness = _maxOperatorTableStaleness;
    }
    
    /**
     * @notice Updates the operator table
     * @param referenceTimestamp The timestamp at which the operatorInfos were sourced
     * @param operatorInfosArray The new operator infos
     * @dev Only callable by the operatorTableUpdater
     */
    function updateOperatorTable(
        uint32 referenceTimestamp,
        ECDSAOperatorInfo[] memory operatorInfosArray
    ) external {
        require(msg.sender == operatorTableUpdater, "Not authorized");
        require(referenceTimestamp > latestReferenceTimestamp, "Outdated timestamp");
        
        // Store the operator infos
        uint256 numOperators = operatorInfosArray.length;
        for (uint256 i = 0; i < numOperators; i++) {
            _operatorInfos[referenceTimestamp].push(operatorInfosArray[i]);
        }
        
        // Calculate and store total weights
        if (numOperators > 0) {
            uint256 numWeightTypes = operatorInfosArray[0].weights.length;
            _totalWeights[referenceTimestamp] = new uint96[](numWeightTypes);
            
            for (uint256 i = 0; i < numOperators; i++) {
                for (uint256 j = 0; j < numWeightTypes; j++) {
                    _totalWeights[referenceTimestamp][j] += operatorInfosArray[i].weights[j];
                }
            }
        }
        
        // Update the latest timestamp
        latestReferenceTimestamp = referenceTimestamp;
        
        emit OperatorTableUpdated(referenceTimestamp, uint32(numOperators));
    }
    
    /**
     * @notice Ejects operators from the operator set
     * @param referenceTimestamp The timestamp of the operator table against which the ejection is being done
     * @param operatorIndices The indices of the operators to eject
     * @dev Only callable by the operatorTableUpdater
     */
    function ejectOperators(
        uint32 referenceTimestamp,
        uint32[] memory operatorIndices
    ) external {
        require(msg.sender == operatorTableUpdater, "Not authorized");
        require(referenceTimestamp <= latestReferenceTimestamp, "Invalid timestamp");
        
        ECDSAOperatorInfo[] storage infos = _operatorInfos[referenceTimestamp];
        uint96[] storage weights = _totalWeights[referenceTimestamp];
        
        for (uint256 i = 0; i < operatorIndices.length; i++) {
            uint32 index = operatorIndices[i];
            require(index < infos.length, "Invalid index");
            
            // Subtract the operator's weights from the total
            for (uint256 j = 0; j < weights.length; j++) {
                weights[j] -= infos[index].weights[j];
                // Set the operator's weight to 0
                infos[index].weights[j] = 0;
            }
        }
        
        emit OperatorsEjected(referenceTimestamp, operatorIndices);
    }
    
    /**
     * @notice Verifies a certificate
     * @param cert A certificate
     * @return signedStakes The amount of stake that signed the certificate for each stake type
     */
    function verifyCertificate(ECDSACertificate memory cert) 
        public view returns(uint96[] memory signedStakes) 
    {
        // Check that the reference timestamp is not too stale
        require(
            cert.referenceTimestamp <= latestReferenceTimestamp && 
            latestReferenceTimestamp - cert.referenceTimestamp <= maxOperatorTableStaleness,
            "Stale reference timestamp"
        );
        
        // Get the operator infos for this timestamp
        ECDSAOperatorInfo[] storage infos = _operatorInfos[cert.referenceTimestamp];
        require(infos.length > 0, "No operator infos for timestamp");
        
        // Initialize the signed stakes array
        uint256 numWeightTypes = infos[0].weights.length;
        signedStakes = new uint96[](numWeightTypes);
        
        // The signature length must be a multiple of 65 bytes (each ECDSA signature is 65 bytes)
        require(cert.sig.length % 65 == 0, "Invalid signature length");
        
        // Determine how many signatures we have
        uint256 numSignatures = cert.sig.length / 65;
        
        // Process each signature
        for (uint256 i = 0; i < numSignatures; i++) {
            // Extract this signature
            bytes memory signature = new bytes(65);
            for (uint256 j = 0; j < 65; j++) {
                signature[j] = cert.sig[i * 65 + j];
            }
            
            // Try to find the signer among the operators
            for (uint256 j = 0; j < infos.length; j++) {
                ECDSAOperatorInfo storage info = infos[j];
                
                // Skip if this signature has already been processed (weight set to 0)
                if (info.weights[0] == 0) continue;
                
                // Verify if this operator signed the message
                if (SignatureCheckerUpgradeable.isValidSignatureNow(
                    info.pubkey,
                    cert.messageHash,
                    signature
                )) {
                    // Add the weights to the signed stakes
                    for (uint256 k = 0; k < numWeightTypes; k++) {
                        signedStakes[k] += info.weights[k];
                    }
                    
                    // Mark this operator as processed
                    break;
                }
            }
        }
        
        return signedStakes;
    }
    
    /**
     * @notice Verifies a certificate and makes sure that the signed stakes meet provided portions of the total stake
     * @param cert A certificate
     * @param totalStakeProportionThresholds The proportion of total stake that the signed stake should meet (in basis points, e.g. 6600 = 66%)
     * @return Whether or not certificate is valid and meets thresholds
     */
    function verifyCertificateProportion(
        ECDSACertificate memory cert,
        uint16[] memory totalStakeProportionThresholds
    ) external view returns(bool) {
        // Verify the certificate and get the signed stakes
        uint96[] memory signedStakes = verifyCertificate(cert);
        
        // Get the total weights for this timestamp
        uint96[] storage weights = _totalWeights[cert.referenceTimestamp];
        
        // Check that the proportion thresholds match the number of weight types
        require(totalStakeProportionThresholds.length == signedStakes.length, "Invalid thresholds length");
        
        // Check each threshold
        for (uint256 i = 0; i < signedStakes.length; i++) {
            // Calculate the required stake (totalWeight * proportion / 10000)
            uint256 requiredStake = (uint256(weights[i]) * uint256(totalStakeProportionThresholds[i])) / 10000;
            
            // Check if the signed stake meets the threshold
            if (uint256(signedStakes[i]) < requiredStake) {
                return false;
            }
        }
        
        return true;
    }
    
    /**
     * @notice Verifies a certificate and makes sure that the signed stakes meet provided nominal stake thresholds
     * @param cert A certificate
     * @param totalStakeNominalThresholds The nominal amount of stake that the signed stake should meet
     * @return Whether or not certificate is valid and meets thresholds
     */
    function verifyCertificateNominal(
        ECDSACertificate memory cert,
        uint96[] memory totalStakeNominalThresholds
    ) external view returns(bool) {
        // Verify the certificate and get the signed stakes
        uint96[] memory signedStakes = verifyCertificate(cert);
        
        // Check that the nominal thresholds match the number of weight types
        require(totalStakeNominalThresholds.length == signedStakes.length, "Invalid thresholds length");
        
        // Check each threshold
        for (uint256 i = 0; i < signedStakes.length; i++) {
            // Check if the signed stake meets the threshold
            if (signedStakes[i] < totalStakeNominalThresholds[i]) {
                return false;
            }
        }
        
        return true;
    }
}
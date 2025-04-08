// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet, OperatorSetLib} from "lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {BN254} from "../libraries/BN254.sol";
import {MerkleTreeLib} from "../operator-tables/libraries/MerkleTreeLib.sol";
import {BN254OperatorInfo, BN254OperatorSetInfo} from "../operator-tables/BN254OperatorTableCalculator.sol";

struct BN254OperatorInfoWitness {
    uint32 operatorIndex;
    // empty implies already cached in storage
    bytes operatorInfoProofs;
    BN254OperatorInfo operatorInfo;
}

struct BN254Certificate {
    uint32 referenceTimestamp;
    bytes32 messageHash;
    
    // signature data
    BN254.G1Point sig;
    BN254.G2Point apk;
    uint32[] nonsignerIndices;
    BN254OperatorInfoWitness[] nonSignerWitnesses;
}

/**
 * @title BN254CertificateVerifier
 * @notice Verifies certificates signed with BN254 BLS signatures
 * @dev Stores operator set info and caches operator info as needed
 */
contract BN254CertificateVerifier {
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
    
    /// @notice Mapping from reference timestamp to operator info tree root
    mapping(uint32 => bytes32) public operatorInfoTreeRoots;
    
    /// @notice Mapping from reference timestamp to operator set info
    mapping(uint32 => BN254OperatorSetInfo) internal _operatorSetInfos;
    
    /**
     * @notice Get the operator set info for a reference timestamp
     * @param referenceTimestamp The timestamp to get operator set info for
     * @return The operator set info
     */
    function operatorSetInfos(uint32 referenceTimestamp) external view returns (BN254OperatorSetInfo memory) {
        return _operatorSetInfos[referenceTimestamp];
    }
    
    /// @notice Mapping from reference timestamp to index to operator info
    mapping(uint32 => mapping(uint256 => BN254OperatorInfo)) public operatorInfos;
    
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
     * @param referenceTimestamp The timestamp at which the operatorSetInfo and operatorInfoTreeRoot were sourced
     * @param operatorSetInfo The aggregate information about the operatorSet
     * @dev Only callable by the operatorTableUpdater
     */
    function updateOperatorTable(
        uint32 referenceTimestamp,
        BN254OperatorSetInfo memory operatorSetInfo
    ) external {
        require(msg.sender == operatorTableUpdater, "Not authorized");
        require(referenceTimestamp > latestReferenceTimestamp, "Outdated timestamp");
        
        // Store the operator set info
        operatorInfoTreeRoots[referenceTimestamp] = operatorSetInfo.operatorInfoTreeRoot;
        _operatorSetInfos[referenceTimestamp] = operatorSetInfo;
        
        // Update the latest timestamp
        latestReferenceTimestamp = referenceTimestamp;
        
        emit OperatorTableUpdated(referenceTimestamp, operatorSetInfo.numOperators);
    }
    
    /**
     * @notice Ejects operators from the operator set
     * @param referenceTimestamp The timestamp of the operator table against which the ejection is being done
     * @param operatorIndices The indices of the operators to eject
     * @param witnesses For the operators that are not already in storage
     * @dev Only callable by the operatorTableUpdater
     */
    function ejectOperators(
        uint32 referenceTimestamp,
        uint32[] memory operatorIndices,
        BN254OperatorInfoWitness[] memory witnesses
    ) external {
        require(msg.sender == operatorTableUpdater, "Not authorized");
        require(referenceTimestamp <= latestReferenceTimestamp, "Invalid timestamp");
        
        BN254OperatorSetInfo storage setInfo = _operatorSetInfos[referenceTimestamp];
        bytes32 treeRoot = operatorInfoTreeRoots[referenceTimestamp];
        
        // First, process any operators that need to be loaded from witnesses
        for (uint256 i = 0; i < witnesses.length; i++) {
            BN254OperatorInfoWitness memory witness = witnesses[i];
            
            // Check if we already have this operator info cached
            if (operatorInfos[referenceTimestamp][witness.operatorIndex].pubkey.X != 0) {
                continue;
            }
            
            // Verify the witness
            bytes32 operatorHash = hashOperatorInfo(witness.operatorInfo);
            require(
                MerkleTreeLib.verifyProof(
                    treeRoot,
                    operatorHash,
                    witness.operatorIndex,
                    witness.operatorInfoProofs
                ),
                "Invalid operator proof"
            );
            
            // Cache the operator info
            operatorInfos[referenceTimestamp][witness.operatorIndex] = witness.operatorInfo;
        }
        
        // Now eject the operators
        for (uint256 i = 0; i < operatorIndices.length; i++) {
            uint32 index = operatorIndices[i];
            require(index < setInfo.numOperators, "Invalid index");
            
            // Get the operator info
            BN254OperatorInfo storage info = operatorInfos[referenceTimestamp][index];
            
            // Make sure we have this operator in storage
            require(info.pubkey.X != 0, "Operator info not loaded");
            
            // Subtract the operator's weights from the total and pubkey from aggregate
            for (uint256 j = 0; j < setInfo.totalWeights.length; j++) {
                setInfo.totalWeights[j] -= info.weights[j];
                // Set the operator's weight to 0
                info.weights[j] = 0;
            }
            
            // Subtract the operator's pubkey from the aggregate pubkey
            setInfo.aggregatePubkey = BN254.plus(
                setInfo.aggregatePubkey,
                BN254.negate(info.pubkey)
            );
        }
        
        emit OperatorsEjected(referenceTimestamp, operatorIndices);
    }
    
    /**
     * @notice Verifies a certificate
     * @param cert A certificate
     * @return signedStakes The amount of stake that signed the certificate for each stake type
     */
    function verifyCertificate(BN254Certificate memory cert) 
        public returns(uint96[] memory signedStakes) 
    {
        // Check that the reference timestamp is not too stale
        require(
            cert.referenceTimestamp <= latestReferenceTimestamp && 
            latestReferenceTimestamp - cert.referenceTimestamp <= maxOperatorTableStaleness,
            "Stale reference timestamp"
        );
        
        // Get the operator set info for this timestamp
        BN254OperatorSetInfo storage setInfo = _operatorSetInfos[cert.referenceTimestamp];
        bytes32 treeRoot = operatorInfoTreeRoots[cert.referenceTimestamp];
        
        require(setInfo.numOperators > 0, "No operator set info for timestamp");
        
        // Initialize the signed stakes array with the total weights
        signedStakes = new uint96[](setInfo.totalWeights.length);
        for (uint256 i = 0; i < signedStakes.length; i++) {
            signedStakes[i] = setInfo.totalWeights[i];
        }
        
        // Start with the aggregate BLS public key
        BN254.G1Point memory computedApk = setInfo.aggregatePubkey;
        
        // Process each non-signer
        for (uint256 i = 0; i < cert.nonsignerIndices.length; i++) {
            uint32 index = cert.nonsignerIndices[i];
            require(index < setInfo.numOperators, "Invalid nonsigner index");
            
            // Check if we already have this operator info cached
            BN254OperatorInfo storage info = operatorInfos[cert.referenceTimestamp][index];
            
            // If not cached, we need to verify and cache it
            if (info.pubkey.X == 0) {
                // Find the corresponding witness
                bool foundWitness = false;
                for (uint256 j = 0; j < cert.nonSignerWitnesses.length; j++) {
                    if (cert.nonSignerWitnesses[j].operatorIndex == index) {
                        // Verify the witness
                        bytes32 operatorHash = hashOperatorInfo(cert.nonSignerWitnesses[j].operatorInfo);
                        require(
                            MerkleTreeLib.verifyProof(
                                treeRoot,
                                operatorHash,
                                index,
                                cert.nonSignerWitnesses[j].operatorInfoProofs
                            ),
                            "Invalid nonsigner proof"
                        );
                        
                        // Cache the operator info
                        operatorInfos[cert.referenceTimestamp][index] = cert.nonSignerWitnesses[j].operatorInfo;
                        info = operatorInfos[cert.referenceTimestamp][index];
                        foundWitness = true;
                        break;
                    }
                }
                
                require(foundWitness, "Missing nonsigner witness");
            }
            
            // Subtract the non-signer's pubkey from the aggregate pubkey
            computedApk = BN254.plus(computedApk, BN254.negate(info.pubkey));
            
            // Subtract the non-signer's weights from the signed stakes
            for (uint256 j = 0; j < signedStakes.length; j++) {
                signedStakes[j] -= info.weights[j];
            }
        }
        
        // Verify the BLS signature
        BN254.G2Point memory hashToG2 = hashToG2Point(cert.messageHash);
        
        require(
            BN254.pairing(
                BN254.negate(BN254.generatorG1()), 
                cert.apk,
                cert.sig, 
                hashToG2
            ),
            "Invalid signature"
        );
        
        // Also verify that the provided APK matches our computed APK
        require(
            cert.apk.X[0] == computedApk.X && 
            cert.apk.X[1] == computedApk.Y,
            "APK mismatch"
        );
        
        return signedStakes;
    }
    
    /**
     * @notice Verifies a certificate and makes sure that the signed stakes meet provided portions of the total stake
     * @param cert A certificate
     * @param totalStakeProportionThresholds The proportion of total stake that the signed stake should meet (in basis points, e.g. 6600 = 66%)
     * @return Whether or not certificate is valid and meets thresholds
     */
    function verifyCertificateProportion(
        BN254Certificate memory cert,
        uint16[] memory totalStakeProportionThresholds
    ) external returns(bool) {
        // Verify the certificate and get the signed stakes
        uint96[] memory signedStakes = verifyCertificate(cert);
        
        // Get the total weights for this timestamp
        BN254OperatorSetInfo storage setInfo = _operatorSetInfos[cert.referenceTimestamp];
        
        // Check that the proportion thresholds match the number of weight types
        require(totalStakeProportionThresholds.length == signedStakes.length, "Invalid thresholds length");
        
        // Check each threshold
        for (uint256 i = 0; i < signedStakes.length; i++) {
            // Calculate the required stake (totalWeight * proportion / 10000)
            uint256 requiredStake = (uint256(setInfo.totalWeights[i]) * uint256(totalStakeProportionThresholds[i])) / 10000;
            
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
        BN254Certificate memory cert,
        uint96[] memory totalStakeNominalThresholds
    ) external returns(bool) {
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
    
    /**
     * @notice Hash an operator info struct for inclusion in the merkle tree
     * @param operatorInfo The operator info to hash
     * @return The hash of the operator info
     */
    function hashOperatorInfo(BN254OperatorInfo memory operatorInfo) 
        internal pure returns (bytes32) 
    {
        // Hash the pubkey
        bytes32 pubkeyHash = BN254.hashG1Point(operatorInfo.pubkey);
        
        // Hash the weights
        bytes32 weightsHash = keccak256(abi.encode(operatorInfo.weights));
        
        // Combine the hashes
        return keccak256(abi.encode(pubkeyHash, weightsHash));
    }
    
    /**
     * @notice Maps a message hash to a point on the G2 curve
     * @param messageHash The message hash to map
     * @return A point on the G2 curve
     */
    function hashToG2Point(bytes32 messageHash) internal pure returns (BN254.G2Point memory) {
        // Note: In a real implementation, this would use a proper hash-to-curve algorithm
        // For simplicity, we're just using a placeholder implementation
        return BN254.generatorG2();
    }
}
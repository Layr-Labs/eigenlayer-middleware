// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet} from "lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAllocationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {BN254} from "../libraries/BN254.sol";
import {MerkleTreeLib} from "./libraries/MerkleTreeLib.sol";

struct BN254OperatorInfo {
    BN254.G1Point pubkey;
    uint96[] weights;
}

struct BN254OperatorSetInfo {
    bytes32 operatorInfoTreeRoot;
    uint32 numOperators;
    BN254.G1Point aggregatePubkey;
    uint96[] totalWeights;
}

interface IBN254OperatorTableCalculator {
    /**
     * @notice calculates the operatorInfos for a given operatorSet
     * @param operatorSet the operatorSet to calculate the operator table for
     * @return operatorSetInfo the operator set information including merkle root and aggregate pubkey
     */
    function calculateOperatorTable(OperatorSet calldata operatorSet) 
        external view returns(BN254OperatorSetInfo memory operatorSetInfo);
        
    /**
     * @notice Gets the operator info for a specific operator in the set
     * @param operatorSet The operator set to query
     * @param operatorIndex The index of the operator in the set
     * @return The operator information including pubkey and weights
     */
    function getOperatorInfo(OperatorSet calldata operatorSet, uint32 operatorIndex)
        external view returns(BN254OperatorInfo memory);
        
    /**
     * @notice Gets the merkle proof for an operator
     * @param operatorSet The operator set to query
     * @param operatorIndex The index of the operator in the set
     * @return The merkle proof for the operator
     */
    function getOperatorProof(OperatorSet calldata operatorSet, uint32 operatorIndex)
        external view returns(bytes memory);
}

/**
 * @title BN254OperatorTableCalculator
 * @notice Calculates operator tables for BN254 BLS signatures
 * @dev Returns a merkle root of operator infos along with aggregate information about the operator set
 */
contract BN254OperatorTableCalculator is IBN254OperatorTableCalculator {
    /// @notice The AllocationManager contract from EigenLayer core
    IAllocationManager public immutable allocationManager;
    
    /// @notice Mapping from operator address to BLS pubkey
    mapping(address => BN254.G1Point) public operatorToPubkey;
    
    /// @notice Strategies used for calculating weights
    IStrategy[] public strategies;
    
    /// @notice Multipliers for each strategy (used to calculate the final weights)
    uint256[] public strategyMultipliers;
    
    /// @notice The number of stake weight types to track (e.g. slashable, delegated, etc.)
    uint8 public immutable numWeightTypes;
    
    /**
     * @notice Constructor to initialize the calculator
     * @param _allocationManager The AllocationManager from EigenLayer core
     * @param _strategies Array of strategies to consider for operator weights
     * @param _strategyMultipliers Multipliers for each strategy to calculate weights
     * @param _numWeightTypes Number of different weight types to track
     */
    constructor(
        IAllocationManager _allocationManager,
        IStrategy[] memory _strategies, 
        uint256[] memory _strategyMultipliers,
        uint8 _numWeightTypes
    ) {
        require(_strategies.length == _strategyMultipliers.length, "Mismatched arrays");
        require(_numWeightTypes > 0, "Must track at least one weight type");
        
        allocationManager = _allocationManager;
        numWeightTypes = _numWeightTypes;
        
        for (uint256 i = 0; i < _strategies.length; i++) {
            strategies.push(_strategies[i]);
            strategyMultipliers.push(_strategyMultipliers[i]);
        }
    }
    
    /**
     * @notice Register a BLS pubkey for an operator
     * @param operator The operator address
     * @param pubkey The BLS public key in G1
     */
    function registerOperatorPubkey(address operator, BN254.G1Point calldata pubkey) external {
        // In a real implementation, this would verify the pubkey belongs to the operator
        // using a signature verification
        operatorToPubkey[operator] = pubkey;
    }
    
    /**
     * @notice Calculates the operator table for a given operatorSet
     * @param operatorSet The operatorSet to calculate the operator table for
     * @return operatorSetInfo The operator set information including merkle root and aggregate data
     */
    function calculateOperatorTable(OperatorSet calldata operatorSet) 
        external view returns(BN254OperatorSetInfo memory operatorSetInfo) 
    {
        // Get all operators registered to this operator set
        address[] memory operators = allocationManager.getMembers(operatorSet);
        
        // Initialize operator set info
        operatorSetInfo = BN254OperatorSetInfo({
            operatorInfoTreeRoot: bytes32(0),
            numOperators: uint32(operators.length),
            aggregatePubkey: BN254.G1Point(0, 0),
            totalWeights: new uint96[](numWeightTypes)
        });
        
        // Exit early if there are no operators
        if (operators.length == 0) {
            return operatorSetInfo;
        }
        
        // Get all allocated stake for all operators and all strategies
        uint256[][] memory allocatedStake = allocationManager.getAllocatedStake(
            operatorSet,
            operators,
            strategies
        );
        
        // Create an array to store the hashed operator infos for the merkle tree
        bytes32[] memory hashedOperatorInfos = new bytes32[](operators.length);
        
        // For each operator, calculate their weights and build the operator info
        for (uint256 i = 0; i < operators.length; i++) {
            BN254OperatorInfo memory operatorInfo = BN254OperatorInfo({
                pubkey: operatorToPubkey[operators[i]],
                weights: new uint96[](numWeightTypes)
            });
            
            // Calculate weights based on strategy multipliers
            for (uint256 j = 0; j < numWeightTypes; j++) {
                uint256 totalWeight = 0;
                
                // Apply the appropriate weight calculation based on strategy multipliers
                for (uint256 k = 0; k < strategies.length; k++) {
                    // For each strategy, get the appropriate weight component and apply the multiplier
                    uint256 strategyWeight = allocatedStake[i][k];
                    
                    // Apply the strategy multiplier
                    totalWeight += (strategyWeight * strategyMultipliers[k]) / 1e18;
                }
                
                // Ensure the weight fits within uint96
                require(totalWeight <= type(uint96).max, "Weight overflow");
                operatorInfo.weights[j] = uint96(totalWeight);
                
                // Add to the total weights for the operator set
                operatorSetInfo.totalWeights[j] += uint96(totalWeight);
            }
            
            // Add the operator's pubkey to the aggregate pubkey
            operatorSetInfo.aggregatePubkey = BN254.plus(
                operatorSetInfo.aggregatePubkey, 
                operatorInfo.pubkey
            );
            
            // Hash the operator info for the merkle tree
            hashedOperatorInfos[i] = hashOperatorInfo(operatorInfo);
        }
        
        // Build the merkle tree and set the root
        operatorSetInfo.operatorInfoTreeRoot = MerkleTreeLib.merkleRoot(hashedOperatorInfos);
        
        return operatorSetInfo;
    }
    
    /**
     * @notice Gets the operator info for a specific operator in the set
     * @param operatorSet The operator set to query
     * @param operatorIndex The index of the operator in the set
     * @return The operator information including pubkey and weights
     */
    function getOperatorInfo(OperatorSet calldata operatorSet, uint32 operatorIndex)
        external view returns(BN254OperatorInfo memory)
    {
        // Get all operators registered to this operator set
        address[] memory operators = allocationManager.getMembers(operatorSet);
        
        require(operatorIndex < operators.length, "Invalid operator index");
        
        // Get the operator address at the specified index
        address operator = operators[operatorIndex];
        
        // Get operator's stake allocations
        address[] memory operatorArray = new address[](1);
        operatorArray[0] = operator;
        uint256[][] memory allocatedStake = allocationManager.getAllocatedStake(
            operatorSet,
            operatorArray,
            strategies
        );
        
        // Create and populate the operator info
        BN254OperatorInfo memory operatorInfo = BN254OperatorInfo({
            pubkey: operatorToPubkey[operator],
            weights: new uint96[](numWeightTypes)
        });
        
        // Calculate weights based on strategy multipliers
        for (uint256 j = 0; j < numWeightTypes; j++) {
            uint256 totalWeight = 0;
            
            // Apply the appropriate weight calculation based on strategy multipliers
            for (uint256 k = 0; k < strategies.length; k++) {
                // For each strategy, get the appropriate weight component and apply the multiplier
                uint256 strategyWeight = allocatedStake[0][k];
                
                // Apply the strategy multiplier
                totalWeight += (strategyWeight * strategyMultipliers[k]) / 1e18;
            }
            
            // Ensure the weight fits within uint96
            require(totalWeight <= type(uint96).max, "Weight overflow");
            operatorInfo.weights[j] = uint96(totalWeight);
        }
        
        return operatorInfo;
    }
    
    /**
     * @notice Gets the merkle proof for an operator
     * @param operatorSet The operator set to query
     * @param operatorIndex The index of the operator in the set
     * @return The merkle proof for the operator
     */
    function getOperatorProof(OperatorSet calldata operatorSet, uint32 operatorIndex)
        external view returns(bytes memory)
    {
        // Get all operators registered to this operator set
        address[] memory operators = allocationManager.getMembers(operatorSet);
        
        require(operatorIndex < operators.length, "Invalid operator index");
        
        // Calculate all operator infos and their hashes
        bytes32[] memory hashedOperatorInfos = new bytes32[](operators.length);
        
        // Get all allocated stake for all operators and all strategies
        uint256[][] memory allocatedStake = allocationManager.getAllocatedStake(
            operatorSet,
            operators,
            strategies
        );
        
        // For each operator, calculate their weights and hash their info
        for (uint256 i = 0; i < operators.length; i++) {
            BN254OperatorInfo memory operatorInfo = BN254OperatorInfo({
                pubkey: operatorToPubkey[operators[i]],
                weights: new uint96[](numWeightTypes)
            });
            
            // Calculate weights based on strategy multipliers
            for (uint256 j = 0; j < numWeightTypes; j++) {
                uint256 totalWeight = 0;
                
                // Apply the appropriate weight calculation based on strategy multipliers
                for (uint256 k = 0; k < strategies.length; k++) {
                    // For each strategy, get the appropriate weight component and apply the multiplier
                    uint256 strategyWeight = allocatedStake[i][k];
                    
                    // Apply the strategy multiplier
                    totalWeight += (strategyWeight * strategyMultipliers[k]) / 1e18;
                }
                
                // Ensure the weight fits within uint96
                require(totalWeight <= type(uint96).max, "Weight overflow");
                operatorInfo.weights[j] = uint96(totalWeight);
            }
            
            // Hash the operator info for the merkle tree
            hashedOperatorInfos[i] = hashOperatorInfo(operatorInfo);
        }
        
        // Generate and return the merkle proof
        return MerkleTreeLib.getProof(hashedOperatorInfos, operatorIndex);
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
}
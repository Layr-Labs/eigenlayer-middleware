// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IBLSTableCalculator} from "../interfaces/IBLSTableCalculator.sol";

import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {IBLSApkRegistry} from "../interfaces/IBLSApkRegistry.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

import {BN254} from "../libraries/BN254.sol";

/// @notice A contract that calculates the operator table for a given operatorSet
abstract contract BLSTableCalculator is IBLSTableCalculator {

    /// @notice The BLS Aggregate Pubkey Registry contract that will keep track of operators' aggregate BLS public keys per quorum
    IBLSApkRegistry public immutable blsApkRegistry;

    constructor(IBLSApkRegistry _blsApkRegistry) {
        blsApkRegistry = _blsApkRegistry;
    }
    
    /// @inheritdoc IBLSTableCalculator
    function calculateOperatorTable(OperatorSet calldata operatorSet) external view returns (BN254OperatorSetInfo memory operatorSetInfo) {
        validateOperatorSet(operatorSet);

        // Get the weights for all operators in the operatorSet
        (address[] memory operators, uint96[][] memory weights) = getOperatorWeights(operatorSet);

        // Collate weights into a single array of total weights by
        // 1. Getting the length of each sub-array
        // 2. Iterating through each sub-array and summing the weights
        uint256 subArrayLength = weights[0].length;
        uint96[] memory totalWeights = new uint96[](subArrayLength);

        for (uint256 i = 0; i < weights.length; i++) {
            for (uint256 j = 0; j < subArrayLength; j++) {
                totalWeights[j] += weights[i][j];
            }
        }
        
        return BN254OperatorSetInfo({
            numOperators: operators.length,
            aggregatePubkey: blsApkRegistry.getApk(uint8(operatorSet.id)),
            totalWeights: totalWeights
        });
    }

    /// @inheritdoc IBLSTableCalculator
    function getOperatorInfos(OperatorSet calldata operatorSet) external view returns (BN254OperatorInfo[] memory) {
        // Get the weights for all operators
        (address[] memory operators, uint96[][] memory weights) = getOperatorWeights(operatorSet);

        BN254OperatorInfo[] memory operatorInfos = new BN254OperatorInfo[](operators.length);

        for (uint256 i = 0; i < operators.length; i++) {
            (BN254.G1Point memory pubkey,) = blsApkRegistry.getRegisteredPubkey(operators[i]);
            operatorInfos[i] = BN254OperatorInfo({
                pubkey: pubkey,
                weights: weights[i]
            });
        }

        return operatorInfos;
    }

    /// @dev This function must be implemented by an `IOperatorWeightCalculator`
    function getOperatorWeights(OperatorSet calldata operatorSet) public view virtual returns (address[] memory operators, uint96[][] memory weights);

    /// @dev This function can be used to validate that an operatorSet exists
    /// @dev This function is dependent on whether the AVS interacts with the `AllocationManager` or `AVSDirectory`
    function validateOperatorSet(OperatorSet calldata operatorSet) public view virtual returns (bool);
}
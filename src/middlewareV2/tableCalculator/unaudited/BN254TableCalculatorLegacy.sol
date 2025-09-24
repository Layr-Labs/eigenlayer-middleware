// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IOperatorTableCalculator} from
    "eigenlayer-contracts/src/contracts/interfaces/IOperatorTableCalculator.sol";
import {Merkle} from "eigenlayer-contracts/src/contracts/libraries/Merkle.sol";
import {BN254} from "eigenlayer-contracts/src/contracts/libraries/BN254.sol";
import {LeafCalculatorMixin} from
    "eigenlayer-contracts/src/contracts/mixins/LeafCalculatorMixin.sol";
import {IBN254TableCalculator} from "../../../interfaces/IBN254TableCalculator.sol";

import {IBLSApkRegistry} from "../../../interfaces/IBLSAPKRegistry.sol";
import {IStakeRegistry} from "../../../interfaces/IStakeRegistry.sol";
import {IIndexRegistry, IIndexRegistryTypes} from "../../../interfaces/IIndexRegistry.sol";

/**
 * @title BN254TableCalculatorLegacy
 * @notice BN254 table calculator that works with the middlewareV1 architecture
 * @dev Extends the basic table calculator to work with the middlewareV1 architecture. Specifically we use:
 *      - `BLSAPKRegistry` for key introspection
 *      - `StakeRegistry` for quorum membership
 * @dev We use `operatorSet` everywhere instead of `quorumNumber`. We have to do this in order
 *      to be compliant with the table calculator interface. Developers should use the
 *      `quorumNumber` as the `id` of the `operatorSet`
 * // TODO: update all natspec. Maybe look into making the key getters in the base contract abstract?
 */
contract BN254TableCalculatorLegacy is IBN254TableCalculator, LeafCalculatorMixin {
    using Merkle for bytes32[];
    using BN254 for BN254.G1Point;

    // Immutables
    IBLSApkRegistry public immutable blsApkRegistry;
    IStakeRegistry public immutable stakeRegistry;
    IIndexRegistry public immutable indexRegistry;

    /**
     * @notice Constructor to initialize the BN254TableCalculatorBase
     * @param _blsApkRegistry The BLSAPKRegistry contract for key introspection
     * @param _stakeRegistry The StakeRegistry contract for stakes
     */
    constructor(
        IBLSApkRegistry _blsApkRegistry,
        IStakeRegistry _stakeRegistry,
        IIndexRegistry _indexRegistry
    ) {
        blsApkRegistry = _blsApkRegistry;
        stakeRegistry = _stakeRegistry;
        indexRegistry = _indexRegistry;
    }

    /// @inheritdoc IBN254TableCalculator
    function calculateOperatorTable(
        OperatorSet calldata operatorSet
    ) external view virtual returns (BN254OperatorSetInfo memory operatorSetInfo) {
        return _calculateOperatorTable(operatorSet);
    }

    /// @inheritdoc IOperatorTableCalculator
    function calculateOperatorTableBytes(
        OperatorSet calldata operatorSet
    ) external view virtual returns (bytes memory operatorTableBytes) {
        return abi.encode(_calculateOperatorTable(operatorSet));
    }

    /// @inheritdoc IOperatorTableCalculator
    function getOperatorSetWeights(
        OperatorSet calldata operatorSet
    ) external view virtual returns (address[] memory operators, uint256[][] memory weights) {
        return _getOperatorWeights(operatorSet);
    }

    /// @inheritdoc IOperatorTableCalculator
    function getOperatorWeights(
        OperatorSet calldata operatorSet,
        address operator
    ) external view virtual returns (uint256[] memory) {
        (address[] memory operators, uint256[][] memory weights) = _getOperatorWeights(operatorSet);

        // Find the index of the operator in the operators array
        for (uint256 i = 0; i < operators.length; i++) {
            if (operators[i] == operator) {
                return weights[i];
            }
        }

        return new uint256[](0);
    }

    /// @inheritdoc IBN254TableCalculator
    function getOperatorInfos(
        OperatorSet calldata operatorSet
    ) external view virtual returns (BN254OperatorInfo[] memory) {
        // Get the weights for all operators
        (address[] memory operators, uint256[][] memory weights) = _getOperatorWeights(operatorSet);

        BN254OperatorInfo[] memory operatorInfos = new BN254OperatorInfo[](operators.length);

        for (uint256 i = 0; i < operators.length; i++) {
            // Skip if the operator has not registered their key - we can check the operator's pubkeyHash
            if (blsApkRegistry.getOperatorId(operators[i]) == bytes32(0)) {
                continue;
            }

            // TODO: fix types
            (BN254.G1Point memory g1Point,) = blsApkRegistry.getRegisteredPubkey(operators[i]);

            operatorInfos[i] = BN254OperatorInfo({pubkey: g1Point, weights: weights[i]});
        }

        return operatorInfos;
    }

    /**
     * @notice Abstract function to get the operator weights for a given operatorSet
     * @param operatorSet The operatorSet to get the weights for
     * @return operators The addresses of the operators in the operatorSet
     * @return weights The weights for each operator in the operatorSet, this is a 2D array where the first index is the operator
     * and the second index is the type of weight
     * @dev Each single `weights` array is as a list of arbitrary stake types. For example,
     *      it can be [slashable_stake, delegated_stake, strategy_i_stake, ...]. Each stake type is an index in the array
     * @dev Must be implemented by derived contracts to define specific weight calculation logic
     * @dev The certificate verification assumes the composition weights array for each operator is the same.
     *      If the length of the array is different or the stake types are different, then verification issues can arise, including
     *      verification failing silently for multiple operators with different weights structures
     */
    /**
     * @notice Get operator weights with caps applied
     * @param operatorSet The operator set to calculate weights for
     * @return operators Array of operator addresses
     * @return weights Array of weights per operator
     */
    function _getOperatorWeights(
        OperatorSet calldata operatorSet
    ) internal view returns (address[] memory operators, uint256[][] memory weights) {
        // Get the latest operator list for the quorum
        // TODO: is it valid to get the latest quorum update here?
        IIndexRegistryTypes.QuorumUpdate memory latestQuorumUpdate = indexRegistry.getLatestQuorumUpdate(uint8(operatorSet.id));
        bytes32[] memory operatorIds = indexRegistry.getOperatorListAtBlockNumber(uint8(operatorSet.id), latestQuorumUpdate.fromBlockNumber);

        operators = new address[](operatorIds.length);
        weights = new uint256[][](operatorIds.length);
        uint256 operatorCount = 0;
        for (uint256 i = 0; i < operatorIds.length; ++i) {
            uint256 totalWeight = stakeRegistry.getCurrentStake(operatorIds[i], uint8(operatorSet.id));

            if (totalWeight > 0) {
                weights[operatorCount] = new uint256[](1);
                weights[operatorCount][0] = totalWeight;
                operators[operatorCount] = blsApkRegistry.getOperatorFromPubkeyHash(operatorIds[i]);
                operatorCount++;
            }
        }

        assembly {
            mstore(operators, operatorCount)
            mstore(weights, operatorCount)
        }

        return (operators, weights);
    }

    /**
     * @notice Calculates the operator table for a given operatorSet, also calculates the aggregate pubkey for the operatorSet
     * @param operatorSet The operatorSet to calculate the operator table for
     * @return operatorSetInfo The BN254OperatorSetInfo containing merkle root, operator count, aggregate pubkey, and total weights
     * @dev This function:
     * 1. Gets operator weights from the weight calculator
     * 2. Collates weights into total weights
     * 3. Creates a merkle tree of operator info
     *    - assumes that the operator has a registered BN254 key
     * 4. Calculates the aggregate public key
     * @dev Returns empty operator set info if no operators have registered keys or non-zero weights
     */
    function _calculateOperatorTable(
        OperatorSet calldata operatorSet
    ) internal view returns (BN254OperatorSetInfo memory operatorSetInfo) {
        // Get the weights for all operators in the operatorSet
        (address[] memory operators, uint256[][] memory weights) = _getOperatorWeights(operatorSet);

        // If there are no weights, return an empty operator set info
        if (weights.length == 0) {
            return BN254OperatorSetInfo({
                operatorInfoTreeRoot: bytes32(0),
                numOperators: 0,
                aggregatePubkey: BN254.G1Point(0, 0),
                totalWeights: new uint256[](0)
            });
        }

        // Initialize arrays
        uint256 subArrayLength = weights[0].length;
        uint256[] memory totalWeights = new uint256[](subArrayLength);
        bytes32[] memory operatorInfoLeaves = new bytes32[](operators.length);
        BN254.G1Point memory aggregatePubkey;
        uint256 operatorCount = 0;

        for (uint256 i = 0; i < operators.length; i++) {
            // Skip if the operator has not registered their key
            if (blsApkRegistry.getOperatorId(operators[i]) == bytes32(0)) { 
                continue;
            }

            // Read the weights for the operator and encode them into the operatorInfoLeaves
            // for all weights, add them to the total weights. The ith index returns the weights array for the ith operator
            for (uint256 j = 0; j < subArrayLength; j++) {
                totalWeights[j] += weights[i][j];
            }
            (BN254.G1Point memory g1Point,) = blsApkRegistry.getRegisteredPubkey(operators[i]);

            // Use `LeafCalculatorMixin` to calculate the leaf hash for the operator info
            operatorInfoLeaves[operatorCount] =
                calculateOperatorInfoLeaf(BN254OperatorInfo({pubkey: g1Point, weights: weights[i]}));

            // Add the operator's G1 point to the aggregate pubkey
            aggregatePubkey = aggregatePubkey.plus(g1Point);

            // Increment the operator count
            operatorCount++;
        }

        // If there are no operators, return an empty operator set info
        if (operatorCount == 0) {
            return BN254OperatorSetInfo({
                operatorInfoTreeRoot: bytes32(0),
                numOperators: 0,
                aggregatePubkey: BN254.G1Point(0, 0),
                totalWeights: new uint256[](0)
            });
        }

        // Resize the operatorInfoLeaves array to the number of operators and merkleize
        assembly {
            mstore(operatorInfoLeaves, operatorCount)
        }

        bytes32 operatorInfoTreeRoot = operatorInfoLeaves.merkleizeKeccak();

        return BN254OperatorSetInfo({
            operatorInfoTreeRoot: operatorInfoTreeRoot,
            numOperators: operatorCount,
            aggregatePubkey: aggregatePubkey,
            totalWeights: totalWeights
        });
    }
}
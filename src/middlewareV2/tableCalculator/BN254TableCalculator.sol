// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";

import "./BN254TableCalculatorBase.sol";

/**
 * @title BN254TableCalculator
 * @notice Implementation that calculates BN254 operator tables using the sum of the minimum slashable stake weights
 * @dev This contract assumes that slashable stake is valued the **same** across all strategies.
 */
contract BN254TableCalculator is BN254TableCalculatorBase {
    // Immutables
    /// @notice AllocationManager contract for managing operator allocations
    IAllocationManager public immutable allocationManager;
    /// @notice The default lookahead blocks for the slashable stake lookup
    uint256 public immutable LOOKAHEAD_BLOCKS;

    /**
     * @notice Constructor to initialize the BN254TableCalculator
     * @param _keyRegistrar The KeyRegistrar contract for managing operator BN254 keys
     * @param _allocationManager The AllocationManager contract for operator allocations and slashable stake
     * @param _LOOKAHEAD_BLOCKS The number of blocks to look ahead when calculating minimum slashable stake
     * @dev The lookahead blocks parameter helps ensure stake calculations account for future slashing events
     */
    constructor(
        IKeyRegistrar _keyRegistrar,
        IAllocationManager _allocationManager,
        uint256 _LOOKAHEAD_BLOCKS
    ) BN254TableCalculatorBase(_keyRegistrar) {
        allocationManager = _allocationManager;
        LOOKAHEAD_BLOCKS = _LOOKAHEAD_BLOCKS;
    }

    /**
     * @notice Get the operator weights for a given operatorSet based on the minimum slashable stake.
     * @param operatorSet The operatorSet to get the weights for
     * @return operators The addresses of the operators in the operatorSet with non-zero slashable stake
     * @return weights The weights for each operator in the operatorSet, this is a 2D array where the first index is the operator
     * and the second index is the type of weight. In this case its of length 1 and returns the slashable stake for the operatorSet.
     * @dev This implementation sums the minimum slashable stake across all strategies for each operator
     * @dev Only includes operators with non-zero total slashable stake to optimize gas usage
     * @dev The weights array contains only one element per operator representing their total slashable stake
     */
    function _getOperatorWeights(
        OperatorSet calldata operatorSet
    ) internal view override returns (address[] memory operators, uint256[][] memory weights) {
        // Get all operators & strategies in the operatorSet
        address[] memory registeredOperators = allocationManager.getMembers(operatorSet);
        IStrategy[] memory strategies = allocationManager.getStrategiesInOperatorSet(operatorSet);

        // Get the minimum slashable stake for each operator
        uint256[][] memory minSlashableStake = allocationManager.getMinimumSlashableStake({
            operatorSet: operatorSet,
            operators: registeredOperators,
            strategies: strategies,
            futureBlock: uint32(block.number + LOOKAHEAD_BLOCKS)
        });

        operators = new address[](registeredOperators.length);
        weights = new uint256[][](registeredOperators.length);
        uint256 operatorCount = 0;
        for (uint256 i = 0; i < registeredOperators.length; ++i) {
            // For the given operator, loop through the strategies and sum together to calculate the operator's weight for the operatorSet
            uint256 totalWeight;
            for (uint256 stratIndex = 0; stratIndex < strategies.length; ++stratIndex) {
                totalWeight += minSlashableStake[i][stratIndex];
            }

            // If the operator has nonzero slashable stake, add them to the operators array
            if (totalWeight > 0) {
                // Initialize operator weights array of length 1 just for slashable stake
                weights[operatorCount] = new uint256[](1);
                weights[operatorCount][0] = totalWeight;

                // Add the operator to the operators array
                operators[operatorCount] = registeredOperators[i];
                operatorCount++;
            }
        }

        // Resize arrays to be the size of the number of operators with nonzero slashable stake
        assembly {
            mstore(operators, operatorCount)
            mstore(weights, operatorCount)
        }

        return (operators, weights);
    }
}

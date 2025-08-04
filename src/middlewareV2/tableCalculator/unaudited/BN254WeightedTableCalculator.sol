// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {PermissionControllerMixin} from
    "eigenlayer-contracts/src/contracts/mixins/PermissionControllerMixin.sol";

import "../BN254TableCalculatorBase.sol";

/**
 * @title BN254WeightedTableCalculator
 * @notice Implementation that calculates BN254 operator tables using custom multipliers for different strategies
 * @dev This contract allows AVSs to set custom multipliers for each strategy instead of weighting all strategies equally.
 */
contract BN254WeightedTableCalculator is BN254TableCalculatorBase, PermissionControllerMixin {
    // Constants
    /// @notice Default multiplier in basis points (10000 = 1x)
    uint256 public constant DEFAULT_STRATEGY_MULTIPLIER = 10000;

    // Immutables
    /// @notice AllocationManager contract for managing operator allocations
    IAllocationManager public immutable allocationManager;
    /// @notice The default lookahead blocks for the slashable stake lookup
    uint256 public immutable LOOKAHEAD_BLOCKS;

    // Storage
    /// @notice Mapping from operatorSet hash to strategy to multiplier (in basis points, 10000 = 1x)
    mapping(bytes32 => mapping(IStrategy => uint256)) public strategyMultipliers;

    // Events
    /// @notice Emitted when strategy multipliers are updated for an operator set
    event StrategyMultipliersUpdated(
        OperatorSet indexed operatorSet, IStrategy[] strategies, uint256[] multipliers
    );

    // Errors
    error ArrayLengthMismatch();

    constructor(
        IKeyRegistrar _keyRegistrar,
        IAllocationManager _allocationManager,
        IPermissionController _permissionController,
        uint256 _LOOKAHEAD_BLOCKS
    ) BN254TableCalculatorBase(_keyRegistrar) PermissionControllerMixin(_permissionController) {
        allocationManager = _allocationManager;
        LOOKAHEAD_BLOCKS = _LOOKAHEAD_BLOCKS;
    }

    /**
     * @notice Set strategy multipliers for a given operator set
     * @param operatorSet The operator set to set multipliers for
     * @param strategies Array of strategies to set multipliers for
     * @param multipliers Array of multipliers in basis points (10000 = 1x)
     * @dev Only the AVS can set multipliers for their operator sets
     */
    function setStrategyMultipliers(
        OperatorSet calldata operatorSet,
        IStrategy[] calldata strategies,
        uint256[] calldata multipliers
    ) external checkCanCall(operatorSet.avs) {
        // Validate input arrays
        require(strategies.length == multipliers.length, ArrayLengthMismatch());

        bytes32 operatorSetKey = operatorSet.key();

        // Set multipliers for each strategy
        for (uint256 i = 0; i < strategies.length; i++) {
            strategyMultipliers[operatorSetKey][strategies[i]] = multipliers[i];
            strategyMultipliersSet[operatorSetKey][strategies[i]] = true;
        }

        emit StrategyMultipliersUpdated(operatorSet, strategies, multipliers);
    }

    // Storage to track which strategies have been explicitly set
    mapping(bytes32 => mapping(IStrategy => bool)) public strategyMultipliersSet;

    /**
     * @notice Get the strategy multiplier for a given operator set and strategy
     * @param operatorSet The operator set
     * @param strategy The strategy
     * @return multiplier The multiplier in basis points (returns 10000 if not set)
     */
    function getStrategyMultiplier(
        OperatorSet calldata operatorSet,
        IStrategy strategy
    ) external view returns (uint256 multiplier) {
        bytes32 operatorSetKey = operatorSet.key();
        if (strategyMultipliersSet[operatorSetKey][strategy]) {
            multiplier = strategyMultipliers[operatorSetKey][strategy];
        } else {
            multiplier = DEFAULT_STRATEGY_MULTIPLIER; // Default 1x multiplier
        }
    }

    /**
     * @notice Get the operator weights for a given operatorSet based on weighted slashable stake.
     * @param operatorSet The operatorSet to get the weights for
     * @return operators The addresses of the operators in the operatorSet
     * @return weights The weights for each operator in the operatorSet, this is a 2D array where the first index is the operator
     * and the second index is the type of weight. In this case its of length 1 and returns the weighted slashable stake for the operatorSet.
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

        bytes32 operatorSetKey = operatorSet.key();

        operators = new address[](registeredOperators.length);
        weights = new uint256[][](registeredOperators.length);
        uint256 operatorCount = 0;
        for (uint256 i = 0; i < registeredOperators.length; ++i) {
            // For the given operator, loop through the strategies and apply multipliers before summing
            uint256 totalWeight;
            for (uint256 stratIndex = 0; stratIndex < strategies.length; ++stratIndex) {
                uint256 stakeAmount = minSlashableStake[i][stratIndex];

                // Get the multiplier for this strategy (default to DEFAULT_STRATEGY_MULTIPLIER if not set)
                uint256 multiplier;
                if (strategyMultipliersSet[operatorSetKey][strategies[stratIndex]]) {
                    multiplier = strategyMultipliers[operatorSetKey][strategies[stratIndex]];
                } else {
                    multiplier = DEFAULT_STRATEGY_MULTIPLIER; // Default 1x multiplier
                }

                // Apply multiplier (divide by DEFAULT_STRATEGY_MULTIPLIER to convert from basis points)
                totalWeight += (stakeAmount * multiplier) / DEFAULT_STRATEGY_MULTIPLIER;
            }

            // If the operator has nonzero weighted stake, add them to the operators array
            if (totalWeight > 0) {
                // Initialize operator weights array of length 1 just for weighted slashable stake
                weights[operatorCount] = new uint256[](1);
                weights[operatorCount][0] = totalWeight;

                // Add the operator to the operators array
                operators[operatorCount] = registeredOperators[i];
                operatorCount++;
            }
        }

        // Resize arrays to be the size of the number of operators with nonzero weighted stake
        assembly {
            mstore(operators, operatorCount)
            mstore(weights, operatorCount)
        }

        return (operators, weights);
    }
}

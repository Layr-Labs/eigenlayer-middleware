// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import {IPermissionController} from "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {PermissionControllerMixin} from "eigenlayer-contracts/src/contracts/mixins/PermissionControllerMixin.sol";

import "./BN254TableCalculatorBase.sol";
import {WeightCapUtils} from "../../libraries/WeightCapUtils.sol";

/**
 * @title BN254TableCalculatorWithCaps
 * @notice BN254 table calculator with configurable weight caps
 * @dev Extends the basic table calculator to cap operator weights
 */
contract BN254TableCalculatorWithCaps is BN254TableCalculatorBase, PermissionControllerMixin {
    // Immutables
    /// @notice AllocationManager contract for managing operator allocations
    IAllocationManager public immutable allocationManager;
    /// @notice The default lookahead blocks for the slashable stake lookup
    uint256 public immutable LOOKAHEAD_BLOCKS;

    // Storage
    /// @notice Mapping from operatorSet hash to weight cap (0 = no cap)
    mapping(bytes32 => uint256) public weightCaps;

    // Events
    /// @notice Emitted when a weight cap is set for an operator set
    event WeightCapSet(OperatorSet indexed operatorSet, uint256 maxWeight);

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
     * @notice Set the weight cap for a given operator set
     * @param operatorSet The operator set to set the cap for
     * @param maxWeight Maximum allowed total weight per operator (0 = no cap)
     * @dev Only the AVS can set caps for their operator sets
     */
    function setWeightCap(OperatorSet calldata operatorSet, uint256 maxWeight) external checkCanCall(operatorSet.avs) {
        bytes32 operatorSetHash = keccak256(abi.encode(operatorSet.avs, operatorSet.id));
        weightCaps[operatorSetHash] = maxWeight;
        
        emit WeightCapSet(operatorSet, maxWeight);
    }

    /**
     * @notice Get the weight cap for a given operator set
     * @param operatorSet The operator set to get the cap for
     * @return maxWeight The maximum weight cap (0 = no cap)
     */
    function getWeightCap(OperatorSet calldata operatorSet) external view returns (uint256 maxWeight) {
        bytes32 operatorSetHash = keccak256(abi.encode(operatorSet.avs, operatorSet.id));
        return weightCaps[operatorSetHash];
    }

    /**
     * @notice Get operator weights with caps applied
     * @param operatorSet The operator set to calculate weights for
     * @return operators Array of operator addresses
     * @return weights Array of weights per operator
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
            uint256 totalWeight;
            for (uint256 stratIndex = 0; stratIndex < strategies.length; ++stratIndex) {
                totalWeight += minSlashableStake[i][stratIndex];
            }

            if (totalWeight > 0) {
                weights[operatorCount] = new uint256[](1);
                weights[operatorCount][0] = totalWeight;
                operators[operatorCount] = registeredOperators[i];
                operatorCount++;
            }
        }

        assembly {
            mstore(operators, operatorCount)
            mstore(weights, operatorCount)
        }

        // Apply weight caps if configured
        bytes32 operatorSetHash = keccak256(abi.encode(operatorSet.avs, operatorSet.id));
        uint256 maxWeight = weightCaps[operatorSetHash];
        
        if (maxWeight > 0) {
            (operators, weights) = WeightCapUtils.applyWeightCap(operators, weights, maxWeight);
        }

        return (operators, weights);
    }
} 
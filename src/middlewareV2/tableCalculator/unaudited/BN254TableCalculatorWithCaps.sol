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
import {WeightCapUtils} from "../../../unaudited/libraries/WeightCapUtils.sol";

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
    /// @notice Mapping from operatorSet key to weight caps per stake type (0 = no cap)
    /// @dev Index 0 represents the total weight cap for backwards compatibility
    mapping(bytes32 => uint256[]) public weightCaps;

    // Events
    /// @notice Emitted when weight caps are set for an operator set
    event WeightCapsSet(OperatorSet indexed operatorSet, uint256[] maxWeights);

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
     * @notice Set weight caps for a given operator set
     * @param operatorSet The operator set to set caps for
     * @param maxWeights Array of maximum allowed weights per stake type (0 = no cap)
     *                   Index 0 is the total weight cap for backwards compatibility
     * @dev Only the AVS can set caps for their operator sets
     */
    function setWeightCaps(
        OperatorSet calldata operatorSet,
        uint256[] calldata maxWeights
    ) external checkCanCall(operatorSet.avs) {
        require(maxWeights.length > 0, "BN254TableCalculatorWithCaps: empty weight caps array");

        bytes32 operatorSetKey = operatorSet.key();
        weightCaps[operatorSetKey] = maxWeights;

        emit WeightCapsSet(operatorSet, maxWeights);
    }

    /**
     * @notice Set the total weight cap for a given operator set (backwards compatibility)
     * @param operatorSet The operator set to set the cap for
     * @param maxWeight Maximum allowed total weight per operator (0 = no cap)
     * @dev Only the AVS can set caps for their operator sets
     */
    function setWeightCap(
        OperatorSet calldata operatorSet,
        uint256 maxWeight
    ) external checkCanCall(operatorSet.avs) {
        bytes32 operatorSetKey = operatorSet.key();
        uint256[] memory caps = new uint256[](1);
        caps[0] = maxWeight;
        weightCaps[operatorSetKey] = caps;

        emit WeightCapsSet(operatorSet, caps);
    }

    /**
     * @notice Get weight caps for a given operator set
     * @param operatorSet The operator set to get caps for
     * @return maxWeights Array of maximum weight caps per stake type (0 = no cap)
     */
    function getWeightCaps(
        OperatorSet calldata operatorSet
    ) external view returns (uint256[] memory maxWeights) {
        bytes32 operatorSetKey = operatorSet.key();
        return weightCaps[operatorSetKey];
    }

    /**
     * @notice Get the total weight cap for a given operator set (backwards compatibility)
     * @param operatorSet The operator set to get the cap for
     * @return maxWeight The maximum weight cap (0 = no cap)
     */
    function getWeightCap(
        OperatorSet calldata operatorSet
    ) external view returns (uint256 maxWeight) {
        bytes32 operatorSetKey = operatorSet.key();
        uint256[] storage caps = weightCaps[operatorSetKey];
        return caps.length > 0 ? caps[0] : 0;
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
        bytes32 operatorSetKey = operatorSet.key();
        uint256[] storage maxWeights = weightCaps[operatorSetKey];

        if (maxWeights.length > 0) {
            (operators, weights) = WeightCapUtils.applyWeightCaps(operators, weights, maxWeights);
        }

        return (operators, weights);
    }
}

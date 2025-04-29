// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IOperatorWeightCalculator} from "../../interfaces/IOperatorWeightCalculator.sol";
import {AllocationManager} from "eigenlayer-contracts/src/contracts/core/AllocationManager.sol";

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {OperatorSetLib} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

/// @title LinearSlashableStakeCalculator
/// @notice A contract that calculates the operator weights for a given operatorSet
/// @dev This contract assumes that all operator stakes are stored in the `AllocationManager`
contract LinearSlashableStakeCalculator is Ownable, IOperatorWeightCalculator {
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using OperatorSetLib for OperatorSet;

    error LookaheadBlocksTooHigh();

    /// @notice Constant used as a divisor in calculating weights.
    uint256 public constant WEIGHTING_DIVISOR = 1e18;

    /// @notice A struct that contains a strategy and a multiplier
    struct StrategyAndMultiplier {
        address strategy;
        uint96 multiplier;
    }

    /// @notice The multipliers for each strategy, per operatorSet
    mapping(bytes32 operatorSetKey => EnumerableMap.AddressToUintMap) internal _multipliers;

    /// @notice The lookahead blocks for the slashable stake calculation
    uint256 public lookaheadBlocks = 100_800;

    /// @notice Emitted when a strategy multiplier is set
    event StrategyMultiplierSet(address indexed strategy, uint96 multiplier);

    /// @notice Emitted when the lookahead blocks are set
    event LookaheadBlocksSet(uint256 lookaheadBlocks);

    /// @notice The allocation manager contract in core
    AllocationManager public immutable allocationManager;

    constructor(AllocationManager _allocationManager, address _owner) {
        allocationManager = _allocationManager;
        _transferOwnership(_owner);
    }

    /**
     * @notice Set the multipliers for each strategy
     * @param strategiesAndMultipliers The strategies and their multipliers
     */
    function setStrategyMultipliers(OperatorSet memory operatorSet, StrategyAndMultiplier[] memory strategiesAndMultipliers) external onlyOwner {
        // Validate the lengths of strategies and multipliers
        IStrategy[] memory strategies = allocationManager.getStrategiesInOperatorSet(operatorSet);
        require(strategies.length == strategiesAndMultipliers.length, "Incorrect length of strategyAndMultipliers");

        // Get the key for the operatorSet
        bytes32 operatorSetKey = operatorSet.key();

        for (uint256 i = 0; i < strategiesAndMultipliers.length; i++) {
            _multipliers[operatorSetKey].set(strategiesAndMultipliers[i].strategy, strategiesAndMultipliers[i].multiplier);
            emit StrategyMultiplierSet(strategiesAndMultipliers[i].strategy, strategiesAndMultipliers[i].multiplier);
        }
    }

    /**
     * @notice Set the lookahead blocks for the slashable stake calculation
     * @param _lookaheadBlocks The lookahead blocks to set
     */
    function setLookaheadBlocks(uint256 _lookaheadBlocks) external onlyOwner {
        require(_lookaheadBlocks < allocationManager.DEALLOCATION_DELAY(), LookaheadBlocksTooHigh());
        lookaheadBlocks = _lookaheadBlocks;
        emit LookaheadBlocksSet(_lookaheadBlocks);
    }

    /**
     * @notice Get the operator weights for a given operatorSet based on the slashable stake
     * @param operatorSet The operatorSet to get the weights for
     * @return operators The addresses of the operators in the operatorSet
     * @return weights The weights for each operator in the operatorSet
     */
    function getOperatorWeights(OperatorSet calldata operatorSet) public virtual view override returns (address[] memory operators, uint96[][] memory weights) {
        // Get all operators & strategies in the operatorSet
        operators = allocationManager.getMembers(operatorSet);
        IStrategy[] memory strategies = allocationManager.getStrategiesInOperatorSet(operatorSet);


        // Get the minimum slashable stake for each operator
        uint256[][] memory minSlashableStake = allocationManager.getMinimumSlashableStake({
            operatorSet: operatorSet,
            operators: operators,
            strategies: strategies,
            futureBlock: uint32(block.number + lookaheadBlocks)
        });

        // Cache the operatorSetKey and enumerate map for weights
        bytes32 operatorSetKey = operatorSet.key();
        EnumerableMap.AddressToUintMap storage multipliers = _multipliers[operatorSetKey];

        weights = new uint96[][](operators.length);
        for (uint256 operatorIndex = 0; operatorIndex < operators.length; operatorIndex++) {
            weights[operatorIndex] = new uint96[](strategies.length);
            // 1. For the given operator, loop through the strategies and calculate the operator's weight for the opereatorSet
            for (uint256 stratIndex = 0; stratIndex < strategies.length; stratIndex++) {
                // Update the weight for the operator and strategy, only if there's a nonzero minimum slashable stake
                if (minSlashableStake[operatorIndex][stratIndex] > 0) {
                    // Get the multiplier for the strategy
                    (bool exists, uint256 value) = multipliers.tryGet(address(strategies[stratIndex]));
                    uint96 multiplier = exists ? uint96(value) : 0;

                    // We're only returning the weights of slashable stake in this calculator, hence the 0 index
                    weights[operatorIndex][0] += uint96(minSlashableStake[operatorIndex][stratIndex] * multiplier / WEIGHTING_DIVISOR);
                }
            }
        }
        
        return (operators, weights);
    }
}


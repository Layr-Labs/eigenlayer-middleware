// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet} from "lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAllocationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

struct ECDSAOperatorInfo {
    address pubkey;
    uint96[] weights;
}

interface IECDSAOperatorTableCalculator {
    /**
     * @notice calculates the operatorInfos for a given operatorSet
     * @param operatorSet the operatorSet to calculate the operator table for
     * @return operatorInfos the list of operatorInfos
     */
    function calculateOperatorTable(OperatorSet calldata operatorSet) 
        external view returns(ECDSAOperatorInfo[] memory operatorInfos);
}

/**
 * @title ECDSAOperatorTableCalculator
 * @notice Calculates operator tables for ECDSA signatures
 * @dev Returns all operators in the order returned by the AllocationManager along with 
 * weights calculated using the configured strategy multipliers
 */
contract ECDSAOperatorTableCalculator is IECDSAOperatorTableCalculator {
    /// @notice The AllocationManager contract from EigenLayer core
    IAllocationManager public immutable allocationManager;

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
     * @notice Calculates the operator table for a given operatorSet
     * @param operatorSet The operatorSet to calculate the operator table for
     * @return operatorInfos The list of operator infos including pubkeys and weights
     */
    function calculateOperatorTable(OperatorSet calldata operatorSet) 
        external view returns(ECDSAOperatorInfo[] memory operatorInfos) 
    {
        // Get all operators registered to this operator set
        address[] memory operators = allocationManager.getMembers(operatorSet);
        
        // Create the operator infos array
        operatorInfos = new ECDSAOperatorInfo[](operators.length);
        
        // Get all allocated stake for all operators and all strategies
        uint256[][] memory allocatedStake = allocationManager.getAllocatedStake(
            operatorSet,
            operators,
            strategies
        );
        
        // For each operator, calculate their weights
        for (uint256 i = 0; i < operators.length; i++) {
            ECDSAOperatorInfo memory operatorInfo = ECDSAOperatorInfo({
                pubkey: operators[i],
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
            
            operatorInfos[i] = operatorInfo;
        }
        
        return operatorInfos;
    }
}
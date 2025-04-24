// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {BLSTableCalculator} from "../BLSTableCalculator.sol";
import {LinearSlashableStakeCalculator} from "../stakeCalculators/LinearSlashableStakeCalculator.sol";

import {IBLSTableCalculator} from "../../interfaces/IBLSTableCalculator.sol";

import {IStakeRegistry} from "../../interfaces/IStakeRegistry.sol";
import {IBLSApkRegistry} from "../../interfaces/IBLSApkRegistry.sol";
import {AllocationManager} from "eigenlayer-contracts/src/contracts/core/AllocationManager.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

import {BN254} from "../../libraries/BN254.sol";

/// @notice A contract that calculates the operator table for a given operatorSet
/// @dev This contract assumes that all operator stakes are stored in the `AllocationManager`
/// @dev This contract calculates slashable operator stakes based on the `LinearSlashableStakeCalculator`
contract BLSLinearSlashableStakeCalculator is BLSTableCalculator, LinearSlashableStakeCalculator {
    constructor(IBLSApkRegistry _blsApkRegistry, AllocationManager _allocationManager, address _owner) 
        BLSTableCalculator(_blsApkRegistry)
        LinearSlashableStakeCalculator(_allocationManager, _owner)
    {}
    
    /**
     * @notice Validates that an operatorSet exists in the `AllocationManager`
     * @param operatorSet The operatorSet to validate
     * @return true if the operatorSet exists, false otherwise
     */
    function validateOperatorSet(OperatorSet calldata operatorSet) public virtual view override returns (bool) {
        return allocationManager.isOperatorSet(operatorSet);
    }

    ///@inheritdoc LinearSlashableStakeCalculator
    function getOperatorWeights(OperatorSet calldata operatorSet) public virtual view override(BLSTableCalculator, LinearSlashableStakeCalculator) returns (address[] memory operators, uint96[][] memory weights) {
        return LinearSlashableStakeCalculator.getOperatorWeights(operatorSet);
    }
}
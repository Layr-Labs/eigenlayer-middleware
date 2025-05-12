// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IOperatorWeightCalculator} from "./IOperatorWeightCalculator.sol";

/// @notice A base interface that calculates an operator table for a given operatorSet and returns its bytes representation
/// @notice This is a base interface that all curve table calculators (eg. BN254, ECDSA) must implement
/// @dev A single `OperatorTableCalculator` can be used for multiple operatorSets of an AVS
interface IOperatorTableCalculator {
    /// @notice Thrown when the operatorSet does not exist.
    error InvalidOperatorSet();

    /**
     * @notice Sets the operatorWeightCalculator for a given operatorSet
     * @param operatorSet The operatorSet to set the operatorWeightCalculator for
     * @param operatorWeightCalculator The operatorWeightCalculator to set for the given operatorSet
     * @dev This function is only callable by the owner of the contract
     */
    function setOperatorWeightCalculator(
        OperatorSet calldata operatorSet,
        IOperatorWeightCalculator operatorWeightCalculator
    ) external;

    /**
     * @notice calculates the operatorTableBytes for a given operatorSet
     * @param operatorSet the operatorSet to calculate the operatorTableBytes for
     * @return operatorTableBytes The operatorTable bytes
     */
    function calculateOperatorTableBytes(
        OperatorSet calldata operatorSet
    ) external view returns (bytes memory operatorTableBytes);

    /**
     * @notice For a given operatorSet, returns the operatorWeightCalculator
     * @param operatorSet The operatorSet to get the operatorWeightCalculator for
     * @return operatorWeightCalculator The operatorWeightCalculator for the given operatorSet
     * @dev This contract
     */
    function getOperatorWeightCalculator(
        OperatorSet calldata operatorSet
    ) external view returns (IOperatorWeightCalculator);
}

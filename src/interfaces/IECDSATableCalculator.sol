// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IOperatorTableCalculator} from "./IOperatorTableCalculator.sol";
import {IOperatorWeightCalculator} from "./IOperatorWeightCalculator.sol";

interface IECDSATableCalculatorErrors {
    /// @notice Thrown when the operatorSet does not exist in EigenLayer core.
    error InvalidOperatorSet();
}

interface IECDSATableCalculatorTypes {
    /// @notice Contains information about a single operator
    /// @param pubkey The public key of the operator.
    /// @param weights The weights of the operator for a single operatorSet.
    struct ECDSAOperatorInfo {
        address pubkey;
        uint96[] weights;
    }
}

interface IECDSATableCalculatorEvents is IECDSATableCalculatorTypes {}

interface IECDSATableCalculator is
    IOperatorTableCalculator,
    IOperatorWeightCalculator,
    IECDSATableCalculatorErrors,
    IECDSATableCalculatorEvents
{
    /**
     * @notice calculates the operatorInfos for a given operatorSet
     * @param operatorSet the operatorSet to calculate the operator table for
     * @return operatorInfos the operatorInfos for the given operatorSet
     */
    function calculateOperatorTable(
        OperatorSet calldata operatorSet
    ) external view returns (ECDSAOperatorInfo[] memory operatorInfos);

    /**
     * @notice Validates that the operatorSet exists
     * @param operatorSet the operatorSet to validate
     * @return true if the operatorSet exists, false otherwise
     */
    function validateOperatorSet(
        OperatorSet calldata operatorSet
    ) external view returns (bool);
}
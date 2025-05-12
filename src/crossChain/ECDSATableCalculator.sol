// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IECDSATableCalculator} from "../interfaces/IECDSATableCalculator.sol";
import {IOperatorTableCalculator} from "../interfaces/IOperatorTableCalculator.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

/// @notice A contract that calculates the operator table for a given operatorSet
abstract contract ECDSATableCalculator is IECDSATableCalculator {

    constructor(
    ) {
    }

    /// @inheritdoc IOperatorTableCalculator
    function calculateOperatorTableBytes(
        OperatorSet calldata operatorSet
    ) external view returns (bytes memory operatorTableBytes) {
        return abi.encode(calculateOperatorTable(operatorSet));
    }

    /// @inheritdoc IECDSATableCalculator
    function calculateOperatorTable(
        OperatorSet calldata operatorSet
    ) public view returns (ECDSAOperatorInfo[] memory operatorInfos) {
        validateOperatorSet(operatorSet);

        // Get the weights for all operators in the operatorSet
        (address[] memory operators, uint96[][] memory weights) = getOperatorWeights(operatorSet);

        operatorInfos = new ECDSAOperatorInfo[](operators.length);

        for (uint i = 0; i < operators.length; i++) {
            operatorInfos[i] = ECDSAOperatorInfo(operators[i], weights[i]);
        }

        return operatorInfos;
    }

    /// @dev This function must be implemented by an `IOperatorWeightCalculator`
    function getOperatorWeights(
        OperatorSet calldata operatorSet
    ) public view virtual returns (address[] memory operators, uint96[][] memory weights);

    /// @dev This function can be used to validate that an operatorSet exists
    /// @dev This function is dependent on whether the AVS interacts with the `AllocationManager` or `AVSDirectory`
    function validateOperatorSet(
        OperatorSet calldata operatorSet
    ) public view virtual returns (bool);
}

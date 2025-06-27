// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IOperatorTableCalculator, IOperatorTableCalculatorTypes} from "eigenlayer-contracts/src/contracts/interfaces/IOperatorTableCalculator.sol";

interface IBN254TableCalculator is IOperatorTableCalculator, IOperatorTableCalculatorTypes {
    /**
     * @notice calculates the operatorInfos for a given operatorSet
     * @param operatorSet the operatorSet to calculate the operator table for
     * @return operatorSetInfo the operatorSetInfo for the given operatorSet
     * @dev The output of this function is converted to bytes via the `calculateOperatorTableBytes` function
     */
    function calculateOperatorTable(
        OperatorSet calldata operatorSet
    ) external view returns (BN254OperatorSetInfo memory operatorSetInfo);

    /**
     * @notice Get the operatorInfos for a given operatorSet
     * @param operatorSet the operatorSet to get the operatorInfos for
     * @return operatorInfos the operatorInfos for the given operatorSet
     */
    function getOperatorInfos(
        OperatorSet calldata operatorSet
    ) external view returns (BN254OperatorInfo[] memory operatorInfos);
}
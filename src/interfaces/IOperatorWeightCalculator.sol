// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

interface IOperatorWeightCalculator {
    /**
     * @notice Get the weights for all operators in a given operatorSet
     * @param operatorSet The operatorSet to get the weights for
     * @return operators The addresses of the operators in the operatorSet
     * @return weights The weights for each operator in the operatorSet
     */
    function getOperatorWeights(
        OperatorSet calldata operatorSet
    ) external view returns (address[] memory operators, uint96[][] memory weights);
}

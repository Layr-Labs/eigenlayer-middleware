// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

interface IOperatorTableCalculator {
    /**
     * @notice calculates the operatorTableBytes for a given operatorSet
     * @param operatorSet the operatorSet to calculate the operatorTableBytes for
     * @return operatorTableBytes The operatorTable bytes
     */
    function calculateOperatorTableBytes(
        OperatorSet calldata operatorSet
    ) external view returns (bytes memory operatorTableBytes);
}

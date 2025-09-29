// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {
    IOperatorTableCalculator,
    IOperatorTableCalculatorTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IOperatorTableCalculator.sol";

interface IECDSATableCalculator is IOperatorTableCalculator, IOperatorTableCalculatorTypes {
    /**
     * @notice Calculates the ECDSA operator infos for a given operatorSet
     * @param operatorSet The operatorSet to calculate the operator table for
     * @return operatorInfos The array of ECDSAOperatorInfo structs containing ECDSA addresses and weights for registered operators
     * @dev The output of this function is used by the multichain protocol to transport operator stake weights to destination chains
     * @dev Only returns operators that have registered their ECDSA keys with the KeyRegistrar and have non-zero stake
     */
    function calculateOperatorTable(
        OperatorSet calldata operatorSet
    ) external view returns (ECDSAOperatorInfo[] memory operatorInfos);
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {
    IOperatorTableCalculator,
    IOperatorTableCalculatorTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IOperatorTableCalculator.sol";

interface IBN254TableCalculator is IOperatorTableCalculator, IOperatorTableCalculatorTypes {
    /**
     * @notice Calculates the BN254 operator table info for a given operatorSet
     * @param operatorSet The operatorSet to calculate the operator table for
     * @return operatorSetInfo The BN254OperatorSetInfo containing merkle root, aggregate pubkey, and total weights
     * @dev The output of this function is used by the multichain protocol to transport operator stake weights to destination chains
     * @dev This function aggregates operator weights, creates a merkle tree of operator info, and calculates the aggregate BN254 public key
     */
    function calculateOperatorTable(
        OperatorSet calldata operatorSet
    ) external view returns (BN254OperatorSetInfo memory operatorSetInfo);

    /**
     * @notice Get the individual operator infos for a given operatorSet
     * @param operatorSet The operatorSet to get the operatorInfos for
     * @return operatorInfos The array of BN254OperatorInfo structs containing pubkeys and weights for registered operators
     * @dev Only returns operators that have registered their BN254 keys with the KeyRegistrar
     */
    function getOperatorInfos(
        OperatorSet calldata operatorSet
    ) external view returns (BN254OperatorInfo[] memory operatorInfos);
}

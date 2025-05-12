// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {BN254} from "../libraries/BN254.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IOperatorTableCalculator} from "./IOperatorTableCalculator.sol";
import {IOperatorWeightCalculator} from "./IOperatorWeightCalculator.sol";

interface IBLSTableCalculatorErrors {
    /// @notice Thrown when the operatorSet does not exist in EigenLayer core.
    error InvalidOperatorSet();
}

interface IBLSTableCalculatorTypes {
    /// @notice Contains information about a single operator
    /// @param pubkey The G1 public key of the operator.
    /// @param weights The weights of the operator for a single operatorSet.
    struct BN254OperatorInfo {
        BN254.G1Point pubkey;
        uint96[] weights;
    }

    /// @notice Information about all operators for a given operatorSet
    /// @param operatorInfoTreeRoot The root of the operatorInfo tree.
    /// @param numOperators The number of operators in the operatorSet.
    /// @param aggregatePubkey The aggregate G1 public key of the operators in the operatorSet.
    /// @param totalWeights The total weights of the operators in the operatorSet.
    struct BN254OperatorSetInfo {
        bytes32 operatorInfoTreeRoot;
        uint256 numOperators;
        BN254.G1Point aggregatePubkey;
        uint96[] totalWeights;
    }
}

interface IBLSTableCalculatorEvents is IBLSTableCalculatorTypes {}

interface IBLSTableCalculator is
    IOperatorTableCalculator,
    IOperatorWeightCalculator,
    IBLSTableCalculatorErrors,
    IBLSTableCalculatorEvents
{
    /**
     * @notice calculates the operatorInfos for a given operatorSet
     * @param operatorSet the operatorSet to calculate the operator table for
     * @return operatorSetInfo the operatorSetInfo for the given operatorSet
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

    /**
     * @notice Validates that the operatorSet exists
     * @param operatorSet the operatorSet to validate
     * @return true if the operatorSet exists, false otherwise
     */
    function validateOperatorSet(
        OperatorSet calldata operatorSet
    ) external view returns (bool);
}

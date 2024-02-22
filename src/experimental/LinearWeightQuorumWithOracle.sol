// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {SimpleLinearWeightQuorum} from "./SimpleLinearWeightQuorum.sol";

interface IOperatorQualityOracle {
    function operatorQualityScore(address operator) external view returns (uint256);
}

abstract contract LinearWeightQuorumWithOracle is SimpleLinearWeightQuorum {
    
    // constants used to constrain the scale of weight modifications made by the `operatorQualityOracle`
    uint256 public constant MIN_OPERATOR_QUALITY_SCORE = 1e18;
    uint256 public constant MAX_OPERATOR_QUALITY_SCORE = 10e18;
    uint256 public constant OPERATOR_QUALITY_SCORE_DIVISOR = 1e18;

    // @notice OperatorQualityOracle used to modify operator weights
    IOperatorQualityOracle public operatorQualityOracle;

    // storage gap for upgradeability
    // slither-disable-next-line shadowing-state
    uint256[49] private __GAP;

    event OperatorQualityOracleSet(IOperatorQualityOracle previousOracle, IOperatorQualityOracle newOracle);

    constructor(
        IDelegationManager _delegationManager,
        IOperatorQualityOracle _operatorQualityOracle
    )
        SimpleLinearWeightQuorum(_delegationManager)
    {
        _setOperatorQualityOracle(_operatorQualityOracle);
    }

    /*******************************************************************************
                    EXTERNAL FUNCTIONS -- permissioned
    *******************************************************************************/
    function setOperatorQualityOracle(IOperatorQualityOracle newOracle) public virtual onlyOwner {
        _setOperatorQualityOracle(newOracle);
    }

    /*******************************************************************************
                            INTERNAL FUNCTIONS
    *******************************************************************************/
    function _setOperatorQualityOracle(IOperatorQualityOracle newOracle) internal {
        emit OperatorQualityOracleSet(operatorQualityOracle, newOracle);
        operatorQualityOracle = newOracle;
    }

    /*******************************************************************************
                            VIEW FUNCTIONS
    *******************************************************************************/
    /**
     * @notice This function computes the total weight of the @param operator.
     * @return `uint256` The weighted sum of the operator's shares across each strategy considered
     */
    function weightOfOperator(address operator) public virtual override view returns (uint256) {
        uint256 weight = SimpleLinearWeightQuorum.weightOfOperator(operator);
        uint256 operatorQualityScore = operatorQualityOracle.operatorQualityScore(operator);

        if (operatorQualityScore < MIN_OPERATOR_QUALITY_SCORE) {
            operatorQualityScore = MIN_OPERATOR_QUALITY_SCORE;
        } else if (operatorQualityScore > MAX_OPERATOR_QUALITY_SCORE) {
            operatorQualityScore = MAX_OPERATOR_QUALITY_SCORE;
        }

        weight = (weight * operatorQualityScore) / OPERATOR_QUALITY_SCORE_DIVISOR;

        return weight;
    }
}
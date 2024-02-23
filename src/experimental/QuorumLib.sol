// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IOperatorQualityOracle} from "./IOperatorQualityOracle.sol";

/**
 * @notice Stateless, library-tized version of `SimpleLinearWeightQuorum` and `LinearWeightQuorumWithOracle`
 * @dev note that the `quorum` object is passed as a storage reference, to avoid excessive memory-copying.
 */
// TODO: there may be a more elegant or efficient way to pass the quorum in memory rather than as a storage reference
// likely this means just passing a memory pointer/reference instead of using Solidity's default behavior.
library QuorumLib {
    
    /// @notice Constant used as a divisor in calculating weights.
    uint256 constant WEIGHTING_DIVISOR = 1e18;

    // constants used to constrain the scale of weight modifications made by an `operatorQualityOracle`
    uint256 constant MIN_OPERATOR_QUALITY_SCORE = 1e18;
    uint256 constant MAX_OPERATOR_QUALITY_SCORE = 10e18;
    uint256 constant OPERATOR_QUALITY_SCORE_DIVISOR = 1e18;

    /**
     * @notice In weighing a particular strategy, the amount of delegated shares for that strategy is
     * multiplied by its weight, then divided by WEIGHTING_DIVISOR
     */
    struct Quorum {
        IStrategy[] strategies;
        uint256[] weights;
    }

    /**
     * @notice This function computes the total weight of the @param operator.
     * @return `uint256` The weighted sum of the operator's shares across each strategy considered
     */
    function linearWeightOfOperator(
        IDelegationManager delegationManager,
        Quorum storage quorum,
        address operator
    ) internal view returns (uint256) {
        uint256[] memory sharesAmounts = delegationManager.getOperatorShares(operator, quorum.strategies);

        uint256 weight = 0;
        for (uint256 i = 0; i < sharesAmounts.length; i++) {
            // add the weight from the shares for this strategy to the total weight
            if (sharesAmounts[i] > 0) {
                weight += (sharesAmounts[i] * quorum.weights[i]) / WEIGHTING_DIVISOR;
            }
        }
        return weight;
    }

    function oracleAdjustedLinearWeightOfOperator(
        IDelegationManager delegationManager,
        Quorum storage quorum,
        address operator,
        IOperatorQualityOracle operatorQualityOracle
    ) internal view returns (uint256) {
        uint256 weight = linearWeightOfOperator(delegationManager, quorum, operator);
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

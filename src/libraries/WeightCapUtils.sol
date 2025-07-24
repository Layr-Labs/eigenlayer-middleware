// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

/**
 * @title WeightCapUtils
 * @notice Utility library for applying weight caps to operator weights
 */
library WeightCapUtils {
    /**
     * @notice Apply weight caps to operator weights
     * @param operators Array of operator addresses
     * @param weights 2D array of weights for each operator
     * @param maxWeight Maximum allowed total weight per operator (0 = no cap)
     * @return cappedOperators Array of operators after filtering
     * @return cappedWeights Array of weights after applying caps
     * @dev Caps total weight at maxWeight, filters out zero-weight operators
     */
    function applyWeightCap(
        address[] memory operators,
        uint256[][] memory weights,
        uint256 maxWeight
    ) internal pure returns (address[] memory cappedOperators, uint256[][] memory cappedWeights) {
        require(operators.length == weights.length, "WeightCapUtils: length mismatch");

        if (maxWeight == 0 || operators.length == 0) {
            return (operators, weights);
        }

        // Count operators with non-zero weights
        uint256 validOperatorCount = 0;
        bool[] memory isValid = new bool[](operators.length);

        for (uint256 i = 0; i < operators.length; i++) {
            uint256 totalWeight = 0;
            for (uint256 j = 0; j < weights[i].length; j++) {
                totalWeight += weights[i][j];
            }

            if (totalWeight > 0) {
                isValid[i] = true;
                validOperatorCount++;
            }
        }

        // Initialize result arrays
        cappedOperators = new address[](validOperatorCount);
        cappedWeights = new uint256[][](validOperatorCount);

        uint256 resultIndex = 0;
        for (uint256 i = 0; i < operators.length; i++) {
            if (!isValid[i]) continue;

            uint256 totalWeight = 0;
            for (uint256 j = 0; j < weights[i].length; j++) {
                totalWeight += weights[i][j];
            }

            cappedOperators[resultIndex] = operators[i];
            cappedWeights[resultIndex] = new uint256[](weights[i].length);

            if (totalWeight <= maxWeight) {
                for (uint256 j = 0; j < weights[i].length; j++) {
                    cappedWeights[resultIndex][j] = weights[i][j];
                }
            } else {
                // Cap at maxWeight, zero out additional weight types
                cappedWeights[resultIndex][0] = maxWeight;
                for (uint256 j = 1; j < weights[i].length; j++) {
                    cappedWeights[resultIndex][j] = 0;
                }
            }

            resultIndex++;
        }
    }
}

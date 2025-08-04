// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

/**
 * @title WeightCapUtils
 * @notice Utility library for applying weight caps to operator weights
 */
library WeightCapUtils {
    /**
     * @notice Apply single weight cap to operator weights (backwards compatibility)
     * @param operators Array of operator addresses
     * @param weights 2D array of weights for each operator
     * @param maxWeight Maximum allowed total weight per operator (0 = no cap)
     * @return cappedOperators Array of operators after applying caps
     * @return cappedWeights Array of weights after applying caps
     */
    function applyWeightCap(
        address[] memory operators,
        uint256[][] memory weights,
        uint256 maxWeight
    ) internal pure returns (address[] memory cappedOperators, uint256[][] memory cappedWeights) {
        uint256[] memory maxWeights = new uint256[](1);
        maxWeights[0] = maxWeight;
        return applyWeightCaps(operators, weights, maxWeights);
    }
    /**
     * @notice Apply weight caps to operator weights
     * @param operators Array of operator addresses
     * @param weights 2D array of weights for each operator
     * @param maxWeights Array of maximum allowed weights per stake type (0 = no cap)
     *                   Index 0 is treated as total weight cap if array length is 1
     * @return cappedOperators Array of operators after filtering
     * @return cappedWeights Array of weights after applying caps
     * @dev For single cap: truncates to cap (first weight = cap, rest = 0) and filters zero-weight operators. For multi-cap: applies per-stake-type caps.
     */

    function applyWeightCaps(
        address[] memory operators,
        uint256[][] memory weights,
        uint256[] memory maxWeights
    ) internal pure returns (address[] memory cappedOperators, uint256[][] memory cappedWeights) {
        require(
            operators.length == weights.length, "WeightCapUtils: operators/weights length mismatch"
        );

        if (maxWeights.length == 0 || operators.length == 0) {
            return (operators, weights);
        }

        if (maxWeights.length == 1 && maxWeights[0] == 0) {
            return (operators, weights);
        }

        // Count operators with non-zero weights for filtering
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

        // Initialize result arrays with only valid operators
        cappedOperators = new address[](validOperatorCount);
        cappedWeights = new uint256[][](validOperatorCount);

        uint256 resultIndex = 0;
        for (uint256 i = 0; i < operators.length; i++) {
            if (!isValid[i]) continue;

            cappedOperators[resultIndex] = operators[i];
            cappedWeights[resultIndex] = new uint256[](weights[i].length);

            if (maxWeights.length == 1 && maxWeights[0] > 0) {
                // Legacy mode: single total weight cap with truncation behavior
                uint256 totalWeight = 0;
                for (uint256 j = 0; j < weights[i].length; j++) {
                    totalWeight += weights[i][j];
                }

                if (totalWeight <= maxWeights[0]) {
                    // No cap needed
                    for (uint256 j = 0; j < weights[i].length; j++) {
                        cappedWeights[resultIndex][j] = weights[i][j];
                    }
                } else {
                    // Cap with truncation: set first weight to cap, zero out rest
                    cappedWeights[resultIndex][0] = maxWeights[0];
                    for (uint256 j = 1; j < weights[i].length; j++) {
                        cappedWeights[resultIndex][j] = 0;
                    }
                }
            } else {
                // Per-stake-type caps
                for (uint256 j = 0; j < weights[i].length; j++) {
                    if (j < maxWeights.length && maxWeights[j] > 0) {
                        cappedWeights[resultIndex][j] =
                            weights[i][j] > maxWeights[j] ? maxWeights[j] : weights[i][j];
                    } else {
                        cappedWeights[resultIndex][j] = weights[i][j];
                    }
                }
            }

            resultIndex++;
        }
    }
}

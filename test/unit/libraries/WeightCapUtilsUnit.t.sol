// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {WeightCapUtils} from "../../../src/unaudited/libraries/WeightCapUtils.sol";

/**
 * @title WeightCapUtilsUnitTests
 * @notice Unit tests for WeightCapUtils library
 */
contract WeightCapUtilsUnitTests is Test {
    // Test addresses
    address public operator1 = address(0x1);
    address public operator2 = address(0x2);
    address public operator3 = address(0x3);

    function _createSingleWeights(
        uint256[] memory weights
    ) internal pure returns (uint256[][] memory) {
        uint256[][] memory result = new uint256[][](weights.length);
        for (uint256 i = 0; i < weights.length; i++) {
            result[i] = new uint256[](1);
            result[i][0] = weights[i];
        }
        return result;
    }

    function _extractTotalWeights(
        uint256[][] memory weights
    ) internal pure returns (uint256[] memory) {
        uint256[] memory totals = new uint256[](weights.length);
        for (uint256 i = 0; i < weights.length; i++) {
            for (uint256 j = 0; j < weights[i].length; j++) {
                totals[i] += weights[i][j];
            }
        }
        return totals;
    }

    function test_applyWeightCap_noCap() public {
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        uint256[] memory weights = new uint256[](2);
        weights[0] = 100 ether;
        weights[1] = 200 ether;

        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            WeightCapUtils.applyWeightCap(operators, _createSingleWeights(weights), 0);

        // Should be unchanged with no cap
        assertEq(resultOperators.length, 2);
        assertEq(resultOperators[0], operator1);
        assertEq(resultOperators[1], operator2);

        uint256[] memory resultTotals = _extractTotalWeights(resultWeights);
        assertEq(resultTotals[0], 100 ether);
        assertEq(resultTotals[1], 200 ether);
    }

    function test_applyWeightCap_someOperatorsCapped() public {
        address[] memory operators = new address[](3);
        operators[0] = operator1;
        operators[1] = operator2;
        operators[2] = operator3;

        uint256[] memory weights = new uint256[](3);
        weights[0] = 50 ether; // Under cap
        weights[1] = 150 ether; // Over cap
        weights[2] = 200 ether; // Over cap

        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            WeightCapUtils.applyWeightCap(operators, _createSingleWeights(weights), 100 ether);

        assertEq(resultOperators.length, 3);
        assertEq(resultOperators[0], operator1);
        assertEq(resultOperators[1], operator2);
        assertEq(resultOperators[2], operator3);
        uint256[] memory resultTotals = _extractTotalWeights(resultWeights);
        assertEq(resultTotals[0], 50 ether); // Unchanged (under cap)
        assertEq(resultTotals[1], 100 ether); // Capped from 150
        assertEq(resultTotals[2], 100 ether); // Capped from 200
    }

    function test_applyWeightCap_allOperatorsUnderCap() public {
        address[] memory operators = new address[](3);
        operators[0] = operator1;
        operators[1] = operator2;
        operators[2] = operator3;

        uint256[] memory weights = new uint256[](3);
        weights[0] = 50 ether;
        weights[1] = 75 ether;
        weights[2] = 90 ether;

        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            WeightCapUtils.applyWeightCap(operators, _createSingleWeights(weights), 100 ether);

        assertEq(resultOperators.length, 3);

        uint256[] memory resultTotals = _extractTotalWeights(resultWeights);
        assertEq(resultTotals[0], 50 ether);
        assertEq(resultTotals[1], 75 ether);
        assertEq(resultTotals[2], 90 ether);
    }

    function test_applyWeightCap_zeroWeightOperatorsFiltered() public {
        address[] memory operators = new address[](4);
        operators[0] = operator1;
        operators[1] = operator2;
        operators[2] = operator3;
        operators[3] = address(0x4);

        uint256[] memory weights = new uint256[](4);
        weights[0] = 100 ether;
        weights[1] = 0; // Zero weight
        weights[2] = 150 ether;
        weights[3] = 0; // Zero weight

        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            WeightCapUtils.applyWeightCap(operators, _createSingleWeights(weights), 120 ether);

        // Only non-zero weight operators should remain
        assertEq(resultOperators.length, 2);
        assertEq(resultOperators[0], operator1);
        assertEq(resultOperators[1], operator3);

        uint256[] memory resultTotals = _extractTotalWeights(resultWeights);
        assertEq(resultTotals[0], 100 ether); // Under cap
        assertEq(resultTotals[1], 120 ether); // Capped from 150
    }

    function test_applyWeightCap_emptyOperators() public {
        address[] memory operators = new address[](0);
        uint256[][] memory weights = new uint256[][](0);

        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            WeightCapUtils.applyWeightCap(operators, weights, 100 ether);

        assertEq(resultOperators.length, 0);
        assertEq(resultWeights.length, 0);
    }

    function test_applyWeightCap_multiDimensionalWeights() public {
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        // Create 2D weights where each operator has 2 weight types
        uint256[][] memory weights = new uint256[][](2);
        weights[0] = new uint256[](2);
        weights[0][0] = 60 ether; // operator1: 60 + 40 = 100 total (at cap)
        weights[0][1] = 40 ether;
        weights[1] = new uint256[](2);
        weights[1][0] = 120 ether; // operator2: 120 + 80 = 200 total (over cap)
        weights[1][1] = 80 ether;

        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            WeightCapUtils.applyWeightCap(operators, weights, 100 ether);

        assertEq(resultOperators.length, 2);

        // operator1 should be unchanged (total = 100, exactly at cap)
        assertEq(resultWeights[0][0], 60 ether);
        assertEq(resultWeights[0][1], 40 ether);

        // operator2 should be capped: primary weight = 100, secondary = 0
        assertEq(resultWeights[1][0], 100 ether); // Capped to maxWeight
        assertEq(resultWeights[1][1], 0); // Zeroed out

        // Verify total weights
        uint256[] memory resultTotals = _extractTotalWeights(resultWeights);
        assertEq(resultTotals[0], 100 ether);
        assertEq(resultTotals[1], 100 ether);
    }

    function test_applyWeightCap_simpleTruncation() public {
        address[] memory operators = new address[](1);
        operators[0] = operator1;

        // Create weights that exceed the cap
        uint256[][] memory weights = new uint256[][](1);
        weights[0] = new uint256[](3);
        weights[0][0] = 300 ether; // Primary weight
        weights[0][1] = 200 ether; // Secondary weight
        weights[0][2] = 100 ether; // Tertiary weight
        // Total: 600 ether, should be capped to 150 ether

        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            WeightCapUtils.applyWeightCap(operators, weights, 150 ether);

        assertEq(resultOperators.length, 1);

        // Check simple truncation: primary weight = cap, others = 0
        assertEq(resultWeights[0][0], 150 ether); // Capped to maxWeight
        assertEq(resultWeights[0][1], 0); // Zeroed out
        assertEq(resultWeights[0][2], 0); // Zeroed out

        // Verify total
        uint256 total = resultWeights[0][0] + resultWeights[0][1] + resultWeights[0][2];
        assertEq(total, 150 ether);
    }
}

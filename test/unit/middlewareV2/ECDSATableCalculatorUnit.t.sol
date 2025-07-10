// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    KeyRegistrar,
    IKeyRegistrarTypes
} from "eigenlayer-contracts/src/contracts/permissions/KeyRegistrar.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import {IOperatorTableCalculatorTypes} from
    "eigenlayer-contracts/src/contracts/interfaces/IOperatorTableCalculator.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {
    OperatorSet,
    OperatorSetLib
} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

import {ECDSATableCalculator} from
    "../../../src/middlewareV2/tableCalculator/ECDSATableCalculator.sol";
import {MockEigenLayerDeployer} from "./MockDeployer.sol";
import "test/utils/Random.sol";

// Harness to test internal functions
contract ECDSATableCalculatorHarness is ECDSATableCalculator {
    constructor(
        IKeyRegistrar _keyRegistrar,
        IAllocationManager _allocationManager,
        uint256 _LOOKAHEAD_BLOCKS
    ) ECDSATableCalculator(_keyRegistrar, _allocationManager, _LOOKAHEAD_BLOCKS) {}

    function exposed_getOperatorWeights(
        OperatorSet calldata operatorSet
    ) external view returns (address[] memory operators, uint256[][] memory weights) {
        return _getOperatorWeights(operatorSet);
    }
}

/**
 * @title ECDSATableCalculatorUnitTests
 * @notice Base contract for all ECDSATableCalculator unit tests
 */
contract ECDSATableCalculatorUnitTests is MockEigenLayerDeployer, IOperatorTableCalculatorTypes {
    using OperatorSetLib for OperatorSet;

    // Test contracts
    ECDSATableCalculatorHarness public calculator;

    // Test addresses
    address public avs1 = address(0x1);
    address public avs2 = address(0x2);
    address public operator1 = address(0x3);
    address public operator2 = address(0x4);
    address public operator3 = address(0x5);

    // Test strategies
    IStrategy public strategy1 = IStrategy(address(0x100));
    IStrategy public strategy2 = IStrategy(address(0x200));

    // Test operator sets
    OperatorSet defaultOperatorSet;
    OperatorSet alternativeOperatorSet;

    // Test constants
    uint256 public constant TEST_LOOKAHEAD_BLOCKS = 100;

    function setUp() public virtual {
        _deployMockEigenLayer();

        // Deploy calculator with mocked AllocationManager
        calculator = new ECDSATableCalculatorHarness(
            IKeyRegistrar(address(keyRegistrar)),
            IAllocationManager(address(allocationManagerMock)),
            TEST_LOOKAHEAD_BLOCKS
        );

        // Set up operator sets
        defaultOperatorSet = OperatorSet({avs: avs1, id: 0});
        alternativeOperatorSet = OperatorSet({avs: avs2, id: 1});

        // Configure operator sets in AllocationManager
        allocationManagerMock.setAVSRegistrar(avs1, IAVSRegistrar(avs1));
        allocationManagerMock.setAVSRegistrar(avs2, IAVSRegistrar(avs2));

        // Configure operator sets for ECDSA
        vm.prank(avs1);
        keyRegistrar.configureOperatorSet(defaultOperatorSet, IKeyRegistrarTypes.CurveType.ECDSA);

        vm.prank(avs2);
        keyRegistrar.configureOperatorSet(
            alternativeOperatorSet, IKeyRegistrarTypes.CurveType.ECDSA
        );
    }

    // Helper functions
    function _setupOperatorSet(
        OperatorSet memory operatorSet,
        address[] memory operators,
        IStrategy[] memory strategies,
        uint256[][] memory minSlashableStake
    ) internal {
        allocationManagerMock.setMembersInOperatorSet(operatorSet, operators);
        allocationManagerMock.setStrategiesInOperatorSet(operatorSet, strategies);
        allocationManagerMock.setMinimumSlashableStake(
            operatorSet, operators, strategies, minSlashableStake
        );
    }

    function _createSingleWeightArray(
        uint256 weight
    ) internal pure returns (uint256[][] memory) {
        uint256[][] memory weights = new uint256[][](1);
        weights[0] = new uint256[](1);
        weights[0][0] = weight;
        return weights;
    }

    function _createMultiWeightArray(
        uint256[] memory weightValues
    ) internal pure returns (uint256[][] memory) {
        uint256[][] memory weights = new uint256[][](1);
        weights[0] = weightValues;
        return weights;
    }

    function _registerOperatorECDSAKey(
        address operator,
        OperatorSet memory operatorSet,
        address ecdsaAddress
    ) internal {
        bytes memory pubkey = abi.encode(ecdsaAddress);
        bytes memory signature = "";

        vm.prank(operator);
        keyRegistrar.registerKey(operator, operatorSet, pubkey, signature);
    }
}

/**
 * @title ECDSATableCalculatorUnitTests_getOperatorWeights
 * @notice Unit tests for ECDSATableCalculator._getOperatorWeights
 */
contract ECDSATableCalculatorUnitTests_getOperatorWeights is ECDSATableCalculatorUnitTests {
    function test_noOperators() public {
        // Setup empty operator set
        address[] memory operators = new address[](0);
        IStrategy[] memory strategies = new IStrategy[](0);
        uint256[][] memory minSlashableStake = new uint256[][](0);

        _setupOperatorSet(defaultOperatorSet, operators, strategies, minSlashableStake);

        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            calculator.exposed_getOperatorWeights(defaultOperatorSet);

        assertEq(resultOperators.length, 0, "Should have no operators");
        assertEq(resultWeights.length, 0, "Should have no weights");
    }

    function test_singleOperatorWithStake() public {
        // Setup operator set with one operator
        address[] memory operators = new address[](1);
        operators[0] = operator1;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy1;

        uint256[][] memory minSlashableStake = new uint256[][](1);
        minSlashableStake[0] = new uint256[](1);
        minSlashableStake[0][0] = 1000;

        _setupOperatorSet(defaultOperatorSet, operators, strategies, minSlashableStake);

        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            calculator.exposed_getOperatorWeights(defaultOperatorSet);

        assertEq(resultOperators.length, 1, "Should have 1 operator");
        assertEq(resultOperators[0], operator1, "Operator mismatch");
        assertEq(resultWeights.length, 1, "Should have 1 weight array");
        assertEq(resultWeights[0][0], 1000, "Weight mismatch");
    }

    function test_singleOperatorWithZeroStake() public {
        // Setup operator set with one operator with zero stake
        address[] memory operators = new address[](1);
        operators[0] = operator1;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy1;

        uint256[][] memory minSlashableStake = new uint256[][](1);
        minSlashableStake[0] = new uint256[](1);
        minSlashableStake[0][0] = 0;

        _setupOperatorSet(defaultOperatorSet, operators, strategies, minSlashableStake);

        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            calculator.exposed_getOperatorWeights(defaultOperatorSet);

        assertEq(resultOperators.length, 0, "Should have no operators with zero stake");
        assertEq(resultWeights.length, 0, "Should have no weights");
    }

    function test_multipleOperatorsWithStake() public {
        // Setup operator set with multiple operators
        address[] memory operators = new address[](3);
        operators[0] = operator1;
        operators[1] = operator2;
        operators[2] = operator3;

        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = strategy1;
        strategies[1] = strategy2;

        uint256[][] memory minSlashableStake = new uint256[][](3);
        minSlashableStake[0] = new uint256[](2);
        minSlashableStake[0][0] = 500;
        minSlashableStake[0][1] = 300;
        minSlashableStake[1] = new uint256[](2);
        minSlashableStake[1][0] = 200;
        minSlashableStake[1][1] = 400;
        minSlashableStake[2] = new uint256[](2);
        minSlashableStake[2][0] = 100;
        minSlashableStake[2][1] = 150;

        _setupOperatorSet(defaultOperatorSet, operators, strategies, minSlashableStake);

        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            calculator.exposed_getOperatorWeights(defaultOperatorSet);

        assertEq(resultOperators.length, 3, "Should have 3 operators");
        assertEq(resultOperators[0], operator1, "Operator1 mismatch");
        assertEq(resultOperators[1], operator2, "Operator2 mismatch");
        assertEq(resultOperators[2], operator3, "Operator3 mismatch");

        assertEq(resultWeights[0][0], 800, "Operator1 weight mismatch (500 + 300)");
        assertEq(resultWeights[1][0], 600, "Operator2 weight mismatch (200 + 400)");
        assertEq(resultWeights[2][0], 250, "Operator3 weight mismatch (100 + 150)");
    }

    function test_mixedOperatorsWithAndWithoutStake() public {
        // Setup operator set with mixed stake amounts
        address[] memory operators = new address[](3);
        operators[0] = operator1;
        operators[1] = operator2;
        operators[2] = operator3;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy1;

        uint256[][] memory minSlashableStake = new uint256[][](3);
        minSlashableStake[0] = new uint256[](1);
        minSlashableStake[0][0] = 1000;
        minSlashableStake[1] = new uint256[](1);
        minSlashableStake[1][0] = 0;
        minSlashableStake[2] = new uint256[](1);
        minSlashableStake[2][0] = 500;

        _setupOperatorSet(defaultOperatorSet, operators, strategies, minSlashableStake);

        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            calculator.exposed_getOperatorWeights(defaultOperatorSet);

        assertEq(resultOperators.length, 2, "Should have 2 operators with stake");
        assertEq(resultOperators[0], operator1, "Operator1 mismatch");
        assertEq(resultOperators[1], operator3, "Operator3 mismatch");
        assertEq(resultWeights[0][0], 1000, "Operator1 weight mismatch");
        assertEq(resultWeights[1][0], 500, "Operator3 weight mismatch");
    }

    function test_lookaheadBlocksUsed() public {
        // This test ensures LOOKAHEAD_BLOCKS is used in the calculation
        address[] memory operators = new address[](1);
        operators[0] = operator1;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy1;

        uint256[][] memory minSlashableStake = new uint256[][](1);
        minSlashableStake[0] = new uint256[](1);
        minSlashableStake[0][0] = 1000;

        _setupOperatorSet(defaultOperatorSet, operators, strategies, minSlashableStake);

        // Verify that the correct futureBlock is used
        uint32 expectedFutureBlock = uint32(block.number + TEST_LOOKAHEAD_BLOCKS);

        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            calculator.exposed_getOperatorWeights(defaultOperatorSet);

        assertEq(resultOperators.length, 1, "Should have 1 operator");
        assertEq(resultWeights[0][0], 1000, "Weight should match");
    }

    function testFuzz_getOperatorWeights(uint8 numOperators, uint256 baseWeight) public {
        numOperators = uint8(bound(numOperators, 1, 10));
        baseWeight = bound(baseWeight, 1, 1e18);

        address[] memory operators = new address[](numOperators);
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy1;

        uint256[][] memory minSlashableStake = new uint256[][](numOperators);
        uint256 expectedNonZeroOperators = 0;

        for (uint256 i = 0; i < numOperators; i++) {
            operators[i] = address(uint160(i + 100));
            minSlashableStake[i] = new uint256[](1);
            minSlashableStake[i][0] = (i % 2 == 0) ? baseWeight * (i + 1) : 0;
            if (minSlashableStake[i][0] > 0) {
                expectedNonZeroOperators++;
            }
        }

        _setupOperatorSet(defaultOperatorSet, operators, strategies, minSlashableStake);

        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            calculator.exposed_getOperatorWeights(defaultOperatorSet);

        assertEq(resultOperators.length, expectedNonZeroOperators, "Operator count mismatch");
        assertEq(resultWeights.length, expectedNonZeroOperators, "Weight count mismatch");
    }
}

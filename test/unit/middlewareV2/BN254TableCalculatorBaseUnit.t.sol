// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    KeyRegistrar,
    IKeyRegistrarTypes
} from "eigenlayer-contracts/src/contracts/permissions/KeyRegistrar.sol";
import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import {
    BN254,
    IOperatorTableCalculatorTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IOperatorTableCalculator.sol";
import {IBN254TableCalculator} from "../../../src/interfaces/IBN254TableCalculator.sol";
import {
    OperatorSet,
    OperatorSetLib
} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {BLSWallet, OperatorWalletLib} from "test/utils/OperatorWalletLib.sol";
import {BN254TableCalculatorBase} from
    "../../../src/middlewareV2/tableCalculator/BN254TableCalculatorBase.sol";
import {MockEigenLayerDeployer} from "./MockDeployer.sol";
import {Random} from "test/utils/Random.sol";
import {Merkle} from "eigenlayer-contracts/src/contracts/libraries/Merkle.sol";
import {LeafCalculatorMixin} from
    "eigenlayer-contracts/src/contracts/mixins/LeafCalculatorMixin.sol";

// Mock implementation for testing abstract contract
contract BN254TableCalculatorBaseHarness is BN254TableCalculatorBase {
    // Storage for mock weights
    mapping(bytes32 => address[]) internal _mockOperators;
    mapping(bytes32 => uint256[][]) internal _mockWeights;

    using Merkle for bytes32[];

    constructor(
        IKeyRegistrar _keyRegistrar
    ) BN254TableCalculatorBase(_keyRegistrar) {}

    function setMockOperatorWeights(
        OperatorSet calldata operatorSet,
        address[] memory operators,
        uint256[][] memory weights
    ) external {
        bytes32 key = operatorSet.key();
        _mockOperators[key] = operators;
        _mockWeights[key] = weights;
    }

    function _getOperatorWeights(
        OperatorSet calldata operatorSet
    ) internal view override returns (address[] memory operators, uint256[][] memory weights) {
        bytes32 key = operatorSet.key();
        operators = _mockOperators[key];
        weights = _mockWeights[key];
    }
}

/**
 * @title BN254TableCalculatorBaseUnitTests
 * @notice Base contract for all BN254TableCalculatorBase unit tests
 */
contract BN254TableCalculatorBaseUnitTests is
    MockEigenLayerDeployer,
    IOperatorTableCalculatorTypes,
    IKeyRegistrarTypes,
    LeafCalculatorMixin
{
    using BN254 for BN254.G1Point;
    using OperatorSetLib for OperatorSet;

    // Test contracts
    BN254TableCalculatorBaseHarness public calculator;

    // Test addresses
    address public avs1 = address(0x1);
    address public avs2 = address(0x2);
    address public operator1 = address(0x3);
    address public operator2 = address(0x4);
    address public operator3 = address(0x5);

    // Test operator sets
    OperatorSet defaultOperatorSet;
    OperatorSet alternativeOperatorSet;

    // BN254 test keys
    uint256 BN254_PRIV_KEY_1;
    uint256 BN254_PRIV_KEY_2;
    uint256 BN254_PRIV_KEY_3;

    BN254.G1Point bn254G1Key1;
    BN254.G1Point bn254G1Key2;
    BN254.G1Point bn254G1Key3;
    BN254.G2Point bn254G2Key1;
    BN254.G2Point bn254G2Key2;
    BN254.G2Point bn254G2Key3;

    function setUp() public virtual {
        _deployMockEigenLayer();

        // Deploy calculator with KeyRegistrar
        calculator = new BN254TableCalculatorBaseHarness(IKeyRegistrar(address(keyRegistrar)));

        // Set up operator sets
        defaultOperatorSet = OperatorSet({avs: avs1, id: 0});
        alternativeOperatorSet = OperatorSet({avs: avs2, id: 1});

        // Set up BN254 keys
        BLSWallet memory blsWallet = OperatorWalletLib.createBLSWallet(69);
        BN254_PRIV_KEY_1 = blsWallet.privateKey;

        bn254G2Key1.X[1] = blsWallet.publicKeyG2.X[1];
        bn254G2Key1.X[0] = blsWallet.publicKeyG2.X[0];
        bn254G2Key1.Y[1] = blsWallet.publicKeyG2.Y[1];
        bn254G2Key1.Y[0] = blsWallet.publicKeyG2.Y[0];

        bn254G1Key1 = BN254.generatorG1().scalar_mul(BN254_PRIV_KEY_1);

        blsWallet = OperatorWalletLib.createBLSWallet(123);
        BN254_PRIV_KEY_2 = blsWallet.privateKey;

        bn254G2Key2.X[1] = blsWallet.publicKeyG2.X[1];
        bn254G2Key2.X[0] = blsWallet.publicKeyG2.X[0];
        bn254G2Key2.Y[1] = blsWallet.publicKeyG2.Y[1];
        bn254G2Key2.Y[0] = blsWallet.publicKeyG2.Y[0];

        bn254G1Key2 = BN254.generatorG1().scalar_mul(BN254_PRIV_KEY_2);

        blsWallet = OperatorWalletLib.createBLSWallet(456);
        BN254_PRIV_KEY_3 = blsWallet.privateKey;

        bn254G2Key3.X[1] = blsWallet.publicKeyG2.X[1];
        bn254G2Key3.X[0] = blsWallet.publicKeyG2.X[0];
        bn254G2Key3.Y[1] = blsWallet.publicKeyG2.Y[1];
        bn254G2Key3.Y[0] = blsWallet.publicKeyG2.Y[0];

        bn254G1Key3 = BN254.generatorG1().scalar_mul(BN254_PRIV_KEY_3);

        // Configure operator sets in AllocationManager
        allocationManagerMock.setAVSRegistrar(avs1, IAVSRegistrar(avs1));
        allocationManagerMock.setAVSRegistrar(avs2, IAVSRegistrar(avs2));

        // Configure operator sets for BN254
        vm.prank(avs1);
        keyRegistrar.configureOperatorSet(defaultOperatorSet, IKeyRegistrarTypes.CurveType.BN254);

        vm.prank(avs2);
        keyRegistrar.configureOperatorSet(
            alternativeOperatorSet, IKeyRegistrarTypes.CurveType.BN254
        );
    }

    // Helper functions
    function _registerOperatorKey(
        address operator,
        OperatorSet memory operatorSet,
        BN254.G1Point memory g1Key,
        BN254.G2Point memory g2Key,
        uint256 privKey
    ) internal {
        bytes memory pubkey = abi.encode(g1Key.X, g1Key.Y, g2Key.X, g2Key.Y);
        bytes memory signature = _generateBN254Signature(operator, operatorSet, pubkey, privKey);

        vm.prank(operator);
        keyRegistrar.registerKey(operator, operatorSet, pubkey, signature);
    }

    function _generateBN254Signature(
        address operator,
        OperatorSet memory operatorSet,
        bytes memory pubkey,
        uint256 privKey
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keyRegistrar.BN254_KEY_REGISTRATION_TYPEHASH(),
                operator,
                operatorSet.avs,
                operatorSet.id,
                keccak256(pubkey)
            )
        );
        bytes32 messageHash = keyRegistrar.domainSeparator();
        messageHash = keccak256(abi.encodePacked("\x19\x01", messageHash, structHash));

        BN254.G1Point memory msgPoint = BN254.hashToG1(messageHash);
        BN254.G1Point memory signature = msgPoint.scalar_mul(privKey);

        return abi.encode(signature.X, signature.Y);
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

    function _addG1Points(
        BN254.G1Point memory p1,
        BN254.G1Point memory p2
    ) internal view returns (BN254.G1Point memory) {
        if (p1.X == 0 && p1.Y == 0) return p2;
        if (p2.X == 0 && p2.Y == 0) return p1;
        return BN254.plus(p1, p2);
    }

    function _returnEncodedLeaf(
        BN254.G1Point memory pubkey,
        uint256[] memory weights
    ) internal pure returns (bytes32) {
        return calculateOperatorInfoLeaf(
            IOperatorTableCalculatorTypes.BN254OperatorInfo({pubkey: pubkey, weights: weights})
        );
    }
}

/**
 * @title BN254TableCalculatorBaseUnitTests_calculateOperatorTable
 * @notice Unit tests for BN254TableCalculatorBase.calculateOperatorTable
 */
contract BN254TableCalculatorBaseUnitTests_calculateOperatorTable is
    BN254TableCalculatorBaseUnitTests
{
    function test_noOperators() public {
        // Set empty operators and weights
        address[] memory operators = new address[](0);
        uint256[][] memory weights = new uint256[][](0);
        calculator.setMockOperatorWeights(defaultOperatorSet, operators, weights);

        BN254OperatorSetInfo memory info = calculator.calculateOperatorTable(defaultOperatorSet);

        assertEq(info.numOperators, 0, "Should have 0 operators");
        assertEq(info.totalWeights.length, 0, "Should have empty total weights");
        assertEq(info.aggregatePubkey.X, 0, "Aggregate pubkey X should be 0");
        assertEq(info.aggregatePubkey.Y, 0, "Aggregate pubkey Y should be 0");
    }

    function test_operatorsWithNoRegisteredKeys() public {
        // Set operators without registering their keys
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        uint256[][] memory weights = new uint256[][](2);
        weights[0] = _createSingleWeightArray(100)[0];
        weights[1] = _createSingleWeightArray(200)[0];

        calculator.setMockOperatorWeights(defaultOperatorSet, operators, weights);

        BN254OperatorSetInfo memory info = calculator.calculateOperatorTable(defaultOperatorSet);

        // When no operators have registered keys, operatorCount should be 0 and return empty table
        assertEq(info.numOperators, 0, "Should have 0 operators when none are registered");
        assertEq(
            info.totalWeights.length,
            0,
            "Should have empty total weights when no operators registered"
        );
        assertEq(info.operatorInfoTreeRoot, bytes32(0), "Should have zero tree root");
        assertEq(info.aggregatePubkey.X, 0, "Aggregate pubkey X should be 0");
        assertEq(info.aggregatePubkey.Y, 0, "Aggregate pubkey Y should be 0");
    }

    function test_allOperatorsRegistered() public {
        // Register operators
        _registerOperatorKey(
            operator1, defaultOperatorSet, bn254G1Key1, bn254G2Key1, BN254_PRIV_KEY_1
        );
        _registerOperatorKey(
            operator2, defaultOperatorSet, bn254G1Key2, bn254G2Key2, BN254_PRIV_KEY_2
        );

        // Set operators and weights
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        uint256[][] memory weights = new uint256[][](2);
        weights[0] = _createSingleWeightArray(100)[0];
        weights[1] = _createSingleWeightArray(200)[0];

        calculator.setMockOperatorWeights(defaultOperatorSet, operators, weights);

        BN254OperatorSetInfo memory info = calculator.calculateOperatorTable(defaultOperatorSet);

        assertEq(info.numOperators, 2, "Should have 2 operators");
        assertEq(info.totalWeights.length, 1, "Should have 1 weight type");
        assertEq(info.totalWeights[0], 300, "Total weight should be 300");

        // Verify aggregate pubkey is correct (sum of G1 points)
        BN254.G1Point memory expectedAggregate = _addG1Points(bn254G1Key1, bn254G1Key2);
        assertEq(info.aggregatePubkey.X, expectedAggregate.X, "Aggregate pubkey X mismatch");
        assertEq(info.aggregatePubkey.Y, expectedAggregate.Y, "Aggregate pubkey Y mismatch");
    }

    function test_multipleWeightTypes() public {
        // Register operators
        _registerOperatorKey(
            operator1, defaultOperatorSet, bn254G1Key1, bn254G2Key1, BN254_PRIV_KEY_1
        );
        _registerOperatorKey(
            operator2, defaultOperatorSet, bn254G1Key2, bn254G2Key2, BN254_PRIV_KEY_2
        );

        // Set operators and weights with multiple types
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        uint256[][] memory weights = new uint256[][](2);
        uint256[] memory op1Weights = new uint256[](3);
        op1Weights[0] = 100;
        op1Weights[1] = 150;
        op1Weights[2] = 50;
        weights[0] = op1Weights;

        uint256[] memory op2Weights = new uint256[](3);
        op2Weights[0] = 200;
        op2Weights[1] = 250;
        op2Weights[2] = 100;
        weights[1] = op2Weights;

        calculator.setMockOperatorWeights(defaultOperatorSet, operators, weights);

        BN254OperatorSetInfo memory info = calculator.calculateOperatorTable(defaultOperatorSet);

        assertEq(info.totalWeights.length, 3, "Should have 3 weight types");
        assertEq(info.totalWeights[0], 300, "Total weight[0] should be 300");
        assertEq(info.totalWeights[1], 400, "Total weight[1] should be 400");
        assertEq(info.totalWeights[2], 150, "Total weight[2] should be 150");
    }

    function test_mixedRegistrationStatus() public {
        // Register only operator1
        _registerOperatorKey(
            operator1, defaultOperatorSet, bn254G1Key1, bn254G2Key1, BN254_PRIV_KEY_1
        );

        // Set operators and weights
        address[] memory operators = new address[](3);
        operators[0] = operator1; // registered
        operators[1] = operator2; // not registered
        operators[2] = operator3; // not registered

        uint256[][] memory weights = new uint256[][](3);
        weights[0] = _createSingleWeightArray(100)[0];
        weights[1] = _createSingleWeightArray(200)[0];
        weights[2] = _createSingleWeightArray(300)[0];

        calculator.setMockOperatorWeights(defaultOperatorSet, operators, weights);

        BN254OperatorSetInfo memory info = calculator.calculateOperatorTable(defaultOperatorSet);

        assertEq(info.numOperators, 1, "Should have 1 operator (only registered ones count)");
        assertEq(info.totalWeights[0], 100, "Total weight should be 100 (only operator1)");
        assertEq(info.aggregatePubkey.X, bn254G1Key1.X, "Aggregate pubkey X should be operator1's");
        assertEq(info.aggregatePubkey.Y, bn254G1Key1.Y, "Aggregate pubkey Y should be operator1's");
    }

    function test_singleOperatorRegistered() public {
        // Test with 1 operator, 1 registered
        address newOperator = address(uint160(100));

        address[] memory operators = new address[](1);
        operators[0] = newOperator;
        uint256[][] memory weights = new uint256[][](1);
        weights[0] = _createSingleWeightArray(100)[0];

        _registerOperatorKey(
            newOperator, defaultOperatorSet, bn254G1Key1, bn254G2Key1, BN254_PRIV_KEY_1
        );
        calculator.setMockOperatorWeights(defaultOperatorSet, operators, weights);

        BN254OperatorSetInfo memory info = calculator.calculateOperatorTable(defaultOperatorSet);
        assertEq(info.numOperators, 1, "Should have 1 operator");
        assertEq(info.totalWeights[0], 100, "Total weight should be 100");
        assertEq(info.aggregatePubkey.X, bn254G1Key1.X, "Aggregate pubkey X mismatch");
        assertEq(info.aggregatePubkey.Y, bn254G1Key1.Y, "Aggregate pubkey Y mismatch");
    }

    function test_subsetOfOperatorsRegistered() public {
        // Register operator1 and operator3, but not operator2
        _registerOperatorKey(
            operator1, defaultOperatorSet, bn254G1Key1, bn254G2Key1, BN254_PRIV_KEY_1
        );

        _registerOperatorKey(
            operator3, defaultOperatorSet, bn254G1Key3, bn254G2Key3, BN254_PRIV_KEY_3
        );

        // Set operators and weights
        address[] memory operators = new address[](3);
        operators[0] = operator1; // registered
        operators[1] = operator2; // not registered
        operators[2] = operator3; // registered

        uint256[][] memory weights = new uint256[][](3);
        weights[0] = _createSingleWeightArray(100)[0];
        weights[1] = _createSingleWeightArray(200)[0]; // This weight won't be included
        weights[2] = _createSingleWeightArray(300)[0];

        calculator.setMockOperatorWeights(defaultOperatorSet, operators, weights);

        BN254OperatorSetInfo memory info = calculator.calculateOperatorTable(defaultOperatorSet);

        assertEq(info.numOperators, 2, "Should have 2 operators (only registered ones)");
        assertEq(info.totalWeights[0], 400, "Total weight should be 400 (100 + 300)");

        // Verify aggregate pubkey is sum of registered operators' keys
        BN254.G1Point memory expectedAggregate = _addG1Points(bn254G1Key1, bn254G1Key3);
        assertEq(info.aggregatePubkey.X, expectedAggregate.X, "Aggregate pubkey X mismatch");
        assertEq(info.aggregatePubkey.Y, expectedAggregate.Y, "Aggregate pubkey Y mismatch");

        // Verify merkle root matches
        bytes32[] memory operatorInfoLeaves = new bytes32[](2);
        operatorInfoLeaves[0] = _returnEncodedLeaf(bn254G1Key1, weights[0]);
        operatorInfoLeaves[1] = _returnEncodedLeaf(bn254G1Key3, weights[2]);
        bytes32 operatorInfoTreeRoot = Merkle.merkleizeKeccak(operatorInfoLeaves);
        assertEq(operatorInfoTreeRoot, info.operatorInfoTreeRoot, "Merkle root mismatch");
    }

    function test_emptyOperatorSetReturnsZeroValues() public {
        // Test with operators that exist but none registered
        address[] memory operators = new address[](3);
        operators[0] = operator1;
        operators[1] = operator2;
        operators[2] = operator3;

        uint256[][] memory weights = new uint256[][](3);
        weights[0] = _createSingleWeightArray(100)[0];
        weights[1] = _createSingleWeightArray(200)[0];
        weights[2] = _createSingleWeightArray(300)[0];

        // Don't register any operators
        calculator.setMockOperatorWeights(defaultOperatorSet, operators, weights);

        BN254OperatorSetInfo memory info = calculator.calculateOperatorTable(defaultOperatorSet);

        // Verify all values are zero/empty when no operators are registered
        assertEq(info.operatorInfoTreeRoot, bytes32(0), "Tree root should be zero");
        assertEq(info.numOperators, 0, "Should have 0 operators");
        assertEq(info.aggregatePubkey.X, 0, "Aggregate pubkey X should be 0");
        assertEq(info.aggregatePubkey.Y, 0, "Aggregate pubkey Y should be 0");
        assertEq(info.totalWeights.length, 0, "Total weights should be empty array");
    }
}

/**
 * @title BN254TableCalculatorBaseUnitTests_calculateOperatorTableBytes
 * @notice Unit tests for BN254TableCalculatorBase.calculateOperatorTableBytes
 */
contract BN254TableCalculatorBaseUnitTests_calculateOperatorTableBytes is
    BN254TableCalculatorBaseUnitTests
{
    function test_encodesCorrectly() public {
        // Register operator
        _registerOperatorKey(
            operator1, defaultOperatorSet, bn254G1Key1, bn254G2Key1, BN254_PRIV_KEY_1
        );

        // Set operators and weights
        address[] memory operators = new address[](1);
        operators[0] = operator1;
        uint256[][] memory weights = _createSingleWeightArray(100);

        calculator.setMockOperatorWeights(defaultOperatorSet, operators, weights);

        bytes memory tableBytes = calculator.calculateOperatorTableBytes(defaultOperatorSet);

        // Decode and verify
        BN254OperatorSetInfo memory decodedInfo = abi.decode(tableBytes, (BN254OperatorSetInfo));

        assertEq(decodedInfo.numOperators, 1, "Should have 1 operator");
        assertEq(decodedInfo.totalWeights[0], 100, "Total weight should be 100");
        assertEq(decodedInfo.aggregatePubkey.X, bn254G1Key1.X, "Aggregate pubkey X mismatch");
        assertEq(decodedInfo.aggregatePubkey.Y, bn254G1Key1.Y, "Aggregate pubkey Y mismatch");
    }

    function testFuzz_encodesCorrectly(
        uint256 weight
    ) public {
        weight = bound(weight, 1, 1e18);

        // Register operator
        _registerOperatorKey(
            operator1, defaultOperatorSet, bn254G1Key1, bn254G2Key1, BN254_PRIV_KEY_1
        );

        // Set operators and weights
        address[] memory operators = new address[](1);
        operators[0] = operator1;
        uint256[][] memory weights = _createSingleWeightArray(weight);

        calculator.setMockOperatorWeights(defaultOperatorSet, operators, weights);

        bytes memory tableBytes = calculator.calculateOperatorTableBytes(defaultOperatorSet);

        // Decode and verify
        BN254OperatorSetInfo memory decodedInfo = abi.decode(tableBytes, (BN254OperatorSetInfo));

        assertEq(decodedInfo.totalWeights[0], weight, "Weight mismatch");
    }
}

/**
 * @title BN254TableCalculatorBaseUnitTests_getOperatorSetWeights
 * @notice Unit tests for BN254TableCalculatorBase.getOperatorSetWeights
 */
contract BN254TableCalculatorBaseUnitTests_getOperatorSetWeights is
    BN254TableCalculatorBaseUnitTests
{
    function test_returnsImplementationResult() public {
        // Set mock weights
        address[] memory expectedOperators = new address[](2);
        expectedOperators[0] = operator1;
        expectedOperators[1] = operator2;

        uint256[][] memory expectedWeights = new uint256[][](2);
        expectedWeights[0] = _createSingleWeightArray(100)[0];
        expectedWeights[1] = _createSingleWeightArray(200)[0];

        calculator.setMockOperatorWeights(defaultOperatorSet, expectedOperators, expectedWeights);

        (address[] memory operators, uint256[][] memory weights) =
            calculator.getOperatorSetWeights(defaultOperatorSet);

        assertEq(operators.length, expectedOperators.length, "Operators length mismatch");
        assertEq(weights.length, expectedWeights.length, "Weights length mismatch");

        for (uint256 i = 0; i < operators.length; i++) {
            assertEq(operators[i], expectedOperators[i], "Operator address mismatch");
            assertEq(weights[i][0], expectedWeights[i][0], "Weight value mismatch");
        }
    }

    function testFuzz_returnsImplementationResult(
        uint8 numOperators
    ) public {
        numOperators = uint8(bound(numOperators, 0, 20));

        address[] memory expectedOperators = new address[](numOperators);
        uint256[][] memory expectedWeights = new uint256[][](numOperators);

        for (uint256 i = 0; i < numOperators; i++) {
            expectedOperators[i] = address(uint160(i + 100));
            expectedWeights[i] = _createSingleWeightArray((i + 1) * 100)[0];
        }

        calculator.setMockOperatorWeights(defaultOperatorSet, expectedOperators, expectedWeights);

        (address[] memory operators, uint256[][] memory weights) =
            calculator.getOperatorSetWeights(defaultOperatorSet);

        assertEq(operators.length, numOperators, "Operators length mismatch");
        assertEq(weights.length, numOperators, "Weights length mismatch");
    }
}

/**
 * @title BN254TableCalculatorBaseUnitTests_getOperatorWeights
 * @notice Unit tests for BN254TableCalculatorBase.getOperatorWeights
 */
contract BN254TableCalculatorBaseUnitTests_getOperatorWeights is
    BN254TableCalculatorBaseUnitTests
{
    function test_operatorExists() public {
        // Set operators and weights
        address[] memory operators = new address[](3);
        operators[0] = operator1;
        operators[1] = operator2;
        operators[2] = operator3;

        uint256[][] memory weights = new uint256[][](3);
        weights[0] = _createSingleWeightArray(100)[0];
        weights[1] = _createSingleWeightArray(200)[0];
        weights[2] = _createSingleWeightArray(300)[0];

        calculator.setMockOperatorWeights(defaultOperatorSet, operators, weights);

        uint256[] memory op1Weights = calculator.getOperatorWeights(defaultOperatorSet, operator1);
        assertEq(op1Weights.length, 1, "Operator1 should have 1 weight type");
        assertEq(op1Weights[0], 100, "Operator1 weight mismatch");

        uint256[] memory op2Weights = calculator.getOperatorWeights(defaultOperatorSet, operator2);
        assertEq(op2Weights.length, 1, "Operator2 should have 1 weight type");
        assertEq(op2Weights[0], 200, "Operator2 weight mismatch");

        uint256[] memory op3Weights = calculator.getOperatorWeights(defaultOperatorSet, operator3);
        assertEq(op3Weights.length, 1, "Operator3 should have 1 weight type");
        assertEq(op3Weights[0], 300, "Operator3 weight mismatch");
    }

    function test_operatorDoesNotExist() public {
        // Set operators and weights
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        uint256[][] memory weights = new uint256[][](2);
        weights[0] = _createSingleWeightArray(100)[0];
        weights[1] = _createSingleWeightArray(200)[0];

        calculator.setMockOperatorWeights(defaultOperatorSet, operators, weights);

        uint256[] memory op3Weights = calculator.getOperatorWeights(defaultOperatorSet, operator3);
        assertEq(op3Weights.length, 0, "Non-existent operator should return empty array");

        uint256[] memory deadWeights =
            calculator.getOperatorWeights(defaultOperatorSet, address(0xdead));
        assertEq(deadWeights.length, 0, "Random address should return empty array");
    }

    function test_emptyOperatorSet() public {
        // Set empty operators and weights
        address[] memory operators = new address[](0);
        uint256[][] memory weights = new uint256[][](0);

        calculator.setMockOperatorWeights(defaultOperatorSet, operators, weights);

        uint256[] memory op1Weights = calculator.getOperatorWeights(defaultOperatorSet, operator1);
        assertEq(op1Weights.length, 0, "Should return empty array for empty set");
    }

    function testFuzz_getOperatorWeights(address operator, uint256 weight) public {
        weight = bound(weight, 0, 1e18);

        // Set single operator
        address[] memory operators = new address[](1);
        operators[0] = operator;

        uint256[][] memory weights = _createSingleWeightArray(weight);

        calculator.setMockOperatorWeights(defaultOperatorSet, operators, weights);

        uint256[] memory opWeights = calculator.getOperatorWeights(defaultOperatorSet, operator);
        assertEq(opWeights.length, 1, "Should have 1 weight type");
        assertEq(opWeights[0], weight, "Weight mismatch");

        // Different operator should return empty array
        address differentOperator = address(uint160(uint256(uint160(operator)) + 1));
        uint256[] memory diffWeights =
            calculator.getOperatorWeights(defaultOperatorSet, differentOperator);
        assertEq(diffWeights.length, 0, "Different operator should return empty array");
    }
}

/**
 * @title BN254TableCalculatorBaseUnitTests_getOperatorInfos
 * @notice Unit tests for BN254TableCalculatorBase.getOperatorInfos
 */
contract BN254TableCalculatorBaseUnitTests_getOperatorInfos is BN254TableCalculatorBaseUnitTests {
    function test_noOperatorsRegistered() public {
        // Set operators without registering keys
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        uint256[][] memory weights = new uint256[][](2);
        weights[0] = _createSingleWeightArray(100)[0];
        weights[1] = _createSingleWeightArray(200)[0];

        calculator.setMockOperatorWeights(defaultOperatorSet, operators, weights);

        BN254OperatorInfo[] memory infos = calculator.getOperatorInfos(defaultOperatorSet);

        assertEq(infos.length, 2, "Should have 2 operator infos");

        // Both should have zero pubkeys since not registered
        for (uint256 i = 0; i < infos.length; i++) {
            assertEq(infos[i].pubkey.X, 0, "Unregistered operator pubkey X should be 0");
            assertEq(infos[i].pubkey.Y, 0, "Unregistered operator pubkey Y should be 0");
            assertEq(infos[i].weights.length, 0, "Unregistered operator weights should be empty");
        }
    }

    function test_someOperatorsNotRegistered() public {
        // Register only operator1 (skip operator3 to avoid pairing issues)
        _registerOperatorKey(
            operator1, defaultOperatorSet, bn254G1Key1, bn254G2Key1, BN254_PRIV_KEY_1
        );

        // Set operators and weights
        address[] memory operators = new address[](3);
        operators[0] = operator1; // registered
        operators[1] = operator2; // not registered
        operators[2] = operator3; // not registered

        uint256[][] memory weights = new uint256[][](3);
        weights[0] = _createSingleWeightArray(100)[0];
        weights[1] = _createSingleWeightArray(200)[0];
        weights[2] = _createSingleWeightArray(300)[0];

        calculator.setMockOperatorWeights(defaultOperatorSet, operators, weights);

        BN254OperatorInfo[] memory infos = calculator.getOperatorInfos(defaultOperatorSet);

        assertEq(infos.length, 3, "Should have 3 operator infos");

        // Check operator1 (registered)
        assertEq(infos[0].pubkey.X, bn254G1Key1.X, "Operator1 pubkey X mismatch");
        assertEq(infos[0].pubkey.Y, bn254G1Key1.Y, "Operator1 pubkey Y mismatch");
        assertEq(infos[0].weights[0], 100, "Operator1 weight mismatch");

        // Check operator2 (not registered)
        assertEq(infos[1].pubkey.X, 0, "Operator2 pubkey X should be 0");
        assertEq(infos[1].pubkey.Y, 0, "Operator2 pubkey Y should be 0");
        assertEq(infos[1].weights.length, 0, "Operator2 weights should be empty");

        // Check operator3 (not registered)
        assertEq(infos[2].pubkey.X, 0, "Operator3 pubkey X should be 0");
        assertEq(infos[2].pubkey.Y, 0, "Operator3 pubkey Y should be 0");
        assertEq(infos[2].weights.length, 0, "Operator3 weights should be empty");
    }

    function test_allOperatorsRegistered() public {
        // Register all operators
        _registerOperatorKey(
            operator1, defaultOperatorSet, bn254G1Key1, bn254G2Key1, BN254_PRIV_KEY_1
        );
        _registerOperatorKey(
            operator2, defaultOperatorSet, bn254G1Key2, bn254G2Key2, BN254_PRIV_KEY_2
        );

        // Set operators and weights
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        uint256[][] memory weights = new uint256[][](2);
        weights[0] = _createSingleWeightArray(100)[0];
        weights[1] = _createSingleWeightArray(200)[0];

        calculator.setMockOperatorWeights(defaultOperatorSet, operators, weights);

        BN254OperatorInfo[] memory infos = calculator.getOperatorInfos(defaultOperatorSet);

        assertEq(infos.length, 2, "Should have 2 operator infos");

        // Check operator1
        assertEq(infos[0].pubkey.X, bn254G1Key1.X, "Operator1 pubkey X mismatch");
        assertEq(infos[0].pubkey.Y, bn254G1Key1.Y, "Operator1 pubkey Y mismatch");
        assertEq(infos[0].weights[0], 100, "Operator1 weight mismatch");

        // Check operator2
        assertEq(infos[1].pubkey.X, bn254G1Key2.X, "Operator2 pubkey X mismatch");
        assertEq(infos[1].pubkey.Y, bn254G1Key2.Y, "Operator2 pubkey Y mismatch");
        assertEq(infos[1].weights[0], 200, "Operator2 weight mismatch");
    }

    function test_multipleWeightTypes() public {
        // Register operator
        _registerOperatorKey(
            operator1, defaultOperatorSet, bn254G1Key1, bn254G2Key1, BN254_PRIV_KEY_1
        );

        // Set operators and weights with multiple types
        address[] memory operators = new address[](1);
        operators[0] = operator1;

        uint256[][] memory weights = new uint256[][](1);
        uint256[] memory multiWeights = new uint256[](3);
        multiWeights[0] = 100;
        multiWeights[1] = 200;
        multiWeights[2] = 300;
        weights[0] = multiWeights;

        calculator.setMockOperatorWeights(defaultOperatorSet, operators, weights);

        BN254OperatorInfo[] memory infos = calculator.getOperatorInfos(defaultOperatorSet);

        assertEq(infos.length, 1, "Should have 1 operator info");
        assertEq(infos[0].weights.length, 3, "Should have 3 weight types");
        assertEq(infos[0].weights[0], 100, "Weight[0] mismatch");
        assertEq(infos[0].weights[1], 200, "Weight[1] mismatch");
        assertEq(infos[0].weights[2], 300, "Weight[2] mismatch");
    }

    function testFuzz_getOperatorInfos(
        uint8 numOperators
    ) public {
        numOperators = uint8(bound(numOperators, 1, 5));

        address[] memory operators = new address[](numOperators);
        uint256[][] memory weights = new uint256[][](numOperators);

        // Generate operators and weights
        for (uint256 i = 0; i < numOperators; i++) {
            operators[i] = address(uint160(i + 100));
            weights[i] = _createSingleWeightArray((i + 1) * 100)[0];
        }

        // Register some operators with valid keys
        if (numOperators >= 1) {
            _registerOperatorKey(
                operators[0], defaultOperatorSet, bn254G1Key1, bn254G2Key1, BN254_PRIV_KEY_1
            );
        }
        if (numOperators >= 3) {
            _registerOperatorKey(
                operators[2], defaultOperatorSet, bn254G1Key2, bn254G2Key2, BN254_PRIV_KEY_2
            );
        }

        calculator.setMockOperatorWeights(defaultOperatorSet, operators, weights);

        BN254OperatorInfo[] memory infos = calculator.getOperatorInfos(defaultOperatorSet);

        assertEq(infos.length, numOperators, "Operator info count mismatch");

        for (uint256 i = 0; i < numOperators; i++) {
            if ((i == 0 && numOperators >= 1) || (i == 2 && numOperators >= 3)) {
                // Registered operators should have weights
                assertEq(infos[i].weights.length, 1, "Registered operator should have weights");
                assertEq(infos[i].weights[0], (i + 1) * 100, "Weight value mismatch");
                assertTrue(
                    infos[i].pubkey.X != 0 || infos[i].pubkey.Y != 0,
                    "Registered operator should have pubkey"
                );
            } else {
                // Unregistered operators should have empty weights
                assertEq(
                    infos[i].weights.length, 0, "Unregistered operator should have empty weights"
                );
                assertEq(infos[i].pubkey.X, 0, "Unregistered operator pubkey X should be 0");
                assertEq(infos[i].pubkey.Y, 0, "Unregistered operator pubkey Y should be 0");
            }
        }
    }
}

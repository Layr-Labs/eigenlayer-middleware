// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    KeyRegistrar,
    IKeyRegistrarTypes
} from "eigenlayer-contracts/src/contracts/permissions/KeyRegistrar.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {
    OperatorSet,
    OperatorSetLib
} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {PermissionControllerMixin} from
    "eigenlayer-contracts/src/contracts/mixins/PermissionControllerMixin.sol";

import {BN254TableCalculatorWithCaps} from
    "../../../src/middlewareV2/tableCalculator/unaudited/BN254TableCalculatorWithCaps.sol";
import {BN254TableCalculatorBase} from
    "../../../src/middlewareV2/tableCalculator/BN254TableCalculatorBase.sol";
import {MockEigenLayerDeployer} from "./MockDeployer.sol";

/**
 * @title BN254TableCalculatorWithCapsUnitTests
 * @notice Unit tests for BN254TableCalculatorWithCaps
 */
contract BN254TableCalculatorWithCapsUnitTests is MockEigenLayerDeployer {
    using OperatorSetLib for OperatorSet;

    // Test contracts
    BN254TableCalculatorWithCaps public calculator;

    IStrategy public strategy1 = IStrategy(address(0x100));
    IStrategy public strategy2 = IStrategy(address(0x200));
    OperatorSet public operatorSet;

    // Test addresses
    address public avs1 = address(0x1);
    address public operator1 = address(0x3);
    address public operator2 = address(0x4);
    address public operator3 = address(0x5);
    address public unauthorizedCaller = address(0x999);

    // Test constants
    uint256 public constant TEST_LOOKAHEAD_BLOCKS = 100;

    event WeightCapsSet(OperatorSet indexed operatorSet, uint256[] maxWeights);

    function setUp() public virtual {
        _deployMockEigenLayer();

        // Deploy calculator
        calculator = new BN254TableCalculatorWithCaps(
            IKeyRegistrar(address(keyRegistrarMock)),
            IAllocationManager(address(allocationManagerMock)),
            IPermissionController(address(permissionController)),
            TEST_LOOKAHEAD_BLOCKS
        );

        // Set up operator set
        operatorSet = OperatorSet({avs: avs1, id: 1});
    }

    function _setupOperatorSet(
        OperatorSet memory opSet,
        address[] memory operators,
        IStrategy[] memory strategies,
        uint256[][] memory minSlashableStake
    ) internal {
        allocationManagerMock.setMembersInOperatorSet(opSet, operators);
        allocationManagerMock.setStrategiesInOperatorSet(opSet, strategies);
        allocationManagerMock.setMinimumSlashableStake(
            opSet, operators, strategies, minSlashableStake
        );
    }

    /*//////////////////////////////////////////////////////////////
                        WEIGHT CAP CONFIGURATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setWeightCap_success() public {
        uint256 maxWeight = 100 ether;

        uint256[] memory expectedWeights = new uint256[](1);
        expectedWeights[0] = maxWeight;

        vm.expectEmit(true, false, false, true);
        emit WeightCapsSet(operatorSet, expectedWeights);

        vm.prank(avs1);
        calculator.setWeightCap(operatorSet, maxWeight);
        assertEq(calculator.getWeightCap(operatorSet), maxWeight);
    }

    function test_setWeightCap_revertsOnUnauthorized() public {
        vm.prank(unauthorizedCaller);
        vm.expectRevert(PermissionControllerMixin.InvalidPermissions.selector);
        calculator.setWeightCap(operatorSet, 100 ether);
    }

    function test_setWeightCap_allowsZeroCap() public {
        // Set a cap first
        vm.prank(avs1);
        calculator.setWeightCap(operatorSet, 100 ether);
        assertEq(calculator.getWeightCap(operatorSet), 100 ether);

        // Remove the cap by setting to 0
        uint256[] memory expectedZeroWeights = new uint256[](1);
        expectedZeroWeights[0] = 0;

        vm.expectEmit(true, false, false, true);
        emit WeightCapsSet(operatorSet, expectedZeroWeights);

        vm.prank(avs1);
        calculator.setWeightCap(operatorSet, 0);

        assertEq(calculator.getWeightCap(operatorSet), 0);
    }

    function test_getWeightCap_returnsZeroByDefault() public {
        uint256 cap = calculator.getWeightCap(operatorSet);
        assertEq(cap, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        WEIGHT CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getOperatorWeights_withoutCap() public {
        // Setup operators and strategies
        address[] memory operators = new address[](3);
        operators[0] = operator1;
        operators[1] = operator2;
        operators[2] = operator3;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy1;

        // Set up stakes: different amounts
        uint256[][] memory stakes = new uint256[][](3);
        stakes[0] = new uint256[](1);
        stakes[0][0] = 50 ether;
        stakes[1] = new uint256[](1);
        stakes[1][0] = 150 ether;
        stakes[2] = new uint256[](1);
        stakes[2][0] = 300 ether;

        _setupOperatorSet(operatorSet, operators, strategies, stakes);

        // Set key registrations
        keyRegistrarMock.setIsRegistered(operator1, operatorSet, true);
        keyRegistrarMock.setIsRegistered(operator2, operatorSet, true);
        keyRegistrarMock.setIsRegistered(operator3, operatorSet, true);

        // No cap set (default 0)
        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            calculator.getOperatorSetWeights(operatorSet);

        // Should return uncapped weights
        assertEq(resultOperators.length, 3);
        assertEq(resultOperators[0], operator1);
        assertEq(resultOperators[1], operator2);
        assertEq(resultOperators[2], operator3);
        assertEq(resultWeights[0][0], 50 ether);
        assertEq(resultWeights[1][0], 150 ether);
        assertEq(resultWeights[2][0], 300 ether);
    }

    function test_getOperatorWeights_withCap() public {
        // Setup operators and strategies
        address[] memory operators = new address[](3);
        operators[0] = operator1;
        operators[1] = operator2;
        operators[2] = operator3;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy1;

        // Set up stakes: different amounts
        uint256[][] memory stakes = new uint256[][](3);
        stakes[0] = new uint256[](1);
        stakes[0][0] = 50 ether; // Under cap
        stakes[1] = new uint256[](1);
        stakes[1][0] = 150 ether; // Over cap
        stakes[2] = new uint256[](1);
        stakes[2][0] = 300 ether; // Way over cap

        _setupOperatorSet(operatorSet, operators, strategies, stakes);

        // Set key registrations
        keyRegistrarMock.setIsRegistered(operator1, operatorSet, true);
        keyRegistrarMock.setIsRegistered(operator2, operatorSet, true);
        keyRegistrarMock.setIsRegistered(operator3, operatorSet, true);

        // Set weight cap
        vm.prank(avs1);
        calculator.setWeightCap(operatorSet, 100 ether);

        // Get weights (should be capped automatically)
        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            calculator.getOperatorSetWeights(operatorSet);

        // Should return capped weights
        assertEq(resultOperators.length, 3);
        assertEq(resultOperators[0], operator1);
        assertEq(resultOperators[1], operator2);
        assertEq(resultOperators[2], operator3);
        assertEq(resultWeights[0][0], 50 ether); // Unchanged (under cap)
        assertEq(resultWeights[1][0], 100 ether); // Capped from 150
        assertEq(resultWeights[2][0], 100 ether); // Capped from 300
    }

    function test_getOperatorWeights_zeroWeightOperatorsFiltered() public {
        // Setup operators where one has zero weight
        address[] memory operators = new address[](3);
        operators[0] = operator1;
        operators[1] = operator2;
        operators[2] = operator3;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy1;

        uint256[][] memory stakes = new uint256[][](3);
        stakes[0] = new uint256[](1);
        stakes[0][0] = 100 ether;
        stakes[1] = new uint256[](1);
        stakes[1][0] = 0; // Zero weight
        stakes[2] = new uint256[](1);
        stakes[2][0] = 200 ether;

        _setupOperatorSet(operatorSet, operators, strategies, stakes);

        // Set key registrations
        keyRegistrarMock.setIsRegistered(operator1, operatorSet, true);
        keyRegistrarMock.setIsRegistered(operator2, operatorSet, true);
        keyRegistrarMock.setIsRegistered(operator3, operatorSet, true);

        // Set weight cap
        vm.prank(avs1);
        calculator.setWeightCap(operatorSet, 150 ether);

        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            calculator.getOperatorSetWeights(operatorSet);

        // Should only include non-zero weight operators, with caps applied
        assertEq(resultOperators.length, 2);
        assertEq(resultOperators[0], operator1);
        assertEq(resultOperators[1], operator3);
        assertEq(resultWeights[0][0], 100 ether); // Under cap
        assertEq(resultWeights[1][0], 150 ether); // Capped from 200
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_calculateOperatorTable_withCaps() public {
        // Setup a complete scenario with caps applied
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy1;

        uint256[][] memory stakes = new uint256[][](2);
        stakes[0] = new uint256[](1);
        stakes[0][0] = 80 ether; // Under cap
        stakes[1] = new uint256[](1);
        stakes[1][0] = 200 ether; // Over cap

        _setupOperatorSet(operatorSet, operators, strategies, stakes);
        keyRegistrarMock.setIsRegistered(operator1, operatorSet, true);
        keyRegistrarMock.setIsRegistered(operator2, operatorSet, true);

        // Set weight cap
        vm.prank(avs1);
        calculator.setWeightCap(operatorSet, 100 ether);

        // Calculate operator table (should apply caps automatically)
        BN254TableCalculatorBase.BN254OperatorSetInfo memory operatorSetInfo =
            calculator.calculateOperatorTable(operatorSet);

        assertEq(operatorSetInfo.numOperators, 2);
        assertEq(operatorSetInfo.totalWeights.length, 1);
        // Total weight should be: 80 + 100 = 180 (operator2 capped)
        assertEq(operatorSetInfo.totalWeights[0], 180 ether);

        // Verify operator tree root is not empty
        assertTrue(operatorSetInfo.operatorInfoTreeRoot != bytes32(0));
    }

    function test_calculateOperatorTable_noCapsSet() public {
        // Same test but without caps to verify normal behavior
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy1;

        uint256[][] memory stakes = new uint256[][](2);
        stakes[0] = new uint256[](1);
        stakes[0][0] = 80 ether;
        stakes[1] = new uint256[](1);
        stakes[1][0] = 200 ether;

        _setupOperatorSet(operatorSet, operators, strategies, stakes);
        keyRegistrarMock.setIsRegistered(operator1, operatorSet, true);
        keyRegistrarMock.setIsRegistered(operator2, operatorSet, true);

        // No caps set (default 0)
        BN254TableCalculatorBase.BN254OperatorSetInfo memory operatorSetInfo =
            calculator.calculateOperatorTable(operatorSet);

        assertEq(operatorSetInfo.numOperators, 2);
        assertEq(operatorSetInfo.totalWeights.length, 1);
        // Total weight should be: 80 + 200 = 280 (no caps)
        assertEq(operatorSetInfo.totalWeights[0], 280 ether);
    }
}

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

import {BN254WeightedTableCalculator} from
    "../../../src/middlewareV2/tableCalculator/unaudited/BN254WeightedTableCalculator.sol";
import {BN254TableCalculatorBase} from
    "../../../src/middlewareV2/tableCalculator/BN254TableCalculatorBase.sol";
import {MockEigenLayerDeployer} from "./MockDeployer.sol";

// Harness to test internal functions
contract BN254WeightedTableCalculatorHarness is BN254WeightedTableCalculator {
    constructor(
        IKeyRegistrar _keyRegistrar,
        IAllocationManager _allocationManager,
        IPermissionController _permissionController,
        uint256 _LOOKAHEAD_BLOCKS
    )
        BN254WeightedTableCalculator(
            _keyRegistrar,
            _allocationManager,
            _permissionController,
            _LOOKAHEAD_BLOCKS
        )
    {}

    function exposed_getOperatorWeights(
        OperatorSet calldata operatorSet
    ) external view returns (address[] memory operators, uint256[][] memory weights) {
        return _getOperatorWeights(operatorSet);
    }
}

/**
 * @title BN254WeightedTableCalculatorUnitTests
 * @notice Unit tests for BN254WeightedTableCalculator
 */
contract BN254WeightedTableCalculatorUnitTests is MockEigenLayerDeployer {
    using OperatorSetLib for OperatorSet;

    // Test contracts
    BN254WeightedTableCalculatorHarness public calculator;

    // Test strategies (simple address casting like the original tests)
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

    event StrategyMultipliersUpdated(
        OperatorSet indexed operatorSet, IStrategy[] strategies, uint256[] multipliers
    );

    function setUp() public virtual {
        _deployMockEigenLayer();

        // Deploy calculator
        calculator = new BN254WeightedTableCalculatorHarness(
            IKeyRegistrar(address(keyRegistrarMock)),
            IAllocationManager(address(allocationManagerMock)),
            IPermissionController(address(permissionController)),
            TEST_LOOKAHEAD_BLOCKS
        );

        // Set up operator set
        operatorSet = OperatorSet({avs: avs1, id: 1});

        // Configure operator set for BN254 if needed for some tests
        vm.prank(avs1);
        keyRegistrar.configureOperatorSet(operatorSet, IKeyRegistrarTypes.CurveType.BN254);
    }

    // Helper functions
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

    function _createSingleWeightArray(
        uint256 weight
    ) internal pure returns (uint256[][] memory) {
        uint256[][] memory weights = new uint256[][](1);
        weights[0] = new uint256[](1);
        weights[0][0] = weight;
        return weights;
    }

    /*//////////////////////////////////////////////////////////////
                            MULTIPLIER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setStrategyMultipliers_success() public {
        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = strategy1;
        strategies[1] = strategy2;

        uint256[] memory multipliers = new uint256[](2);
        multipliers[0] = 20000; // 2x
        multipliers[1] = 5000; // 0.5x

        // Expect event emission
        vm.expectEmit(true, false, false, true);
        emit StrategyMultipliersUpdated(operatorSet, strategies, multipliers);

        vm.prank(avs1);
        calculator.setStrategyMultipliers(operatorSet, strategies, multipliers);

        // Verify multipliers were set
        assertEq(calculator.getStrategyMultiplier(operatorSet, strategies[0]), 20000);
        assertEq(calculator.getStrategyMultiplier(operatorSet, strategies[1]), 5000);
    }

    function test_setStrategyMultipliers_revertsOnUnauthorized() public {
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy1;

        uint256[] memory multipliers = new uint256[](1);
        multipliers[0] = 15000;

        vm.prank(unauthorizedCaller);
        vm.expectRevert(PermissionControllerMixin.InvalidPermissions.selector);
        calculator.setStrategyMultipliers(operatorSet, strategies, multipliers);
    }

    function test_setStrategyMultipliers_revertsOnArrayLengthMismatch() public {
        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = strategy1;
        strategies[1] = strategy2;

        uint256[] memory multipliers = new uint256[](1); // Wrong length
        multipliers[0] = 10000;

        vm.prank(avs1);
        vm.expectRevert(BN254WeightedTableCalculator.ArrayLengthMismatch.selector);
        calculator.setStrategyMultipliers(operatorSet, strategies, multipliers);
    }

    function test_getStrategyMultiplier_returnsDefaultForUnset() public {
        uint256 multiplier = calculator.getStrategyMultiplier(operatorSet, strategy1);
        assertEq(multiplier, 10000); // Default 1x multiplier
    }

    function test_setStrategyMultipliers_allowsZeroMultiplier() public {
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy1;

        uint256[] memory multipliers = new uint256[](1);
        multipliers[0] = 0; // Zero multiplier

        vm.prank(avs1);
        calculator.setStrategyMultipliers(operatorSet, strategies, multipliers);

        // Should return 0, not default
        assertEq(calculator.getStrategyMultiplier(operatorSet, strategies[0]), 0);
    }

    function test_setStrategyMultipliers_allowsExtremeMultipliers() public {
        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = strategy1;
        strategies[1] = strategy2;

        uint256[] memory multipliers = new uint256[](2);
        multipliers[0] = 1; // Very small
        multipliers[1] = type(uint256).max; // Very large

        vm.prank(avs1);
        calculator.setStrategyMultipliers(operatorSet, strategies, multipliers);

        assertEq(calculator.getStrategyMultiplier(operatorSet, strategies[0]), 1);
        assertEq(calculator.getStrategyMultiplier(operatorSet, strategies[1]), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        WEIGHT CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getOperatorWeights_withMultipliers() public {
        // Setup operators and strategies
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = strategy1;
        strategies[1] = strategy2;

        // Set up stakes: operator1 has 100 in each strategy, operator2 has 200 in each
        uint256[][] memory stakes = new uint256[][](2);
        stakes[0] = new uint256[](2);
        stakes[0][0] = 100 ether; // operator1, strategy1
        stakes[0][1] = 100 ether; // operator1, strategy2
        stakes[1] = new uint256[](2);
        stakes[1][0] = 200 ether; // operator2, strategy1
        stakes[1][1] = 200 ether; // operator2, strategy2

        _setupOperatorSet(operatorSet, operators, strategies, stakes);

        // Set key registrations
        keyRegistrarMock.setIsRegistered(operator1, operatorSet, true);
        keyRegistrarMock.setIsRegistered(operator2, operatorSet, true);

        // Set multipliers: strategy1 = 2x, strategy2 = 0.5x
        IStrategy[] memory strategiesForMultiplier = new IStrategy[](2);
        strategiesForMultiplier[0] = strategy1;
        strategiesForMultiplier[1] = strategy2;

        uint256[] memory multipliers = new uint256[](2);
        multipliers[0] = 20000; // 2x
        multipliers[1] = 5000; // 0.5x

        vm.prank(avs1);
        calculator.setStrategyMultipliers(operatorSet, strategiesForMultiplier, multipliers);

        // Calculate weights
        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            calculator.exposed_getOperatorWeights(operatorSet);

        // Verify results
        assertEq(resultOperators.length, 2);
        assertEq(resultOperators[0], operator1);
        assertEq(resultOperators[1], operator2);

        // Expected weights:
        // operator1: (100 * 20000/10000) + (100 * 5000/10000) = 200 + 50 = 250
        // operator2: (200 * 20000/10000) + (200 * 5000/10000) = 400 + 100 = 500
        assertEq(resultWeights[0][0], 250 ether);
        assertEq(resultWeights[1][0], 500 ether);
    }

    function test_getOperatorWeights_withoutMultipliers() public {
        // Setup without setting any multipliers (should use default 1x)
        address[] memory operators = new address[](1);
        operators[0] = operator1;

        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = strategy1;
        strategies[1] = strategy2;

        uint256[][] memory stakes = new uint256[][](1);
        stakes[0] = new uint256[](2);
        stakes[0][0] = 100 ether;
        stakes[0][1] = 200 ether;

        _setupOperatorSet(operatorSet, operators, strategies, stakes);
        keyRegistrarMock.setIsRegistered(operator1, operatorSet, true);

        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            calculator.exposed_getOperatorWeights(operatorSet);

        // Should sum with default 1x multipliers: 100 + 200 = 300
        assertEq(resultOperators.length, 1);
        assertEq(resultOperators[0], operator1);
        assertEq(resultWeights[0][0], 300 ether);
    }

    function test_getOperatorWeights_excludesUnregisteredOperators() public {
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy1;

        uint256[][] memory stakes = new uint256[][](2);
        stakes[0] = new uint256[](1);
        stakes[0][0] = 100 ether;
        stakes[1] = new uint256[](1);
        stakes[1][0] = 200 ether;

        _setupOperatorSet(operatorSet, operators, strategies, stakes);

        // Only register operator1
        keyRegistrarMock.setIsRegistered(operator1, operatorSet, true);
        keyRegistrarMock.setIsRegistered(operator2, operatorSet, false);

        // Use calculateOperatorTable which does check registration, not just weights
        BN254TableCalculatorBase.BN254OperatorSetInfo memory operatorSetInfo =
            calculator.calculateOperatorTable(operatorSet);

        // Should only include operator1 (registered)
        assertEq(operatorSetInfo.numOperators, 1);
        assertEq(operatorSetInfo.totalWeights.length, 1);
        assertEq(operatorSetInfo.totalWeights[0], 100 ether);
    }

    function test_getOperatorWeights_withZeroStake() public {
        address[] memory operators = new address[](1);
        operators[0] = operator1;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy1;

        // Set zero stake
        uint256[][] memory stakes = new uint256[][](1);
        stakes[0] = new uint256[](1);
        stakes[0][0] = 0;

        _setupOperatorSet(operatorSet, operators, strategies, stakes);
        keyRegistrarMock.setIsRegistered(operator1, operatorSet, true);

        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            calculator.exposed_getOperatorWeights(operatorSet);

        // Should exclude operators with zero total weight
        assertEq(resultOperators.length, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_calculateOperatorTable_integration() public {
        // Setup a complete scenario and verify the full operator table calculation
        address[] memory operators = new address[](1);
        operators[0] = operator1;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy1;

        uint256[][] memory stakes = new uint256[][](1);
        stakes[0] = new uint256[](1);
        stakes[0][0] = 100 ether;

        _setupOperatorSet(operatorSet, operators, strategies, stakes);
        keyRegistrarMock.setIsRegistered(operator1, operatorSet, true);

        // This should work without reverting and return a valid operator set info
        BN254TableCalculatorBase.BN254OperatorSetInfo memory operatorSetInfo =
            calculator.calculateOperatorTable(operatorSet);

        assertEq(operatorSetInfo.numOperators, 1);
        assertEq(operatorSetInfo.totalWeights.length, 1);
        assertEq(operatorSetInfo.totalWeights[0], 100 ether);
    }

    function test_calculateOperatorTable_withSomeUnregisteredOperators() public {
        // This test catches the audit issue where operatorInfoLeaves[i] was used instead of operatorInfoLeaves[operatorCount]
        // When some operators are in allocation manager but not registered with key registrar

        address operator4 = address(0x6);

        // Setup 4 operators in allocation manager
        address[] memory operators = new address[](4);
        operators[0] = operator1;
        operators[1] = operator2;
        operators[2] = operator3;
        operators[3] = operator4;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy1;

        // All operators have stake
        uint256[][] memory stakes = new uint256[][](4);
        for (uint256 i = 0; i < 4; i++) {
            stakes[i] = new uint256[](1);
            stakes[i][0] = (i + 1) * 100 ether; // 100, 200, 300, 400
        }

        _setupOperatorSet(operatorSet, operators, strategies, stakes);

        // Only register operators 1 and 3 with key registrar (skip 2 and 4)
        keyRegistrarMock.setIsRegistered(operator1, operatorSet, true);
        keyRegistrarMock.setIsRegistered(operator2, operatorSet, false);
        keyRegistrarMock.setIsRegistered(operator3, operatorSet, true);
        keyRegistrarMock.setIsRegistered(operator4, operatorSet, false);

        // Set multiplier for strategy1
        IStrategy[] memory strategiesForMultiplier = new IStrategy[](1);
        strategiesForMultiplier[0] = strategy1;
        uint256[] memory multipliers = new uint256[](1);
        multipliers[0] = 20000; // 2x multiplier

        vm.prank(avs1);
        calculator.setStrategyMultipliers(operatorSet, strategiesForMultiplier, multipliers);

        // Calculate operator table - this would fail with the audit bug because of array indexing mismatch
        BN254TableCalculatorBase.BN254OperatorSetInfo memory operatorSetInfo =
            calculator.calculateOperatorTable(operatorSet);

        // Should only include registered operators (1 and 3)
        assertEq(operatorSetInfo.numOperators, 2);
        assertEq(operatorSetInfo.totalWeights.length, 1);

        // Total weight should be: (100 * 2) + (300 * 2) = 200 + 600 = 800
        assertEq(operatorSetInfo.totalWeights[0], 800 ether);

        // Verify operator tree root is not empty (proves merkle tree was built correctly)
        assertTrue(operatorSetInfo.operatorInfoTreeRoot != bytes32(0));
    }
}

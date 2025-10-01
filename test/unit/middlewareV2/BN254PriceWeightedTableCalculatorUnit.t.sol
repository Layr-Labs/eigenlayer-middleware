// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

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

import {BN254TableCalculatorBase} from
    "../../../src/middlewareV2/tableCalculator/BN254TableCalculatorBase.sol";
import {BN254PriceWeightedTableCalculator} from
    "../../../src/middlewareV2/tableCalculator/unaudited/BN254PriceWeightedTableCalculator.sol";
import {MockEigenLayerDeployer} from "./MockDeployer.sol";
import {ChainlinkAggregatorMock} from "test/mocks/ChainlinkAggregatorMock.sol";

contract BN254PriceWeightedTableCalculatorHarness is BN254PriceWeightedTableCalculator {
    constructor(
        IKeyRegistrar _keyRegistrar,
        IAllocationManager _allocationManager,
        IPermissionController _permissionController,
        uint256 _LOOKAHEAD_BLOCKS
    )
        BN254PriceWeightedTableCalculator(
            _keyRegistrar, _allocationManager, _permissionController, _LOOKAHEAD_BLOCKS
        )
    {}

    function exposed_getOperatorWeights(
        OperatorSet calldata operatorSet
    ) external view returns (address[] memory operators, uint256[][] memory weights) {
        return _getOperatorWeights(operatorSet);
    }
}

contract BN254PriceWeightedTableCalculatorUnitTests is MockEigenLayerDeployer {
    using OperatorSetLib for OperatorSet;

    BN254PriceWeightedTableCalculatorHarness public calculator;
    OperatorSet public operatorSet;

    // Simple strategy identifiers
    IStrategy public strategy1 = IStrategy(address(0x100));
    IStrategy public strategy2 = IStrategy(address(0x200));

    // Actors
    address public avs1 = address(0x1);
    address public operator1 = address(0x3);
    address public operator2 = address(0x4);

    uint256 public constant TEST_LOOKAHEAD_BLOCKS = 100;

    function setUp() public {
        _deployMockEigenLayer();
        calculator = new BN254PriceWeightedTableCalculatorHarness(
            IKeyRegistrar(address(keyRegistrarMock)),
            IAllocationManager(address(allocationManagerMock)),
            IPermissionController(address(permissionController)),
            TEST_LOOKAHEAD_BLOCKS
        );
        operatorSet = OperatorSet({avs: avs1, id: 7});
    }

    function _setupOperatorSet(
        OperatorSet memory opSet,
        address[] memory operators,
        IStrategy[] memory strategies,
        uint256[][] memory minSlashableStake
    ) internal {
        allocationManagerMock.setMembersInOperatorSet(opSet, operators);
        allocationManagerMock.setStrategiesInOperatorSet(opSet, strategies);
        allocationManagerMock.setMinimumSlashableStake(opSet, operators, strategies, minSlashableStake);
    }

    function test_getOperatorWeights_priceWeighted_basic() public {
        // two operators, two strategies
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = strategy1; // token with 18 decimals
        strategies[1] = strategy2; // token with 6 decimals

        uint256[][] memory stakes = new uint256[][](2);
        stakes[0] = new uint256[](2);
        stakes[1] = new uint256[](2);

        // operator1: 10 units on s1, 2,000,000 units on s2 (to simulate 6 decimals scale)
        stakes[0][0] = 10 ether; // assume already in 1e18 for simplicity
        stakes[0][1] = 2_000_000; // raw amount with 6 decimals

        // operator2: 5 units on s1, 3,000,000 units on s2
        stakes[1][0] = 5 ether;
        stakes[1][1] = 3_000_000;

        _setupOperatorSet(operatorSet, operators, strategies, stakes);

        // Configure feeds and decimals
        // price1 = 2e8 with 8 decimals => 2.0 -> scaled to 1e18 becomes 2e18
        ChainlinkAggregatorMock feed1 = new ChainlinkAggregatorMock(8, 200_000_000);
        // price2 = 3e8 with 8 decimals => 3.0 -> scaled to 1e18 becomes 3e18
        ChainlinkAggregatorMock feed2 = new ChainlinkAggregatorMock(8, 300_000_000);

        IStrategy[] memory feedStrats = new IStrategy[](2);
        feedStrats[0] = strategy1;
        feedStrats[1] = strategy2;
        address[] memory feeds = new address[](2);
        feeds[0] = address(feed1);
        feeds[1] = address(feed2);

        vm.prank(avs1);
        calculator.setStrategyPriceFeeds(operatorSet, feedStrats, feeds);

        // set stake decimals: s1=18, s2=6
        IStrategy[] memory decStrats = new IStrategy[](2);
        decStrats[0] = strategy1;
        decStrats[1] = strategy2;
        uint8[] memory decs = new uint8[](2);
        decs[0] = 18;
        decs[1] = 6;
        vm.prank(avs1);
        calculator.setStrategyStakeDecimals(operatorSet, decStrats, decs);

        // Compute
        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            calculator.exposed_getOperatorWeights(operatorSet);

        assertEq(resultOperators.length, 2);
        assertEq(resultOperators[0], operator1);
        assertEq(resultOperators[1], operator2);

        // Expected:
        // op1: s1 -> 10e18 * 2e18 / 1e18 = 20e18
        //      s2 -> (2_000_000 scaled from 6 to 18 => 2_000_000 * 1e12 = 2e18) * 3e18 / 1e18 = 6e18
        // total = 26e18
        assertEq(resultWeights[0][0], 26 ether);

        // op2: s1 -> 5e18 * 2e18 / 1e18 = 10e18
        //      s2 -> (3_000_000 -> 3e18) * 3e18 / 1e18 = 9e18
        // total = 19e18
        assertEq(resultWeights[1][0], 19 ether);
    }

    function test_getOperatorWeights_skipsUnsetFeedsOrDecimals() public {
        address[] memory operators = new address[](1);
        operators[0] = operator1;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy1;

        uint256[][] memory stakes = new uint256[][](1);
        stakes[0] = new uint256[](1);
        stakes[0][0] = 100 ether;

        _setupOperatorSet(operatorSet, operators, strategies, stakes);

        // Only set price feed, not stake decimals -> skipped
        ChainlinkAggregatorMock feed1 = new ChainlinkAggregatorMock(8, 200_000_000);
        IStrategy[] memory feedStrats = new IStrategy[](1);
        feedStrats[0] = strategy1;
        address[] memory feeds = new address[](1);
        feeds[0] = address(feed1);
        vm.prank(avs1);
        calculator.setStrategyPriceFeeds(operatorSet, feedStrats, feeds);

        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            calculator.exposed_getOperatorWeights(operatorSet);
        // Should be skipped due to missing stake decimals -> zero operators
        assertEq(resultOperators.length, 0);
        assertEq(resultWeights.length, 0);
    }

    function test_getOperatorWeights_skipsNonPositivePrice() public {
        address[] memory operators = new address[](1);
        operators[0] = operator1;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy1;

        uint256[][] memory stakes = new uint256[][](1);
        stakes[0] = new uint256[](1);
        stakes[0][0] = 100 ether;
        _setupOperatorSet(operatorSet, operators, strategies, stakes);

        // Set decimals but zero price
        IStrategy[] memory decStrats = new IStrategy[](1);
        decStrats[0] = strategy1;
        uint8[] memory decs = new uint8[](1);
        decs[0] = 18;
        vm.prank(avs1);
        calculator.setStrategyStakeDecimals(operatorSet, decStrats, decs);

        ChainlinkAggregatorMock feed = new ChainlinkAggregatorMock(8, 0);
        IStrategy[] memory feedStrats = new IStrategy[](1);
        feedStrats[0] = strategy1;
        address[] memory feeds = new address[](1);
        feeds[0] = address(feed);
        vm.prank(avs1);
        calculator.setStrategyPriceFeeds(operatorSet, feedStrats, feeds);

        (address[] memory resultOperators, uint256[][] memory resultWeights) =
            calculator.exposed_getOperatorWeights(operatorSet);
        assertEq(resultOperators.length, 0);
        assertEq(resultWeights.length, 0);
    }
}



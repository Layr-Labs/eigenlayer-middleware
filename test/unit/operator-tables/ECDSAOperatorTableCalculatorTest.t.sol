// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {OperatorSet} from "../../../lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IStrategy} from "../../../lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAllocationManager} from "../../../lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {ECDSAOperatorInfo, ECDSAOperatorTableCalculator, IECDSAOperatorTableCalculator} from "../../../src/operator-tables/ECDSAOperatorTableCalculator.sol";
import {MockStrategy, MockAllocationManager} from "../../mocks/OperatorTableMocks.sol";

contract ECDSAOperatorTableCalculatorTest is Test {
    MockAllocationManager public allocationManager;
    ECDSAOperatorTableCalculator public calculator;
    
    MockStrategy public strategy1;
    MockStrategy public strategy2;
    
    address public avs;
    uint32 public operatorSetId;
    OperatorSet public operatorSet;
    
    address public operator1;
    address public operator2;
    address public operator3;
    
    uint8 public constant NUM_WEIGHT_TYPES = 2; // Slashable and delegated
    
    function setUp() public {
        // Create the mock allocation manager
        allocationManager = new MockAllocationManager();
        
        // Create mock strategies
        strategy1 = new MockStrategy("Strategy1");
        strategy2 = new MockStrategy("Strategy2");
        
        // Set up strategies and multipliers for the calculator
        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = IStrategy(address(strategy1));
        strategies[1] = IStrategy(address(strategy2));
        
        uint256[] memory multipliers = new uint256[](2);
        multipliers[0] = 1e18; // 1.0 for strategy1
        multipliers[1] = 2e18; // 2.0 for strategy2
        
        // Create the calculator
        calculator = new ECDSAOperatorTableCalculator(
            IAllocationManager(address(allocationManager)),
            strategies,
            multipliers,
            NUM_WEIGHT_TYPES
        );
        
        // Set up operator set
        avs = address(0x1);
        operatorSetId = 1;
        operatorSet = OperatorSet(avs, operatorSetId);
        
        // Set up test operators
        operator1 = makeAddr("operator1");
        operator2 = makeAddr("operator2");
        operator3 = makeAddr("operator3");
        
        // Add operators to the operator set
        allocationManager.addOperatorToSet(operatorSet, operator1);
        allocationManager.addOperatorToSet(operatorSet, operator2);
        allocationManager.addOperatorToSet(operatorSet, operator3);
        
        // Set stakes for operators
        // Operator 1: 100 for strategy1, 200 for strategy2
        allocationManager.setOperatorStake(operator1, operatorSet, IStrategy(address(strategy1)), 100e18);
        allocationManager.setOperatorStake(operator1, operatorSet, IStrategy(address(strategy2)), 200e18);
        
        // Operator 2: 150 for strategy1, 50 for strategy2
        allocationManager.setOperatorStake(operator2, operatorSet, IStrategy(address(strategy1)), 150e18);
        allocationManager.setOperatorStake(operator2, operatorSet, IStrategy(address(strategy2)), 50e18);
        
        // Operator 3: 300 for strategy1, 100 for strategy2
        allocationManager.setOperatorStake(operator3, operatorSet, IStrategy(address(strategy1)), 300e18);
        allocationManager.setOperatorStake(operator3, operatorSet, IStrategy(address(strategy2)), 100e18);
    }
    
    function testCalculateOperatorTable() public {
        // Calculate the operator table
        ECDSAOperatorInfo[] memory operatorInfos = calculator.calculateOperatorTable(operatorSet);
        
        // Verify number of operators
        assertEq(operatorInfos.length, 3, "Should have 3 operators");
        
        // Verify operator1 info
        assertEq(operatorInfos[0].pubkey, operator1, "Operator1 pubkey incorrect");
        assertEq(operatorInfos[0].weights.length, NUM_WEIGHT_TYPES, "Operator1 should have 2 weight types");
        
        // Calculate expected weights for operator1
        // Strategy1: 100e18 * 1.0 = 100e18
        // Strategy2: 200e18 * 2.0 = 400e18
        // Total: 500e18
        assertEq(uint256(operatorInfos[0].weights[0]), 500e18, "Operator1 weight[0] incorrect");
        assertEq(uint256(operatorInfos[0].weights[1]), 500e18, "Operator1 weight[1] incorrect");
        
        // Verify operator2 info
        assertEq(operatorInfos[1].pubkey, operator2, "Operator2 pubkey incorrect");
        
        // Calculate expected weights for operator2
        // Strategy1: 150e18 * 1.0 = 150e18
        // Strategy2: 50e18 * 2.0 = 100e18
        // Total: 250e18
        assertEq(uint256(operatorInfos[1].weights[0]), 250e18, "Operator2 weight[0] incorrect");
        assertEq(uint256(operatorInfos[1].weights[1]), 250e18, "Operator2 weight[1] incorrect");
        
        // Verify operator3 info
        assertEq(operatorInfos[2].pubkey, operator3, "Operator3 pubkey incorrect");
        
        // Calculate expected weights for operator3
        // Strategy1: 300e18 * 1.0 = 300e18
        // Strategy2: 100e18 * 2.0 = 200e18
        // Total: 500e18
        assertEq(uint256(operatorInfos[2].weights[0]), 500e18, "Operator3 weight[0] incorrect");
        assertEq(uint256(operatorInfos[2].weights[1]), 500e18, "Operator3 weight[1] incorrect");
    }
    
    function testEdgeCaseEmptyOperatorSet() public {
        // Create a new empty operator set
        OperatorSet memory emptySet = OperatorSet(address(0x2), 2);
        
        // Calculate the operator table
        ECDSAOperatorInfo[] memory operatorInfos = calculator.calculateOperatorTable(emptySet);
        
        // Verify empty result
        assertEq(operatorInfos.length, 0, "Should have 0 operators");
    }
    
    function testEdgeCaseZeroStake() public {
        // Create a new operator set with zero stake
        OperatorSet memory zeroStakeSet = OperatorSet(address(0x3), 3);
        address zeroStakeOperator = makeAddr("zeroStakeOperator");
        
        // Add operator with zero stake
        allocationManager.addOperatorToSet(zeroStakeSet, zeroStakeOperator);
        allocationManager.setOperatorStake(zeroStakeOperator, zeroStakeSet, IStrategy(address(strategy1)), 0);
        allocationManager.setOperatorStake(zeroStakeOperator, zeroStakeSet, IStrategy(address(strategy2)), 0);
        
        // Calculate the operator table
        ECDSAOperatorInfo[] memory operatorInfos = calculator.calculateOperatorTable(zeroStakeSet);
        
        // Verify operator info
        assertEq(operatorInfos.length, 1, "Should have 1 operator");
        assertEq(operatorInfos[0].pubkey, zeroStakeOperator, "Operator pubkey incorrect");
        assertEq(uint256(operatorInfos[0].weights[0]), 0, "Operator weight[0] should be zero");
        assertEq(uint256(operatorInfos[0].weights[1]), 0, "Operator weight[1] should be zero");
    }
}
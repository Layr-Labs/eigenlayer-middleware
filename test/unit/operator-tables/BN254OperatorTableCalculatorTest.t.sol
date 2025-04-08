// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {OperatorSet} from "../../../lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IStrategy} from "../../../lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAllocationManager} from "../../../lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {BN254} from "../../../src/libraries/BN254.sol";
import {BN254OperatorInfo, BN254OperatorSetInfo, BN254OperatorTableCalculator, IBN254OperatorTableCalculator} from "../../../src/operator-tables/BN254OperatorTableCalculator.sol";
import {MerkleTreeLib} from "../../../src/operator-tables/libraries/MerkleTreeLib.sol";
import {MockStrategy, MockAllocationManager, MockBN254OperatorRegistry} from "../../mocks/OperatorTableMocks.sol";

contract BN254OperatorTableCalculatorTest is Test {
    MockAllocationManager public allocationManager;
    MockBN254OperatorRegistry public operatorRegistry;
    BN254OperatorTableCalculator public calculator;
    
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
        // Create the mock allocation manager and operator registry
        allocationManager = new MockAllocationManager();
        operatorRegistry = new MockBN254OperatorRegistry();
        
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
        calculator = new BN254OperatorTableCalculator(
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
        
        // Set up BLS pubkeys for operators
        // These are just test values, real BLS keys would be different
        operatorRegistry.setOperatorPubkey(operator1, BN254.G1Point(1, 2));
        operatorRegistry.setOperatorPubkey(operator2, BN254.G1Point(3, 4));
        operatorRegistry.setOperatorPubkey(operator3, BN254.G1Point(5, 6));
        
        // Register pubkeys in the calculator
        calculator.registerOperatorPubkey(operator1, operatorRegistry.getOperatorPubkey(operator1));
        calculator.registerOperatorPubkey(operator2, operatorRegistry.getOperatorPubkey(operator2));
        calculator.registerOperatorPubkey(operator3, operatorRegistry.getOperatorPubkey(operator3));
        
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
        BN254OperatorSetInfo memory operatorSetInfo = calculator.calculateOperatorTable(operatorSet);
        
        // Verify operator set info
        assertEq(operatorSetInfo.numOperators, 3, "Should have 3 operators");
        
        // Verify total weights
        // Expected total weights:
        // Weight 0: 500e18 (Operator1) + 250e18 (Operator2) + 500e18 (Operator3) = 1250e18
        // Weight 1: 500e18 (Operator1) + 250e18 (Operator2) + 500e18 (Operator3) = 1250e18
        assertEq(uint256(operatorSetInfo.totalWeights[0]), 1250e18, "Total weight[0] incorrect");
        assertEq(uint256(operatorSetInfo.totalWeights[1]), 1250e18, "Total weight[1] incorrect");
        
        // Verify aggregate pubkey (1,2) + (3,4) + (5,6) = (9,12) in simple addition
        // But this is on the elliptic curve, so we need to use the actual BN254 addition
        BN254.G1Point memory expectedApk = BN254.G1Point(0, 0);
        expectedApk = BN254.plus(expectedApk, operatorRegistry.getOperatorPubkey(operator1));
        expectedApk = BN254.plus(expectedApk, operatorRegistry.getOperatorPubkey(operator2));
        expectedApk = BN254.plus(expectedApk, operatorRegistry.getOperatorPubkey(operator3));
        
        assertEq(operatorSetInfo.aggregatePubkey.X, expectedApk.X, "Aggregate pubkey X incorrect");
        assertEq(operatorSetInfo.aggregatePubkey.Y, expectedApk.Y, "Aggregate pubkey Y incorrect");
        
        // Verify merkle root is non-zero
        assertTrue(operatorSetInfo.operatorInfoTreeRoot != bytes32(0), "Merkle root should not be zero");
    }
    
    function testGetOperatorInfo() public {
        // Get operator info for operator1
        BN254OperatorInfo memory operatorInfo = calculator.getOperatorInfo(operatorSet, 0);
        
        // Verify operator info
        assertEq(operatorInfo.pubkey.X, operatorRegistry.getOperatorPubkey(operator1).X, "Operator pubkey X incorrect");
        assertEq(operatorInfo.pubkey.Y, operatorRegistry.getOperatorPubkey(operator1).Y, "Operator pubkey Y incorrect");
        
        // Calculate expected weights for operator1
        // Strategy1: 100e18 * 1.0 = 100e18
        // Strategy2: 200e18 * 2.0 = 400e18
        // Total: 500e18
        assertEq(uint256(operatorInfo.weights[0]), 500e18, "Operator1 weight[0] incorrect");
        assertEq(uint256(operatorInfo.weights[1]), 500e18, "Operator1 weight[1] incorrect");
    }
    
    function testGetOperatorProof() public {
        // Calculate the operator table to get the merkle root
        BN254OperatorSetInfo memory operatorSetInfo = calculator.calculateOperatorTable(operatorSet);
        
        // Get operator proof for operator1
        bytes memory proof = calculator.getOperatorProof(operatorSet, 0);
        
        // Get operator info for operator1
        BN254OperatorInfo memory operatorInfo = calculator.getOperatorInfo(operatorSet, 0);
        
        // Hash the operator info
        bytes32 operatorInfoHash = keccak256(abi.encode(
            BN254.hashG1Point(operatorInfo.pubkey),
            keccak256(abi.encode(operatorInfo.weights))
        ));
        
        // Verify the proof
        assertTrue(
            MerkleTreeLib.verifyProof(
                operatorSetInfo.operatorInfoTreeRoot,
                operatorInfoHash,
                0,
                proof
            ),
            "Operator proof should be valid"
        );
    }
    
    function testEdgeCaseEmptyOperatorSet() public {
        // Create a new empty operator set
        OperatorSet memory emptySet = OperatorSet(address(0x2), 2);
        
        // Calculate the operator table
        BN254OperatorSetInfo memory operatorSetInfo = calculator.calculateOperatorTable(emptySet);
        
        // Verify empty result
        assertEq(operatorSetInfo.numOperators, 0, "Should have 0 operators");
        assertEq(operatorSetInfo.aggregatePubkey.X, 0, "Aggregate pubkey X should be zero");
        assertEq(operatorSetInfo.aggregatePubkey.Y, 0, "Aggregate pubkey Y should be zero");
        assertEq(uint256(operatorSetInfo.totalWeights[0]), 0, "Total weight[0] should be zero");
        assertEq(uint256(operatorSetInfo.totalWeights[1]), 0, "Total weight[1] should be zero");
    }
}
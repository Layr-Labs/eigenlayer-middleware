// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {OperatorSet} from "../../lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IStrategy} from "../../lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAllocationManager} from "../../lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {BN254} from "../../src/libraries/BN254.sol";
import {MerkleTreeLib} from "../../src/operator-tables/libraries/MerkleTreeLib.sol";

// Operator Table Calculator imports
import {ECDSAOperatorInfo, ECDSAOperatorTableCalculator, IECDSAOperatorTableCalculator} from "../../src/operator-tables/ECDSAOperatorTableCalculator.sol";
import {BN254OperatorInfo, BN254OperatorSetInfo, BN254OperatorTableCalculator, IBN254OperatorTableCalculator} from "../../src/operator-tables/BN254OperatorTableCalculator.sol";
import {OperatorTableUpdater} from "../../src/operator-tables/OperatorTableUpdater.sol";

// Certificate Verifier imports
import {ECDSACertificate, ECDSACertificateVerifier} from "../../src/certificate-verifiers/ECDSACertificateVerifier.sol";
import {BN254OperatorInfoWitness, BN254Certificate, BN254CertificateVerifier} from "../../src/certificate-verifiers/BN254CertificateVerifier.sol";

// Consumer import
import {CertificateConsumer} from "../../src/examples/CertificateConsumer.sol";

// Mocks
import {MockStrategy, MockAllocationManager, MockECDSAOperatorRegistry, MockBN254OperatorRegistry} from "../mocks/OperatorTableMocks.sol";

contract CertificateVerificationIntegration is Test {
    // Core components
    MockAllocationManager public allocationManager;
    MockECDSAOperatorRegistry public ecdsaRegistry;
    MockBN254OperatorRegistry public bn254Registry;
    
    // Operator Table Calculators
    ECDSAOperatorTableCalculator public ecdsaCalculator;
    BN254OperatorTableCalculator public bn254Calculator;
    
    // Operator Table Updater
    OperatorTableUpdater public tableUpdater;
    
    // Certificate Verifiers
    ECDSACertificateVerifier public ecdsaVerifier;
    BN254CertificateVerifier public bn254Verifier;
    
    // Consumer
    CertificateConsumer public consumer;
    
    // Test data
    MockStrategy public strategy1;
    MockStrategy public strategy2;
    
    address public avs;
    uint32 public operatorSetId;
    OperatorSet public operatorSet;
    
    address public operator1;
    address public operator2;
    address public operator3;
    
    uint256 private operator1Key;
    uint256 private operator2Key;
    uint256 private operator3Key;
    
    uint32 public maxOperatorTableStaleness = 86400; // 1 day in seconds
    uint32 public referenceTimestamp = 1000;
    
    // BLS test variables
    BN254.G1Point public operator1Pubkey;
    BN254.G1Point public operator2Pubkey;
    BN254.G1Point public operator3Pubkey;
    
    function setUp() public {
        // Create mock components
        allocationManager = new MockAllocationManager();
        ecdsaRegistry = new MockECDSAOperatorRegistry();
        bn254Registry = new MockBN254OperatorRegistry();
        
        // Create mock strategies
        strategy1 = new MockStrategy("Strategy1");
        strategy2 = new MockStrategy("Strategy2");
        
        // Set up strategies and multipliers
        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = IStrategy(address(strategy1));
        strategies[1] = IStrategy(address(strategy2));
        
        uint256[] memory multipliers = new uint256[](2);
        multipliers[0] = 1e18; // 1.0 for strategy1
        multipliers[1] = 2e18; // 2.0 for strategy2
        
        // Create the calculators
        ecdsaCalculator = new ECDSAOperatorTableCalculator(
            IAllocationManager(address(allocationManager)),
            strategies,
            multipliers,
            2 // 2 weight types
        );
        
        bn254Calculator = new BN254OperatorTableCalculator(
            IAllocationManager(address(allocationManager)),
            strategies,
            multipliers,
            2 // 2 weight types
        );
        
        // Set up operator set
        avs = address(0x1);
        operatorSetId = 1;
        operatorSet = OperatorSet(avs, operatorSetId);
        
        // Create verifiers
        ecdsaVerifier = new ECDSACertificateVerifier(
            operatorSet,
            address(this), // We'll act as the updater for now
            maxOperatorTableStaleness
        );
        
        bn254Verifier = new BN254CertificateVerifier(
            operatorSet,
            address(this), // We'll act as the updater for now
            maxOperatorTableStaleness
        );
        
        // Create the table updater
        tableUpdater = new OperatorTableUpdater(
            IECDSAOperatorTableCalculator(address(ecdsaCalculator)),
            IBN254OperatorTableCalculator(address(bn254Calculator))
        );
        
        // Register verifiers with the updater
        tableUpdater.registerVerifier(operatorSet, address(ecdsaVerifier), true);
        tableUpdater.registerVerifier(operatorSet, address(bn254Verifier), false);
        
        // Set up proportion and nominal thresholds for the consumer
        uint16[] memory proportionThresholds = new uint16[](2);
        proportionThresholds[0] = 5000; // 50%
        proportionThresholds[1] = 5000; // 50%
        
        uint96[] memory nominalThresholds = new uint96[](2);
        nominalThresholds[0] = 300; // 300 units
        nominalThresholds[1] = 300; // 300 units
        
        // Create the consumer
        consumer = new CertificateConsumer(
            address(ecdsaVerifier),
            address(bn254Verifier),
            proportionThresholds,
            nominalThresholds
        );
        
        // Set up test operators
        operator1 = makeAddr("operator1");
        operator2 = makeAddr("operator2");
        operator3 = makeAddr("operator3");
        
        // Generate private keys for ECDSA
        operator1Key = uint256(keccak256(abi.encodePacked("operator1Key")));
        operator2Key = uint256(keccak256(abi.encodePacked("operator2Key")));
        operator3Key = uint256(keccak256(abi.encodePacked("operator3Key")));
        
        // Store private keys in the registry
        ecdsaRegistry.setOperatorPrivateKey(operator1, operator1Key);
        ecdsaRegistry.setOperatorPrivateKey(operator2, operator2Key);
        ecdsaRegistry.setOperatorPrivateKey(operator3, operator3Key);
        
        // Set up BLS pubkeys - in a real implementation these would be valid BLS keys
        operator1Pubkey = BN254.G1Point(1, 2);
        operator2Pubkey = BN254.G1Point(3, 4);
        operator3Pubkey = BN254.G1Point(5, 6);
        
        // Store pubkeys in the registry and calculator
        bn254Registry.setOperatorPubkey(operator1, operator1Pubkey);
        bn254Registry.setOperatorPubkey(operator2, operator2Pubkey);
        bn254Registry.setOperatorPubkey(operator3, operator3Pubkey);
        
        bn254Calculator.registerOperatorPubkey(operator1, operator1Pubkey);
        bn254Calculator.registerOperatorPubkey(operator2, operator2Pubkey);
        bn254Calculator.registerOperatorPubkey(operator3, operator3Pubkey);
        
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
    
    function testEndToEndECDSAFlow() public {
        // Step 1: Update operator tables using the calculator and updater
        tableUpdater.updateECDSAOperatorTable(operatorSet, referenceTimestamp);
        
        // Step 2: Create a certificate with signatures from operator1 and operator2
        bytes32 messageHash = keccak256("Hello, EigenLayer!");
        
        // Generate signatures from operator1 and operator2
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(operator1Key, messageHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(operator2Key, messageHash);
        
        // Concatenate signatures
        bytes memory sig = abi.encodePacked(r1, s1, v1, r2, s2, v2);
        
        // Create the certificate
        ECDSACertificate memory cert = ECDSACertificate({
            referenceTimestamp: referenceTimestamp,
            messageHash: messageHash,
            sig: sig
        });
        
        // Step 3: Verify the certificate directly
        uint96[] memory signedStakes = ecdsaVerifier.verifyCertificate(cert);
        
        // Verify the result
        // Expected signed stake for operators 1 and 2:
        // Operator 1: 100*1 + 200*2 = 500
        // Operator 2: 150*1 + 50*2 = 250
        // Total: 750
        uint256 expectedSignedStake = 750e18;
        
        // Step 4: Use the consumer contract to verify the certificate
        bool success = consumer.verifyECDSACertificate(cert, true); // Use proportion verification
        assertTrue(success, "Consumer should verify the certificate successfully");
        
        // Check that the message is now certified
        assertTrue(consumer.isMessageCertified(messageHash), "Message should be certified");
    }
    
    function testOperatorEjection() public {
        // Step 1: Update operator tables
        tableUpdater.updateECDSAOperatorTable(operatorSet, referenceTimestamp);
        
        // Step 2: Eject operator3
        uint32[] memory operatorIndices = new uint32[](1);
        operatorIndices[0] = 2; // operator3 is at index 2
        
        tableUpdater.ejectECDSAOperators(operatorSet, referenceTimestamp, operatorIndices);
        
        // Step 3: Verify the total weights after ejection
        // Get the total weights information
        uint96[] memory totalWeights = ecdsaVerifier.totalWeights(referenceTimestamp);
        
        // Expected total weights without operator3:
        // Operator 1: 100*1 + 200*2 = 500
        // Operator 2: 150*1 + 50*2 = 250
        // Total: 750
        uint256 expectedTotalWeight = 750e18;
        
        // Step 4: Create a certificate with a signature from operator3 only
        bytes32 messageHash = keccak256("Hello, EigenLayer!");
        
        // Generate signature from operator3
        (uint8 v3, bytes32 r3, bytes32 s3) = vm.sign(operator3Key, messageHash);
        
        // Create the certificate
        ECDSACertificate memory cert = ECDSACertificate({
            referenceTimestamp: referenceTimestamp,
            messageHash: messageHash,
            sig: abi.encodePacked(r3, s3, v3)
        });
        
        // Step 5: Try to verify the certificate
        uint96[] memory signedStakes = ecdsaVerifier.verifyCertificate(cert);
        
        // The signature is valid, but the stake should be 0 because operator3 was ejected
        assertEq(uint256(signedStakes[0]), 0, "Signed stake[0] should be 0 for ejected operator");
        assertEq(uint256(signedStakes[1]), 0, "Signed stake[1] should be 0 for ejected operator");
        
        // Step 6: Try to use the consumer contract to verify the certificate
        bool success = consumer.verifyECDSACertificate(cert, true); // Use proportion verification
        assertFalse(success, "Consumer should not verify the certificate from ejected operator");
        
        // Check that the message is not certified
        assertFalse(consumer.isMessageCertified(messageHash), "Message should not be certified");
    }
}
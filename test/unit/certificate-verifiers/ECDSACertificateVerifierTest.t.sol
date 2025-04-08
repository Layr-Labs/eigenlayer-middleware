// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {OperatorSet} from "../../../lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IStrategy} from "../../../lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ECDSAOperatorInfo} from "../../../src/operator-tables/ECDSAOperatorTableCalculator.sol";
import {ECDSACertificate, ECDSACertificateVerifier} from "../../../src/certificate-verifiers/ECDSACertificateVerifier.sol";
import {SignatureCheckerLib} from "../../../src/libraries/SignatureCheckerLib.sol";
import {MockStrategy, MockECDSAOperatorRegistry} from "../../mocks/OperatorTableMocks.sol";

contract ECDSACertificateVerifierTest is Test {
    ECDSACertificateVerifier public verifier;
    MockECDSAOperatorRegistry public operatorRegistry;
    
    address public operatorTableUpdater;
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
    
    function setUp() public {
        // Create the operator registry
        operatorRegistry = new MockECDSAOperatorRegistry();
        
        // Set up operator set
        operatorTableUpdater = makeAddr("operatorTableUpdater");
        avs = address(0x1);
        operatorSetId = 1;
        operatorSet = OperatorSet(avs, operatorSetId);
        
        // Create the verifier
        verifier = new ECDSACertificateVerifier(
            operatorSet,
            operatorTableUpdater,
            maxOperatorTableStaleness
        );
        
        // Set up test operators
        operator1 = makeAddr("operator1");
        operator2 = makeAddr("operator2");
        operator3 = makeAddr("operator3");
        
        // Generate private keys for operators
        operator1Key = uint256(keccak256(abi.encodePacked("operator1Key")));
        operator2Key = uint256(keccak256(abi.encodePacked("operator2Key")));
        operator3Key = uint256(keccak256(abi.encodePacked("operator3Key")));
        
        // Store private keys in the registry
        operatorRegistry.setOperatorPrivateKey(operator1, operator1Key);
        operatorRegistry.setOperatorPrivateKey(operator2, operator2Key);
        operatorRegistry.setOperatorPrivateKey(operator3, operator3Key);
        
        // Create operator infos
        ECDSAOperatorInfo[] memory operatorInfos = new ECDSAOperatorInfo[](3);
        
        // Operator 1 - pubkey derived from private key
        operatorInfos[0] = ECDSAOperatorInfo({
            pubkey: vm.addr(operator1Key),
            weights: new uint96[](2)
        });
        operatorInfos[0].weights[0] = 100;
        operatorInfos[0].weights[1] = 100;
        
        // Operator 2 - pubkey derived from private key
        operatorInfos[1] = ECDSAOperatorInfo({
            pubkey: vm.addr(operator2Key),
            weights: new uint96[](2)
        });
        operatorInfos[1].weights[0] = 200;
        operatorInfos[1].weights[1] = 200;
        
        // Operator 3 - pubkey derived from private key
        operatorInfos[2] = ECDSAOperatorInfo({
            pubkey: vm.addr(operator3Key),
            weights: new uint96[](2)
        });
        operatorInfos[2].weights[0] = 300;
        operatorInfos[2].weights[1] = 300;
        
        // Update the operator table
        vm.startPrank(operatorTableUpdater);
        verifier.updateOperatorTable(referenceTimestamp, operatorInfos);
        vm.stopPrank();
    }
    
    function testVerifyCertificate() public {
        // Create a test message hash
        bytes32 messageHash = keccak256("test message");
        
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
        
        // Verify the certificate
        uint96[] memory signedStakes = verifier.verifyCertificate(cert);
        
        // Verify the result
        // Expected signed stake: 100 (operator1) + 200 (operator2) = 300
        assertEq(uint256(signedStakes[0]), 300, "Signed stake[0] incorrect");
        assertEq(uint256(signedStakes[1]), 300, "Signed stake[1] incorrect");
    }
    
    function testVerifyCertificateProportion() public {
        // Create a test message hash
        bytes32 messageHash = keccak256("test message");
        
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
        
        // Set proportion thresholds
        // Total stake is 600 (100 + 200 + 300)
        // Signed stake is 300 (100 + 200)
        // 300/600 = 0.5 = 50%
        uint16[] memory thresholds = new uint16[](2);
        thresholds[0] = 5000; // 50%
        thresholds[1] = 5000; // 50%
        
        // Verify the certificate with proportion thresholds
        bool validProportion = verifier.verifyCertificateProportion(cert, thresholds);
        assertTrue(validProportion, "Certificate should meet proportion thresholds");
        
        // Try with higher thresholds
        thresholds[0] = 5100; // 51%
        thresholds[1] = 5100; // 51%
        
        // This should also pass
        validProportion = verifier.verifyCertificateProportion(cert, thresholds);
        assertFalse(validProportion, "Certificate should not meet higher proportion thresholds");
    }
    
    function testVerifyCertificateNominal() public {
        // Create a test message hash
        bytes32 messageHash = keccak256("test message");
        
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
        
        // Set nominal thresholds
        // Signed stake is 300 (100 + 200)
        uint96[] memory thresholds = new uint96[](2);
        thresholds[0] = 300; // exactly 300
        thresholds[1] = 300; // exactly 300
        
        // Verify the certificate with nominal thresholds
        bool validNominal = verifier.verifyCertificateNominal(cert, thresholds);
        assertTrue(validNominal, "Certificate should meet nominal thresholds");
        
        // Try with higher thresholds
        thresholds[0] = 301; // 301
        thresholds[1] = 301; // 301
        
        // This should fail
        validNominal = verifier.verifyCertificateNominal(cert, thresholds);
        assertFalse(validNominal, "Certificate should not meet higher nominal thresholds");
    }
    
    function testEjectOperators() public {
        // First verify the total weights before ejection
        uint96[] memory weights = verifier.totalWeights(referenceTimestamp);
        assertEq(uint256(weights[0]), 600, "Initial total weight[0] incorrect");
        assertEq(uint256(weights[1]), 600, "Initial total weight[1] incorrect");
        
        // Eject operator1
        uint32[] memory operatorIndices = new uint32[](1);
        operatorIndices[0] = 0; // operator1 is at index 0
        
        vm.prank(operatorTableUpdater);
        verifier.ejectOperators(referenceTimestamp, operatorIndices);
        
        // Verify the total weights after ejection
        // Expected: 600 - 100 = 500
        uint96[] memory weightsAfterEjection = verifier.totalWeights(referenceTimestamp);
        assertEq(uint256(weightsAfterEjection[0]), 500, "Total weight[0] after ejection incorrect");
        assertEq(uint256(weightsAfterEjection[1]), 500, "Total weight[1] after ejection incorrect");
        
        // Verify that operator1's weight is now 0
        assertEq(uint256(verifier.operatorInfos(referenceTimestamp, 0).weights[0]), 0, "Operator1 weight[0] should be zero after ejection");
        assertEq(uint256(verifier.operatorInfos(referenceTimestamp, 0).weights[1]), 0, "Operator1 weight[1] should be zero after ejection");
    }
}
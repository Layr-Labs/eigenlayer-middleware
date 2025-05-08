// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {BN254} from "../../src/libraries/BN254.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {BLSCertificateVerifier} from "../../src/crossChain/BLSCertificateVerifier.sol";
import {IBLSCertificateVerifier, IBLSCertificateVerifierTypes} from "../../src/interfaces/IBLSCertificateVerifier.sol";
import {IBLSTableCalculatorTypes} from "../../src/interfaces/IBLSTableCalculator.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {Merkle} from "../../src/libraries/Merkle.sol";

contract BLSCertificateVerifierTest is Test {
    using BN254 for BN254.G1Point;
    using Merkle for bytes32[];
    using Merkle for bytes;

    // Contract being tested
    BLSCertificateVerifier verifier;
    
    // Test accounts
    address owner = address(0x1);
    address tableUpdater = address(0x2);
    address nonOwner = address(0x3);
    
    // Test data
    uint32 numOperators = 4;
    uint32 maxStaleness = 3600; // 1 hour max staleness
    
    // BLS signature specific fields
    bytes32 msgHash;
    uint256 aggSignerPrivKey = 69; 
    BN254.G2Point aggSignerApkG2; // G2 public key corresponding to aggSignerPrivKey
    
    // Event
    event TableUpdated(uint32 referenceTimestamp, IBLSTableCalculatorTypes.BN254OperatorSetInfo operatorSetInfo);

    function setUp() public {
        vm.warp(1000000);  // Set block timestamp
        
        // Create an OperatorSet for testing
        OperatorSet memory testOperatorSet;
        testOperatorSet.avs = address(0x4);
        testOperatorSet.id = 1;
        
        // Deploy contract with owner
        vm.startPrank(owner);
        verifier = new BLSCertificateVerifier(
            testOperatorSet,
            tableUpdater,
            maxStaleness
        );
        vm.stopPrank();
        
        // Set standard test message hash
        msgHash = keccak256(abi.encodePacked("test message"));
        
        // Set up the aggregate public key in G2
        aggSignerApkG2.X[1] =
            19101821850089705274637533855249918363070101489527618151493230256975900223847;
        aggSignerApkG2.X[0] =
            5334410886741819556325359147377682006012228123419628681352847439302316235957;
        aggSignerApkG2.Y[1] =
            354176189041917478648604979334478067325821134838555150300539079146482658331;
        aggSignerApkG2.Y[0] =
            4185483097059047421902184823581361466320657066600218863748375739772335928910;
    }
    
    // Generate signer and non-signer private keys
    function generateSignerAndNonSignerPrivateKeys(
        uint256 pseudoRandomNumber,
        uint256 numSigners,
        uint256 numNonSigners
    ) internal view returns (uint256[] memory, uint256[] memory) {
        uint256[] memory signerPrivKeys = new uint256[](numSigners);
        uint256 sum = 0;

        // Generate numSigners-1 random keys
        for (uint256 i = 0; i < numSigners - 1; i++) {
            signerPrivKeys[i] = uint256(
                keccak256(abi.encodePacked("signerPrivateKey", pseudoRandomNumber, i))
            ) % BN254.FR_MODULUS;
            sum = addmod(sum, signerPrivKeys[i], BN254.FR_MODULUS);
        }

        // Last key makes the total sum equal to aggSignerPrivKey
        signerPrivKeys[numSigners - 1] = 
            addmod(aggSignerPrivKey, BN254.FR_MODULUS - sum % BN254.FR_MODULUS, BN254.FR_MODULUS);

        // Generate non-signer keys
        uint256[] memory nonSignerPrivKeys = new uint256[](numNonSigners);
        for (uint256 i = 0; i < numNonSigners; i++) {
            nonSignerPrivKeys[i] = uint256(
                keccak256(abi.encodePacked("nonSignerPrivateKey", pseudoRandomNumber, i))
            ) % BN254.FR_MODULUS;
        }

        // Sort nonSignerPrivateKeys in order of ascending pubkeyHash
        for (uint256 i = 1; i < nonSignerPrivKeys.length; i++) {
            uint256 privateKey = nonSignerPrivKeys[i];
            bytes32 pubkeyHash = toPubkeyHash(privateKey);
            uint256 j = i;

            // Move elements that are greater than the current key ahead
            while (j > 0 && toPubkeyHash(nonSignerPrivKeys[j - 1]) > pubkeyHash) {
                nonSignerPrivKeys[j] = nonSignerPrivKeys[j - 1];
                j--;
            }
            nonSignerPrivKeys[j] = privateKey;
        }

        return (signerPrivKeys, nonSignerPrivKeys);
    }
    
    // Helper to hash a public key
    function toPubkeyHash(uint256 privKey) internal view returns (bytes32) {
        return BN254.generatorG1().scalar_mul(privKey).hashG1Point();
    }
    
    // Create operators with split keys
    function createOperatorsWithSplitKeys(uint256 pseudoRandomNumber, uint256 numSigners, uint256 numNonSigners) 
        internal view returns (
            IBLSTableCalculatorTypes.BN254OperatorInfo[] memory,
            uint32[] memory,
            BN254.G1Point memory
        ) 
    {
        require(numSigners + numNonSigners == numOperators, "Total operators mismatch");
        
        // Generate private keys
        (uint256[] memory signerPrivKeys, uint256[] memory nonSignerPrivKeys) = 
            generateSignerAndNonSignerPrivateKeys(pseudoRandomNumber, numSigners, numNonSigners);
        
        // Create all operators
        IBLSTableCalculatorTypes.BN254OperatorInfo[] memory ops = new IBLSTableCalculatorTypes.BN254OperatorInfo[](numOperators);
        
        // Track indices of non-signers
        uint32[] memory nonSignerIndices = new uint32[](numNonSigners);
        
        // Create signers first
        for (uint32 i = 0; i < numSigners; i++) {
            ops[i].pubkey = BN254.generatorG1().scalar_mul(signerPrivKeys[i]);
            ops[i].weights = new uint96[](2);
            ops[i].weights[0] = uint96(100 + i * 10);
            ops[i].weights[1] = uint96(200 + i * 20);
        }
        
        // Create non-signers
        for (uint32 i = 0; i < numNonSigners; i++) {
            uint32 idx = uint32(numSigners + i);
            ops[idx].pubkey = BN254.generatorG1().scalar_mul(nonSignerPrivKeys[i]);
            ops[idx].weights = new uint96[](2);
            ops[idx].weights[0] = uint96(100 + idx * 10);
            ops[idx].weights[1] = uint96(200 + idx * 20);
            nonSignerIndices[i] = idx;
        }
        
        // Calculate aggregate signature for the signers
        BN254.G1Point memory signature = BN254.hashToG1(msgHash).scalar_mul(aggSignerPrivKey);
        
        return (ops, nonSignerIndices, signature);
    }

    function getMerkleProof(IBLSTableCalculatorTypes.BN254OperatorInfo[] memory ops, uint32 operatorIndex) 
        internal returns (bytes memory proof) {
        
        bytes32[] memory leaves = new bytes32[](ops.length);
        for (uint i = 0; i < ops.length; i++) {
            leaves[i] = keccak256(abi.encode(ops[i]));
            emit log_named_bytes32(string.concat("leaf", vm.toString(i)), leaves[i]);
        }
        proof = leaves.getProofKeccak(operatorIndex);
    }
    
    // Create operator set info
    function createOperatorSetInfo(IBLSTableCalculatorTypes.BN254OperatorInfo[] memory ops) 
        internal view returns (IBLSTableCalculatorTypes.BN254OperatorSetInfo memory) {
            
        uint32 _numOperators = uint32(ops.length);
            
        // Create aggregate public key (sum of all operator pubkeys)
        BN254.G1Point memory aggregatePubkey = BN254.G1Point(0, 0);
        
        // Create total weights (sum of all operator weights)
        uint96[] memory _totalWeights = new uint96[](2);
        
        for (uint32 i = 0; i < _numOperators; i++) {
            // Add pubkey to aggregate
            aggregatePubkey = aggregatePubkey.plus(ops[i].pubkey);
            
            // Add weights to total
            for (uint256 j = 0; j < 2; j++) {
                _totalWeights[j] += ops[i].weights[j];
            }
        }

        bytes32[] memory leaves = new bytes32[](ops.length);
        for (uint i = 0; i < ops.length; i++) {
            leaves[i] = keccak256(abi.encode(ops[i]));
        }
        bytes32 operatorInfoTreeRoot = leaves.merkleizeKeccak();
        
        // Create the operator set info
        return IBLSTableCalculatorTypes.BN254OperatorSetInfo({
            numOperators: _numOperators,
            aggregatePubkey: aggregatePubkey,
            totalWeights: _totalWeights,
            operatorInfoTreeRoot: operatorInfoTreeRoot
        });
    }
    
    // Helper to create a certificate with real BLS signature
    function createCertificate(
        uint32 referenceTimestamp,
        bytes32 messageHash,
        uint32[] memory nonSignerIndices,
        IBLSTableCalculatorTypes.BN254OperatorInfo[] memory ops,
        BN254.G1Point memory signature
    ) internal returns (IBLSCertificateVerifierTypes.BN254Certificate memory) {
        
        // Create witnesses for non-signers
        IBLSCertificateVerifierTypes.BN254OperatorInfoWitness[] memory witnesses = 
            new IBLSCertificateVerifierTypes.BN254OperatorInfoWitness[](nonSignerIndices.length);
        
        for (uint256 i = 0; i < nonSignerIndices.length; i++) {
            uint32 nonSignerIndex = nonSignerIndices[i];
            
            witnesses[i] = IBLSCertificateVerifierTypes.BN254OperatorInfoWitness({
                operatorIndex: nonSignerIndex,
                operatorInfoProof: getMerkleProof(ops, nonSignerIndex),
                operatorInfo: ops[nonSignerIndex]
            });
        }
        
        return IBLSCertificateVerifierTypes.BN254Certificate({
            referenceTimestamp: referenceTimestamp,
            messageHash: messageHash,
            signature: signature,
            apk: aggSignerApkG2,
            nonSignerIndices: nonSignerIndices,
            nonSignerWitnesses: witnesses
        });
    }

    // Test updating the operator table
    function testUpdateOperatorTable() public {
        // Create test data
        uint32 referenceTimestamp = uint32(block.timestamp);
        
        // Create operators with split keys - 3 signers, 1 non-signer
        (IBLSTableCalculatorTypes.BN254OperatorInfo[] memory operators, , ) = 
            createOperatorsWithSplitKeys(123, 3, 1);        
        // Create operator set info
        IBLSTableCalculatorTypes.BN254OperatorSetInfo memory operatorSetInfo = createOperatorSetInfo(operators);
        
        vm.startPrank(tableUpdater);
        
        // Expect the TableUpdated event
        vm.expectEmit(true, true, true, true);
        emit TableUpdated(referenceTimestamp, operatorSetInfo);
        
        // Update the operator table
        verifier.updateOperatorTable(
            referenceTimestamp,
            operatorSetInfo
        );
        
        vm.stopPrank();
        
        // Verify storage updates
        assertEq(verifier.latestReferenceTimestamp(), referenceTimestamp, "Reference timestamp not updated correctly");
        
        // Verify operator set info was stored correctly
        (bytes32 storedOperatorInfoTreeRoot, uint256 storedNumOps, BN254.G1Point memory storedAggPubkey) = 
            verifier.operatorSetInfos(referenceTimestamp);
        
        assertEq(storedOperatorInfoTreeRoot, operatorSetInfo.operatorInfoTreeRoot, "Operator info tree root not stored correctly");
        assertEq(storedNumOps, operatorSetInfo.numOperators, "Num operators not stored correctly");
        assertEq(storedAggPubkey.X, operatorSetInfo.aggregatePubkey.X, "Aggregate pubkey X not stored correctly");
        assertEq(storedAggPubkey.Y, operatorSetInfo.aggregatePubkey.Y, "Aggregate pubkey Y not stored correctly");
    }
    
    // Test verifyCertificate with actual BLS signature validation and multiple signers
    function testVerifyCertificate() public {
        // Create test data
        uint32 referenceTimestamp = uint32(block.timestamp);
        
        // Create operators with split keys - 3 signers, 1 non-signer
        uint256 pseudoRandomNumber = 123;
        (
            IBLSTableCalculatorTypes.BN254OperatorInfo[] memory operators, 
            uint32[] memory nonSignerIndices,
            BN254.G1Point memory signature
        ) = createOperatorsWithSplitKeys(pseudoRandomNumber, 3, 1);
                    
        // Create operator set info
        IBLSTableCalculatorTypes.BN254OperatorSetInfo memory operatorSetInfo = createOperatorSetInfo(operators);
        
        vm.prank(tableUpdater);
        verifier.updateOperatorTable(
            referenceTimestamp,
            operatorSetInfo
        );
        
        // Create certificate with real BLS signature
        IBLSCertificateVerifierTypes.BN254Certificate memory cert = createCertificate(
            referenceTimestamp,
            msgHash,
            nonSignerIndices,
            operators,
            signature
        );
        
        // No mocking needed - verify certificate with real verification
        uint96[] memory signedStakes = verifier.verifyCertificate(cert);
        
        // Check that the signed stakes are correct
        assertEq(signedStakes.length, 2, "Wrong number of stake types");
        
        // Calculate expected signed stakes
        uint96[] memory expectedSignedStakes = new uint96[](2);
        
        // Start with total stakes
        expectedSignedStakes[0] = operatorSetInfo.totalWeights[0];
        expectedSignedStakes[1] = operatorSetInfo.totalWeights[1];
        
        // Subtract non-signer stakes
        for (uint i = 0; i < nonSignerIndices.length; i++) {
            uint32 nonSignerIndex = nonSignerIndices[i];
            expectedSignedStakes[0] -= operators[nonSignerIndex].weights[0];
            expectedSignedStakes[1] -= operators[nonSignerIndex].weights[1];
        }
        
        assertEq(signedStakes[0], expectedSignedStakes[0], "Wrong signed stake for type 0");
        assertEq(signedStakes[1], expectedSignedStakes[1], "Wrong signed stake for type 1");
    }
    
    // Test verifyCertificate with a different distribution of signers/non-signers
    function testVerifyCertificateDifferentSplit() public {
        // Create test data
        uint32 referenceTimestamp = uint32(block.timestamp);
        
        // Create operators with split keys - 2 signers, 2 non-signers
        uint256 pseudoRandomNumber = 456;
        (
            IBLSTableCalculatorTypes.BN254OperatorInfo[] memory operators, 
            uint32[] memory nonSignerIndices,
            BN254.G1Point memory signature
        ) = createOperatorsWithSplitKeys(pseudoRandomNumber, 2, 2);
                    
        // Create operator set info
        IBLSTableCalculatorTypes.BN254OperatorSetInfo memory operatorSetInfo = createOperatorSetInfo(operators);
        
        vm.prank(tableUpdater);
        verifier.updateOperatorTable(
            referenceTimestamp,
            operatorSetInfo
        );
        
        // Create certificate with real BLS signature
        IBLSCertificateVerifierTypes.BN254Certificate memory cert = createCertificate(
            referenceTimestamp,
            msgHash,
            nonSignerIndices,
            operators,
            signature
        );
        
        // No mocking needed - verify certificate with real verification
        uint96[] memory signedStakes = verifier.verifyCertificate(cert);
        
        // Calculate expected signed stakes
        uint96[] memory expectedSignedStakes = new uint96[](2);
        
        // Start with total stakes
        expectedSignedStakes[0] = operatorSetInfo.totalWeights[0];
        expectedSignedStakes[1] = operatorSetInfo.totalWeights[1];
        
        // Subtract non-signer stakes
        for (uint i = 0; i < nonSignerIndices.length; i++) {
            uint32 nonSignerIndex = nonSignerIndices[i];
            expectedSignedStakes[0] -= operators[nonSignerIndex].weights[0];
            expectedSignedStakes[1] -= operators[nonSignerIndex].weights[1];
        }
        
        assertEq(signedStakes[0], expectedSignedStakes[0], "Wrong signed stake for type 0");
        assertEq(signedStakes[1], expectedSignedStakes[1], "Wrong signed stake for type 1");
    }
    
    // Test verifyCertificateProportion
    function testVerifyCertificateProportion() public {
        // Create test data
        uint32 referenceTimestamp = uint32(block.timestamp);
        
        // Create operators with split keys - 3 signers, 1 non-signer
        uint256 pseudoRandomNumber = 789;
        (
            IBLSTableCalculatorTypes.BN254OperatorInfo[] memory operators, 
            uint32[] memory nonSignerIndices,
            BN254.G1Point memory signature
        ) = createOperatorsWithSplitKeys(pseudoRandomNumber, 3, 1);
                    
        // Create operator set info
        IBLSTableCalculatorTypes.BN254OperatorSetInfo memory operatorSetInfo = createOperatorSetInfo(operators);
        
        vm.prank(tableUpdater);
        verifier.updateOperatorTable(
            referenceTimestamp,
            operatorSetInfo
        );
        
        // Create certificate with real BLS signature
        IBLSCertificateVerifierTypes.BN254Certificate memory cert = createCertificate(
            referenceTimestamp,
            msgHash,
            nonSignerIndices,
            operators,
            signature
        );
        
        // Set thresholds at 60% of total stake for each type
        uint16[] memory thresholds = new uint16[](2);
        thresholds[0] = 6000; // 60%
        thresholds[1] = 6000; // 60%
        
        // Verify certificate meets thresholds - no mocking needed
        bool meetsThresholds = verifier.verifyCertificateProportion(cert, thresholds);
        
        // With 3 signers out of 4, should meet 60% threshold
        assertTrue(meetsThresholds, "Certificate should meet thresholds");
        
        // Try with higher threshold that shouldn't be met
        thresholds[0] = 9000; // 90%
        thresholds[1] = 9000; // 90%
        
        meetsThresholds = verifier.verifyCertificateProportion(cert, thresholds);
        
        // May or may not meet 90% threshold depending on weights
        // We'll assert based on calculation
        
        // Calculate percentage of signed stakes
        uint96[] memory signedStakes = verifier.verifyCertificate(cert);
        uint256 signedPercentage0 = (uint256(signedStakes[0]) * 10000) / uint256(operatorSetInfo.totalWeights[0]);
        uint256 signedPercentage1 = (uint256(signedStakes[1]) * 10000) / uint256(operatorSetInfo.totalWeights[1]);
        
        bool shouldMeetThreshold = (signedPercentage0 >= 9000) && (signedPercentage1 >= 9000);
        assertEq(meetsThresholds, shouldMeetThreshold, "Certificate threshold check incorrect");
    }
    
    // Test with invalid signature (wrong message hash)
    function testVerifyCertificateInvalidSignature() public {
        // Create test data
        uint32 referenceTimestamp = uint32(block.timestamp);
        
        // Create operators with split keys - 3 signers, 1 non-signer
        uint256 pseudoRandomNumber = 123;
        (
            IBLSTableCalculatorTypes.BN254OperatorInfo[] memory operators, 
            uint32[] memory nonSignerIndices,
            BN254.G1Point memory signature
        ) = createOperatorsWithSplitKeys(pseudoRandomNumber, 3, 1);
                    
        // Create operator set info
        IBLSTableCalculatorTypes.BN254OperatorSetInfo memory operatorSetInfo = createOperatorSetInfo(operators);
        
        vm.prank(tableUpdater);
        verifier.updateOperatorTable(
            referenceTimestamp,
            operatorSetInfo
        );
        
        // Create certificate with real BLS signature but WRONG message hash
        bytes32 wrongHash = keccak256("wrong message");
        
        IBLSCertificateVerifierTypes.BN254Certificate memory cert = createCertificate(
            referenceTimestamp,
            wrongHash, // Use wrong hash here
            nonSignerIndices,
            operators,
            signature // Signature is for original msgHash, not wrongHash
        );
        
        // Verification should fail without mocking
        vm.expectRevert(abi.encodeWithSignature("CertVerificationFailed()"));
        verifier.verifyCertificate(cert);
    }
    
    // Test certificate with stale timestamp (should fail)
    function testVerifyCertificateStaleTimestamp() public {
        // Create test data
        uint32 referenceTimestamp = uint32(block.timestamp);
        
        // Create operators with split keys - 3 signers, 1 non-signer
        uint256 pseudoRandomNumber = 123;
        (
            IBLSTableCalculatorTypes.BN254OperatorInfo[] memory operators, 
            uint32[] memory nonSignerIndices,
            BN254.G1Point memory signature
        ) = createOperatorsWithSplitKeys(pseudoRandomNumber, 3, 1);
            
        // Create operator set info
        IBLSTableCalculatorTypes.BN254OperatorSetInfo memory operatorSetInfo = createOperatorSetInfo(operators);
        
        vm.prank(tableUpdater);
        verifier.updateOperatorTable(
            referenceTimestamp,
            operatorSetInfo
        );
        
        // Create certificate with real BLS signature
        IBLSCertificateVerifierTypes.BN254Certificate memory cert = createCertificate(
            referenceTimestamp,
            msgHash,
            nonSignerIndices,
            operators,
            signature
        );
        
        // Jump forward in time beyond the max staleness
        vm.warp(block.timestamp + maxStaleness + 1);
        
        // Verification should fail due to staleness
        vm.expectRevert(abi.encodeWithSignature("TableStale()"));
        verifier.verifyCertificate(cert);
    }

    // Test verifyCertificateNominal functionality
    function testVerifyCertificateNominal() public {
        // Create test data
        uint32 referenceTimestamp = uint32(block.timestamp);
        
        // Create operators with split keys - 3 signers, 1 non-signer
        uint256 pseudoRandomNumber = 567;
        (
            IBLSTableCalculatorTypes.BN254OperatorInfo[] memory operators, 
            uint32[] memory nonSignerIndices,
            BN254.G1Point memory signature
        ) = createOperatorsWithSplitKeys(pseudoRandomNumber, 3, 1);
                    
        // Create operator set info
        IBLSTableCalculatorTypes.BN254OperatorSetInfo memory operatorSetInfo = createOperatorSetInfo(operators);
        
        vm.prank(tableUpdater);
        verifier.updateOperatorTable(
            referenceTimestamp,
            operatorSetInfo
        );
        
        // Create certificate with real BLS signature
        IBLSCertificateVerifierTypes.BN254Certificate memory cert = createCertificate(
            referenceTimestamp,
            msgHash,
            nonSignerIndices,
            operators,
            signature
        );
        
        // Get the signed stakes first
        uint96[] memory signedStakes = verifier.verifyCertificate(cert);
        
        // Test with thresholds lower than signed stakes (should pass)
        uint96[] memory passThresholds = new uint96[](2);
        passThresholds[0] = signedStakes[0] - 10;
        passThresholds[1] = signedStakes[1] - 10;
        
        bool meetsThresholds = verifier.verifyCertificateNominal(cert, passThresholds);
        assertTrue(meetsThresholds, "Certificate should meet nominal thresholds");
        
        // Test with thresholds higher than signed stakes (should fail)
        uint96[] memory failThresholds = new uint96[](2);
        failThresholds[0] = signedStakes[0] + 10;
        failThresholds[1] = signedStakes[1] + 10;
        
        meetsThresholds = verifier.verifyCertificateNominal(cert, failThresholds);
        assertFalse(meetsThresholds, "Certificate should not meet impossible nominal thresholds");
    }

    // Test ejection of operators
    function testEjectOperators() public {
        // Create test data
        uint32 referenceTimestamp = uint32(block.timestamp);
        
        // Create operators with any distribution (doesn't matter for this test)
        uint256 pseudoRandomNumber = 888;
        (
            IBLSTableCalculatorTypes.BN254OperatorInfo[] memory operators,
            ,
            
        ) = createOperatorsWithSplitKeys(pseudoRandomNumber, numOperators, 0);
                    
        // Create operator set info and store initial total weights
        IBLSTableCalculatorTypes.BN254OperatorSetInfo memory operatorSetInfo = createOperatorSetInfo(operators);
        uint96 initialTotalWeight0 = operatorSetInfo.totalWeights[0];
        uint96 initialTotalWeight1 = operatorSetInfo.totalWeights[1];
        
        vm.startPrank(tableUpdater);
        
        // Update the operator table
        verifier.updateOperatorTable(
            referenceTimestamp,
            operatorSetInfo
        );
        
        // Choose operator index 1 to eject
        uint32 operatorToEject = 1;
        
        // Store the initial weights of the operator to eject
        uint96 ejectedWeight0 = operators[operatorToEject].weights[0];
        uint96 ejectedWeight1 = operators[operatorToEject].weights[1];
        
        // Prepare to eject operator
        uint32[] memory operatorIndicesToEject = new uint32[](1);
        operatorIndicesToEject[0] = operatorToEject;
        
        // Create witnesses for the operator to eject
        IBLSCertificateVerifierTypes.BN254OperatorInfoWitness[] memory witnesses = 
            new IBLSCertificateVerifierTypes.BN254OperatorInfoWitness[](1);
        
        witnesses[0] = IBLSCertificateVerifierTypes.BN254OperatorInfoWitness({
            operatorIndex: operatorToEject,
            operatorInfoProof: getMerkleProof(operators, operatorToEject),
            operatorInfo: operators[operatorToEject]
        });

        
        
        // Eject the operator
        verifier.ejectOperators(
            referenceTimestamp,
            operatorIndicesToEject,
            witnesses
        );
        
        vm.stopPrank();
        
        // Verify the operator's weights are now zero in the stored state
        IBLSTableCalculatorTypes.BN254OperatorInfo memory ejectedOperatorInfo = 
            verifier.getOperatorInfo(referenceTimestamp, operatorToEject);
        
        assertEq(ejectedOperatorInfo.weights[0], 0, "Ejected operator's weight 0 should be zero");
        assertEq(ejectedOperatorInfo.weights[1], 0, "Ejected operator's weight 1 should be zero");
        
        // Verify the total weights have been reduced by the ejected operator's weights
        IBLSTableCalculatorTypes.BN254OperatorSetInfo memory updatedOperatorSetInfo = 
            verifier.getOperatorSetInfo(referenceTimestamp);
        
        assertEq(
            updatedOperatorSetInfo.totalWeights[0], 
            initialTotalWeight0 - ejectedWeight0, 
            "Total weight 0 should be reduced by ejected operator's weight"
        );
        
        assertEq(
            updatedOperatorSetInfo.totalWeights[1], 
            initialTotalWeight1 - ejectedWeight1, 
            "Total weight 1 should be reduced by ejected operator's weight"
        );
    }

    // Test with no non-signers (all operators sign)
    function testVerifyCertificateAllSigners() public {
        // Create test data
        uint32 referenceTimestamp = uint32(block.timestamp);
        
        // Create operators with all signers
        uint256 pseudoRandomNumber = 999;
        (
            IBLSTableCalculatorTypes.BN254OperatorInfo[] memory operators,
            ,
            BN254.G1Point memory signature
        ) = createOperatorsWithSplitKeys(pseudoRandomNumber, numOperators, 0);
                    
        // Create operator set info
        IBLSTableCalculatorTypes.BN254OperatorSetInfo memory operatorSetInfo = createOperatorSetInfo(operators);
        
        vm.prank(tableUpdater);
        verifier.updateOperatorTable(
            referenceTimestamp,
            operatorSetInfo
        );
        
        // Create certificate with no non-signers
        IBLSCertificateVerifierTypes.BN254Certificate memory cert = IBLSCertificateVerifierTypes.BN254Certificate({
            referenceTimestamp: referenceTimestamp,
            messageHash: msgHash,
            signature: signature,
            apk: aggSignerApkG2,
            nonSignerIndices: new uint32[](0),
            nonSignerWitnesses: new IBLSCertificateVerifierTypes.BN254OperatorInfoWitness[](0)
        });
        
        // Verify certificate
        uint96[] memory signedStakes = verifier.verifyCertificate(cert);
        
        // All stakes should be signed
        assertEq(signedStakes[0], operatorSetInfo.totalWeights[0], "All stake should be signed for type 0");
        assertEq(signedStakes[1], operatorSetInfo.totalWeights[1], "All stake should be signed for type 1");
    }

    // Test with invalid reference timestamp
    function testInvalidReferenceTimestamp() public {
        // Create test data - use a non-existent reference timestamp
        uint32 existingReferenceTimestamp = uint32(block.timestamp);
        uint32 nonExistentTimestamp = existingReferenceTimestamp + 1000;
        
        // Create operators with split keys - 3 signers, 1 non-signer
        uint256 pseudoRandomNumber = 123;
        (
            IBLSTableCalculatorTypes.BN254OperatorInfo[] memory operators, 
            uint32[] memory nonSignerIndices,
            BN254.G1Point memory signature
        ) = createOperatorsWithSplitKeys(pseudoRandomNumber, 3, 1);
                    
        // Create operator set info
        IBLSTableCalculatorTypes.BN254OperatorSetInfo memory operatorSetInfo = createOperatorSetInfo(operators);
        
        vm.prank(tableUpdater);
        verifier.updateOperatorTable(
            existingReferenceTimestamp,
            operatorSetInfo
        );
        
        // Create certificate using a non-existent timestamp
        IBLSCertificateVerifierTypes.BN254Certificate memory cert = IBLSCertificateVerifierTypes.BN254Certificate({
            referenceTimestamp: nonExistentTimestamp,
            messageHash: msgHash,
            signature: signature,
            apk: aggSignerApkG2,
            nonSignerIndices: nonSignerIndices,
            nonSignerWitnesses: new IBLSCertificateVerifierTypes.BN254OperatorInfoWitness[](0)
        });
        
        // Verification should fail due to timestamp not existing
        vm.expectRevert(bytes("timestamp does not exist"));
        verifier.verifyCertificate(cert);
    }

}
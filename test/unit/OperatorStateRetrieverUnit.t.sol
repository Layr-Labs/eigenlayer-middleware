// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "../utils/MockAVSDeployer.sol";

contract OperatorStateRetrieverUnitTests is MockAVSDeployer {
    using BN254 for BN254.G1Point;


    function setUp() virtual public {
        numQuorums = 8;
        _deployMockEigenLayerAndAVS(numQuorums);
    }

    function test_getOperatorState_revert_neverRegistered() public {
        cheats.expectRevert("RegistryCoordinator.getQuorumBitmapIndexAtBlockNumber: no bitmap update found for operatorId at block number");
        operatorStateRetriever.getOperatorState(registryCoordinator, defaultOperatorId, uint32(block.number));
    }

    function test_getOperatorState_revert_registeredFirstAfterReferenceBlockNumber() public {
        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, 1, defaultPubKey);

        // should revert because the operator was registered for the first time after the reference block number
        cheats.expectRevert("RegistryCoordinator.getQuorumBitmapIndexAtBlockNumber: no bitmap update found for operatorId at block number");
        operatorStateRetriever.getOperatorState(registryCoordinator, defaultOperatorId, registrationBlockNumber - 1);
    }

    function test_getOperatorState_deregisteredBeforeReferenceBlockNumber() public {
        uint256 quorumBitmap = 1;
        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmap, defaultPubKey);

        cheats.roll(registrationBlockNumber + 10);
        cheats.prank(defaultOperator);
        registryCoordinator.deregisterOperator(BitmapUtils.bitmapToBytesArray(quorumBitmap));

        (uint256 fetchedQuorumBitmap, OperatorStateRetriever.Operator[][] memory operators) = operatorStateRetriever.getOperatorState(registryCoordinator, defaultOperatorId, uint32(block.number));
        assertEq(fetchedQuorumBitmap, 0, "quorumBitmap should be zero because the operator was deregistered before the reference block number");
        assertEq(operators.length, 0, "operators should be empty because the operator was deregistered before the reference block number");
    }

    function test_getOperatorState_registeredAtReferenceBlockNumber() public {
        uint256 quorumBitmap = 1;
        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmap, defaultPubKey);

        (uint256 fetchedQuorumBitmap, OperatorStateRetriever.Operator[][] memory operators) = operatorStateRetriever.getOperatorState(registryCoordinator, defaultOperatorId, uint32(block.number));
        assertEq(fetchedQuorumBitmap, 1, "quorumBitmap should be zero because the operator was deregistered before the reference block number");
        assertEq(operators.length, 1, "operators should be empty because the operator was deregistered before the reference block number");
        assertEq(operators[0].length, 1, "operators should be empty because the operator was deregistered before the reference block number");
        assertEq(operators[0][0].operatorId, defaultOperatorId, "operators should be empty because the operator was deregistered before the reference block number");
        assertEq(operators[0][0].stake, defaultStake, "operators should be empty because the operator was deregistered before the reference block number");
    }

    function test_getOperatorState_revert_quorumNotCreatedAtCallTime() public {
        uint256 nonExistantQuorumBitmap = 1 << numQuorums;

        cheats.expectRevert("IndexRegistry._operatorCountAtBlockNumber: quorum does not exist");
        operatorStateRetriever.getOperatorState(registryCoordinator, BitmapUtils.bitmapToBytesArray(nonExistantQuorumBitmap), uint32(block.number));
    }

    function test_getOperatorState_returnsCorrect() public {
        uint256 quorumBitmapOne = 1;
        uint256 quorumBitmapThree = 3;
        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmapOne, defaultPubKey);

        address otherOperator = _incrementAddress(defaultOperator, 1);
        BN254.G1Point memory otherPubKey = BN254.G1Point(1, 2);
        bytes32 otherOperatorId = BN254.hashG1Point(otherPubKey);
        _registerOperatorWithCoordinator(otherOperator, quorumBitmapThree, otherPubKey, defaultStake -1);

        OperatorStateRetriever.Operator[][] memory operators = operatorStateRetriever.getOperatorState(registryCoordinator, BitmapUtils.bitmapToBytesArray(quorumBitmapThree), uint32(block.number));
        assertEq(operators.length, 2, "operators are registered for 2 quorums, so there should be 2 arrays of operators");
        assertEq(operators[0].length, 2, "operators are registered for 2 quorums, so there should be 1 operator in the first quorum");
        assertEq(operators[1].length, 1, "operators are registered for 2 quorums, so there should be 1 operator in the second quorum");
        assertEq(operators[0][0].operatorId, defaultOperatorId, "the first operator in the first quorum should be the default operator");
        assertEq(operators[0][0].stake, defaultStake, "the first operator in the first quorum should have the default stake");
        assertEq(operators[0][1].operatorId, otherOperatorId, "the second operator in the first quorum should be the other operator");
        assertEq(operators[0][1].stake, defaultStake - 1, "the second operator in the first quorum should have the default stake minus 1");
        assertEq(operators[1][0].operatorId, otherOperatorId, "the first operator in the second quorum should be the other operator");
        assertEq(operators[1][0].stake, defaultStake - 1, "the first operator in the second quorum should have the default stake minus 1");
    }

    function testGetOperatorState_Valid(uint256 pseudoRandomNumber) public {
        // register random operators and get the expected indices within the quorums and the metadata for the operators
        (
            OperatorMetadata[] memory operatorMetadatas,
            uint256[][] memory expectedOperatorOverallIndices
        ) = _registerRandomOperators(pseudoRandomNumber);

        for (uint i = 0; i < operatorMetadatas.length; i++) {
            uint32 blockNumber = uint32(registrationBlockNumber + blocksBetweenRegistrations * i);

            uint256 gasBefore = gasleft();
            // retrieve the ordered list of operators for each quorum along with their id and stake
            (uint256 quorumBitmap, OperatorStateRetriever.Operator[][] memory operators) = 
                operatorStateRetriever.getOperatorState(registryCoordinator, operatorMetadatas[i].operatorId, blockNumber);
            uint256 gasAfter = gasleft();
            emit log_named_uint("gasUsed", gasBefore - gasAfter);

            assertEq(operatorMetadatas[i].quorumBitmap, quorumBitmap);
            bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);
            
            // assert that the operators returned are the expected ones
            _assertExpectedOperators(
                quorumNumbers,
                operators,
                expectedOperatorOverallIndices,
                operatorMetadatas
            );
        }

        // choose a random operator to deregister
        uint256 operatorIndexToDeregister = pseudoRandomNumber % maxOperatorsToRegister;
        bytes memory quorumNumbersToDeregister = BitmapUtils.bitmapToBytesArray(operatorMetadatas[operatorIndexToDeregister].quorumBitmap);

        uint32 deregistrationBlockNumber = registrationBlockNumber + blocksBetweenRegistrations * (uint32(operatorMetadatas.length) + 1);
        cheats.roll(deregistrationBlockNumber);

        cheats.prank(_incrementAddress(defaultOperator, operatorIndexToDeregister));
        registryCoordinator.deregisterOperator(quorumNumbersToDeregister);
        // modify expectedOperatorOverallIndices by moving th operatorIdsToSwap to the index where the operatorIndexToDeregister was
        for (uint i = 0; i < quorumNumbersToDeregister.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbersToDeregister[i]);
            // loop through indices till we find operatorIndexToDeregister, then move that last operator into that index
            for (uint j = 0; j < expectedOperatorOverallIndices[quorumNumber].length; j++) {
                if (expectedOperatorOverallIndices[quorumNumber][j] == operatorIndexToDeregister) {
                    expectedOperatorOverallIndices[quorumNumber][j] = expectedOperatorOverallIndices[quorumNumber][expectedOperatorOverallIndices[quorumNumber].length - 1];
                    break;
                }
            }
        }

        // make sure the state retriever returns the expected state after deregistration
        bytes memory allQuorumNumbers = new bytes(maxQuorumsToRegisterFor);
        for (uint8 i = 0; i < allQuorumNumbers.length; i++) {
            allQuorumNumbers[i] = bytes1(i);
        }
        
        _assertExpectedOperators(
            allQuorumNumbers,
            operatorStateRetriever.getOperatorState(registryCoordinator, allQuorumNumbers, deregistrationBlockNumber),
            expectedOperatorOverallIndices,
            operatorMetadatas
        );
    }

    function testCheckSignaturesIndices_NoNonSigners_Valid(uint256 pseudoRandomNumber) public {
        (
            OperatorMetadata[] memory operatorMetadatas,
            uint256[][] memory expectedOperatorOverallIndices
        ) = _registerRandomOperators(pseudoRandomNumber);

        uint32 cumulativeBlockNumber = registrationBlockNumber + blocksBetweenRegistrations * uint32(operatorMetadatas.length);

        // get the quorum bitmap for which there is at least 1 operator
        uint256 allInclusiveQuorumBitmap = 0;
        for (uint8 i = 0; i < operatorMetadatas.length; i++) {
            allInclusiveQuorumBitmap |= operatorMetadatas[i].quorumBitmap;
        }

        bytes memory allInclusiveQuorumNumbers = BitmapUtils.bitmapToBytesArray(allInclusiveQuorumBitmap);

        bytes32[] memory nonSignerOperatorIds = new bytes32[](0);

        OperatorStateRetriever.CheckSignaturesIndices memory checkSignaturesIndices =
            operatorStateRetriever.getCheckSignaturesIndices(
                registryCoordinator,
                cumulativeBlockNumber, 
                allInclusiveQuorumNumbers, 
                nonSignerOperatorIds
            );

        assertEq(checkSignaturesIndices.nonSignerQuorumBitmapIndices.length, 0, "nonSignerQuorumBitmapIndices should be empty if no nonsigners");
        assertEq(checkSignaturesIndices.quorumApkIndices.length, allInclusiveQuorumNumbers.length, "quorumApkIndices should be the number of quorums queried for");
        assertEq(checkSignaturesIndices.totalStakeIndices.length, allInclusiveQuorumNumbers.length, "totalStakeIndices should be the number of quorums queried for");
        assertEq(checkSignaturesIndices.nonSignerStakeIndices.length, allInclusiveQuorumNumbers.length, "nonSignerStakeIndices should be the number of quorums queried for");

        // assert the indices are the number of registered operators for the quorum minus 1
        for (uint8 i = 0; i < allInclusiveQuorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(allInclusiveQuorumNumbers[i]);
            assertEq(checkSignaturesIndices.quorumApkIndices[i], expectedOperatorOverallIndices[quorumNumber].length, "quorumApkIndex should be the number of registered operators for the quorum");
            assertEq(checkSignaturesIndices.totalStakeIndices[i], expectedOperatorOverallIndices[quorumNumber].length, "totalStakeIndex should be the number of registered operators for the quorum");
        }
    }

    function testCheckSignaturesIndices_FewNonSigners_Valid(uint256 pseudoRandomNumber) public {
        (
            OperatorMetadata[] memory operatorMetadatas,
            uint256[][] memory expectedOperatorOverallIndices
        ) = _registerRandomOperators(pseudoRandomNumber);

        uint32 cumulativeBlockNumber = registrationBlockNumber + blocksBetweenRegistrations * uint32(operatorMetadatas.length);

        // get the quorum bitmap for which there is at least 1 operator
        uint256 allInclusiveQuorumBitmap = 0;
        for (uint8 i = 0; i < operatorMetadatas.length; i++) {
            allInclusiveQuorumBitmap |= operatorMetadatas[i].quorumBitmap;
        }

        bytes memory allInclusiveQuorumNumbers = BitmapUtils.bitmapToBytesArray(allInclusiveQuorumBitmap);

        bytes32[] memory nonSignerOperatorIds = new bytes32[](pseudoRandomNumber % (operatorMetadatas.length - 1) + 1);
        uint256 randomIndex = uint256(keccak256(abi.encodePacked("nonSignerOperatorIds", pseudoRandomNumber))) % operatorMetadatas.length;
        for (uint i = 0; i < nonSignerOperatorIds.length; i++) {
            nonSignerOperatorIds[i] = operatorMetadatas[(randomIndex + i) % operatorMetadatas.length].operatorId;
        }

        OperatorStateRetriever.CheckSignaturesIndices memory checkSignaturesIndices =
            operatorStateRetriever.getCheckSignaturesIndices(
                registryCoordinator,
                cumulativeBlockNumber, 
                allInclusiveQuorumNumbers, 
                nonSignerOperatorIds
            );

        assertEq(checkSignaturesIndices.nonSignerQuorumBitmapIndices.length, nonSignerOperatorIds.length, "nonSignerQuorumBitmapIndices should be the number of nonsigners");
        assertEq(checkSignaturesIndices.quorumApkIndices.length, allInclusiveQuorumNumbers.length, "quorumApkIndices should be the number of quorums queried for");
        assertEq(checkSignaturesIndices.totalStakeIndices.length, allInclusiveQuorumNumbers.length, "totalStakeIndices should be the number of quorums queried for");
        assertEq(checkSignaturesIndices.nonSignerStakeIndices.length, allInclusiveQuorumNumbers.length, "nonSignerStakeIndices should be the number of quorums queried for");

        // assert the indices are the number of registered operators for the quorum minus 1
        for (uint8 i = 0; i < allInclusiveQuorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(allInclusiveQuorumNumbers[i]);
            assertEq(checkSignaturesIndices.quorumApkIndices[i], expectedOperatorOverallIndices[quorumNumber].length, "quorumApkIndex should be the number of registered operators for the quorum");
            assertEq(checkSignaturesIndices.totalStakeIndices[i], expectedOperatorOverallIndices[quorumNumber].length, "totalStakeIndex should be the number of registered operators for the quorum");
        }

        // assert the quorum bitmap and stake indices are zero because there have been no kicks or stake updates
        for (uint i = 0; i < nonSignerOperatorIds.length; i++) {
            assertEq(checkSignaturesIndices.nonSignerQuorumBitmapIndices[i], 0, "nonSignerQuorumBitmapIndices should be zero because there have been no kicks");
        }
        for (uint i = 0; i < checkSignaturesIndices.nonSignerStakeIndices.length; i++) {
            for (uint j = 0; j < checkSignaturesIndices.nonSignerStakeIndices[i].length; j++) {
                assertEq(checkSignaturesIndices.nonSignerStakeIndices[i][j], 0, "nonSignerStakeIndices should be zero because there have been no stake updates past the first one");
            }
        }
    }

    function _assertExpectedOperators(
        bytes memory quorumNumbers,
        OperatorStateRetriever.Operator[][] memory operators,
        uint256[][] memory expectedOperatorOverallIndices,
        OperatorMetadata[] memory operatorMetadatas
    ) internal {
        // for each quorum
        for (uint j = 0; j < quorumNumbers.length; j++) {
            // make sure the each operator id and stake is correct
            for (uint k = 0; k < operators[j].length; k++) {
                uint8 quorumNumber = uint8(quorumNumbers[j]);
                assertEq(operators[j][k].operatorId, operatorMetadatas[expectedOperatorOverallIndices[quorumNumber][k]].operatorId);
                // using assertApprox to account for rounding errors
                assertApproxEqAbs(
                    operators[j][k].stake,
                    operatorMetadatas[expectedOperatorOverallIndices[quorumNumber][k]].stakes[quorumNumber],
                    1
                );
            }
        }
    }
}
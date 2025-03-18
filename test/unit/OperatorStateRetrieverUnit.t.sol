// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../utils/MockAVSDeployer.sol";
import {IStakeRegistryErrors} from "../../src/interfaces/IStakeRegistry.sol";
import {ISlashingRegistryCoordinatorTypes} from "../../src/interfaces/IRegistryCoordinator.sol";
import {IBLSSignatureCheckerTypes} from "../../src/interfaces/IBLSSignatureChecker.sol";
import {BN256G2} from "../../src/libraries/BN256G2.sol";


contract OperatorStateRetrieverUnitTests is MockAVSDeployer {
    using BN254 for BN254.G1Point;

    function setUp() public virtual {
        numQuorums = 8;
        _deployMockEigenLayerAndAVS(numQuorums);
    }

    function test_getOperatorState_revert_neverRegistered() public {
        cheats.expectRevert(
            "RegistryCoordinator.getQuorumBitmapIndexAtBlockNumber: no bitmap update found for operatorId"
        );
        operatorStateRetriever.getOperatorState(
            registryCoordinator, defaultOperatorId, uint32(block.number)
        );
    }

    function test_getOperatorState_revert_registeredFirstAfterReferenceBlockNumber() public {
        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, 1, defaultPubKey);

        // should revert because the operator was registered for the first time after the reference block number
        cheats.expectRevert(
            "RegistryCoordinator.getQuorumBitmapIndexAtBlockNumber: no bitmap update found for operatorId"
        );
        operatorStateRetriever.getOperatorState(
            registryCoordinator, defaultOperatorId, registrationBlockNumber - 1
        );
    }

    function test_getOperatorState_deregisteredBeforeReferenceBlockNumber() public {
        uint256 quorumBitmap = 1;
        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmap, defaultPubKey);

        cheats.roll(registrationBlockNumber + 10);
        cheats.prank(defaultOperator);
        registryCoordinator.deregisterOperator(BitmapUtils.bitmapToBytesArray(quorumBitmap));

        (uint256 fetchedQuorumBitmap, OperatorStateRetriever.Operator[][] memory operators) =
        operatorStateRetriever.getOperatorState(
            registryCoordinator, defaultOperatorId, uint32(block.number)
        );
        assertEq(fetchedQuorumBitmap, 0);
        assertEq(operators.length, 0);
    }

    function test_getOperatorState_registeredAtReferenceBlockNumber() public {
        uint256 quorumBitmap = 1;
        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmap, defaultPubKey);

        (uint256 fetchedQuorumBitmap, OperatorStateRetriever.Operator[][] memory operators) =
        operatorStateRetriever.getOperatorState(
            registryCoordinator, defaultOperatorId, uint32(block.number)
        );
        assertEq(fetchedQuorumBitmap, 1);
        assertEq(operators.length, 1);
        assertEq(operators[0].length, 1);
        assertEq(operators[0][0].operator, defaultOperator);
        assertEq(operators[0][0].operatorId, defaultOperatorId);
        assertEq(operators[0][0].stake, defaultStake);
    }

    function test_getOperatorState_revert_quorumNotCreatedAtCallTime() public {
        cheats.expectRevert(
            "IndexRegistry._operatorCountAtBlockNumber: quorum did not exist at given block number"
        );
        operatorStateRetriever.getOperatorState(
            registryCoordinator,
            BitmapUtils.bitmapToBytesArray(1 << numQuorums),
            uint32(block.number)
        );
    }

    function test_getOperatorState_revert_quorumNotCreatedAtReferenceBlockNumber() public {
        cheats.roll(registrationBlockNumber);
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: defaultMaxOperatorCount,
            kickBIPsOfOperatorStake: defaultKickBIPsOfOperatorStake,
            kickBIPsOfTotalStake: defaultKickBIPsOfTotalStake
        });
        uint96 minimumStake = 1;
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] = IStakeRegistryTypes.StrategyParams({
            strategy: IStrategy(address(1000)),
            multiplier: 1e16
        });

        cheats.prank(registryCoordinator.owner());
        registryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams, minimumStake, strategyParams
        );

        cheats.expectRevert(
            "IndexRegistry._operatorCountAtBlockNumber: quorum did not exist at given block number"
        );
        operatorStateRetriever.getOperatorState(
            registryCoordinator,
            BitmapUtils.bitmapToBytesArray(1 << numQuorums),
            uint32(registrationBlockNumber - 1)
        );
    }

    function test_getOperatorState_returnsCorrect() public {
        uint256 quorumBitmapOne = 1;
        uint256 quorumBitmapThree = 3;
        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmapOne, defaultPubKey);

        address otherOperator = _incrementAddress(defaultOperator, 1);
        BN254.G1Point memory otherPubKey = BN254.G1Point(1, 2);
        bytes32 otherOperatorId = BN254.hashG1Point(otherPubKey);
        _registerOperatorWithCoordinator(
            otherOperator, quorumBitmapThree, otherPubKey, defaultStake - 1
        );

        OperatorStateRetriever.Operator[][] memory operators = operatorStateRetriever
            .getOperatorState(
            registryCoordinator,
            BitmapUtils.bitmapToBytesArray(quorumBitmapThree),
            uint32(block.number)
        );
        assertEq(operators.length, 2);
        assertEq(operators[0].length, 2);
        assertEq(operators[1].length, 1);
        assertEq(operators[0][0].operator, defaultOperator);
        assertEq(operators[0][0].operatorId, defaultOperatorId);
        assertEq(operators[0][0].stake, defaultStake);
        assertEq(operators[0][1].operator, otherOperator);
        assertEq(operators[0][1].operatorId, otherOperatorId);
        assertEq(operators[0][1].stake, defaultStake - 1);
        assertEq(operators[1][0].operator, otherOperator);
        assertEq(operators[1][0].operatorId, otherOperatorId);
        assertEq(operators[1][0].stake, defaultStake - 1);
    }

    function test_getCheckSignaturesIndices_revert_neverRegistered() public {
        bytes32[] memory nonSignerOperatorIds = new bytes32[](1);
        nonSignerOperatorIds[0] = defaultOperatorId;

        cheats.expectRevert(
            "RegistryCoordinator.getQuorumBitmapIndexAtBlockNumber: no bitmap update found for operatorId"
        );
        operatorStateRetriever.getCheckSignaturesIndices(
            registryCoordinator,
            uint32(block.number),
            BitmapUtils.bitmapToBytesArray(1),
            nonSignerOperatorIds
        );
    }

    function test_getCheckSignaturesIndices_revert_registeredFirstAfterReferenceBlockNumber()
        public
    {
        bytes32[] memory nonSignerOperatorIds = new bytes32[](1);
        nonSignerOperatorIds[0] = defaultOperatorId;

        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, 1, defaultPubKey);

        // should revert because the operator was registered for the first time after the reference block number
        cheats.expectRevert(
            "RegistryCoordinator.getQuorumBitmapIndexAtBlockNumber: no bitmap update found for operatorId"
        );
        operatorStateRetriever.getCheckSignaturesIndices(
            registryCoordinator,
            registrationBlockNumber - 1,
            BitmapUtils.bitmapToBytesArray(1),
            nonSignerOperatorIds
        );
    }

    function test_getCheckSignaturesIndices_revert_deregisteredAtReferenceBlockNumber() public {
        bytes32[] memory nonSignerOperatorIds = new bytes32[](1);
        nonSignerOperatorIds[0] = defaultOperatorId;

        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, 1, defaultPubKey);

        cheats.roll(registrationBlockNumber + 10);
        cheats.prank(defaultOperator);
        registryCoordinator.deregisterOperator(BitmapUtils.bitmapToBytesArray(1));

        // should revert because the operator was registered for the first time after the reference block number
        cheats.expectRevert(OperatorStateRetriever.OperatorNotRegistered.selector);
        operatorStateRetriever.getCheckSignaturesIndices(
            registryCoordinator,
            uint32(block.number),
            BitmapUtils.bitmapToBytesArray(1),
            nonSignerOperatorIds
        );
    }

    function test_getCheckSignaturesIndices_revert_quorumNotCreatedAtCallTime() public {
        bytes32[] memory nonSignerOperatorIds = new bytes32[](1);
        nonSignerOperatorIds[0] = defaultOperatorId;

        _registerOperatorWithCoordinator(defaultOperator, 1, defaultPubKey);

        cheats.expectRevert(IStakeRegistryErrors.QuorumDoesNotExist.selector);
        operatorStateRetriever.getCheckSignaturesIndices(
            registryCoordinator,
            uint32(block.number),
            BitmapUtils.bitmapToBytesArray(1 << numQuorums),
            nonSignerOperatorIds
        );
    }

    function test_getCheckSignaturesIndices_revert_quorumNotCreatedAtReferenceBlockNumber()
        public
    {
        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, 1, defaultPubKey);

        cheats.roll(registrationBlockNumber + 10);
        bytes32[] memory nonSignerOperatorIds = new bytes32[](1);
        nonSignerOperatorIds[0] = defaultOperatorId;

        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: defaultMaxOperatorCount,
            kickBIPsOfOperatorStake: defaultKickBIPsOfOperatorStake,
            kickBIPsOfTotalStake: defaultKickBIPsOfTotalStake
        });
        uint96 minimumStake = 1;
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] = IStakeRegistryTypes.StrategyParams({
            strategy: IStrategy(address(1000)),
            multiplier: 1e16
        });

        cheats.prank(registryCoordinator.owner());
        registryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams, minimumStake, strategyParams
        );

        cheats.expectRevert(IStakeRegistryErrors.EmptyStakeHistory.selector);
        operatorStateRetriever.getCheckSignaturesIndices(
            registryCoordinator,
            registrationBlockNumber + 5,
            BitmapUtils.bitmapToBytesArray(1 << numQuorums),
            nonSignerOperatorIds
        );
    }

    function test_getCheckSignaturesIndices_returnsCorrect() public {
        uint256 quorumBitmapOne = 1;
        uint256 quorumBitmapTwo = 2;
        uint256 quorumBitmapThree = 3;

        assertFalse(
            registryCoordinator.operatorSetsEnabled(), "operatorSetsEnabled should be false"
        );

        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmapOne, defaultPubKey);

        cheats.roll(registrationBlockNumber + 10);
        address otherOperator = _incrementAddress(defaultOperator, 1);
        BN254.G1Point memory otherPubKey = BN254.G1Point(1, 2);
        bytes32 otherOperatorId = BN254.hashG1Point(otherPubKey);
        _registerOperatorWithCoordinator(
            otherOperator, quorumBitmapThree, otherPubKey, defaultStake - 1
        );

        cheats.roll(registrationBlockNumber + 15);
        cheats.prank(defaultOperator);
        registryCoordinator.deregisterOperator(BitmapUtils.bitmapToBytesArray(quorumBitmapOne));

        cheats.roll(registrationBlockNumber + 20);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmapTwo, defaultPubKey);

        cheats.roll(registrationBlockNumber + 25);
        cheats.prank(otherOperator);
        registryCoordinator.deregisterOperator(BitmapUtils.bitmapToBytesArray(quorumBitmapTwo));

        cheats.roll(registrationBlockNumber + 30);
        _registerOperatorWithCoordinator(
            otherOperator, quorumBitmapTwo, otherPubKey, defaultStake - 2
        );

        bytes32[] memory nonSignerOperatorIds = new bytes32[](2);
        nonSignerOperatorIds[0] = defaultOperatorId;
        nonSignerOperatorIds[1] = otherOperatorId;

        OperatorStateRetriever.CheckSignaturesIndices memory checkSignaturesIndices =
        operatorStateRetriever.getCheckSignaturesIndices(
            registryCoordinator,
            uint32(block.number),
            BitmapUtils.bitmapToBytesArray(quorumBitmapThree),
            nonSignerOperatorIds
        );
        // we're querying for 2 operators, so there should be 2 nonSignerQuorumBitmapIndices
        assertEq(checkSignaturesIndices.nonSignerQuorumBitmapIndices.length, 2);
        // the first operator (0) registered for quorum 1, (1) deregistered from quorum 1
        assertEq(checkSignaturesIndices.nonSignerQuorumBitmapIndices[0], 2);
        // the second operator (0) registered for quorum 1 and 2 (1) deregistered from quorum 2
        assertEq(checkSignaturesIndices.nonSignerQuorumBitmapIndices[1], 2);
        // the operators, together, serve 2 quorums so there should be 2 quorumApkIndices
        assertEq(checkSignaturesIndices.quorumApkIndices.length, 2);
        // quorum 1 (0) was initialized, (1) the first operator registered, (2) the second operator registered, and (3) the first operator deregistered
        assertEq(checkSignaturesIndices.quorumApkIndices[0], 3);
        // quorum 2 (0) was initialized, (1) the second operator registered, (2) the first operator registered, (3) the second operator deregistered, and (4) the second operator registered
        assertEq(checkSignaturesIndices.quorumApkIndices[1], 4);
        // the operators, together, serve 2 quorums so there should be 2 totalStakeIndices
        assertEq(checkSignaturesIndices.totalStakeIndices.length, 2);
        // quorum 1 (0) was initialized, (1) the first operator registered, (2) the second operator registered, and (3) the first operator deregistered
        assertEq(checkSignaturesIndices.totalStakeIndices[0], 3);
        // quorum 2 (0) was initialized, (1) the second operator registered, (2) the first operator registered, (3) the second operator deregistered, and (4) the second operator registered
        assertEq(checkSignaturesIndices.totalStakeIndices[1], 4);
        // the operators, together, serve 2 quorums so there should be 2 nonSignerStakeIndices
        assertEq(checkSignaturesIndices.nonSignerStakeIndices.length, 2);
        // quorum 1 only has the second operator registered, so there should be 1 nonSignerStakeIndices
        assertEq(checkSignaturesIndices.nonSignerStakeIndices[0].length, 1);
        // the second operator has (0) registered for quorum 1
        assertEq(checkSignaturesIndices.nonSignerStakeIndices[0][0], 0);
        // quorum 2 has both operators registered, so there should be 2 nonSignerStakeIndices
        assertEq(checkSignaturesIndices.nonSignerStakeIndices[1].length, 2);
        // the first operator has (0) registered for quorum 1
        assertEq(checkSignaturesIndices.nonSignerStakeIndices[1][0], 0);
        // the second operator has (0) registered for quorum 2, (1) deregistered from quorum 2, and (2) registered for quorum 2
        assertEq(checkSignaturesIndices.nonSignerStakeIndices[1][1], 2);

        nonSignerOperatorIds = new bytes32[](1);
        nonSignerOperatorIds[0] = otherOperatorId;
        // taking only the deregistration into account
        checkSignaturesIndices = operatorStateRetriever.getCheckSignaturesIndices(
            registryCoordinator,
            registrationBlockNumber + 15,
            BitmapUtils.bitmapToBytesArray(quorumBitmapThree),
            nonSignerOperatorIds
        );
        // we're querying for 1 operator, so there should be 1 nonSignerQuorumBitmapIndices
        assertEq(checkSignaturesIndices.nonSignerQuorumBitmapIndices.length, 1);
        // the second operator (0) registered for quorum 1 and 2
        assertEq(checkSignaturesIndices.nonSignerQuorumBitmapIndices[0], 0);
        // at the time, the operator served 2 quorums so there should be 2 quorumApkIndices
        assertEq(checkSignaturesIndices.quorumApkIndices.length, 2);
        // at the time, quorum 1 (0) was initialized, (1) the first operator registered, (2) the second operator registered, and (3) the first operator deregistered
        assertEq(checkSignaturesIndices.quorumApkIndices[0], 3);
        // at the time, quorum 2 (0) was initialized, (1) the second operator registered
        assertEq(checkSignaturesIndices.quorumApkIndices[1], 1);
        // at the time, the operator served 2 quorums so there should be 2 totalStakeIndices
        assertEq(checkSignaturesIndices.totalStakeIndices.length, 2);
        // at the time, quorum 1 (0) was initialized, (1) the first operator registered, (2) the second operator registered, and (3) the first operator deregistered
        assertEq(checkSignaturesIndices.totalStakeIndices[0], 3);
        // at the time, quorum 2 (0) was initialized, (1) the second operator registered
        assertEq(checkSignaturesIndices.totalStakeIndices[1], 1);
        // at the time, the operator served 2 quorums so there should be 2 nonSignerStakeIndices
        assertEq(checkSignaturesIndices.nonSignerStakeIndices.length, 2);
        // quorum 1 only has the second operator registered, so there should be 1 nonSignerStakeIndices
        assertEq(checkSignaturesIndices.nonSignerStakeIndices[0].length, 1);
        // the second operator has (0) registered for quorum 1
        assertEq(checkSignaturesIndices.nonSignerStakeIndices[0][0], 0);
        // quorum 2 only has the second operator registered, so there should be 1 nonSignerStakeIndices
        assertEq(checkSignaturesIndices.nonSignerStakeIndices[1].length, 1);
        // the second operator has (0) registered for quorum 2
        assertEq(checkSignaturesIndices.nonSignerStakeIndices[1][0], 0);
    }

    function testGetOperatorState_Valid(
        uint256 pseudoRandomNumber
    ) public {
        // register random operators and get the expected indices within the quorums and the metadata for the operators
        (
            OperatorMetadata[] memory operatorMetadatas,
            uint256[][] memory expectedOperatorOverallIndices
        ) = _registerRandomOperators(pseudoRandomNumber);

        for (uint256 i = 0; i < operatorMetadatas.length; i++) {
            uint32 blockNumber = uint32(registrationBlockNumber + blocksBetweenRegistrations * i);

            uint256 gasBefore = gasleft();
            // retrieve the ordered list of operators for each quorum along with their id and stake
            (uint256 quorumBitmap, OperatorStateRetriever.Operator[][] memory operators) =
            operatorStateRetriever.getOperatorState(
                registryCoordinator, operatorMetadatas[i].operatorId, blockNumber
            );
            uint256 gasAfter = gasleft();
            emit log_named_uint("gasUsed", gasBefore - gasAfter);

            assertEq(operatorMetadatas[i].quorumBitmap, quorumBitmap);
            bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

            // assert that the operators returned are the expected ones
            _assertExpectedOperators(
                quorumNumbers, operators, expectedOperatorOverallIndices, operatorMetadatas
            );
        }

        // choose a random operator to deregister
        uint256 operatorIndexToDeregister = pseudoRandomNumber % maxOperatorsToRegister;
        bytes memory quorumNumbersToDeregister = BitmapUtils.bitmapToBytesArray(
            operatorMetadatas[operatorIndexToDeregister].quorumBitmap
        );

        uint32 deregistrationBlockNumber = registrationBlockNumber
            + blocksBetweenRegistrations * (uint32(operatorMetadatas.length) + 1);
        cheats.roll(deregistrationBlockNumber);

        cheats.prank(_incrementAddress(defaultOperator, operatorIndexToDeregister));
        registryCoordinator.deregisterOperator(quorumNumbersToDeregister);
        // modify expectedOperatorOverallIndices by moving th operatorIdsToSwap to the index where the operatorIndexToDeregister was
        for (uint256 i = 0; i < quorumNumbersToDeregister.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbersToDeregister[i]);
            // loop through indices till we find operatorIndexToDeregister, then move that last operator into that index
            for (uint256 j = 0; j < expectedOperatorOverallIndices[quorumNumber].length; j++) {
                if (expectedOperatorOverallIndices[quorumNumber][j] == operatorIndexToDeregister) {
                    expectedOperatorOverallIndices[quorumNumber][j] = expectedOperatorOverallIndices[quorumNumber][expectedOperatorOverallIndices[quorumNumber]
                        .length - 1];
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
            operatorStateRetriever.getOperatorState(
                registryCoordinator, allQuorumNumbers, deregistrationBlockNumber
            ),
            expectedOperatorOverallIndices,
            operatorMetadatas
        );
    }

    function testCheckSignaturesIndices_NoNonSigners_Valid(
        uint256 pseudoRandomNumber
    ) public {
        (
            OperatorMetadata[] memory operatorMetadatas,
            uint256[][] memory expectedOperatorOverallIndices
        ) = _registerRandomOperators(pseudoRandomNumber);

        uint32 cumulativeBlockNumber =
            registrationBlockNumber + blocksBetweenRegistrations * uint32(operatorMetadatas.length);

        // get the quorum bitmap for which there is at least 1 operator
        uint256 allInclusiveQuorumBitmap = 0;
        for (uint8 i = 0; i < operatorMetadatas.length; i++) {
            allInclusiveQuorumBitmap |= operatorMetadatas[i].quorumBitmap;
        }

        bytes memory allInclusiveQuorumNumbers =
            BitmapUtils.bitmapToBytesArray(allInclusiveQuorumBitmap);

        bytes32[] memory nonSignerOperatorIds = new bytes32[](0);

        OperatorStateRetriever.CheckSignaturesIndices memory checkSignaturesIndices =
        operatorStateRetriever.getCheckSignaturesIndices(
            registryCoordinator,
            cumulativeBlockNumber,
            allInclusiveQuorumNumbers,
            nonSignerOperatorIds
        );

        assertEq(
            checkSignaturesIndices.nonSignerQuorumBitmapIndices.length,
            0,
            "nonSignerQuorumBitmapIndices should be empty if no nonsigners"
        );
        assertEq(
            checkSignaturesIndices.quorumApkIndices.length,
            allInclusiveQuorumNumbers.length,
            "quorumApkIndices should be the number of quorums queried for"
        );
        assertEq(
            checkSignaturesIndices.totalStakeIndices.length,
            allInclusiveQuorumNumbers.length,
            "totalStakeIndices should be the number of quorums queried for"
        );
        assertEq(
            checkSignaturesIndices.nonSignerStakeIndices.length,
            allInclusiveQuorumNumbers.length,
            "nonSignerStakeIndices should be the number of quorums queried for"
        );

        // assert the indices are the number of registered operators for the quorum minus 1
        for (uint8 i = 0; i < allInclusiveQuorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(allInclusiveQuorumNumbers[i]);
            assertEq(
                checkSignaturesIndices.quorumApkIndices[i],
                expectedOperatorOverallIndices[quorumNumber].length,
                "quorumApkIndex should be the number of registered operators for the quorum"
            );
            assertEq(
                checkSignaturesIndices.totalStakeIndices[i],
                expectedOperatorOverallIndices[quorumNumber].length,
                "totalStakeIndex should be the number of registered operators for the quorum"
            );
        }
    }

    function testCheckSignaturesIndices_FewNonSigners_Valid(
        uint256 pseudoRandomNumber
    ) public {
        (
            OperatorMetadata[] memory operatorMetadatas,
            uint256[][] memory expectedOperatorOverallIndices
        ) = _registerRandomOperators(pseudoRandomNumber);

        uint32 cumulativeBlockNumber =
            registrationBlockNumber + blocksBetweenRegistrations * uint32(operatorMetadatas.length);

        // get the quorum bitmap for which there is at least 1 operator
        uint256 allInclusiveQuorumBitmap = 0;
        for (uint8 i = 0; i < operatorMetadatas.length; i++) {
            allInclusiveQuorumBitmap |= operatorMetadatas[i].quorumBitmap;
        }

        bytes memory allInclusiveQuorumNumbers =
            BitmapUtils.bitmapToBytesArray(allInclusiveQuorumBitmap);

        bytes32[] memory nonSignerOperatorIds =
            new bytes32[](pseudoRandomNumber % (operatorMetadatas.length - 1) + 1);
        uint256 randomIndex = uint256(
            keccak256(abi.encodePacked("nonSignerOperatorIds", pseudoRandomNumber))
        ) % operatorMetadatas.length;
        for (uint256 i = 0; i < nonSignerOperatorIds.length; i++) {
            nonSignerOperatorIds[i] =
                operatorMetadatas[(randomIndex + i) % operatorMetadatas.length].operatorId;
        }

        OperatorStateRetriever.CheckSignaturesIndices memory checkSignaturesIndices =
        operatorStateRetriever.getCheckSignaturesIndices(
            registryCoordinator,
            cumulativeBlockNumber,
            allInclusiveQuorumNumbers,
            nonSignerOperatorIds
        );

        assertEq(
            checkSignaturesIndices.nonSignerQuorumBitmapIndices.length,
            nonSignerOperatorIds.length,
            "nonSignerQuorumBitmapIndices should be the number of nonsigners"
        );
        assertEq(
            checkSignaturesIndices.quorumApkIndices.length,
            allInclusiveQuorumNumbers.length,
            "quorumApkIndices should be the number of quorums queried for"
        );
        assertEq(
            checkSignaturesIndices.totalStakeIndices.length,
            allInclusiveQuorumNumbers.length,
            "totalStakeIndices should be the number of quorums queried for"
        );
        assertEq(
            checkSignaturesIndices.nonSignerStakeIndices.length,
            allInclusiveQuorumNumbers.length,
            "nonSignerStakeIndices should be the number of quorums queried for"
        );

        // assert the indices are the number of registered operators for the quorum minus 1
        for (uint8 i = 0; i < allInclusiveQuorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(allInclusiveQuorumNumbers[i]);
            assertEq(
                checkSignaturesIndices.quorumApkIndices[i],
                expectedOperatorOverallIndices[quorumNumber].length,
                "quorumApkIndex should be the number of registered operators for the quorum"
            );
            assertEq(
                checkSignaturesIndices.totalStakeIndices[i],
                expectedOperatorOverallIndices[quorumNumber].length,
                "totalStakeIndex should be the number of registered operators for the quorum"
            );
        }

        // assert the quorum bitmap and stake indices are zero because there have been no kicks or stake updates
        for (uint256 i = 0; i < nonSignerOperatorIds.length; i++) {
            assertEq(
                checkSignaturesIndices.nonSignerQuorumBitmapIndices[i],
                0,
                "nonSignerQuorumBitmapIndices should be zero because there have been no kicks"
            );
        }
        for (uint256 i = 0; i < checkSignaturesIndices.nonSignerStakeIndices.length; i++) {
            for (uint256 j = 0; j < checkSignaturesIndices.nonSignerStakeIndices[i].length; j++) {
                assertEq(
                    checkSignaturesIndices.nonSignerStakeIndices[i][j],
                    0,
                    "nonSignerStakeIndices should be zero because there have been no stake updates past the first one"
                );
            }
        }
    }

    function test_getQuorumBitmapsAtBlockNumber_returnsCorrect() public {
        uint256 quorumBitmapOne = 1;
        uint256 quorumBitmapThree = 3;
        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmapOne, defaultPubKey);

        address otherOperator = _incrementAddress(defaultOperator, 1);
        BN254.G1Point memory otherPubKey = BN254.G1Point(1, 2);
        bytes32 otherOperatorId = BN254.hashG1Point(otherPubKey);
        _registerOperatorWithCoordinator(
            otherOperator, quorumBitmapThree, otherPubKey, defaultStake - 1
        );

        bytes32[] memory operatorIds = new bytes32[](2);
        operatorIds[0] = defaultOperatorId;
        operatorIds[1] = otherOperatorId;
        uint256[] memory quorumBitmaps = operatorStateRetriever.getQuorumBitmapsAtBlockNumber(
            registryCoordinator, operatorIds, uint32(block.number)
        );

        assertEq(quorumBitmaps.length, 2);
        assertEq(quorumBitmaps[0], quorumBitmapOne);
        assertEq(quorumBitmaps[1], quorumBitmapThree);
    }

    function _assertExpectedOperators(
        bytes memory quorumNumbers,
        OperatorStateRetriever.Operator[][] memory operators,
        uint256[][] memory expectedOperatorOverallIndices,
        OperatorMetadata[] memory operatorMetadatas
    ) internal {
        // for each quorum
        for (uint256 j = 0; j < quorumNumbers.length; j++) {
            // make sure the each operator id and stake is correct
            for (uint256 k = 0; k < operators[j].length; k++) {
                uint8 quorumNumber = uint8(quorumNumbers[j]);
                assertEq(
                    operators[j][k].operatorId,
                    operatorMetadatas[expectedOperatorOverallIndices[quorumNumber][k]].operatorId
                );
                // using assertApprox to account for rounding errors
                assertApproxEqAbs(
                    operators[j][k].stake,
                    operatorMetadatas[expectedOperatorOverallIndices[quorumNumber][k]].stakes[quorumNumber],
                    1
                );
            }
        }
    }

    function test_getBatchOperatorId_emptyArray() public {
        address[] memory operators = new address[](0);
        bytes32[] memory operatorIds =
            operatorStateRetriever.getBatchOperatorId(registryCoordinator, operators);
        assertEq(operatorIds.length, 0, "Should return empty array for empty input");
    }

    function test_getBatchOperatorId_unregisteredOperators() public {
        address[] memory operators = new address[](2);
        operators[0] = address(1);
        operators[1] = address(2);

        bytes32[] memory operatorIds =
            operatorStateRetriever.getBatchOperatorId(registryCoordinator, operators);

        assertEq(operatorIds.length, 2, "Should return array of same length as input");
        assertEq(operatorIds[0], bytes32(0), "Unregistered operator should return 0");
        assertEq(operatorIds[1], bytes32(0), "Unregistered operator should return 0");
    }

    function test_getBatchOperatorId_mixedRegistration() public {
        // Register one operator
        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, 1, defaultPubKey);

        // Create test array with one registered and one unregistered operator
        address[] memory operators = new address[](2);
        operators[0] = defaultOperator;
        operators[1] = address(2); // unregistered

        bytes32[] memory operatorIds =
            operatorStateRetriever.getBatchOperatorId(registryCoordinator, operators);

        assertEq(operatorIds.length, 2, "Should return array of same length as input");
        assertEq(
            operatorIds[0], defaultOperatorId, "Should return correct ID for registered operator"
        );
        assertEq(operatorIds[1], bytes32(0), "Should return 0 for unregistered operator");
    }

    function test_getBatchOperatorFromId_emptyArray() public {
        bytes32[] memory operatorIds = new bytes32[](0);
        address[] memory operators =
            operatorStateRetriever.getBatchOperatorFromId(registryCoordinator, operatorIds);
        assertEq(operators.length, 0, "Should return empty array for empty input");
    }

    function test_getBatchOperatorFromId_unregisteredIds() public {
        bytes32[] memory operatorIds = new bytes32[](2);
        operatorIds[0] = bytes32(uint256(1));
        operatorIds[1] = bytes32(uint256(2));

        address[] memory operators =
            operatorStateRetriever.getBatchOperatorFromId(registryCoordinator, operatorIds);

        assertEq(operators.length, 2, "Should return array of same length as input");
        assertEq(operators[0], address(0), "Unregistered ID should return address(0)");
        assertEq(operators[1], address(0), "Unregistered ID should return address(0)");
    }

    function test_getBatchOperatorFromId_mixedRegistration() public {
        // Register one operator
        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, 1, defaultPubKey);

        // Create test array with one registered and one unregistered operator ID
        bytes32[] memory operatorIds = new bytes32[](2);
        operatorIds[0] = defaultOperatorId;
        operatorIds[1] = bytes32(uint256(2)); // unregistered

        address[] memory operators =
            operatorStateRetriever.getBatchOperatorFromId(registryCoordinator, operatorIds);

        assertEq(operators.length, 2, "Should return array of same length as input");
        assertEq(operators[0], defaultOperator, "Should return correct address for registered ID");
        assertEq(operators[1], address(0), "Should return address(0) for unregistered ID");
    }

    // helper function to generate a G2 point from a scalar
    function _makeG2Point(uint256 scalar) internal returns (BN254.G2Point memory) {
        // BN256G2.ECTwistMul returns (X0, X1, Y0, Y1) in that order
        (uint256 reX, uint256 imX, uint256 reY, uint256 imY) =
            BN256G2.ECTwistMul(scalar, BN254.G2x0, BN254.G2x1, BN254.G2y0, BN254.G2y1);

        // BN254.G2Point uses [im, re] ordering
        return BN254.G2Point(
            [imX, reX],
            [imY, reY]
        );
    }

    // helper function to add two G2 points
    function _addG2Points(BN254.G2Point memory a, BN254.G2Point memory b)
        internal
        returns (BN254.G2Point memory)
    {
        BN254.G2Point memory sum;
        // sum starts as (0,0), so we add a first:
        (sum.X[1], sum.X[0], sum.Y[1], sum.Y[0]) = BN256G2.ECTwistAdd(
            // sum so far
            sum.X[1], sum.X[0], sum.Y[1], sum.Y[0],
            // a (flip to [im, re] for BN256G2)
            a.X[1], a.X[0], a.Y[1], a.Y[0]
        );
        // then add b:
        (sum.X[1], sum.X[0], sum.Y[1], sum.Y[0]) = BN256G2.ECTwistAdd(
            sum.X[1], sum.X[0], sum.Y[1], sum.Y[0],
            b.X[1], b.X[0], b.Y[1], b.Y[0]
        );
        return sum;
    }

    function test_getNonSignerStakesAndSignature_returnsCorrect() public {
        // setup
        uint256 quorumBitmapOne = 1;
        uint256 quorumBitmapThree = 3;
        cheats.roll(registrationBlockNumber);

        _registerOperatorWithCoordinator(defaultOperator, quorumBitmapOne, defaultPubKey);

        address otherOperator = _incrementAddress(defaultOperator, 1);
        BN254.G1Point memory otherPubKey = BN254.G1Point(1, 2);
        _registerOperatorWithCoordinator(otherOperator, quorumBitmapThree, otherPubKey, defaultStake - 1);

        // Generate actual G2 pubkeys
        BN254.G2Point memory op1G2 = _makeG2Point(2);
        BN254.G2Point memory op2G2 = _makeG2Point(3);

        // Mock the registry calls so the contract sees those G2 points
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, defaultOperator),
            abi.encode(op1G2)
        );
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, otherOperator),
            abi.encode(op2G2)
        );

        // Prepare inputs
        BN254.G1Point memory dummySigma = BN254.scalar_mul_tiny(BN254.generatorG1(), 123);
        address[] memory signingOperators = new address[](2);
        signingOperators[0] = defaultOperator;
        signingOperators[1] = otherOperator;

        bytes memory quorumNumbers = new bytes(2);
        quorumNumbers[0] = bytes1(uint8(0));
        quorumNumbers[1] = bytes1(uint8(1));

        // Call the function under test
        IBLSSignatureCheckerTypes.NonSignerStakesAndSignature memory result =
            operatorStateRetriever.getNonSignerStakesAndSignature(
                registryCoordinator,
                quorumNumbers,
                dummySigma,
                signingOperators,
                uint32(block.number)
            );

        // Non-signers
        assertEq(result.nonSignerQuorumBitmapIndices.length, 0, "Should have no non-signer");
        assertEq(result.nonSignerPubkeys.length, 0, "Should have no non-signer pubkeys");

        // Quorum APKs
        assertEq(result.quorumApks.length, 2, "Should have 2 quorum APKs");
        (BN254.G1Point memory expectedApk0) = _getApkAtBlocknumber(registryCoordinator, 0, uint32(block.number));
        (BN254.G1Point memory expectedApk1) = _getApkAtBlocknumber(registryCoordinator, 1, uint32(block.number));
        assertEq(result.quorumApks[0].X, expectedApk0.X, "First quorum APK X mismatch");
        assertEq(result.quorumApks[0].Y, expectedApk0.Y, "First quorum APK Y mismatch");
        assertEq(result.quorumApks[1].X, expectedApk1.X, "Second quorum APK X mismatch");
        assertEq(result.quorumApks[1].Y, expectedApk1.Y, "Second quorum APK Y mismatch");

        // Aggregated G2 = op1G2 + op2G2
        BN254.G2Point memory expectedSum = _addG2Points(op1G2, op2G2);
        assertEq(result.apkG2.X[0], expectedSum.X[0], "aggregated X[0] mismatch");
        assertEq(result.apkG2.X[1], expectedSum.X[1], "aggregated X[1] mismatch");
        assertEq(result.apkG2.Y[0], expectedSum.Y[0], "aggregated Y[0] mismatch");
        assertEq(result.apkG2.Y[1], expectedSum.Y[1], "aggregated Y[1] mismatch");

        // Sigma
        assertEq(result.sigma.X, dummySigma.X, "Sigma X mismatch");
        assertEq(result.sigma.Y, dummySigma.Y, "Sigma Y mismatch");

        // Indices
        assertEq(result.quorumApkIndices.length, 2, "Should have 2 quorum APK indices");
        assertEq(result.quorumApkIndices[0], 1, "First quorum APK index mismatch");
        assertEq(result.quorumApkIndices[1], 1, "Second quorum APK index mismatch");
        assertEq(result.totalStakeIndices.length, 2, "Should have 2 total stake indices");
        assertEq(result.totalStakeIndices[0], 1, "First total stake index mismatch");
        assertEq(result.totalStakeIndices[1], 1, "Second total stake index mismatch");

        // Non-signer stake indices
        assertEq(result.nonSignerStakeIndices.length, 2, "Should have 2 arrays of non-signer stake indices");
        assertEq(result.nonSignerStakeIndices[0].length, 0, "First quorum non-signer mismatch");
        assertEq(result.nonSignerStakeIndices[1].length, 0, "Second quorum non-signer mismatch");
    }

    function test_getNonSignerStakesAndSignature_returnsCorrect_oneSigner() public {
        // setup
        uint256 quorumBitmapOne = 1;
        uint256 quorumBitmapThree = 3;
        cheats.roll(registrationBlockNumber);

        _registerOperatorWithCoordinator(defaultOperator, quorumBitmapOne, defaultPubKey);

        address otherOperator = _incrementAddress(defaultOperator, 1);
        BN254.G1Point memory otherPubKey = BN254.G1Point(1, 2);
        _registerOperatorWithCoordinator(otherOperator, quorumBitmapThree, otherPubKey, defaultStake - 1);

        // Generate actual G2 pubkeys
        BN254.G2Point memory op1G2 = _makeG2Point(2);
        BN254.G2Point memory op2G2 = _makeG2Point(3);

        // Mock them
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, defaultOperator),
            abi.encode(op1G2)
        );
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, otherOperator),
            abi.encode(op2G2)
        );

        // Prepare input
        BN254.G1Point memory dummySigma = BN254.scalar_mul_tiny(BN254.generatorG1(), 123);

        address[] memory signingOperators = new address[](1);
        signingOperators[0] = defaultOperator; // only op1

        bytes memory quorumNumbers = new bytes(2);
        quorumNumbers[0] = bytes1(uint8(0));
        quorumNumbers[1] = bytes1(uint8(1));

        // Call under test
        IBLSSignatureCheckerTypes.NonSignerStakesAndSignature memory result =
            operatorStateRetriever.getNonSignerStakesAndSignature(
                registryCoordinator,
                quorumNumbers,
                dummySigma,
                signingOperators,
                uint32(block.number)
            );

        // Validate
        // One non-signer => otherOperator
        assertEq(result.nonSignerQuorumBitmapIndices.length, 1, "Should have 1 non-signer");
        assertEq(result.nonSignerPubkeys.length, 1, "Should have 1 non-signer pubkey");

        // Quorum APKs
        assertEq(result.quorumApks.length, 2, "Should have 2 quorum APKs");
        (BN254.G1Point memory expectedApk0) = _getApkAtBlocknumber(registryCoordinator, 0, uint32(block.number));
        (BN254.G1Point memory expectedApk1) = _getApkAtBlocknumber(registryCoordinator, 1, uint32(block.number));
        assertEq(result.quorumApks[0].X, expectedApk0.X, "First quorum APK X mismatch");
        assertEq(result.quorumApks[0].Y, expectedApk0.Y, "First quorum APK Y mismatch");
        assertEq(result.quorumApks[1].X, expectedApk1.X, "Second quorum APK X mismatch");
        assertEq(result.quorumApks[1].Y, expectedApk1.Y, "Second quorum APK Y mismatch");

        // Since only defaultOperator signed, aggregator's G2 should match op1G2
        assertEq(result.apkG2.X[0], op1G2.X[0], "aggregated X[0] mismatch");
        assertEq(result.apkG2.X[1], op1G2.X[1], "aggregated X[1] mismatch");
        assertEq(result.apkG2.Y[0], op1G2.Y[0], "aggregated Y[0] mismatch");
        assertEq(result.apkG2.Y[1], op1G2.Y[1], "aggregated Y[1] mismatch");

        // Sigma
        assertEq(result.sigma.X, dummySigma.X, "Sigma X mismatch");
        assertEq(result.sigma.Y, dummySigma.Y, "Sigma Y mismatch");

        // Indices
        assertEq(result.quorumApkIndices.length, 2, "Should have 2 quorum APK indices");
        assertEq(result.quorumApkIndices[0], 1, "First quorum index mismatch");
        assertEq(result.quorumApkIndices[1], 1, "Second quorum index mismatch");
        assertEq(result.totalStakeIndices.length, 2, "Should have 2 total stake indices");
        assertEq(result.totalStakeIndices[0], 1, "First total stake index mismatch");
        assertEq(result.totalStakeIndices[1], 1, "Second total stake index mismatch");

        // Non-signer stake indices
        // Each quorum has exactly 1 non-signer (the otherOperator)
        assertEq(result.nonSignerStakeIndices.length, 2, "Should have 2 arrays of non-signer stake indices");
        assertEq(result.nonSignerStakeIndices[0].length, 1, "First quorum should have 1 non-signer stake index");
        assertEq(result.nonSignerStakeIndices[1].length, 1, "Second quorum should have 1 non-signer stake index");
    }

    function test_getNonSignerStakesAndSignature_changingQuorumOperatorSet() public {
        // setup
        uint256 quorumBitmapOne = 1;
        uint256 quorumBitmapThree = 3;
        cheats.roll(registrationBlockNumber);

        _registerOperatorWithCoordinator(defaultOperator, quorumBitmapOne, defaultPubKey);

        address otherOperator = _incrementAddress(defaultOperator, 1);
        BN254.G1Point memory otherPubKey = BN254.G1Point(1, 2);
        _registerOperatorWithCoordinator(otherOperator, quorumBitmapThree, otherPubKey, defaultStake - 1);

        // Generate actual G2 pubkeys
        BN254.G2Point memory op1G2 = _makeG2Point(2);
        BN254.G2Point memory op2G2 = _makeG2Point(3);

        // Mock the registry calls so the contract sees those G2 points
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, defaultOperator),
            abi.encode(op1G2)
        );
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, otherOperator),
            abi.encode(op2G2)
        );

        // Prepare inputs
        BN254.G1Point memory dummySigma = BN254.scalar_mul_tiny(BN254.generatorG1(), 123);
        address[] memory signingOperators = new address[](2);
        signingOperators[0] = defaultOperator;
        signingOperators[1] = otherOperator;

        bytes memory quorumNumbers = new bytes(2);
        quorumNumbers[0] = bytes1(uint8(0));
        quorumNumbers[1] = bytes1(uint8(1));

        // Deregister the otherOperator
        cheats.roll(registrationBlockNumber + 10);
        cheats.prank(otherOperator);
        registryCoordinator.deregisterOperator(BitmapUtils.bitmapToBytesArray(quorumBitmapThree));

        // Call the function under test
        IBLSSignatureCheckerTypes.NonSignerStakesAndSignature memory result =
            operatorStateRetriever.getNonSignerStakesAndSignature(
                registryCoordinator,
                quorumNumbers,
                dummySigma,
                signingOperators,
                registrationBlockNumber
            );

        // Non-signers
        assertEq(result.nonSignerQuorumBitmapIndices.length, 0, "Should have no non-signer");
        assertEq(result.nonSignerPubkeys.length, 0, "Should have no non-signer pubkeys");

        // Quorum APKs
        assertEq(result.quorumApks.length, 2, "Should have 2 quorum APKs");
        (BN254.G1Point memory expectedApk0) = _getApkAtBlocknumber(registryCoordinator, 0, uint32(registrationBlockNumber));
        (BN254.G1Point memory expectedApk1) = _getApkAtBlocknumber(registryCoordinator, 1, uint32(registrationBlockNumber));
        assertEq(result.quorumApks[0].X, expectedApk0.X, "First quorum APK X mismatch");
        assertEq(result.quorumApks[0].Y, expectedApk0.Y, "First quorum APK Y mismatch");
        assertEq(result.quorumApks[1].X, expectedApk1.X, "Second quorum APK X mismatch");
        assertEq(result.quorumApks[1].Y, expectedApk1.Y, "Second quorum APK Y mismatch");

        // Aggregated G2 = op1G2 + op2G2
        BN254.G2Point memory expectedSum = _addG2Points(op1G2, op2G2);
        assertEq(result.apkG2.X[0], expectedSum.X[0], "aggregated X[0] mismatch");
        assertEq(result.apkG2.X[1], expectedSum.X[1], "aggregated X[1] mismatch");
        assertEq(result.apkG2.Y[0], expectedSum.Y[0], "aggregated Y[0] mismatch");
        assertEq(result.apkG2.Y[1], expectedSum.Y[1], "aggregated Y[1] mismatch");

        // Sigma
        assertEq(result.sigma.X, dummySigma.X, "Sigma X mismatch");
        assertEq(result.sigma.Y, dummySigma.Y, "Sigma Y mismatch");

        // Indices
        assertEq(result.quorumApkIndices.length, 2, "Should have 2 quorum APK indices");
        assertEq(result.quorumApkIndices[0], 1, "First quorum APK index mismatch");
        assertEq(result.quorumApkIndices[1], 1, "Second quorum APK index mismatch");
        assertEq(result.totalStakeIndices.length, 2, "Should have 2 total stake indices");
        assertEq(result.totalStakeIndices[0], 1, "First total stake index mismatch");
        assertEq(result.totalStakeIndices[1], 1, "Second total stake index mismatch");

        // Non-signer stake indices
        assertEq(result.nonSignerStakeIndices.length, 2, "Should have 2 arrays of non-signer stake indices");
        assertEq(result.nonSignerStakeIndices[0].length, 0, "First quorum non-signer mismatch");
        assertEq(result.nonSignerStakeIndices[1].length, 0, "Second quorum non-signer mismatch");
    }

    function test_getNonSignerStakesAndSignature_revert_signerNeverRegistered() public {
        // Setup - register only one operator
        uint256 quorumBitmap = 1;  // Quorum 0 only
        
        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmap, defaultPubKey);
        
        // Create G2 points for the registered operator
        BN254.G2Point memory op1G2 = _makeG2Point(2);
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, defaultOperator),
            abi.encode(op1G2)
        );
        
        // Create a dummy signature
        BN254.G1Point memory dummySigma = BN254.scalar_mul_tiny(BN254.generatorG1(), 123);
        
        // Try to include an unregistered operator as a signer
        address unregisteredOperator = _incrementAddress(defaultOperator, 1);
        address[] memory signingOperators = new address[](2);
        signingOperators[0] = defaultOperator;
        signingOperators[1] = unregisteredOperator;  // This operator was never registered
        
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(uint8(0));  // Quorum 0
        
        // Should revert because one of the signers was never registered
        cheats.expectRevert(bytes("RegistryCoordinator.getQuorumBitmapIndexAtBlockNumber: no bitmap update found for operatorId"));
        operatorStateRetriever.getNonSignerStakesAndSignature(
            registryCoordinator,
            quorumNumbers,
            dummySigma,
            signingOperators,
            uint32(block.number)
        );
    }

    function test_getNonSignerStakesAndSignature_revert_signerRegisteredAfterReferenceBlock() public {
        // Setup - register one operator
        uint256 quorumBitmap = 1;  // Quorum 0 only
        
        // Save initial block number
        uint32 initialBlock = registrationBlockNumber;
        
        cheats.roll(initialBlock);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmap, defaultPubKey);
        
        // Register second operator later
        cheats.roll(initialBlock + 10);
        address secondOperator = _incrementAddress(defaultOperator, 1);
        BN254.G1Point memory secondPubKey = BN254.G1Point(1, 2);
        _registerOperatorWithCoordinator(secondOperator, quorumBitmap, secondPubKey, defaultStake - 1);
        
        // Create G2 points for both operators
        BN254.G2Point memory op1G2 = _makeG2Point(2);
        BN254.G2Point memory op2G2 = _makeG2Point(3);
        
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, defaultOperator),
            abi.encode(op1G2)
        );
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, secondOperator),
            abi.encode(op2G2)
        );
        
        // Create a dummy signature
        BN254.G1Point memory dummySigma = BN254.scalar_mul_tiny(BN254.generatorG1(), 123);
        
        // Include both operators as signers
        address[] memory signingOperators = new address[](2);
        signingOperators[0] = defaultOperator;
        signingOperators[1] = secondOperator;
        
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(uint8(0));  // Quorum 0
        
        // Should revert when querying at a block before the second operator was registered
        cheats.expectRevert(bytes("RegistryCoordinator.getQuorumBitmapIndexAtBlockNumber: no bitmap update found for operatorId"));
        operatorStateRetriever.getNonSignerStakesAndSignature(
            registryCoordinator,
            quorumNumbers,
            dummySigma,
            signingOperators,
            initialBlock + 5
        );
    }

    function test_getNonSignerStakesAndSignature_revert_signerDeregisteredAtReferenceBlock() public {
        // Setup - register two operators
        uint256 quorumBitmap = 1;  // Quorum 0 only
        
        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmap, defaultPubKey);
        
        address secondOperator = _incrementAddress(defaultOperator, 1);
        BN254.G1Point memory secondPubKey = BN254.G1Point(1, 2);
        _registerOperatorWithCoordinator(secondOperator, quorumBitmap, secondPubKey, defaultStake - 1);
        
        // Create G2 points for the operators
        BN254.G2Point memory op1G2 = _makeG2Point(2);
        BN254.G2Point memory op2G2 = _makeG2Point(3);
        
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, defaultOperator),
            abi.encode(op1G2)
        );
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, secondOperator),
            abi.encode(op2G2)
        );
        
        // Deregister the second operator
        cheats.roll(registrationBlockNumber + 10);
        cheats.prank(secondOperator);
        registryCoordinator.deregisterOperator(BitmapUtils.bitmapToBytesArray(quorumBitmap));
        
        // Create a dummy signature
        BN254.G1Point memory dummySigma = BN254.scalar_mul_tiny(BN254.generatorG1(), 123);
        
        // Include both operators as signers
        address[] memory signingOperators = new address[](2);
        signingOperators[0] = defaultOperator;
        signingOperators[1] = secondOperator;  // This operator is deregistered
        
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(uint8(0));  // Quorum 0
        
        // Should revert because secondOperator was deregistered
        cheats.expectRevert(OperatorStateRetriever.OperatorNotRegistered.selector);
        operatorStateRetriever.getNonSignerStakesAndSignature(
            registryCoordinator,
            quorumNumbers,
            dummySigma,
            signingOperators,
            uint32(block.number)
        );
    }

    function test_getNonSignerStakesAndSignature_revert_quorumNotCreatedAtCallTime() public {
        // Setup - register one operator
        uint256 quorumBitmap = 1;  // Quorum 0 only
        
        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmap, defaultPubKey);
        
        // Create G2 points for the operator
        BN254.G2Point memory op1G2 = _makeG2Point(2);
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, defaultOperator),
            abi.encode(op1G2)
        );
        
        // Create a dummy signature
        BN254.G1Point memory dummySigma = BN254.scalar_mul_tiny(BN254.generatorG1(), 123);
        
        // Include the operator as a signer
        address[] memory signingOperators = new address[](1);
        signingOperators[0] = defaultOperator;
        
        // Try to query for a non-existent quorum (quorum 9)
        bytes memory invalidQuorumNumbers = new bytes(1);
        invalidQuorumNumbers[0] = bytes1(uint8(9));  // Invalid quorum number
        
        // Should revert because quorum 9 doesn't exist, but with a different error message
        cheats.expectRevert(bytes("IndexRegistry._operatorCountAtBlockNumber: quorum did not exist at given block number"));
        operatorStateRetriever.getNonSignerStakesAndSignature(
            registryCoordinator,
            invalidQuorumNumbers,
            dummySigma,
            signingOperators,
            uint32(block.number)
        );
    }

    function test_getNonSignerStakesAndSignature_revert_quorumNotCreatedAtReferenceBlock() public {
        // Setup - register one operator in quorum 0
        uint256 quorumBitmap = 1; 
        
        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmap, defaultPubKey);
        
        // Save this block number
        uint32 initialBlock = uint32(block.number);
        
        // Create a new quorum later
        cheats.roll(initialBlock + 10);
        
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: defaultMaxOperatorCount,
            kickBIPsOfOperatorStake: defaultKickBIPsOfOperatorStake,
            kickBIPsOfTotalStake: defaultKickBIPsOfTotalStake
        });
        uint96 minimumStake = 1;
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] = IStakeRegistryTypes.StrategyParams({
            strategy: IStrategy(address(1000)),
            multiplier: 1e16
        });

        // Create quorum 8
        cheats.prank(registryCoordinator.owner());
        registryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams, minimumStake, strategyParams
        );
        
        // Create G2 points for the operator
        BN254.G2Point memory op1G2 = _makeG2Point(2);
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, defaultOperator),
            abi.encode(op1G2)
        );
        
        // Create a dummy signature
        BN254.G1Point memory dummySigma = BN254.scalar_mul_tiny(BN254.generatorG1(), 123);
        
        // Include the operator as a signer
        address[] memory signingOperators = new address[](1);
        signingOperators[0] = defaultOperator;
        
        // Try to query for the newly created quorum but at a historical block
        bytes memory newQuorumNumbers = new bytes(1);
        newQuorumNumbers[0] = bytes1(uint8(numQuorums));  
        
        // Should revert when querying for the newly created quorum at a block before it was created
        cheats.expectRevert(bytes("IndexRegistry._operatorCountAtBlockNumber: quorum did not exist at given block number"));
        operatorStateRetriever.getNonSignerStakesAndSignature(
            registryCoordinator,
            newQuorumNumbers,
            dummySigma,
            signingOperators,
            initialBlock
        );
    }

    function _getApkAtBlocknumber(ISlashingRegistryCoordinator registryCoordinator, uint8 quorumNumber, uint32 blockNumber) internal view returns (BN254.G1Point memory) {
        bytes32[] memory operatorIds = registryCoordinator.indexRegistry().getOperatorListAtBlockNumber(quorumNumber, blockNumber);
        BN254.G1Point memory apk = BN254.G1Point(0, 0);
        IBLSApkRegistry blsApkRegistry = registryCoordinator.blsApkRegistry();
        for (uint256 i = 0; i < operatorIds.length; i++) {
            address operator = registryCoordinator.getOperatorFromId(operatorIds[i]);
            BN254.G1Point memory operatorPk;
            (operatorPk.X, operatorPk.Y) = blsApkRegistry.operatorToPubkey(operator);
            apk = BN254.plus(apk, operatorPk);
        }
        return apk;
    }
}

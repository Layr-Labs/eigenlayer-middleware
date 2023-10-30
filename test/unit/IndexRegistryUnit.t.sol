//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "../../src/interfaces/IIndexRegistry.sol";
import "../../src/IndexRegistry.sol";
import "../mocks/RegistryCoordinatorMock.sol";
import "../harnesses/BitmapUtilsWrapper.sol";

import "forge-std/Test.sol";

contract IndexRegistryUnitTests is Test {
    Vm cheats = Vm(HEVM_ADDRESS);

    IndexRegistry indexRegistry;
    RegistryCoordinatorMock registryCoordinatorMock;
    BitmapUtilsWrapper bitmapUtilsWrapper;

    uint8 defaultQuorumNumber = 1;
    bytes32 operatorId1 = bytes32(uint256(34));
    bytes32 operatorId2 = bytes32(uint256(35));
    bytes32 operatorId3 = bytes32(uint256(36));

    // Track initialized quorums so we can filter these out when fuzzing
    mapping(uint8 => bool) initializedQuorums;

    // Test 0 length operators in operators to remove
    function setUp() public {
        // deploy the contract
        registryCoordinatorMock = new RegistryCoordinatorMock();
        indexRegistry = new IndexRegistry(registryCoordinatorMock);
        bitmapUtilsWrapper = new BitmapUtilsWrapper();

        // Initialize quorums and add to fuzz filter
        _initializeQuorum(defaultQuorumNumber);
        _initializeQuorum(defaultQuorumNumber + 1);
        _initializeQuorum(defaultQuorumNumber + 2);
    }

    function testConstructor() public {
        // check that the registry coordinator is set correctly
        assertEq(address(indexRegistry.registryCoordinator()), address(registryCoordinatorMock));
    }

    /*******************************************************************************
                            UNIT TESTS - REGISTRATION
    *******************************************************************************/

    /**
     * Preconditions for registration -> checks in BLSRegistryCoordinator
     * 1. quorumNumbers has no duplicates
     * 2. quorumNumbers ordered in ascending order
     * 3. quorumBitmap is <= uint192.max
     * 4. quorumNumbers.length != 0
     * 5. operator is not already registerd for any quorums being registered for
     */
    function testRegisterOperator() public {
        // register an operator
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        cheats.prank(address(registryCoordinatorMock));
        uint32[] memory numOperatorsPerQuorum = indexRegistry.registerOperator(operatorId1, quorumNumbers);

        // Check return value
        require(
            numOperatorsPerQuorum.length == 1,
            "IndexRegistry.registerOperator: numOperatorsPerQuorum length not 1"
        );
        require(numOperatorsPerQuorum[0] == 1, "IndexRegistry.registerOperator: numOperatorsPerQuorum[0] not 1");


        // Check _operatorIdToIndexHistory updates
        IIndexRegistry.OperatorUpdate memory operatorUpdate = indexRegistry
            .getOperatorIndexUpdateOfIndexForQuorumAtIndex({operatorIndex: 0, quorumNumber: 1, index: 0});
        require(operatorUpdate.operatorId == operatorId1, "IndexRegistry.registerOperator: operatorId not operatorId1");
        require(
            operatorUpdate.fromBlockNumber == block.number,
            "IndexRegistry.registerOperator: fromBlockNumber not correct"
        );

        // Check _totalOperatorsHistory updates
        IIndexRegistry.QuorumUpdate memory quorumUpdate = indexRegistry
            .getQuorumUpdateAtIndex(1, 1);
        require(
            quorumUpdate.numOperators == 1,
            "IndexRegistry.registerOperator: totalOperatorsHistory num operators not 1"
        );
        require(
            quorumUpdate.fromBlockNumber == block.number,
            "IndexRegistry.registerOperator: totalOperatorsHistory fromBlockNumber not correct"
        );
        require(
            indexRegistry.totalOperatorsForQuorum(1) == 1,
            "IndexRegistry.registerOperator: total operators for quorum not updated correctly"
        );
    }

    function testRegisterOperatorMultipleQuorums() public {
        // Register operator for 1st quorum
        testRegisterOperator();

        // Register operator for 2nd quorum
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber + 1);

        cheats.prank(address(registryCoordinatorMock));
        uint32[] memory numOperatorsPerQuorum = indexRegistry.registerOperator(operatorId1, quorumNumbers);

        ///@notice The only value that should be different from before are what quorum we index into and the globalOperatorList
        // Check return value
        require(
            numOperatorsPerQuorum.length == 1,
            "IndexRegistry.registerOperator: numOperatorsPerQuorum length not 2"
        );
        require(numOperatorsPerQuorum[0] == 1, "IndexRegistry.registerOperator: numOperatorsPerQuorum[1] not 1");

        // Check _operatorIdToIndexHistory updates
        IIndexRegistry.OperatorUpdate memory operatorUpdate = indexRegistry
            .getOperatorIndexUpdateOfIndexForQuorumAtIndex({operatorIndex: 0, quorumNumber: 2, index: 0});
        require(operatorUpdate.operatorId == operatorId1, "IndexRegistry.registerOperator: operatorId not operatorId1");
        require(
            operatorUpdate.fromBlockNumber == block.number,
            "IndexRegistry.registerOperator: fromBlockNumber not correct"
        );

        // Check _totalOperatorsHistory updates
        IIndexRegistry.QuorumUpdate memory quorumUpdate = indexRegistry
            .getQuorumUpdateAtIndex(2, 1);
        require(
            quorumUpdate.numOperators == 1,
            "IndexRegistry.registerOperator: totalOperatorsHistory num operators not 1"
        );
        require(
            quorumUpdate.fromBlockNumber == block.number,
            "IndexRegistry.registerOperator: totalOperatorsHistory fromBlockNumber not correct"
        );
        require(
            indexRegistry.totalOperatorsForQuorum(2) == 1,
            "IndexRegistry.registerOperator: total operators for quorum not updated correctly"
        );
    }

    function testRegisterOperatorMultipleQuorumsSingleCall() public {
        // Register operator for 1st and 2nd quorum
        bytes memory quorumNumbers = new bytes(2);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        quorumNumbers[1] = bytes1(defaultQuorumNumber + 1);

        cheats.prank(address(registryCoordinatorMock));
        uint32[] memory numOperatorsPerQuorum = indexRegistry.registerOperator(operatorId1, quorumNumbers);

        // Check return value
        require(
            numOperatorsPerQuorum.length == 2,
            "IndexRegistry.registerOperator: numOperatorsPerQuorum length not 2"
        );
        require(numOperatorsPerQuorum[0] == 1, "IndexRegistry.registerOperator: numOperatorsPerQuorum[0] not 1");
        require(numOperatorsPerQuorum[1] == 1, "IndexRegistry.registerOperator: numOperatorsPerQuorum[1] not 1");

        // Check _operatorIdToIndexHistory updates for quorum 1
        IIndexRegistry.OperatorUpdate memory operatorUpdate = indexRegistry
            .getOperatorIndexUpdateOfIndexForQuorumAtIndex({operatorIndex: 0, quorumNumber: 1, index: 0});
        require(operatorUpdate.operatorId == operatorId1, "IndexRegistry.registerOperator: operatorId not 1operatorId1");
        require(
            operatorUpdate.fromBlockNumber == block.number,
            "IndexRegistry.registerOperator: fromBlockNumber not correct"
        );

        // Check _totalOperatorsHistory updates for quorum 1
        IIndexRegistry.QuorumUpdate memory quorumUpdate = indexRegistry
            .getQuorumUpdateAtIndex(1, 1);
        require(
            quorumUpdate.numOperators == 1,
            "IndexRegistry.registerOperator: totalOperatorsHistory numOperators not 1"
        );
        require(
            quorumUpdate.fromBlockNumber == block.number,
            "IndexRegistry.registerOperator: totalOperatorsHistory fromBlockNumber not correct"
        );
        require(
            indexRegistry.totalOperatorsForQuorum(1) == 1,
            "IndexRegistry.registerOperator: total operators for quorum not updated correctly"
        );

        // Check _operatorIdToIndexHistory updates for quorum 2
        operatorUpdate = indexRegistry.getOperatorIndexUpdateOfIndexForQuorumAtIndex({operatorIndex: 0 , quorumNumber: 2, index: 0});
        require(operatorUpdate.operatorId == operatorId1, "IndexRegistry.registerOperator: operatorId not operatorId1");
        require(
            operatorUpdate.fromBlockNumber == block.number,
            "IndexRegistry.registerOperator: fromBlockNumber not correct"
        );

        // Check _totalOperatorsHistory updates for quorum 2
        quorumUpdate = indexRegistry.getQuorumUpdateAtIndex(2, 1);
        require(
            quorumUpdate.numOperators == 1,
            "IndexRegistry.registerOperator: totalOperatorsHistory num operators not 1"
        );
        require(
            quorumUpdate.fromBlockNumber == block.number,
            "IndexRegistry.registerOperator: totalOperatorsHistory fromBlockNumber not correct"
        );
        require(
            indexRegistry.totalOperatorsForQuorum(2) == 1,
            "IndexRegistry.registerOperator: total operators for quorum not updated correctly"
        );
    }

    function testRegisterMultipleOperatorsSingleQuorum() public {
        // Register operator for first quorum
        testRegisterOperator();

        // Register another operator
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        cheats.prank(address(registryCoordinatorMock));
        uint32[] memory numOperatorsPerQuorum = indexRegistry.registerOperator(operatorId2, quorumNumbers);

        // Check return value
        require(
            numOperatorsPerQuorum.length == 1,
            "IndexRegistry.registerOperator: numOperatorsPerQuorum length not 1"
        );
        require(numOperatorsPerQuorum[0] == 2, "IndexRegistry.registerOperator: numOperatorsPerQuorum[0] not 2");

        // Check _operatorIdToIndexHistory updates
        IIndexRegistry.OperatorUpdate memory operatorUpdate = indexRegistry
            .getOperatorIndexUpdateOfIndexForQuorumAtIndex({operatorIndex: 1, quorumNumber: 1, index: 0});
        require(operatorUpdate.operatorId == operatorId2, "IndexRegistry.registerOperator: operatorId not operatorId2");
        require(
            operatorUpdate.fromBlockNumber == block.number,
            "IndexRegistry.registerOperator: fromBlockNumber not correct"
        );

        // Check _totalOperatorsHistory updates
        IIndexRegistry.QuorumUpdate memory quorumUpdate = indexRegistry
            .getQuorumUpdateAtIndex(1, 2);
        require(
            quorumUpdate.numOperators == 2,
            "IndexRegistry.registerOperator: totalOperatorsHistory num operators not 2"
        );
        require(
            quorumUpdate.fromBlockNumber == block.number,
            "IndexRegistry.registerOperator: totalOperatorsHistory fromBlockNumber not correct"
        );
        require(
            indexRegistry.totalOperatorsForQuorum(1) == 2,
            "IndexRegistry.registerOperator: total operators for quorum not updated correctly"
        );
    }

    /*******************************************************************************
                            UNIT TESTS - DEREGISTRATION
    *******************************************************************************/

    function testDeregisterOperatorSingleOperator() public {
        // Register operator
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        _registerOperator(operatorId1, quorumNumbers);

        // Deregister operator
        cheats.prank(address(registryCoordinatorMock));
        indexRegistry.deregisterOperator(operatorId1, quorumNumbers);

        // Check operator's index
        IIndexRegistry.OperatorUpdate memory operatorUpdate = indexRegistry
            .getOperatorIndexUpdateOfIndexForQuorumAtIndex({operatorIndex: 0, quorumNumber: defaultQuorumNumber, index: 1});
        require(operatorUpdate.fromBlockNumber == block.number, "fromBlockNumber not set correctly");
        require(operatorUpdate.operatorId == bytes32(0), "incorrect operatorId");

        // Check total operators
        IIndexRegistry.QuorumUpdate memory quorumUpdate = indexRegistry
            .getQuorumUpdateAtIndex(defaultQuorumNumber, 2);
        require(quorumUpdate.fromBlockNumber == block.number, "fromBlockNumber not set correctly");
        require(quorumUpdate.numOperators == 0, "incorrect total number of operators");
        require(indexRegistry.totalOperatorsForQuorum(1) == 0, "operator not deregistered correctly");
    }

    function testDeregisterOperatorMultipleQuorums() public {
        // Register 3 operators to two quorums
        bytes memory quorumNumbers = new bytes(3);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        quorumNumbers[1] = bytes1(defaultQuorumNumber + 1);
        quorumNumbers[2] = bytes1(defaultQuorumNumber + 2);
        _registerOperator(operatorId1, quorumNumbers);
        _registerOperator(operatorId2, quorumNumbers);
        _registerOperator(operatorId3, quorumNumbers);

        // Deregister operator from quorums 1 and 2
        bytes memory quorumsToRemove = new bytes(2);
        quorumsToRemove[0] = bytes1(defaultQuorumNumber);
        quorumsToRemove[1] = bytes1(defaultQuorumNumber + 1);

        cheats.prank(address(registryCoordinatorMock));
        indexRegistry.deregisterOperator(operatorId1, quorumsToRemove);

        // Check operator's index for removed quorums
        for (uint256 i = 0; i < quorumsToRemove.length; i++) {
            IIndexRegistry.OperatorUpdate memory operatorUpdate = indexRegistry
                .getOperatorIndexUpdateOfIndexForQuorumAtIndex({operatorIndex: 2, quorumNumber: uint8(quorumsToRemove[i]), index: 1}); // 2 indexes -> 1 update and 1 remove
            require(operatorUpdate.fromBlockNumber == block.number, "fromBlockNumber not set correctly");
            require(operatorUpdate.operatorId == bytes32(0), "incorrect operatorId");
        }

        // Check total operators for removed quorums
        for (uint256 i = 0; i < quorumsToRemove.length; i++) {
            IIndexRegistry.QuorumUpdate memory quorumUpdate = indexRegistry
                .getQuorumUpdateAtIndex(uint8(quorumsToRemove[i]), 4); // 5 updates total
            require(quorumUpdate.fromBlockNumber == block.number, "fromBlockNumber not set correctly");
            require(quorumUpdate.numOperators == 2, "incorrect total number of operators");
            require(
                indexRegistry.totalOperatorsForQuorum(uint8(quorumsToRemove[i])) == 2,
                "operator not deregistered correctly"
            );
        }

        // Check swapped operator's index for removed quorums
        for (uint256 i = 0; i < quorumsToRemove.length; i++) {
            IIndexRegistry.OperatorUpdate memory operatorUpdate = indexRegistry
                .getOperatorIndexUpdateOfIndexForQuorumAtIndex({operatorIndex: 0, quorumNumber: uint8(quorumsToRemove[i]), index: 1}); // 2 indexes -> 1 update and 1 swap
            require(operatorUpdate.fromBlockNumber == block.number, "fromBlockNumber not set correctly");
            require(operatorUpdate.operatorId == operatorId3, "incorrect operatorId");
        }
    }

    /*******************************************************************************
                                UNIT TESTS - GETTERS
    *******************************************************************************/

    function testGetTotalOperatorsForQuorumAtBlockNumberByIndex_revert_indexTooEarly() public {
        // Add operator
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        _registerOperator(operatorId1, quorumNumbers);

        cheats.expectRevert(
            "IndexRegistry.getTotalOperatorsForQuorumAtBlockNumberByIndex: provided index is too far in the past for provided block number"
        );
        indexRegistry.getTotalOperatorsForQuorumAtBlockNumberByIndex(defaultQuorumNumber, uint32(block.number - 1), 0);
    }

    function testGetTotalOperatorsForQuorumAtBlockNumberByIndex_revert_indexBlockMismatch() public {
        // Add two operators
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        _registerOperator(operatorId1, quorumNumbers);
        vm.roll(block.number + 10);
        _registerOperator(operatorId2, quorumNumbers);

        cheats.expectRevert(
            "IndexRegistry.getTotalOperatorsForQuorumAtBlockNumberByIndex: provided index is too far in the future for provided block number"
        );
        indexRegistry.getTotalOperatorsForQuorumAtBlockNumberByIndex(defaultQuorumNumber, uint32(block.number), 0);
    }

    function testGetTotalOperatorsForQuorumAtBlockNumberByIndex() public {
        // Add two operators
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        _registerOperator(operatorId1, quorumNumbers);
        vm.roll(block.number + 10);
        _registerOperator(operatorId2, quorumNumbers);

        // Check that the first total is correct
        uint32 prevTotal = indexRegistry.getTotalOperatorsForQuorumAtBlockNumberByIndex(
            defaultQuorumNumber,
            uint32(block.number - 10),
            1
        );
        require(prevTotal == 1, "IndexRegistry.getTotalOperatorsForQuorumAtBlockNumberByIndex: prev total not 1");

        // Check that the total is correct
        uint32 currentTotal = indexRegistry.getTotalOperatorsForQuorumAtBlockNumberByIndex(
            defaultQuorumNumber,
            uint32(block.number),
            2
        );
        require(currentTotal == 2, "IndexRegistry.getTotalOperatorsForQuorumAtBlockNumberByIndex: current total not 2");
    }

    function testGetOperatorListForQuorumAtBlockNumber() public {
        // Register two operators
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        _registerOperator(operatorId1, quorumNumbers);
        vm.roll(block.number + 10);
        _registerOperator(operatorId2, quorumNumbers);

        // Deregister first operator
        vm.roll(block.number + 10);
        cheats.prank(address(registryCoordinatorMock));
        indexRegistry.deregisterOperator(operatorId1, quorumNumbers);

        // Check the operator list after first registration
        bytes32[] memory operatorList = indexRegistry.getOperatorListForQuorumAtBlockNumber(
            defaultQuorumNumber,
            uint32(block.number - 20)
        );
        require(
            operatorList.length == 1,
            "IndexRegistry.getOperatorListForQuorumAtBlockNumber: operator list length not 1"
        );
        require(
            operatorList[0] == operatorId1,
            "IndexRegistry.getOperatorListForQuorumAtBlockNumber: operator list incorrect"
        );

        // Check the operator list after second registration
        operatorList = indexRegistry.getOperatorListForQuorumAtBlockNumber(
            defaultQuorumNumber,
            uint32(block.number - 10)
        );
        require(
            operatorList.length == 2,
            "IndexRegistry.getOperatorListForQuorumAtBlockNumber: operator list length not 2"
        );
        require(
            operatorList[0] == operatorId1,
            "IndexRegistry.getOperatorListForQuorumAtBlockNumber: operator list incorrect"
        );
        require(
            operatorList[1] == operatorId2,
            "IndexRegistry.getOperatorListForQuorumAtBlockNumber: operator list incorrect"
        );

        // Check the operator list after deregistration
        operatorList = indexRegistry.getOperatorListForQuorumAtBlockNumber(defaultQuorumNumber, uint32(block.number));
        require(
            operatorList.length == 1,
            "IndexRegistry.getOperatorListForQuorumAtBlockNumber: operator list length not 1"
        );
        require(
            operatorList[0] == operatorId2,
            "IndexRegistry.getOperatorListForQuorumAtBlockNumber: operator list incorrect"
        );
    }

    /*******************************************************************************
                                    FUZZ TESTS
    *******************************************************************************/

    function testFuzzRegisterOperatorRevertFromNonRegisterCoordinator(address nonRegistryCoordinator) public {
        cheats.assume(address(registryCoordinatorMock) != nonRegistryCoordinator);
        bytes memory quorumNumbers = new bytes(defaultQuorumNumber);

        cheats.prank(nonRegistryCoordinator);
        cheats.expectRevert(bytes("IndexRegistry.onlyRegistryCoordinator: caller is not the registry coordinator"));
        indexRegistry.registerOperator(bytes32(0), quorumNumbers);
    }

    function testFuzzTotalOperatorUpdatesForOneQuorum(uint8 numOperators) public {
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        uint256 lengthBefore = 0;
        for (uint256 i = 0; i < numOperators; i++) {
            _registerOperator(bytes32(i), quorumNumbers);
            require(indexRegistry.totalOperatorsForQuorum(1) - lengthBefore == 1, "incorrect update");
            lengthBefore++;
        }
    }

    /**
     * Preconditions for registration -> checks in BLSRegistryCoordinator
     * 1. quorumNumbers has no duplicates
     * 2. quorumNumbers ordered in ascending order
     * 3. quorumBitmap is <= uint192.max
     * 4. quorumNumbers.length != 0
     * 5. operator is not already registerd for any quorums being registered for
     */
    function testFuzzRegisterOperatorMultipleQuorums(bytes memory quorumNumbers) public {
        // Initialize quorum numbers, skipping invalid tests
        _initializeFuzzedQuorums(quorumNumbers);

        // Register for quorums
        cheats.prank(address(registryCoordinatorMock));
        uint32[] memory numOperatorsPerQuorum = indexRegistry.registerOperator(operatorId1, quorumNumbers);

        // Check return value
        require(
            numOperatorsPerQuorum.length == quorumNumbers.length,
            "IndexRegistry.registerOperator: numOperatorsPerQuorum length not correct"
        );
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            require(numOperatorsPerQuorum[i] == 1, "IndexRegistry.registerOperator: numOperatorsPerQuorum not 1");
        }

        // Check _operatorIdToIndexHistory updates
        IIndexRegistry.OperatorUpdate memory operatorUpdate;
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            operatorUpdate = indexRegistry.getOperatorIndexUpdateOfIndexForQuorumAtIndex({
                operatorIndex: 0,
                quorumNumber: uint8(quorumNumbers[i]),
                index: 0
            });
            require(operatorUpdate.operatorId == operatorId1, "IndexRegistry.registerOperator: operatorId not operatorId1");
            require(
                operatorUpdate.fromBlockNumber == block.number,
                "IndexRegistry.registerOperator: fromBlockNumber not correct"
            );
        }

        // Check _totalOperatorsHistory updates
        IIndexRegistry.QuorumUpdate memory quorumUpdate;
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            quorumUpdate = indexRegistry.getQuorumUpdateAtIndex(uint8(quorumNumbers[i]), 1);
            require(
                quorumUpdate.numOperators == 1,
                "IndexRegistry.registerOperator: totalOperatorsHistory num operators not 1"
            );
            require(
                quorumUpdate.fromBlockNumber == block.number,
                "IndexRegistry.registerOperator: totalOperatorsHistory fromBlockNumber not correct"
            );
            require(
                indexRegistry.totalOperatorsForQuorum(uint8(quorumNumbers[i])) == 1,
                "IndexRegistry.registerOperator: total operators for quorum not updated correctly"
            );
        }
    }

    function testFuzzRegisterMultipleOperatorsMultipleQuorums(bytes memory quorumNumbers) public {
        // Initialize quorum numbers, skipping invalid tests
        _initializeFuzzedQuorums(quorumNumbers);

        // Register operators 1,2,3
        _registerOperator(operatorId1, quorumNumbers);
        vm.roll(block.number + 10);
        _registerOperator(operatorId2, quorumNumbers);
        vm.roll(block.number + 10);
        _registerOperator(operatorId3, quorumNumbers);

        // Check history of _totalOperatorsHistory updates at each blockNumber
        IIndexRegistry.QuorumUpdate memory quorumUpdate;
        uint256 numOperators = 1;
        for (uint256 blockNumber = block.number - 20; blockNumber <= block.number; blockNumber += 10) {
            for (uint256 i = 0; i < quorumNumbers.length; i++) {
                quorumUpdate = indexRegistry.getQuorumUpdateAtIndex(
                    uint8(quorumNumbers[i]),
                    uint32(numOperators)
                );
                require(
                    quorumUpdate.numOperators == numOperators,
                    "IndexRegistry.registerOperator: totalOperatorsHistory num operators not correct"
                );
                require(
                    quorumUpdate.fromBlockNumber == blockNumber,
                    "IndexRegistry.registerOperator: totalOperatorsHistory fromBlockNumber not correct"
                );
            }
            numOperators++;
        }
    }

    function testFuzzDeregisterOperatorRevertFromNonRegisterCoordinator(address nonRegistryCoordinator) public {
        cheats.assume(address(registryCoordinatorMock) != nonRegistryCoordinator);
        // de-register an operator
        bytes memory quorumNumbers = new bytes(defaultQuorumNumber);

        cheats.prank(nonRegistryCoordinator);
        cheats.expectRevert(bytes("IndexRegistry.onlyRegistryCoordinator: caller is not the registry coordinator"));
        indexRegistry.deregisterOperator(bytes32(0), quorumNumbers);
    }

    function testFuzzDeregisterOperator(bytes memory quorumsToAdd, uint256 bitsToFlip) public {
        // Initialize quorum numbers, skipping invalid tests
        _initializeFuzzedQuorums(quorumsToAdd);
        uint bitmap = bitmapUtilsWrapper.orderedBytesArrayToBitmap(quorumsToAdd);
        
        // Format
        bitsToFlip = bound(bitsToFlip, 1, quorumsToAdd.length);
        uint256 bitsFlipped = 0;
        uint256 bitPosition = 0;
        uint256 bitmapQuorumsToRemove = bitmap;
        while (bitsFlipped < bitsToFlip && bitPosition < 192) {
            uint256 bitMask = 1 << bitPosition;
            if (bitmapQuorumsToRemove & bitMask != 0) {
                bitmapQuorumsToRemove ^= bitMask;
                bitsFlipped++;
            }
            bitPosition++;
        }
        bytes memory quorumsToRemove = bitmapUtilsWrapper.bitmapToBytesArray(bitmapQuorumsToRemove);
        // Sanity check quorumsToRemove
        cheats.assume(bitmapUtilsWrapper.isArrayStrictlyAscendingOrdered(quorumsToRemove));

        // Register operators
        _registerOperator(operatorId1, quorumsToAdd);
        _registerOperator(operatorId2, quorumsToAdd);

        // Deregister operator
        cheats.prank(address(registryCoordinatorMock));
        indexRegistry.deregisterOperator(operatorId1, quorumsToRemove);

        // Check operator's index for removed quorums
        for (uint256 i = 0; i < quorumsToRemove.length; i++) {
            IIndexRegistry.OperatorUpdate memory operatorUpdate = indexRegistry
                .getOperatorIndexUpdateOfIndexForQuorumAtIndex({operatorIndex: 1, quorumNumber: uint8(quorumsToRemove[i]), index: 1}); // 2 indexes -> 1 update and 1 remove
            require(operatorUpdate.fromBlockNumber == block.number, "fromBlockNumber not set correctly");
            require(operatorUpdate.operatorId == bytes32(0), "incorrect operatorId");
        }

        // Check total operators for removed quorums
        for (uint256 i = 0; i < quorumsToRemove.length; i++) {
            IIndexRegistry.QuorumUpdate memory quorumUpdate = indexRegistry
                .getQuorumUpdateAtIndex(uint8(quorumsToRemove[i]), 3); // 4 updates total
            require(quorumUpdate.fromBlockNumber == block.number, "fromBlockNumber not set correctly");
            require(quorumUpdate.numOperators == 1, "incorrect total number of operators");
            require(
                indexRegistry.totalOperatorsForQuorum(uint8(quorumsToRemove[i])) == 1,
                "operator not deregistered correctly"
            );
        }

        // Check swapped operator's index for removed quorums
        for (uint256 i = 0; i < quorumsToRemove.length; i++) {
            IIndexRegistry.OperatorUpdate memory operatorUpdate = indexRegistry
                .getOperatorIndexUpdateOfIndexForQuorumAtIndex({operatorIndex: 0, quorumNumber: uint8(quorumsToRemove[i]), index: 1}); // 2 indexes -> 1 update and 1 swap
            require(operatorUpdate.fromBlockNumber == block.number, "fromBlockNumber not set correctly");
            require(operatorUpdate.operatorId == operatorId2, "incorrect operatorId");
        }
    }

    function _initializeQuorum(uint8 quorumNumber) internal {
        cheats.prank(address(registryCoordinatorMock));

        // Initialize quorum and mark registered
        indexRegistry.initializeQuorum(quorumNumber);
        initializedQuorums[quorumNumber] = true;
    }

    function _initializeFuzzedQuorums(bytes memory quorumNumbers) internal {
        cheats.assume(quorumNumbers.length > 0);
        cheats.assume(bitmapUtilsWrapper.isArrayStrictlyAscendingOrdered(quorumNumbers));
        uint256 bitmap = bitmapUtilsWrapper.orderedBytesArrayToBitmap(quorumNumbers);
        cheats.assume(bitmap <= type(uint192).max);

        // Initialize quorums and add to fuzz filter
        for (uint i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            cheats.assume(!initializedQuorums[quorumNumber]);
            _initializeQuorum(quorumNumber);
        }
    }

    function _registerOperator(bytes32 operatorId, bytes memory quorumNumbers) internal {
        cheats.prank(address(registryCoordinatorMock));
        indexRegistry.registerOperator(operatorId, quorumNumbers);
    }
}

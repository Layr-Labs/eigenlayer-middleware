//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../../src/interfaces/IIndexRegistry.sol";
import "../../src/IndexRegistry.sol";
import "../harnesses/BitmapUtilsWrapper.sol";
import {IIndexRegistryEvents} from "../../src/interfaces/IIndexRegistry.sol";

import "../utils/MockAVSDeployer.sol";

contract IndexRegistryUnitTests is MockAVSDeployer, IIndexRegistryEvents {
    using BitmapUtils for *;

    /// @notice The value that is returned when an operator does not exist at an index at a certain block
    bytes32 public constant OPERATOR_DOES_NOT_EXIST_ID = bytes32(0);

    BitmapUtilsWrapper bitmapUtilsWrapper;

    uint8 nextQuorum = 0;
    address nextOperator = address(1000);
    bytes32 nextOperatorId = bytes32(uint256(1000));

    /**
     * Fuzz input filters:
     */
    uint192 initializedQuorumBitmap = 0;
    bytes initializedQuorumBytes;

    bytes32 operatorId1 = bytes32(uint256(34));
    bytes32 operatorId2 = bytes32(uint256(35));
    bytes32 operatorId3 = bytes32(uint256(36));

    // Track initialized quorums so we can filter these out when fuzzing
    mapping(uint8 => bool) initializedQuorums;

    // Test 0 length operators in operators to remove
    function setUp() public {
        _deployMockEigenLayerAndAVS(0);

        bitmapUtilsWrapper = new BitmapUtilsWrapper();

        // Initialize quorums and set initailizedQuorumBitmap
        _initializeQuorum();
        _initializeQuorum();
        _initializeQuorum();
    }

    /**
     *
     *                         INTERNAL UNIT TEST HELPERS
     *
     */
    function _initializeQuorum() internal {
        uint8 quorumNumber = nextQuorum;
        nextQuorum++;

        cheats.prank(address(registryCoordinator));

        // Initialize quorum and mark registered
        indexRegistry.initializeQuorum(quorumNumber);
        initializedQuorums[quorumNumber] = true;

        // Mark quorum initialized for other tests
        initializedQuorumBitmap = uint192(initializedQuorumBitmap.setBit(quorumNumber));
        initializedQuorumBytes = initializedQuorumBitmap.bitmapToBytesArray();
    }

    /// @dev Doesn't increment nextQuorum as assumes quorumNumber is any valid arbitrary quorumNumber
    function _initializeQuorum(
        uint8 quorumNumber
    ) internal {
        cheats.prank(address(registryCoordinator));

        // Initialize quorum and mark registered
        indexRegistry.initializeQuorum(quorumNumber);
        initializedQuorums[quorumNumber] = true;
    }

    /// @dev initializeQuorum based on passed in bitmap of quorum numbers
    /// assumes that bitmap does not contain already initailized quorums and doesn't increment nextQuorum
    function _initializeFuzzedQuorums(
        uint192 bitmap
    ) internal {
        bytes memory quorumNumbers = bitmapUtilsWrapper.bitmapToBytesArray(bitmap);

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            _initializeQuorum(quorumNumber);
        }
    }

    /// @dev Return a new, unique operator/operatorId pair, guaranteed to be
    /// unregistered from all quorums
    function _selectNewOperator() internal returns (address, bytes32) {
        address operator = nextOperator;
        bytes32 operatorId = nextOperatorId;
        nextOperator = _incrementAddress(nextOperator, 1);
        nextOperatorId = _incrementBytes32(nextOperatorId, 1);
        return (operator, operatorId);
    }

    /// @dev register an operator for a given set of quorums and return a list of the number of operators in each quorum
    function _registerOperator(
        bytes32 operatorId,
        bytes memory quorumNumbers
    ) internal returns (uint32[] memory) {
        cheats.prank(address(registryCoordinator));
        uint32[] memory numOperatorsPerQuorum =
            indexRegistry.registerOperator(operatorId, quorumNumbers);
        return numOperatorsPerQuorum;
    }

    /// @dev register an operator for a single quorum and return the number of operators in that quorum
    function _registerOperatorSingleQuorum(
        bytes32 operatorId,
        uint8 quorumNumber
    ) internal returns (uint32) {
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(quorumNumber);
        cheats.prank(address(registryCoordinator));
        uint32[] memory numOperatorsPerQuorum =
            indexRegistry.registerOperator(operatorId, quorumNumbers);
        return numOperatorsPerQuorum[0];
    }

    /// @dev deregister an operator for a given set of quorums
    function _deregisterOperator(bytes32 operatorId, bytes memory quorumNumbers) internal {
        cheats.prank(address(registryCoordinator));
        indexRegistry.deregisterOperator(operatorId, quorumNumbers);
    }

    /// @dev deregister an operator for a single quorum
    function _deregisterOperatorSingleQuorum(bytes32 operatorId, uint8 quorumNumber) internal {
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(quorumNumber);
        cheats.prank(address(registryCoordinator));
        indexRegistry.deregisterOperator(operatorId, quorumNumbers);
    }

    /// @dev Uses `rand` to return a random uint, with a range given by `min` and `max` (inclusive)
    /// @return `min` <= result <= `max`
    function _randUint(bytes32 rand, uint256 min, uint256 max) internal pure returns (uint256) {
        // hashing makes for more uniform randomness
        rand = keccak256(abi.encodePacked(rand));

        uint256 range = max - min + 1;

        // calculate the number of bits needed for the range
        uint256 bitsNeeded = 0;
        uint256 tempRange = range;
        while (tempRange > 0) {
            bitsNeeded++;
            tempRange >>= 1;
        }

        // create a mask for the required number of bits
        // and extract the value from the hash
        uint256 mask = (1 << bitsNeeded) - 1;
        uint256 value = uint256(rand) & mask;

        // in case value is out of range, wrap around or retry
        while (value >= range) {
            value = (value - range) & mask;
        }

        return min + value;
    }

    /**
     *
     *                         ASSERTION HELPERS
     *
     */
    function _assertQuorumUpdate(
        uint8 quorumNumber,
        uint256 expectedNumOperators,
        uint256 expectedFromBlockNumber
    ) internal {
        // Check _totalOperatorsHistory updates for quorum
        IIndexRegistry.QuorumUpdate memory quorumUpdate =
            indexRegistry.getLatestQuorumUpdate(quorumNumber);
        assertEq(
            quorumUpdate.numOperators,
            expectedNumOperators,
            "totalOperatorsHistory num operators not 1"
        );
        assertEq(
            quorumUpdate.fromBlockNumber,
            expectedFromBlockNumber,
            "totalOperatorsHistory fromBlockNumber not correct"
        );
        assertEq(
            indexRegistry.totalOperatorsForQuorum(quorumNumber),
            expectedNumOperators,
            "total operators for quorum not updated correctly"
        );
    }

    function _assertOperatorUpdate(
        uint8 quorumNumber,
        uint32 operatorIndex,
        uint32 arrayIndex,
        bytes32 operatorId,
        uint256 expectedFromBlockNumber
    ) internal {
        IIndexRegistry.OperatorUpdate memory operatorUpdate =
            indexRegistry.getOperatorUpdateAtIndex(quorumNumber, operatorIndex, arrayIndex);
        assertEq(operatorUpdate.operatorId, operatorId, "incorrect operatorId");
        assertEq(
            operatorUpdate.fromBlockNumber, expectedFromBlockNumber, "fromBlockNumber not correct"
        );
    }
}

contract IndexRegistryUnitTests_configAndGetters is IndexRegistryUnitTests {
    function test_Constructor() public {
        // check that the registry coordinator is set correctly
        assertEq(address(indexRegistry.registryCoordinator()), address(registryCoordinator));
    }

    /**
     *
     *                             UNIT TESTS - GETTERS
     *
     */
    function _assertOperatorListsEqual(
        bytes32[] memory operatorList1,
        bytes32[] memory operatorList2,
        uint256 listLength
    ) internal {
        assertTrue(
            listLength <= operatorList1.length && listLength <= operatorList2.length,
            "invalid operator list lengths"
        );

        for (uint256 i = 0; i < operatorList1.length; i++) {
            assertEq(operatorList1[i], operatorList2[i], "operator lists not equal");
        }
    }

    /**
     * @dev Loop for numOperators randomly registering and deregistering operators for a single quorum
     * Calling getOperatorListAtBlockNumber for an invalid blocknumber, i.e before the quorum existed.
     */
    function testFuzz_getOperatorListForQuorumAtBlockNumber_Revert_WhenInvalidBlockNumber(
        uint8 numOperators,
        bytes32 randSalt
    ) public {
        uint32 startBlockNumber = uint32(block.number);
        uint32 currBlockNumber = startBlockNumber;

        currBlockNumber += 10;
        cheats.roll(currBlockNumber);

        // initialize a new quorum after startBlockNumber
        uint8 quorumNumber = nextQuorum;
        _initializeQuorum();

        bytes32[] memory currRegisteredOperatorIds = new bytes32[](numOperators);
        uint256 currIndex = 0;
        for (uint256 i = 0; i < numOperators; i++) {
            uint256 rand =
                _randUint({rand: keccak256(abi.encodePacked(bytes32(i), randSalt)), min: 0, max: 1});

            // Roll block number
            currBlockNumber += 10;
            cheats.roll(currBlockNumber);

            // deregister operator, must also have at least one registered operator
            if (rand == 0 && currIndex > 0) {
                bytes32 operatorId = currRegisteredOperatorIds[currIndex - 1];
                _deregisterOperatorSingleQuorum(operatorId, quorumNumber);
                currRegisteredOperatorIds[currIndex] = operatorId;
                currIndex--;
                // register operator
            } else {
                (, bytes32 operatorId) = _selectNewOperator();
                _registerOperatorSingleQuorum(operatorId, quorumNumber);

                currRegisteredOperatorIds[currIndex] = operatorId;
                currIndex++;
            }

            // should revert with startBlocknumber
            cheats.expectRevert(
                "IndexRegistry._operatorCountAtBlockNumber: quorum did not exist at given block number"
            );

            indexRegistry.getOperatorListAtBlockNumber(quorumNumber, startBlockNumber);
        }
    }

    /**
     * @dev Loop for numOperators randomly registering and deregistering operators for a single quorum
     * And keeping track of the total operators and their indexes. Checks that the return list of operatorIds
     * from `getOperatorListForQuorum` matches the expected list of operatorIds
     */
    function testFuzz_getOperatorListForQuorumAtBlockNumber(
        uint8 numOperators,
        bytes32 randSalt
    ) public {
        bytes32[] memory currRegisteredOperatorIds = new bytes32[](numOperators);
        uint256 currIndex = 0;
        uint32 currBlockNumber = uint32(block.number);
        for (uint256 i = 0; i < numOperators; i++) {
            uint256 rand =
                _randUint({rand: keccak256(abi.encodePacked(bytes32(i), randSalt)), min: 0, max: 1});

            // Roll block number
            currBlockNumber += 10;
            cheats.roll(currBlockNumber);

            // deregister operator, must also have at least one registered operator
            if (rand == 0 && currIndex > 0) {
                bytes32 operatorId = currRegisteredOperatorIds[currIndex - 1];
                _deregisterOperatorSingleQuorum(operatorId, defaultQuorumNumber);
                currRegisteredOperatorIds[currIndex] = operatorId;
                currIndex--;
                // register operator
            } else {
                (, bytes32 operatorId) = _selectNewOperator();
                _registerOperatorSingleQuorum(operatorId, defaultQuorumNumber);

                currRegisteredOperatorIds[currIndex] = operatorId;
                currIndex++;
            }

            // Check operator list
            bytes32[] memory operatorList =
                indexRegistry.getOperatorListAtBlockNumber(defaultQuorumNumber, currBlockNumber);

            _assertOperatorListsEqual(operatorList, currRegisteredOperatorIds, currIndex);
        }
    }

    /**
     * @dev Loop for numOperators randomly registering and deregistering operators for a single quorum.
     * Checks that the totalOperatorsForQuorum returns the correct total after each register/deregister
     */
    function testFuzz_TotalOperatorUpdatesForOneQuorum(
        uint8 numOperators,
        bytes32 randSalt
    ) public {
        bytes32[] memory currRegisteredOperatorIds = new bytes32[](numOperators);
        uint256 currIndex = 0;
        for (uint256 i = 0; i < numOperators; i++) {
            uint256 rand =
                _randUint({rand: keccak256(abi.encodePacked(bytes32(i), randSalt)), min: 0, max: 1});

            // deregister operator, must also have at least one registered operator
            if (rand == 0 && currIndex > 0) {
                bytes32 operatorId = currRegisteredOperatorIds[currIndex - 1];
                _deregisterOperatorSingleQuorum(operatorId, defaultQuorumNumber);
                currRegisteredOperatorIds[currIndex] = operatorId;
                currIndex--;
                // register operator
            } else {
                (, bytes32 operatorId) = _selectNewOperator();
                _registerOperatorSingleQuorum(operatorId, defaultQuorumNumber);

                currRegisteredOperatorIds[currIndex] = operatorId;
                currIndex++;
            }

            // Check total operators for quorum
            assertEq(
                indexRegistry.totalOperatorsForQuorum(defaultQuorumNumber),
                currIndex,
                "incorrect update"
            );
        }
    }

    function testFuzz_viewFunctions_Revert_WhenInvalidQuorumNumber(
        uint8 quorumNumber
    ) public {
        cheats.assume(quorumNumber >= nextQuorum);

        cheats.expectRevert();
        indexRegistry.getLatestQuorumUpdate(quorumNumber);

        cheats.expectRevert();
        indexRegistry.getLatestOperatorUpdate(quorumNumber, 0);

        cheats.expectRevert();
        indexRegistry.totalOperatorsForQuorum(quorumNumber);

        cheats.expectRevert();
        indexRegistry.getOperatorListAtBlockNumber(quorumNumber, 0);
    }

    function test_getQuorumUpdateAtIndex() public {
        uint8 quorumNumber = nextQuorum;
        _initializeQuorum();

        uint32 blockNum = uint32(block.number);

        // Roll forward to force update
        vm.roll(block.number + 1);

        // Check quorum update at index 0
        IIndexRegistry.QuorumUpdate memory quorumUpdate =
            indexRegistry.getQuorumUpdateAtIndex(quorumNumber, 0);
        assertEq(quorumUpdate.numOperators, 0, "numOperators not 0");
        assertEq(quorumUpdate.fromBlockNumber, blockNum, "fromBlockNumber not correct");

        // Register operator
        (, bytes32 operatorId) = _selectNewOperator();
        _registerOperatorSingleQuorum(operatorId, quorumNumber);

        // Check quorum update at index 1
        quorumUpdate = indexRegistry.getQuorumUpdateAtIndex(quorumNumber, 1);
        assertEq(quorumUpdate.numOperators, 1, "numOperators not 1");
        assertEq(quorumUpdate.fromBlockNumber, block.number, "fromBlockNumber not correct");

        // Roll forward to force update
        vm.roll(block.number + 1);

        // Deregister
        _deregisterOperatorSingleQuorum(operatorId, quorumNumber);

        // Check quorum update at index 2
        quorumUpdate = indexRegistry.getQuorumUpdateAtIndex(quorumNumber, 2);
        assertEq(quorumUpdate.numOperators, 0, "numOperators not 0");
        assertEq(quorumUpdate.fromBlockNumber, block.number, "fromBlockNumber not correct");
    }
}

contract IndexRegistryUnitTests_registerOperator is IndexRegistryUnitTests {
    using BitmapUtils for *;

    /**
     *
     *                         UNIT TESTS - REGISTRATION
     *
     */
    function testFuzz_Revert_WhenNonRegistryCoordinator(
        address nonRegistryCoordinator
    ) public {
        cheats.assume(nonRegistryCoordinator != address(registryCoordinator));
        cheats.assume(nonRegistryCoordinator != proxyAdminOwner);
        bytes memory quorumNumbers = new bytes(defaultQuorumNumber);

        cheats.prank(nonRegistryCoordinator);
        cheats.expectRevert(IIndexRegistryErrors.OnlyRegistryCoordinator.selector);
        indexRegistry.registerOperator(bytes32(0), quorumNumbers);
    }

    /**
     * @dev Creates a fuzzed bitmap of quorums to initialize and a fuzzed bitmap of invalid quorumNumbers.
     * We ensure that none of the invalid quorumNumbers are initialized by masking out the initialized quorums and
     * expect a revert on registerOperator
     */
    function testFuzz_Revert_WhenInvalidQuorums(uint192 bitmap, uint192 invalidBitmap) public {
        cheats.assume(bitmap > initializedQuorumBitmap);
        cheats.assume(invalidBitmap > initializedQuorumBitmap);
        // mask out quorums that are already initialized and the quorums that are not going to be registered
        invalidBitmap = uint192(invalidBitmap.minus(uint256(initializedQuorumBitmap)));
        bitmap =
            uint192(bitmap.minus(uint256(initializedQuorumBitmap)).minus(uint256(invalidBitmap)));
        // Initialize fuzzed quorum numbers
        _initializeFuzzedQuorums(bitmap);

        // Register for invalid quorums, should revert
        bytes memory invalidQuorumNumbers = bitmapUtilsWrapper.bitmapToBytesArray(invalidBitmap);
        cheats.prank(address(registryCoordinator));
        cheats.expectRevert(IIndexRegistryErrors.QuorumDoesNotExist.selector);
        indexRegistry.registerOperator(operatorId1, invalidQuorumNumbers);
    }

    /**
     * Preconditions for registration -> checks in BLSRegistryCoordinator
     * 1. quorumNumbers has no duplicates
     * 2. quorumNumbers ordered in ascending order
     * 3. quorumBitmap is <= uint192.max
     * 4. quorumNumbers.length != 0
     * 5. operator is not already registerd for any quorums being registered for
     */
    function test_registerOperator() public {
        // register an operator
        (, bytes32 operatorId) = _selectNewOperator();
        uint32 numOperators = _registerOperatorSingleQuorum(operatorId, defaultQuorumNumber);

        assertEq(numOperators, 1, "IndexRegistry.registerOperator: numOperators is not 1");

        // Check _totalOperatorsHistory updates
        _assertQuorumUpdate({
            quorumNumber: defaultQuorumNumber,
            expectedNumOperators: 1,
            expectedFromBlockNumber: block.number
        });
        // Check _indexHistory updates
        _assertOperatorUpdate({
            quorumNumber: defaultQuorumNumber,
            operatorIndex: 0,
            arrayIndex: 0,
            operatorId: operatorId,
            expectedFromBlockNumber: block.number
        });
    }

    /**
     * @dev register operator for 2 quorums and check OperatorUpdate and QuorumUpdate values
     */
    function test_registerOperator_MultipleQuorumsSingleCall() public {
        // Register operator for 1st and 2nd quorum
        bytes memory quorumNumbers = new bytes(2);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        quorumNumbers[1] = bytes1(defaultQuorumNumber + 1);

        (, bytes32 operatorId) = _selectNewOperator();
        uint32[] memory numOperatorsPerQuorum = _registerOperator(operatorId, quorumNumbers);

        // Check return value
        assertEq(
            numOperatorsPerQuorum.length,
            2,
            "IndexRegistry.registerOperator: numOperatorsPerQuorum length not 2"
        );
        assertEq(
            numOperatorsPerQuorum[0],
            1,
            "IndexRegistry.registerOperator: numOperatorsPerQuorum[0] not 1"
        );
        assertEq(
            numOperatorsPerQuorum[1],
            1,
            "IndexRegistry.registerOperator: numOperatorsPerQuorum[1] not 1"
        );
        // Check _totalOperatorsHistory and _indexHistory updates for quorum 1
        _assertQuorumUpdate({
            quorumNumber: defaultQuorumNumber,
            expectedNumOperators: 1,
            expectedFromBlockNumber: block.number
        });
        _assertOperatorUpdate({
            quorumNumber: defaultQuorumNumber,
            operatorIndex: 0,
            arrayIndex: 0,
            operatorId: operatorId,
            expectedFromBlockNumber: block.number
        });

        // Check _totalOperatorsHistory and _indexHistory updates for quorum 2
        _assertQuorumUpdate({
            quorumNumber: defaultQuorumNumber + 1,
            expectedNumOperators: 1,
            expectedFromBlockNumber: block.number
        });
        _assertOperatorUpdate({
            quorumNumber: defaultQuorumNumber + 1,
            operatorIndex: 0,
            arrayIndex: 0,
            operatorId: operatorId,
            expectedFromBlockNumber: block.number
        });
    }

    /**
     * @dev register two operators for the same quorum within the same block.
     * operator1 should register with index 0, operator2 should register with index1.
     * Total quorumCount should be 2
     */
    function test_registerOperator_MultipleOperators_SingleBlock() public {
        // Register operator for first quorum
        (, bytes32 operatorId1) = _selectNewOperator();
        _registerOperatorSingleQuorum(operatorId1, defaultQuorumNumber);

        // Register another operator
        (, bytes32 operatorId2) = _selectNewOperator();
        uint32 numOperators = _registerOperatorSingleQuorum(operatorId2, defaultQuorumNumber);

        // Check return value
        assertEq(numOperators, 2, "IndexRegistry.registerOperator: numOperators not 2");

        // Check _totalOperatorsHistory and _indexHistory updates for quorum
        _assertOperatorUpdate({
            quorumNumber: defaultQuorumNumber,
            operatorIndex: 0,
            arrayIndex: 0,
            operatorId: operatorId1,
            expectedFromBlockNumber: block.number
        });
        _assertOperatorUpdate({
            quorumNumber: defaultQuorumNumber,
            operatorIndex: 1,
            arrayIndex: 0,
            operatorId: operatorId2,
            expectedFromBlockNumber: block.number
        });
        _assertQuorumUpdate({
            quorumNumber: defaultQuorumNumber,
            expectedNumOperators: 2,
            expectedFromBlockNumber: block.number
        });
    }

    /**
     * Preconditions for registration -> checks in BLSRegistryCoordinator
     * 1. quorumNumbers has no duplicates
     * 2. quorumNumbers ordered in ascending order
     * 3. quorumBitmap is <= uint192.max
     * 4. quorumNumbers.length != 0
     * 5. operator is not already registerd for any quorums being registered for
     */
    function testFuzz_registerOperator_MultipleQuorums(
        uint192 bitmap
    ) public {
        // mask out quorums that are already initialized
        bitmap = uint192(bitmap.minus(uint256(initializedQuorumBitmap)));
        bytes memory quorumNumbers = bitmapUtilsWrapper.bitmapToBytesArray(bitmap);
        // Initialize fuzzed quorum numbers, skipping invalid tests
        _initializeFuzzedQuorums(bitmap);

        // Register for quorums
        uint32[] memory numOperatorsPerQuorum = _registerOperator(operatorId1, quorumNumbers);

        // Check return value
        assertEq(
            numOperatorsPerQuorum.length,
            quorumNumbers.length,
            "IndexRegistry.registerOperator: numOperatorsPerQuorum length not correct"
        );

        // Check _totalOperatorsHistory and _indexHistory updates for each quorum
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            assertEq(
                numOperatorsPerQuorum[i],
                1,
                "IndexRegistry.registerOperator: numOperatorsPerQuorum[i] not 1"
            );
            _assertOperatorUpdate({
                quorumNumber: uint8(quorumNumbers[i]),
                operatorIndex: 0,
                arrayIndex: 0,
                operatorId: operatorId1,
                expectedFromBlockNumber: block.number
            });
            _assertQuorumUpdate({
                quorumNumber: uint8(quorumNumbers[i]),
                expectedNumOperators: 1,
                expectedFromBlockNumber: block.number
            });
        }
    }

    /**
     * @dev fuzz number of operators and bitmap for operators to register for.
     * For each operator, register for a random number of quorums from the bitmap and assert the correct
     * OperatorUpdate and QuorumUpdate values.
     */
    function testFuzz_registerOperator_MultipleOperatorsMultipleQuorums(
        uint8 numOperators,
        uint192 bitmap
    ) public {
        // mask out quorums that are already initialized
        bitmap = uint192(bound(bitmap, initializedQuorumBitmap, 192));
        bitmap = uint192(bitmap.minus(uint256(initializedQuorumBitmap)));
        bytes memory quorumNumbers = bitmapUtilsWrapper.bitmapToBytesArray(bitmap);
        // Initialize fuzzed quorum numbers
        _initializeFuzzedQuorums(bitmap);

        for (uint256 i = 0; i < numOperators; i++) {
            vm.roll(block.number + 10);
            // Register for quorums
            (, bytes32 operatorId) = _selectNewOperator();
            uint32[] memory numOperatorsPerQuorum = _registerOperator(operatorId, quorumNumbers);

            // Check return value
            assertEq(
                numOperatorsPerQuorum.length,
                quorumNumbers.length,
                "IndexRegistry.registerOperator: numOperatorsPerQuorum length not correct"
            );

            // Check _totalOperatorsHistory and _indexHistory updates for each quorum
            for (uint256 j = 0; j < quorumNumbers.length; j++) {
                assertEq(
                    numOperatorsPerQuorum[j],
                    i + 1,
                    "IndexRegistry.registerOperator: numOperatorsPerQuorum[i] not correct"
                );
                _assertOperatorUpdate({
                    quorumNumber: uint8(quorumNumbers[j]),
                    operatorIndex: uint32(i),
                    arrayIndex: 0,
                    operatorId: operatorId,
                    expectedFromBlockNumber: block.number
                });
                _assertQuorumUpdate({
                    quorumNumber: uint8(quorumNumbers[j]),
                    expectedNumOperators: i + 1,
                    expectedFromBlockNumber: block.number
                });
            }
        }

        // Check history of _totalOperatorsHistory updates at each blockNumber
        IIndexRegistry.QuorumUpdate memory quorumUpdate;
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            quorumUpdate = indexRegistry.getLatestQuorumUpdate(uint8(quorumNumbers[i]));
            assertEq(quorumUpdate.numOperators, numOperators, "num operators not correct");
            assertEq(
                quorumUpdate.fromBlockNumber,
                block.number,
                "latest update should be from current block number"
            );
        }
    }
}

contract IndexRegistryUnitTests_deregisterOperator is IndexRegistryUnitTests {
    using BitmapUtils for *;

    /**
     *
     *                         UNIT TESTS - DEREGISTRATION
     *
     */
    function testFuzz_Revert_WhenNonRegistryCoordinator(
        address nonRegistryCoordinator
    ) public {
        cheats.assume(nonRegistryCoordinator != address(registryCoordinator));
        cheats.assume(nonRegistryCoordinator != address(proxyAdmin));
        // de-register an operator
        bytes memory quorumNumbers = new bytes(defaultQuorumNumber);

        cheats.prank(nonRegistryCoordinator);
        cheats.expectRevert(IIndexRegistryErrors.OnlyRegistryCoordinator.selector);
        indexRegistry.deregisterOperator(bytes32(0), quorumNumbers);
    }

    /**
     * @dev Creates a fuzzed bitmap of quorums to initialize and a fuzzed bitmap of invalid quorumNumbers to deregister
     * we ensure that none of the invalid quorumNumbers are initialized by masking out the initialized quorums and
     * expect a revert on deregisterOperator
     */
    function testFuzz_Revert_WhenInvalidQuorums(uint192 bitmap, uint192 invalidBitmap) public {
        cheats.assume(bitmap > initializedQuorumBitmap);
        cheats.assume(invalidBitmap > initializedQuorumBitmap);
        // mask out quorums that are already initialized and the quorums that are not going to be registered
        invalidBitmap = uint192(invalidBitmap.minus(uint256(initializedQuorumBitmap)));
        bitmap =
            uint192(bitmap.minus(uint256(initializedQuorumBitmap)).minus(uint256(invalidBitmap)));
        bytes memory quorumNumbers = bitmapUtilsWrapper.bitmapToBytesArray(bitmap);
        bytes memory invalidQuorumNumbers = bitmapUtilsWrapper.bitmapToBytesArray(invalidBitmap);
        _initializeFuzzedQuorums(bitmap);

        // Register for quorums
        cheats.prank(address(registryCoordinator));
        indexRegistry.registerOperator(operatorId1, quorumNumbers);

        // Deregister for invalid quorums, should revert
        cheats.prank(address(registryCoordinator));
        cheats.expectRevert(IIndexRegistryErrors.QuorumDoesNotExist.selector);
        indexRegistry.deregisterOperator(operatorId1, invalidQuorumNumbers);
    }

    function test_deregisterOperator_Revert_WhenZeroRegisteredOperators() public {
        // Deregister operator that hasn't registered
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        cheats.prank(address(registryCoordinator));
        cheats.expectRevert();
        indexRegistry.deregisterOperator(operatorId1, quorumNumbers);
    }

    /**
     * @notice deregister an operator for default quorumNumber
     * Checks that for correct latest QuorumUpdate and OperatorUpdate
     */
    function test_deregisterOperator_SingleOperator_SameBlock() public {
        // Register operator
        (, bytes32 operatorId) = _selectNewOperator();
        _registerOperatorSingleQuorum(operatorId, defaultQuorumNumber);

        // Deregister operator
        _deregisterOperatorSingleQuorum(operatorId, defaultQuorumNumber);

        // Check operator's index
        _assertOperatorUpdate({
            quorumNumber: defaultQuorumNumber,
            operatorIndex: 0,
            arrayIndex: 0,
            operatorId: OPERATOR_DOES_NOT_EXIST_ID,
            expectedFromBlockNumber: block.number
        });

        // Check total operators
        _assertQuorumUpdate({
            quorumNumber: defaultQuorumNumber,
            expectedNumOperators: 0,
            expectedFromBlockNumber: block.number
        });
    }

    /**
     * @notice deregister an operator for default quorumNumber
     * Checks that for correct latest QuorumUpdate and OperatorUpdate
     */
    function test_deregisterOperator_SingleOperator_SeparateBlocks() public {
        // Register operator
        (, bytes32 operatorId) = _selectNewOperator();
        _registerOperatorSingleQuorum(operatorId, defaultQuorumNumber);

        // Deregister operator in separate block
        vm.roll(block.number + 1);
        _deregisterOperatorSingleQuorum(operatorId, defaultQuorumNumber);

        // Check operator's index when they registered
        _assertOperatorUpdate({
            quorumNumber: defaultQuorumNumber,
            operatorIndex: 0,
            arrayIndex: 0,
            operatorId: operatorId,
            expectedFromBlockNumber: block.number - 1
        });

        // Check operator's index currently
        _assertOperatorUpdate({
            quorumNumber: defaultQuorumNumber,
            operatorIndex: 0,
            arrayIndex: 1,
            operatorId: OPERATOR_DOES_NOT_EXIST_ID,
            expectedFromBlockNumber: block.number
        });

        // Check total operators
        _assertQuorumUpdate({
            quorumNumber: defaultQuorumNumber,
            expectedNumOperators: 0,
            expectedFromBlockNumber: block.number
        });
    }

    /**
     * @dev fuzz number of operators to register and deregister for default quorumNumber.
     */
    function testFuzz_deregisterOperator_MultipleOperatorsSingleQuorum(
        uint8 numOperators,
        uint256 randSalt
    ) public {
        cheats.assume(numOperators >= 1);
        cheats.assume(randSalt < type(uint256).max - numOperators);
        // register numOperators operators
        uint8 quorumNumber = defaultQuorumNumber;
        bytes32[] memory operators = new bytes32[](numOperators);
        for (uint256 i = 0; i < numOperators; i++) {
            (, bytes32 operatorId) = _selectNewOperator();
            operators[i] = operatorId;
            _registerOperatorSingleQuorum(operatorId, quorumNumber);
        }
        // Deregister each operator, starting from some random index and looping around operators array
        // if the operatorIndex is the same as the quorumCount - 1, then the operatorIndex will be simply popped
        // otherwise the operatorIndex is going to switch with last operatorIndex and then get popped
        for (uint256 i = 0; i < numOperators; i++) {
            bytes32 operatorId = operators[bound((randSalt + i), 0, numOperators - 1)];
            // get operator index, if operator index is new quorumCount
            // then other operator indexes are unchanged
            // otherwise the popped index operatorId will replace the deregistered operator's index
            uint32 operatorIndex =
                IndexRegistry(address(indexRegistry)).currentOperatorIndex(quorumNumber, operatorId);
            uint32 quorumCountBefore =
                indexRegistry.getLatestQuorumUpdate(quorumNumber).numOperators;

            assertTrue(
                operatorIndex <= quorumCountBefore - 1,
                "operator index should be less than quorumCount"
            );
            bytes32 operatorIdAtBeforeQuorumCount = indexRegistry.getLatestOperatorUpdate({
                quorumNumber: quorumNumber,
                operatorIndex: quorumCountBefore - 1
            }).operatorId;

            if (operatorIndex != quorumCountBefore - 1) {
                // expect popped index operator to be reassigned
                cheats.expectEmit(true, true, true, true, address(indexRegistry));
                emit QuorumIndexUpdate(operatorIdAtBeforeQuorumCount, quorumNumber, operatorIndex);
            }
            _deregisterOperatorSingleQuorum(operatorId, quorumNumber);

            if (operatorIndex != quorumCountBefore - 1) {
                assertNotEq(
                    operatorIdAtBeforeQuorumCount,
                    operatorId,
                    "operatorId at currentQuorumCount - 1 should not be operatorId we are deregistering"
                );
                _assertOperatorUpdate({
                    quorumNumber: quorumNumber,
                    operatorIndex: operatorIndex,
                    arrayIndex: 0,
                    operatorId: operatorIdAtBeforeQuorumCount,
                    expectedFromBlockNumber: block.number
                });
            }

            // Check quorumCountBefore index now has operatorId OPERATOR_DOES_NOT_EXIST_ID
            _assertOperatorUpdate({
                quorumNumber: quorumNumber,
                operatorIndex: quorumCountBefore - 1,
                arrayIndex: 0,
                operatorId: OPERATOR_DOES_NOT_EXIST_ID,
                expectedFromBlockNumber: block.number
            });
        }
    }

    /**
     * @dev fuzz number of operators to register and deregister for default quorumNumber but txs done in
     * separate blocks. The `index`/`arrayIndex` passed into the helper _assertOperatorUpdate is always 1 since we push
     * OperatorUpdate structs into the indexHistory with updated operatorIds because the txs are in separate blocks now.
     */
    function testFuzz_deregisterOperator_MultipleOperatorsSingleQuorum_SeparateBlocks(
        uint8 numOperators,
        uint256 randSalt
    ) public {
        cheats.assume(numOperators >= 1);
        cheats.assume(randSalt < type(uint256).max - numOperators);
        // register numOperators operators
        uint8 quorumNumber = defaultQuorumNumber;
        bytes32[] memory operators = new bytes32[](numOperators);
        for (uint256 i = 0; i < numOperators; i++) {
            vm.roll(block.number + 10);
            (, bytes32 operatorId) = _selectNewOperator();
            operators[i] = operatorId;
            _registerOperatorSingleQuorum(operatorId, quorumNumber);
        }
        // Deregister each operator, starting from some random index and looping around operators array
        // if the operatorIndex is the same as the quorumCount - 1, then the operatorIndex will be simply popped
        // otherwise the operatorIndex is going to switch with last operatorIndex and then get popped
        for (uint256 i = 0; i < numOperators; i++) {
            vm.roll(block.number + 10);
            bytes32 operatorId = operators[bound((randSalt + i), 0, numOperators - 1)];
            // get operator index, if operator index is new quorumCount
            // then other operator indexes are unchanged
            // otherwise the popped index operatorId will replace the deregistered operator's index
            uint32 operatorIndex =
                IndexRegistry(address(indexRegistry)).currentOperatorIndex(quorumNumber, operatorId);
            uint32 quorumCountBefore =
                indexRegistry.getLatestQuorumUpdate(quorumNumber).numOperators;

            assertTrue(
                operatorIndex <= quorumCountBefore - 1,
                "operator index should be less than quorumCount"
            );
            bytes32 operatorIdAtBeforeQuorumCount = indexRegistry.getLatestOperatorUpdate({
                quorumNumber: quorumNumber,
                operatorIndex: quorumCountBefore - 1
            }).operatorId;

            if (operatorIndex != quorumCountBefore - 1) {
                // expect popped index operator to be reassigned
                cheats.expectEmit(true, true, true, true, address(indexRegistry));
                emit QuorumIndexUpdate(operatorIdAtBeforeQuorumCount, quorumNumber, operatorIndex);
            }
            _deregisterOperatorSingleQuorum(operatorId, quorumNumber);

            if (operatorIndex != quorumCountBefore - 1) {
                assertNotEq(
                    operatorIdAtBeforeQuorumCount,
                    operatorId,
                    "operatorId at currentQuorumCount - 1 should not be operatorId we are deregistering"
                );
                _assertOperatorUpdate({
                    quorumNumber: quorumNumber,
                    operatorIndex: operatorIndex,
                    arrayIndex: 1,
                    operatorId: operatorIdAtBeforeQuorumCount,
                    expectedFromBlockNumber: block.number
                });
            }
        }
    }

    /**
     * @dev Test deregistering an operator with multiple operators already registered.
     * We deregister the operator with arrayIndex 0 and check that the operator with arrayIndex 2
     * ends up getting swapped with the deregistering operator.
     *
     * Also checking QuorumUpdates and OperatorUpdates as well.
     */
    function test_deregisterOperator_MultipleQuorums() public {
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

        cheats.prank(address(registryCoordinator));
        indexRegistry.deregisterOperator(operatorId1, quorumsToRemove);

        // Check operator's index for removed quorums
        for (uint256 i = 0; i < quorumsToRemove.length; i++) {
            // operatorIndex 0 will be operatorId3 from popping and replacing operatorId1 who deregistered
            _assertOperatorUpdate({
                quorumNumber: uint8(quorumsToRemove[i]),
                operatorIndex: 0,
                arrayIndex: 0,
                operatorId: operatorId3,
                expectedFromBlockNumber: block.number
            });
            // operatorIndex 1 will be operatorId2 as unchanged from initial registration
            _assertOperatorUpdate({
                quorumNumber: uint8(quorumsToRemove[i]),
                operatorIndex: 1,
                arrayIndex: 0,
                operatorId: operatorId2,
                expectedFromBlockNumber: block.number
            });
            // operatorIndex 2 will be OPERATOR_DOES_NOT_EXIST_ID as operatorId1 deregistered
            _assertOperatorUpdate({
                quorumNumber: uint8(quorumsToRemove[i]),
                operatorIndex: 2,
                arrayIndex: 0,
                operatorId: OPERATOR_DOES_NOT_EXIST_ID,
                expectedFromBlockNumber: block.number
            });

            _assertQuorumUpdate({
                quorumNumber: uint8(quorumsToRemove[i]),
                expectedNumOperators: 2,
                expectedFromBlockNumber: block.number
            });

            IIndexRegistry.OperatorUpdate memory operatorUpdate = indexRegistry
                .getLatestOperatorUpdate({quorumNumber: uint8(quorumsToRemove[i]), operatorIndex: 0});
            assertEq(
                operatorUpdate.fromBlockNumber, block.number, "fromBlockNumber not set correctly"
            );
            assertEq(operatorUpdate.operatorId, operatorId3, "incorrect operatorId");
        }
    }

    /**
     * @dev Creating a fuzzed bitmap of quorums to initialize and a fuzzed bitmap of quorums to deregister
     * We bitwise add bitmapToDeregister with bitmapToRegister to ensure that the quorums we deregister are
     * a subset of the quorums we register for.
     */
    function testFuzz_deregisterOperator_MultipleQuorums(
        uint192 bitmapToRegister,
        uint192 bitmapToDeregister
    ) public {
        cheats.assume(bitmapToRegister > initializedQuorumBitmap);
        // Ensure quorums to deregister get registered for, or alternatively
        // ensure quorums we deregister are a subset of quorums we register for
        cheats.assume(bitmapToRegister >= bitmapToDeregister);
        bitmapToRegister = uint192(bitmapToRegister.plus(bitmapToDeregister));
        // mask out quorums that are already initialized
        uint192 bitmap = uint192(bitmapToRegister.minus(uint256(initializedQuorumBitmap)));
        _initializeFuzzedQuorums(bitmap);

        bytes memory quorumNumbers = bitmapUtilsWrapper.bitmapToBytesArray(bitmapToRegister);
        bytes memory quorumsToRemove = bitmapUtilsWrapper.bitmapToBytesArray(bitmapToDeregister);

        // Register operators
        _registerOperator(operatorId1, quorumNumbers);
        _registerOperator(operatorId2, quorumNumbers);

        // Deregister operatorId1
        cheats.prank(address(registryCoordinator));
        indexRegistry.deregisterOperator(operatorId1, quorumsToRemove);

        for (uint256 i = 0; i < quorumsToRemove.length; i++) {
            // Check total operators for removed quorums
            _assertQuorumUpdate({
                quorumNumber: uint8(quorumsToRemove[i]),
                expectedNumOperators: 1,
                expectedFromBlockNumber: block.number
            });
            // Check swapped operator's index for removed quorums
            _assertOperatorUpdate({
                quorumNumber: uint8(quorumsToRemove[i]),
                operatorIndex: 0,
                arrayIndex: 0,
                operatorId: operatorId2,
                expectedFromBlockNumber: block.number
            });

            // Check operator's index for removed quorums
            IIndexRegistry.OperatorUpdate memory operatorUpdate = indexRegistry
                .getLatestOperatorUpdate({quorumNumber: uint8(quorumsToRemove[i]), operatorIndex: 1});
            assertEq(
                operatorUpdate.fromBlockNumber, block.number, "fromBlockNumber not set correctly"
            );
            assertEq(operatorUpdate.operatorId, bytes32(0), "incorrect operatorId");
        }
    }
}

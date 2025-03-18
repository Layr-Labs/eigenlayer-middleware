// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../utils/MockAVSDeployer.sol";

import {StakeRegistry} from "../../src/StakeRegistry.sol";
import {IStakeRegistry, IStakeRegistryErrors} from "../../src/interfaces/IStakeRegistry.sol";
import {IStakeRegistryEvents} from "../events/IStakeRegistryEvents.sol";
import {ISocketRegistry} from "../../src/interfaces/ISocketRegistry.sol";

import "../utils/MockAVSDeployer.sol";

contract StakeRegistryUnitTests is MockAVSDeployer, IStakeRegistryEvents {
    using BitmapUtils for *;

    /// @notice Maximum length of dynamic arrays in the `strategiesConsideredAndMultipliers` mapping.
    uint8 public constant MAX_WEIGHING_FUNCTION_LENGTH = 32;

    /**
     * Tracker variables used as we initialize quorums and operators during tests
     * (see _initializeQuorum and _selectNewOperator)
     */
    uint8 nextQuorum = 0;
    address nextOperator = address(1000);
    bytes32 nextOperatorId = bytes32(uint256(1000));

    /**
     * Fuzz input filters:
     */
    uint192 initializedQuorumBitmap;
    bytes initializedQuorumBytes;

    uint256 gasUsed;

    modifier fuzzOnlyInitializedQuorums(
        uint8 quorumNumber
    ) {
        cheats.assume(initializedQuorumBitmap.isSet(quorumNumber));
        _;
    }

    function setUp() public virtual {
        // Deploy contracts but with 0 quorums initialized, will initializeQuorums afterwards
        _deployMockEigenLayerAndAVS(0);

        // Make registryCoordinatorOwner the owner of the registryCoordinator contract
        cheats.startPrank(registryCoordinatorOwner);
        registryCoordinator = new RegistryCoordinatorHarness(
            serviceManager,
            stakeRegistry,
            IBLSApkRegistry(blsApkRegistry),
            IIndexRegistry(indexRegistry),
            ISocketRegistry(socketRegistry),
            allocationManager,
            pauserRegistry,
            "v0.0.1"
        );

        stakeRegistryImplementation = new StakeRegistryHarness(
            ISlashingRegistryCoordinator(address(registryCoordinator)),
            delegationMock,
            avsDirectoryMock,
            allocationManager
        );

        stakeRegistry = StakeRegistryHarness(
            address(
                new TransparentUpgradeableProxy(
                    address(stakeRegistryImplementation), address(proxyAdmin), ""
                )
            )
        );
        cheats.stopPrank();

        // Initialize several quorums with varying minimum stakes
        _initializeQuorum({minimumStake: uint96(type(uint16).max)});
        _initializeQuorum({minimumStake: uint96(type(uint24).max)});
        _initializeQuorum({minimumStake: uint96(type(uint32).max)});
        _initializeQuorum({minimumStake: uint96(type(uint64).max)});

        _initializeQuorum({minimumStake: uint96(type(uint16).max) + 1});
        _initializeQuorum({minimumStake: uint96(type(uint24).max) + 1});
        _initializeQuorum({minimumStake: uint96(type(uint32).max) + 1});
        _initializeQuorum({minimumStake: uint96(type(uint64).max) + 1});
    }

    /**
     *
     *                              initializers
     *
     */

    /**
     * @dev Initialize a new quorum with `minimumStake`
     * The new quorum's number is sequential, starting with `nextQuorum`
     */
    function _initializeQuorum(
        uint96 minimumStake
    ) internal {
        uint8 quorumNumber = nextQuorum;

        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] = IStakeRegistryTypes.StrategyParams(
            IStrategy(address(uint160(uint256(keccak256(abi.encodePacked(quorumNumber)))))),
            uint96(WEIGHTING_DIVISOR)
        );

        nextQuorum++;

        cheats.prank(address(registryCoordinator));
        stakeRegistry.initializeDelegatedStakeQuorum(quorumNumber, minimumStake, strategyParams);

        IStakeRegistryTypes.StakeType stakeType = stakeRegistry.stakeTypePerQuorum(quorumNumber);
        assertEq(
            uint8(stakeType),
            uint8(IStakeRegistryTypes.StakeType.TOTAL_DELEGATED),
            "invalid stake type"
        );

        // Mark quorum initialized for other tests
        initializedQuorumBitmap = uint192(initializedQuorumBitmap.setBit(quorumNumber));
        initializedQuorumBytes = initializedQuorumBitmap.bitmapToBytesArray();
    }

    /**
     * @dev Initialize a new quorum with `minimumStake` and `numStrats`
     * Create `numStrats` dummy strategies with multiplier of 1 for each.
     * Returns quorumNumber that was just initialized
     */
    function _initializeQuorum(uint96 minimumStake, uint256 numStrats) internal returns (uint8) {
        uint8 quorumNumber = nextQuorum;

        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](numStrats);
        for (uint256 i = 0; i < strategyParams.length; i++) {
            strategyParams[i] = IStakeRegistryTypes.StrategyParams(
                IStrategy(address(uint160(uint256(keccak256(abi.encodePacked(quorumNumber, i)))))),
                uint96(WEIGHTING_DIVISOR)
            );
        }

        nextQuorum++;

        cheats.prank(address(registryCoordinator));
        stakeRegistry.initializeDelegatedStakeQuorum(quorumNumber, minimumStake, strategyParams);

        // Mark quorum initialized for other tests
        initializedQuorumBitmap = uint192(initializedQuorumBitmap.setBit(quorumNumber));
        initializedQuorumBytes = initializedQuorumBitmap.bitmapToBytesArray();

        return quorumNumber;
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

    /**
     *
     *                             test setup methods
     *
     */
    struct RegisterSetup {
        address operator;
        bytes32 operatorId;
        bytes quorumNumbers;
        uint96[] operatorWeights;
        uint96[] minimumStakes;
        IStakeRegistry.StakeUpdate[] prevOperatorStakes;
        IStakeRegistry.StakeUpdate[] prevTotalStakes;
    }

    /// @dev Utility function set up a new operator to be registered for some quorums
    /// The operator's weight is set to the quorum's minimum, plus fuzzy_addtlStake (overflows are skipped)
    /// This function guarantees at least one quorum, and any quorums returned are initialized
    function _fuzz_setupRegisterOperator(
        uint192 fuzzy_Bitmap,
        uint16 fuzzy_addtlStake
    ) internal returns (RegisterSetup memory) {
        // Select an unused operator to register
        (address operator, bytes32 operatorId) = _selectNewOperator();

        // Pick quorums to register for and get each quorum's minimum stake
        (, bytes memory quorumNumbers) = _fuzz_getQuorums(fuzzy_Bitmap);
        uint96[] memory minimumStakes = _getMinimumStakes(quorumNumbers);

        // For each quorum, set the operator's weight as the minimum + addtlStake
        uint96[] memory operatorWeights = new uint96[](quorumNumbers.length);
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);

            unchecked {
                operatorWeights[i] = minimumStakes[i] + fuzzy_addtlStake;
            }
            cheats.assume(operatorWeights[i] >= minimumStakes[i]);
            cheats.assume(operatorWeights[i] >= fuzzy_addtlStake);

            _setOperatorWeight(operator, quorumNumber, operatorWeights[i]);
        }

        /// Get starting state
        IStakeRegistry.StakeUpdate[] memory prevOperatorStakes =
            _getLatestStakeUpdates(operatorId, quorumNumbers);
        IStakeRegistry.StakeUpdate[] memory prevTotalStakes =
            _getLatestTotalStakeUpdates(quorumNumbers);

        // Ensure that the operator has not previously registered
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            assertTrue(prevOperatorStakes[i].updateBlockNumber == 0, "operator already registered");
            assertTrue(prevOperatorStakes[i].stake == 0, "operator already has stake");
        }

        return RegisterSetup({
            operator: operator,
            operatorId: operatorId,
            quorumNumbers: quorumNumbers,
            operatorWeights: operatorWeights,
            minimumStakes: minimumStakes,
            prevOperatorStakes: prevOperatorStakes,
            prevTotalStakes: prevTotalStakes
        });
    }

    function _fuzz_setupRegisterOperators(
        uint192 fuzzy_Bitmap,
        uint16 fuzzy_addtlStake,
        uint256 numOperators
    ) internal returns (RegisterSetup[] memory) {
        RegisterSetup[] memory setups = new RegisterSetup[](numOperators);

        for (uint256 i = 0; i < numOperators; i++) {
            setups[i] = _fuzz_setupRegisterOperator(fuzzy_Bitmap, fuzzy_addtlStake);
        }

        return setups;
    }

    struct DeregisterSetup {
        address operator;
        bytes32 operatorId;
        // registerOperator quorums and state after registration:
        bytes registeredQuorumNumbers;
        IStakeRegistry.StakeUpdate[] prevOperatorStakes;
        IStakeRegistry.StakeUpdate[] prevTotalStakes;
        // deregisterOperator info:
        bytes quorumsToRemove;
        uint192 quorumsToRemoveBitmap;
    }

    /// @dev Utility function set up a new operator to be deregistered from some quorums
    /// The operator's weight is set to the quorum's minimum, plus fuzzy_addtlStake (overflows are skipped)
    /// This function guarantees at least one quorum, and any quorums returned are initialized
    function _fuzz_setupDeregisterOperator(
        uint192 registeredFor,
        uint192 fuzzy_toRemove,
        uint16 fuzzy_addtlStake
    ) internal returns (DeregisterSetup memory) {
        RegisterSetup memory registerSetup =
            _fuzz_setupRegisterOperator(registeredFor, fuzzy_addtlStake);

        // registerOperator
        cheats.prank(address(registryCoordinator));
        stakeRegistry.registerOperator(
            registerSetup.operator, registerSetup.operatorId, registerSetup.quorumNumbers
        );

        // Get state after registering:
        IStakeRegistry.StakeUpdate[] memory operatorStakes =
            _getLatestStakeUpdates(registerSetup.operatorId, registerSetup.quorumNumbers);
        IStakeRegistry.StakeUpdate[] memory totalStakes =
            _getLatestTotalStakeUpdates(registerSetup.quorumNumbers);

        (uint192 quorumsToRemoveBitmap, bytes memory quorumsToRemove) =
            _fuzz_getQuorums(fuzzy_toRemove);

        return DeregisterSetup({
            operator: registerSetup.operator,
            operatorId: registerSetup.operatorId,
            registeredQuorumNumbers: registerSetup.quorumNumbers,
            prevOperatorStakes: operatorStakes,
            prevTotalStakes: totalStakes,
            quorumsToRemove: quorumsToRemove,
            quorumsToRemoveBitmap: quorumsToRemoveBitmap
        });
    }

    function _fuzz_setupDeregisterOperators(
        uint192 registeredFor,
        uint192 fuzzy_toRemove,
        uint16 fuzzy_addtlStake,
        uint256 numOperators
    ) internal returns (DeregisterSetup[] memory) {
        DeregisterSetup[] memory setups = new DeregisterSetup[](numOperators);

        for (uint256 i = 0; i < numOperators; i++) {
            setups[i] =
                _fuzz_setupDeregisterOperator(registeredFor, fuzzy_toRemove, fuzzy_addtlStake);
        }

        return setups;
    }

    struct UpdateSetup {
        address operator;
        bytes32 operatorId;
        bytes quorumNumbers;
        uint96[] minimumStakes;
        uint96[] endingWeights;
        // absolute value of stake delta
        uint96 stakeDeltaAbs;
    }

    /// @dev Utility function to register a new, unique operator for `registeredFor` quorums, giving
    /// the operator exactly the minimum weight required for the quorum.
    /// After registering, and before returning, `fuzzy_Delta` is applied to the operator's weight
    /// to place the operator's weight above or below the minimum stake. (or unchanged!)
    /// The next time `updateOperatorStake` is called, this new weight will be used.
    function _fuzz_setupUpdateOperatorStake(
        uint192 registeredFor,
        int8 fuzzy_Delta
    ) internal returns (UpdateSetup memory) {
        RegisterSetup memory registerSetup = _fuzz_setupRegisterOperator(registeredFor, 0);

        // registerOperator
        cheats.prank(address(registryCoordinator));
        stakeRegistry.registerOperator(
            registerSetup.operator, registerSetup.operatorId, registerSetup.quorumNumbers
        );

        uint96[] memory minimumStakes = _getMinimumStakes(registerSetup.quorumNumbers);
        uint96[] memory endingWeights = new uint96[](minimumStakes.length);

        for (uint256 i = 0; i < minimumStakes.length; i++) {
            uint8 quorumNumber = uint8(registerSetup.quorumNumbers[i]);

            endingWeights[i] = _applyDelta(minimumStakes[i], int256(fuzzy_Delta));

            // Sanity-check setup:
            if (fuzzy_Delta > 0) {
                assertGt(
                    endingWeights[i],
                    minimumStakes[i],
                    "_fuzz_setupUpdateOperatorStake: overflow during setup"
                );
            } else if (fuzzy_Delta < 0) {
                assertLt(
                    endingWeights[i],
                    minimumStakes[i],
                    "_fuzz_setupUpdateOperatorStake: underflow during setup"
                );
            } else {
                assertEq(
                    endingWeights[i],
                    minimumStakes[i],
                    "_fuzz_setupUpdateOperatorStake: invalid delta during setup"
                );
            }
            // Set operator weights. The next time we call `updateOperatorStake`, these new weights will be used
            _setOperatorWeight(registerSetup.operator, quorumNumber, endingWeights[i]);
        }

        uint96 stakeDeltaAbs =
            fuzzy_Delta < 0 ? uint96(-int96(fuzzy_Delta)) : uint96(int96(fuzzy_Delta));

        return UpdateSetup({
            operator: registerSetup.operator,
            operatorId: registerSetup.operatorId,
            quorumNumbers: registerSetup.quorumNumbers,
            minimumStakes: minimumStakes,
            endingWeights: endingWeights,
            stakeDeltaAbs: stakeDeltaAbs
        });
    }

    function _fuzz_setupUpdateOperatorStakes(
        uint8 numOperators,
        uint192 registeredFor,
        int8 fuzzy_Delta
    ) internal returns (UpdateSetup[] memory) {
        UpdateSetup[] memory setups = new UpdateSetup[](numOperators);

        for (uint256 i = 0; i < numOperators; i++) {
            setups[i] = _fuzz_setupUpdateOperatorStake(registeredFor, fuzzy_Delta);
        }

        return setups;
    }

    /**
     *
     *                             helpful getters
     *
     */

    /// @notice Given a fuzzed bitmap input, returns a bitmap and array of quorum numbers
    /// that are guaranteed to be initialized.
    function _fuzz_getQuorums(
        uint192 fuzzy_Bitmap
    ) internal view returns (uint192, bytes memory) {
        fuzzy_Bitmap &= initializedQuorumBitmap;
        cheats.assume(!fuzzy_Bitmap.isEmpty());

        return (fuzzy_Bitmap, fuzzy_Bitmap.bitmapToBytesArray());
    }

    /// @notice Returns a list of initialized quorums ending in a non-initialized quorum
    /// @param rand is used to determine how many legitimate quorums to insert, so we can
    /// check this works for lists of varying lengths
    function _fuzz_getInvalidQuorums(
        bytes32 rand
    ) internal returns (bytes memory) {
        uint256 length = _randUint({rand: rand, min: 1, max: initializedQuorumBytes.length + 1});
        bytes memory invalidQuorums = new bytes(length);

        // Create an invalid quorum number by incrementing the last initialized quorum
        uint8 invalidQuorum = 1 + uint8(initializedQuorumBytes[initializedQuorumBytes.length - 1]);

        // Select real quorums up to the length, then insert an invalid quorum
        for (uint8 quorum = 0; quorum < length - 1; quorum++) {
            // sanity check test setup
            assertTrue(
                initializedQuorumBitmap.isSet(quorum), "_fuzz_getInvalidQuorums: invalid quorum"
            );
            invalidQuorums[quorum] = bytes1(quorum);
        }

        invalidQuorums[length - 1] = bytes1(invalidQuorum);
        return invalidQuorums;
    }

    /// @notice Returns true iff two StakeUpdates are identical
    function _isUnchanged(
        IStakeRegistry.StakeUpdate memory prev,
        IStakeRegistry.StakeUpdate memory cur
    ) internal pure returns (bool) {
        return (
            prev.stake == cur.stake && prev.updateBlockNumber == cur.updateBlockNumber
                && prev.nextUpdateBlockNumber == cur.nextUpdateBlockNumber
        );
    }

    /// @dev Return the minimum stakes required for a list of quorums
    function _getMinimumStakes(
        bytes memory quorumNumbers
    ) internal view returns (uint96[] memory) {
        uint96[] memory minimumStakes = new uint96[](quorumNumbers.length);

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            minimumStakes[i] = stakeRegistry.minimumStakeForQuorum(quorumNumber);
        }

        return minimumStakes;
    }

    /// @dev Return the most recent stake update history entries for an operator
    function _getLatestStakeUpdates(
        bytes32 operatorId,
        bytes memory quorumNumbers
    ) internal view returns (IStakeRegistry.StakeUpdate[] memory) {
        IStakeRegistry.StakeUpdate[] memory stakeUpdates =
            new IStakeRegistry.StakeUpdate[](quorumNumbers.length);

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            stakeUpdates[i] = stakeRegistry.getLatestStakeUpdate(operatorId, quorumNumber);
        }

        return stakeUpdates;
    }

    /// @dev Return the most recent total stake update history entries
    function _getLatestTotalStakeUpdates(
        bytes memory quorumNumbers
    ) internal view returns (IStakeRegistry.StakeUpdate[] memory) {
        IStakeRegistry.StakeUpdate[] memory stakeUpdates =
            new IStakeRegistry.StakeUpdate[](quorumNumbers.length);

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);

            uint256 historyLength = stakeRegistry.getTotalStakeHistoryLength(quorumNumber);
            stakeUpdates[i] =
                stakeRegistry.getTotalStakeUpdateAtIndex(quorumNumber, historyLength - 1);
        }

        return stakeUpdates;
    }

    /// @dev Return the lengths of the operator stake update history for each quorum
    function _getStakeHistoryLengths(
        bytes32 operatorId,
        bytes memory quorumNumbers
    ) internal view returns (uint256[] memory) {
        uint256[] memory operatorStakeHistoryLengths = new uint256[](quorumNumbers.length);

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);

            operatorStakeHistoryLengths[i] =
                stakeRegistry.getStakeHistoryLength(operatorId, quorumNumber);
        }

        return operatorStakeHistoryLengths;
    }

    /// @dev Return the lengths of the total stake update history
    function _getTotalStakeHistoryLengths(
        bytes memory quorumNumbers
    ) internal view returns (uint256[] memory) {
        uint256[] memory historyLengths = new uint256[](quorumNumbers.length);

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);

            historyLengths[i] = stakeRegistry.getTotalStakeHistoryLength(quorumNumber);
        }

        return historyLengths;
    }

    function _calculateDelta(uint96 prev, uint96 cur) internal view returns (int256) {
        return stakeRegistry.calculateDelta({prev: prev, cur: cur});
    }

    function _applyDelta(uint96 value, int256 delta) internal view returns (uint96) {
        return stakeRegistry.applyDelta({value: value, delta: delta});
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

    /// @dev Sort to ensure that the array is in desscending order for removeStrategies
    function _sortArrayDesc(
        uint256[] memory arr
    ) internal pure returns (uint256[] memory) {
        uint256 l = arr.length;
        for (uint256 i = 0; i < l; i++) {
            for (uint256 j = i + 1; j < l; j++) {
                if (arr[i] < arr[j]) {
                    uint256 temp = arr[i];
                    arr[i] = arr[j];
                    arr[j] = temp;
                }
            }
        }
        return arr;
    }

    /// @dev Return the stake histories for an operator for each quorum
    function _getOperatorStakeHistories(
        bytes32 operatorId,
        bytes memory quorumNumbers
    ) internal view returns (IStakeRegistry.StakeUpdate[][] memory) {
        IStakeRegistry.StakeUpdate[][] memory operatorStakeHistories =
            new IStakeRegistry.StakeUpdate[][](quorumNumbers.length);

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);

            operatorStakeHistories[i] = stakeRegistry.getStakeHistory(operatorId, quorumNumber);
        }

        return operatorStakeHistories;
    }

    /// @dev Return the stake history at a given index for each quorum
    function _getOperatorStakeUpdatesAtIndex(
        bytes32 operatorId,
        bytes memory quorumNumbers,
        uint256 index
    ) internal view returns (IStakeRegistry.StakeUpdate[] memory) {
        IStakeRegistry.StakeUpdate[] memory operatorStakeUpdates =
            new IStakeRegistry.StakeUpdate[](quorumNumbers.length);

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);

            operatorStakeUpdates[i] =
                stakeRegistry.getStakeUpdateAtIndex(quorumNumber, operatorId, index);
        }

        return operatorStakeUpdates;
    }
}

/// @notice Tests for any nonstandard/permissioned methods
contract StakeRegistryUnitTests_Config is StakeRegistryUnitTests {
    /**
     *
     *                         initializeQuorum
     *
     */
    function testFuzz_initializeQuorum_Revert_WhenNotRegistryCoordinator(
        uint8 quorumNumber,
        uint96 minimumStake,
        IStakeRegistryTypes.StrategyParams[] memory strategyParams
    ) public {
        cheats.expectRevert(IStakeRegistryErrors.OnlySlashingRegistryCoordinator.selector);
        stakeRegistry.initializeDelegatedStakeQuorum(quorumNumber, minimumStake, strategyParams);
    }

    function testFuzz_initializeQuorum_Revert_WhenQuorumAlreadyExists(
        uint8 quorumNumber,
        uint96 minimumStake,
        IStakeRegistryTypes.StrategyParams[] memory strategyParams
    ) public fuzzOnlyInitializedQuorums(quorumNumber) {
        cheats.expectRevert(IStakeRegistryErrors.QuorumAlreadyExists.selector);
        cheats.prank(address(registryCoordinator));
        stakeRegistry.initializeDelegatedStakeQuorum(quorumNumber, minimumStake, strategyParams);
    }

    function testFuzz_initializeQuorum_Revert_WhenInvalidArrayLengths(
        uint8 quorumNumber,
        uint96 minimumStake
    ) public {
        cheats.assume(quorumNumber >= nextQuorum);
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](0);
        cheats.expectRevert(IStakeRegistryErrors.InputArrayLengthZero.selector);
        cheats.prank(address(registryCoordinator));
        stakeRegistry.initializeDelegatedStakeQuorum(quorumNumber, minimumStake, strategyParams);

        strategyParams = new IStakeRegistryTypes.StrategyParams[](MAX_WEIGHING_FUNCTION_LENGTH + 1);
        for (uint256 i = 0; i < strategyParams.length; i++) {
            strategyParams[i] = IStakeRegistryTypes.StrategyParams(
                IStrategy(address(uint160(uint256(keccak256(abi.encodePacked(i)))))), uint96(1)
            );
        }
        cheats.expectRevert(IStakeRegistryErrors.InputArrayLengthMismatch.selector);
        cheats.prank(address(registryCoordinator));
        stakeRegistry.initializeDelegatedStakeQuorum(quorumNumber, minimumStake, strategyParams);
    }

    event StakeTypeSet(IStakeRegistryTypes.StakeType newStakeType);

    function test_initializeDelegatedStakeQuorum() public {
        uint8 quorumNumber = nextQuorum;
        uint96 minimumStake = 0;
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] = IStakeRegistryTypes.StrategyParams(
            IStrategy(address(uint160(uint256(keccak256(abi.encodePacked(quorumNumber)))))),
            uint96(WEIGHTING_DIVISOR)
        );

        cheats.prank(address(registryCoordinator));
        cheats.expectEmit(true, true, true, true);
        emit StakeTypeSet(IStakeRegistryTypes.StakeType.TOTAL_DELEGATED);
        stakeRegistry.initializeDelegatedStakeQuorum(quorumNumber, minimumStake, strategyParams);

        IStakeRegistryTypes.StakeType stakeType = stakeRegistry.stakeTypePerQuorum(quorumNumber);
        assertEq(
            uint8(stakeType),
            uint8(IStakeRegistryTypes.StakeType.TOTAL_DELEGATED),
            "invalid stake type"
        );
    }

    function test_initializeSlashableStakeQuorum() public {
        uint8 quorumNumber = nextQuorum;
        uint96 minimumStake = 0;
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] = IStakeRegistryTypes.StrategyParams(
            IStrategy(address(uint160(uint256(keccak256(abi.encodePacked(quorumNumber)))))),
            uint96(WEIGHTING_DIVISOR)
        );

        cheats.prank(address(registryCoordinator));
        cheats.expectEmit(true, true, true, true);
        emit StakeTypeSet(IStakeRegistryTypes.StakeType.TOTAL_SLASHABLE);
        stakeRegistry.initializeSlashableStakeQuorum(
            quorumNumber, minimumStake, 7 days, strategyParams
        );

        IStakeRegistryTypes.StakeType stakeType = stakeRegistry.stakeTypePerQuorum(quorumNumber);
        assertEq(
            uint8(stakeType),
            uint8(IStakeRegistryTypes.StakeType.TOTAL_SLASHABLE),
            "invalid stake type"
        );
    }

    /**
     * @dev Initializes a quorum with StrategyParams with fuzzed multipliers inputs and corresponding
     * strategy addresses.
     */
    function testFuzz_initializeQuorum(uint8 quorumNumber, uint96 minimumStake) public {
        quorumNumber = uint8(bound(uint256(quorumNumber), nextQuorum, type(uint8).max));

        // Create multipliers array with bounded length
        uint256 multiplierLength = bound(1, 1, MAX_WEIGHING_FUNCTION_LENGTH);
        uint96[] memory multipliers = new uint96[](multiplierLength);

        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](multipliers.length);
        for (uint256 i = 0; i < strategyParams.length; i++) {
            multipliers[i] = uint96(vm.randomUint(1, type(uint96).max));
            strategyParams[i] = IStakeRegistryTypes.StrategyParams(
                IStrategy(address(uint160(uint256(keccak256(abi.encodePacked(i)))))), multipliers[i]
            );
        }
        quorumNumber = nextQuorum;
        cheats.prank(address(registryCoordinator));
        stakeRegistry.initializeDelegatedStakeQuorum(quorumNumber, minimumStake, strategyParams);

        IStakeRegistry.StakeUpdate memory initialStakeUpdate =
            stakeRegistry.getTotalStakeUpdateAtIndex(quorumNumber, 0);
        assertEq(
            stakeRegistry.minimumStakeForQuorum(quorumNumber), minimumStake, "invalid minimum stake"
        );
        assertEq(
            stakeRegistry.getTotalStakeHistoryLength(quorumNumber),
            1,
            "invalid total stake history length"
        );
        assertEq(initialStakeUpdate.stake, 0, "invalid stake update");
        assertEq(
            initialStakeUpdate.updateBlockNumber,
            uint32(block.number),
            "invalid updateBlockNumber stake update"
        );
        assertEq(
            initialStakeUpdate.nextUpdateBlockNumber,
            0,
            "invalid nextUpdateBlockNumber stake update"
        );
        assertEq(
            stakeRegistry.strategyParamsLength(quorumNumber),
            strategyParams.length,
            "invalid strategy params length"
        );
        for (uint256 i = 0; i < strategyParams.length; i++) {
            (IStrategy strategy, uint96 multiplier) = stakeRegistry.strategyParams(quorumNumber, i);
            assertEq(address(strategy), address(strategyParams[i].strategy), "invalid strategy");
            assertEq(multiplier, strategyParams[i].multiplier, "invalid multiplier");
        }
    }

    /**
     *
     *                         setMinimumStakeForQuorum
     *
     */
    function testFuzz_setMinimumStakeForQuorum_Revert_WhenNotRegistryCoordinatorOwner(
        uint8 quorumNumber,
        uint96 minimumStakeForQuorum
    ) public fuzzOnlyInitializedQuorums(quorumNumber) {
        cheats.expectRevert(IStakeRegistryErrors.OnlySlashingRegistryCoordinatorOwner.selector);
        stakeRegistry.setMinimumStakeForQuorum(quorumNumber, minimumStakeForQuorum);
    }

    function testFuzz_setMinimumStakeForQuorum_Revert_WhenInvalidQuorum(
        uint8 quorumNumber,
        uint96 minimumStakeForQuorum
    ) public {
        // quorums [0,nextQuorum) are initialized, so use an invalid quorumNumber
        cheats.assume(quorumNumber >= nextQuorum);
        cheats.expectRevert(IStakeRegistryErrors.QuorumDoesNotExist.selector);
        cheats.prank(registryCoordinatorOwner);
        stakeRegistry.setMinimumStakeForQuorum(quorumNumber, minimumStakeForQuorum);
    }

    /// @dev Fuzzes initialized quorum numbers and minimum stakes to set to
    function testFuzz_setMinimumStakeForQuorum(
        uint8 quorumNumber,
        uint96 minimumStakeForQuorum
    ) public fuzzOnlyInitializedQuorums(quorumNumber) {
        cheats.prank(registryCoordinatorOwner);
        stakeRegistry.setMinimumStakeForQuorum(quorumNumber, minimumStakeForQuorum);
        assertEq(
            stakeRegistry.minimumStakeForQuorum(quorumNumber),
            minimumStakeForQuorum,
            "invalid minimum stake"
        );
    }

    /**
     *
     *                         addStrategies
     *
     */
    function testFuzz_addStrategies_Revert_WhenNotRegistryCoordinatorOwner(
        uint8 quorumNumber,
        IStakeRegistryTypes.StrategyParams[] memory strategyParams
    ) public fuzzOnlyInitializedQuorums(quorumNumber) {
        cheats.expectRevert(IStakeRegistryErrors.OnlySlashingRegistryCoordinatorOwner.selector);
        stakeRegistry.addStrategies(quorumNumber, strategyParams);
    }

    function testFuzz_addStrategies_Revert_WhenInvalidQuorum(
        uint8 quorumNumber,
        IStakeRegistryTypes.StrategyParams[] memory strategyParams
    ) public {
        // quorums [0,nextQuorum) are initialized, so use an invalid quorumNumber
        cheats.assume(quorumNumber >= nextQuorum);
        cheats.expectRevert(IStakeRegistryErrors.QuorumDoesNotExist.selector);
        cheats.prank(registryCoordinatorOwner);
        stakeRegistry.addStrategies(quorumNumber, strategyParams);
    }

    function test_addStrategies_Revert_WhenDuplicateStrategies() public {
        uint8 quorumNumber = _initializeQuorum(uint96(type(uint16).max), 1);

        IStrategy strat =
            IStrategy(address(uint160(uint256(keccak256(abi.encodePacked("duplicate strat"))))));
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](2);
        strategyParams[0] = IStakeRegistryTypes.StrategyParams(strat, uint96(WEIGHTING_DIVISOR));
        strategyParams[1] = IStakeRegistryTypes.StrategyParams(strat, uint96(WEIGHTING_DIVISOR));

        cheats.expectRevert(IStakeRegistryErrors.InputDuplicateStrategy.selector);
        cheats.prank(registryCoordinatorOwner);
        stakeRegistry.addStrategies(quorumNumber, strategyParams);
    }

    function test_addStrategies_Revert_WhenZeroWeight() public {
        uint8 quorumNumber = _initializeQuorum(uint96(type(uint16).max), 1);

        IStrategy strat =
            IStrategy(address(uint160(uint256(keccak256(abi.encodePacked("duplicate strat"))))));
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](2);
        strategyParams[0] = IStakeRegistryTypes.StrategyParams(strat, 0);

        cheats.expectRevert(IStakeRegistryErrors.InputMultiplierZero.selector);
        cheats.prank(registryCoordinatorOwner);
        stakeRegistry.addStrategies(quorumNumber, strategyParams);
    }

    /**
     * @dev Fuzzes initialized quorum numbers and using multipliers to create StrategyParams to add to
     * quorumNumber.
     */
    function testFuzz_addStrategies(
        uint8 quorumNumber
    ) public fuzzOnlyInitializedQuorums(quorumNumber) {
        uint256 currNumStrategies = stakeRegistry.strategyParamsLength(quorumNumber);
        uint96[] memory multipliers =
            new uint96[](vm.randomUint(1, MAX_WEIGHING_FUNCTION_LENGTH - currNumStrategies));
        for (uint256 i = 0; i < multipliers.length; i++) {
            multipliers[i] = uint96(vm.randomUint(1, type(uint96).max));
        }
        // Expected events emitted
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](multipliers.length);
        for (uint256 i = 0; i < strategyParams.length; i++) {
            IStrategy strat = IStrategy(address(uint160(uint256(keccak256(abi.encodePacked(i))))));
            strategyParams[i] = IStakeRegistryTypes.StrategyParams(strat, multipliers[i]);

            cheats.expectEmit(true, true, true, true, address(stakeRegistry));
            emit StrategyAddedToQuorum(quorumNumber, strat);
            cheats.expectEmit(true, true, true, true, address(stakeRegistry));
            emit StrategyMultiplierUpdated(quorumNumber, strat, multipliers[i]);
        }

        // addStrategies() call and expected assertions
        cheats.prank(registryCoordinatorOwner);
        stakeRegistry.addStrategies(quorumNumber, strategyParams);
        assertEq(
            stakeRegistry.strategyParamsLength(quorumNumber),
            strategyParams.length + 1,
            "invalid strategy params length"
        );
        for (uint256 i = 0; i < strategyParams.length; i++) {
            (IStrategy strategy, uint96 multiplier) =
                stakeRegistry.strategyParams(quorumNumber, i + 1);
            assertEq(address(strategy), address(strategyParams[i].strategy), "invalid strategy");
            assertEq(multiplier, strategyParams[i].multiplier, "invalid multiplier");
        }
    }

    /**
     *
     *                         removeStrategies
     *
     */
    function testFuzz_removeStrategies_Revert_WhenNotRegistryCoordinatorOwner(
        uint8 quorumNumber,
        uint256[] memory indicesToRemove
    ) public fuzzOnlyInitializedQuorums(quorumNumber) {
        cheats.expectRevert(IStakeRegistryErrors.OnlySlashingRegistryCoordinatorOwner.selector);
        stakeRegistry.removeStrategies(quorumNumber, indicesToRemove);
    }

    function testFuzz_removeStrategies_Revert_WhenInvalidQuorum(
        uint8 quorumNumber,
        uint256[] memory indicesToRemove
    ) public {
        // quorums [0,nextQuorum) are initialized, so use an invalid quorumNumber
        cheats.assume(quorumNumber >= nextQuorum);
        cheats.expectRevert(IStakeRegistryErrors.QuorumDoesNotExist.selector);
        cheats.prank(registryCoordinatorOwner);
        stakeRegistry.removeStrategies(quorumNumber, indicesToRemove);
    }

    function testFuzz_removeStrategies_Revert_WhenIndexOutOfBounds(
        uint96 minimumStake,
        uint8 numStrategiesToAdd,
        uint8 indexToRemove
    ) public {
        cheats.assume(0 < numStrategiesToAdd && numStrategiesToAdd <= MAX_WEIGHING_FUNCTION_LENGTH);
        cheats.assume(numStrategiesToAdd <= indexToRemove);
        uint8 quorumNumber = _initializeQuorum(minimumStake, numStrategiesToAdd);

        uint256[] memory indicesToRemove = new uint256[](1);
        indicesToRemove[0] = indexToRemove;
        // index will be >= length of strategy params so should revert from index out of bounds
        cheats.expectRevert();
        cheats.prank(registryCoordinatorOwner);
        stakeRegistry.removeStrategies(quorumNumber, indicesToRemove);
    }

    function testFuzz_removeStrategies_Revert_WhenEmptyStrategiesToRemove(
        uint96 minimumStake,
        uint8 numStrategiesToAdd
    ) public {
        cheats.assume(0 < numStrategiesToAdd && numStrategiesToAdd <= MAX_WEIGHING_FUNCTION_LENGTH);
        uint8 quorumNumber = _initializeQuorum(minimumStake, numStrategiesToAdd);

        uint256[] memory indicesToRemove = new uint256[](0);
        cheats.expectRevert(IStakeRegistryErrors.InputArrayLengthZero.selector);
        cheats.prank(registryCoordinatorOwner);
        stakeRegistry.removeStrategies(quorumNumber, indicesToRemove);
    }

    /**
     * @dev Fuzzes `numStrategiesToAdd` strategies to a quorum and then removes `numStrategiesToRemove` strategies
     * Ensures the indices for `numStrategiesToRemove` are random within bounds, and are sorted desc.
     */
    function testFuzz_removeStrategies(
        uint96 minimumStake,
        uint8 numStrategiesToAdd,
        uint8 numStrategiesToRemove
    ) public {
        numStrategiesToAdd = uint8(bound(numStrategiesToAdd, 1, MAX_WEIGHING_FUNCTION_LENGTH));
        numStrategiesToRemove = uint8(bound(numStrategiesToRemove, 1, numStrategiesToAdd));
        uint8 quorumNumber = _initializeQuorum(minimumStake, numStrategiesToAdd);

        // Create array of indicesToRemove, sort desc, and assume no duplicates
        uint256[] memory indicesToRemove = new uint256[](numStrategiesToRemove);
        for (uint256 i = 0; i < numStrategiesToRemove; i++) {
            indicesToRemove[i] = _randUint({rand: bytes32(i), min: 0, max: numStrategiesToAdd - 1});
        }
        indicesToRemove = _sortArrayDesc(indicesToRemove);
        uint256 prevIndex = indicesToRemove[0];
        for (uint256 i = 0; i < indicesToRemove.length; i++) {
            if (i > 0) {
                cheats.assume(indicesToRemove[i] < prevIndex);
                prevIndex = indicesToRemove[i];
            }
        }

        // Expected events emitted
        for (uint256 i = 0; i < indicesToRemove.length; i++) {
            (IStrategy strategy,) = stakeRegistry.strategyParams(quorumNumber, indicesToRemove[i]);
            cheats.expectEmit(true, true, true, true, address(stakeRegistry));
            emit StrategyRemovedFromQuorum(quorumNumber, strategy);
            cheats.expectEmit(true, true, true, true, address(stakeRegistry));
            emit StrategyMultiplierUpdated(quorumNumber, strategy, 0);
        }

        // Remove strategies and do assertions
        cheats.prank(registryCoordinatorOwner);
        stakeRegistry.removeStrategies(quorumNumber, indicesToRemove);
        assertEq(
            stakeRegistry.strategyParamsLength(quorumNumber),
            numStrategiesToAdd - indicesToRemove.length,
            "invalid strategy params length"
        );
    }

    /**
     *
     *                         modifyStrategyParams
     *
     */
    function testFuzz_modifyStrategyParams_Revert_WhenNotRegistryCoordinatorOwner(
        uint8 quorumNumber,
        uint256[] calldata strategyIndices,
        uint96[] calldata newMultipliers
    ) public fuzzOnlyInitializedQuorums(quorumNumber) {
        cheats.expectRevert(IStakeRegistryErrors.OnlySlashingRegistryCoordinatorOwner.selector);
        stakeRegistry.modifyStrategyParams(quorumNumber, strategyIndices, newMultipliers);
    }

    function testFuzz_modifyStrategyParams_Revert_WhenInvalidQuorum(
        uint8 quorumNumber,
        uint256[] calldata strategyIndices,
        uint96[] calldata newMultipliers
    ) public {
        // quorums [0,nextQuorum) are initialized, so use an invalid quorumNumber
        cheats.assume(quorumNumber >= nextQuorum);
        cheats.expectRevert(IStakeRegistryErrors.QuorumDoesNotExist.selector);
        cheats.prank(registryCoordinatorOwner);
        stakeRegistry.modifyStrategyParams(quorumNumber, strategyIndices, newMultipliers);
    }

    function testFuzz_modifyStrategyParams_Revert_WhenEmptyArray(
        uint8 quorumNumber
    ) public fuzzOnlyInitializedQuorums(quorumNumber) {
        uint256[] memory strategyIndices = new uint256[](0);
        uint96[] memory newMultipliers = new uint96[](0);
        cheats.expectRevert(IStakeRegistryErrors.InputArrayLengthZero.selector);
        cheats.prank(registryCoordinatorOwner);
        stakeRegistry.modifyStrategyParams(quorumNumber, strategyIndices, newMultipliers);
    }

    function testFuzz_modifyStrategyParams_Revert_WhenInvalidArrayLengths(
        uint8 quorumNumber,
        uint256[] calldata strategyIndices,
        uint96[] calldata newMultipliers
    ) public fuzzOnlyInitializedQuorums(quorumNumber) {
        cheats.assume(strategyIndices.length != newMultipliers.length);
        cheats.assume(strategyIndices.length > 0);
        cheats.expectRevert(IStakeRegistryErrors.InputArrayLengthMismatch.selector);
        cheats.prank(registryCoordinatorOwner);
        stakeRegistry.modifyStrategyParams(quorumNumber, strategyIndices, newMultipliers);
    }

    /**
     * @dev Fuzzes initialized quorum with random indices of strategies to modify with new multipliers.
     * Checks for events emitted and new multipliers are updated
     */
    function testFuzz_modifyStrategyParams(
        uint8 numStrategiesToAdd,
        uint8 numStrategiesToModify
    ) public {
        numStrategiesToAdd = uint8(bound(numStrategiesToAdd, 1, MAX_WEIGHING_FUNCTION_LENGTH));
        numStrategiesToModify = uint8(bound(numStrategiesToModify, 1, numStrategiesToAdd));
        uint256 prevIndex;
        uint256[] memory strategyIndices = new uint256[](numStrategiesToModify);
        uint96[] memory newMultipliers = new uint96[](numStrategiesToModify);
        // create array of indices to modify, assume no duplicates, and create array of multipliers for each index
        for (uint256 i = 0; i < numStrategiesToModify; i++) {
            strategyIndices[i] = _randUint({rand: bytes32(i), min: 0, max: numStrategiesToAdd - 1});
            newMultipliers[i] = uint96(_randUint({rand: bytes32(i), min: 1, max: type(uint96).max}));
            // ensure no duplicate indices
            if (i == 0) {
                prevIndex = strategyIndices[0];
            } else if (i > 0) {
                cheats.assume(strategyIndices[i] < prevIndex);
                prevIndex = strategyIndices[i];
            }
        }

        // Expected events emitted
        uint8 quorumNumber = _initializeQuorum(0, /* minimumStake */ numStrategiesToAdd);
        for (uint256 i = 0; i < strategyIndices.length; i++) {
            (IStrategy strategy,) = stakeRegistry.strategyParams(quorumNumber, strategyIndices[i]);
            cheats.expectEmit(true, true, true, true, address(stakeRegistry));
            emit StrategyMultiplierUpdated(quorumNumber, strategy, newMultipliers[i]);
        }

        // modifyStrategyParams() call and expected assertions
        cheats.prank(registryCoordinatorOwner);
        stakeRegistry.modifyStrategyParams(quorumNumber, strategyIndices, newMultipliers);
        for (uint256 i = 0; i < strategyIndices.length; i++) {
            (, uint96 multiplier) = stakeRegistry.strategyParams(quorumNumber, strategyIndices[i]);
            assertEq(multiplier, newMultipliers[i], "invalid multiplier");
        }
    }

    /**
     *
     *                         setSlashableStakeLookahead
     *
     */
    function testFuzz_setSlashableStakeLookahead_Revert_WhenNotRegistryCoordinatorOwner(
        uint8 quorumNumber,
        uint32 lookAheadBlocks
    ) public {
        cheats.expectRevert(IStakeRegistryErrors.OnlySlashingRegistryCoordinatorOwner.selector);
        stakeRegistry.setSlashableStakeLookahead(quorumNumber, lookAheadBlocks);
    }

    function testFuzz_setSlashableStakeLookahead_Revert_WhenQuorumDoesNotExist(
        uint8 quorumNumber,
        uint32 lookAheadBlocks
    ) public {
        // quorums [0,nextQuorum) are initialized, so use an invalid quorumNumber
        cheats.assume(quorumNumber >= nextQuorum);
        cheats.expectRevert(IStakeRegistryErrors.QuorumDoesNotExist.selector);
        cheats.prank(registryCoordinatorOwner);
        stakeRegistry.setSlashableStakeLookahead(quorumNumber, lookAheadBlocks);
    }

    function testFuzz_setSlashableStakeLookahead_Revert_WhenQourumNotSlashable(
        uint8 quorumNumber,
        uint32 lookAheadBlocks
    ) public {
        // Only consider existing quorums and quorums which use delegated stake
        cheats.assume(quorumNumber < nextQuorum);
        cheats.assume(
            stakeRegistry.stakeTypePerQuorum(quorumNumber)
                == IStakeRegistryTypes.StakeType.TOTAL_DELEGATED
        );
        cheats.expectRevert(IStakeRegistryErrors.QuorumNotSlashable.selector);
        cheats.prank(registryCoordinatorOwner);
        stakeRegistry.setSlashableStakeLookahead(quorumNumber, lookAheadBlocks);
    }

    function testFuzz_setSlashableStakeLookahead(
        uint8 quorumNumber,
        uint32 lookAheadBlocks
    ) public {
        // Only consider non-existing quorums
        cheats.assume(quorumNumber >= nextQuorum);

        // Create a new slashable quorum
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] = IStakeRegistryTypes.StrategyParams(
            IStrategy(address(uint160(uint256(keccak256(abi.encodePacked(quorumNumber)))))),
            uint96(WEIGHTING_DIVISOR)
        );
        cheats.prank(address(registryCoordinator));
        stakeRegistry.initializeSlashableStakeQuorum(quorumNumber, 1, 7 days, strategyParams);
        IStakeRegistryTypes.StakeType stakeType = stakeRegistry.stakeTypePerQuorum(quorumNumber);
        assertEq(
            uint8(stakeType),
            uint8(IStakeRegistryTypes.StakeType.TOTAL_SLASHABLE),
            "invalid stake type"
        );

        cheats.prank(registryCoordinatorOwner);
        stakeRegistry.setSlashableStakeLookahead(quorumNumber, lookAheadBlocks);
        assertEq(
            stakeRegistry.slashableStakeLookAheadPerQuorum(quorumNumber),
            lookAheadBlocks,
            "invalid slashable stake lookahead"
        );
    }

    function test_SetSlashableLookAhead_EmitsEvent() public {
        uint8 quorumNumber = nextQuorum;
        uint32 lookAheadBlocks = 10;

        // Create a new slashable quorum
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] = IStakeRegistryTypes.StrategyParams(
            IStrategy(address(uint160(uint256(keccak256(abi.encodePacked(quorumNumber)))))),
            uint96(WEIGHTING_DIVISOR)
        );
        cheats.prank(address(registryCoordinator));
        stakeRegistry.initializeSlashableStakeQuorum(quorumNumber, 1, 7 days, strategyParams);
        IStakeRegistryTypes.StakeType stakeType = stakeRegistry.stakeTypePerQuorum(quorumNumber);
        assertEq(
            uint8(stakeType),
            uint8(IStakeRegistryTypes.StakeType.TOTAL_SLASHABLE),
            "invalid stake type"
        );

        uint32 oldLookahead = stakeRegistry.slashableStakeLookAheadPerQuorum(quorumNumber);

        cheats.prank(registryCoordinatorOwner);
        cheats.expectEmit(true, true, true, true);
        emit IStakeRegistryEvents.LookAheadPeriodChanged(oldLookahead, lookAheadBlocks);
        stakeRegistry.setSlashableStakeLookahead(quorumNumber, lookAheadBlocks);
    }
}

/// @notice Tests for StakeRegistry.registerOperator
contract StakeRegistryUnitTests_Register is StakeRegistryUnitTests {
    /**
     *
     *                           registerOperator
     *
     */
    function test_registerOperator_Revert_WhenNotRegistryCoordinator() public {
        (address operator, bytes32 operatorId) = _selectNewOperator();

        cheats.expectRevert(IStakeRegistryErrors.OnlySlashingRegistryCoordinator.selector);
        stakeRegistry.registerOperator(operator, operatorId, initializedQuorumBytes);
    }

    function testFuzz_Revert_WhenQuorumDoesNotExist(
        bytes32 rand
    ) public {
        RegisterSetup memory setup = _fuzz_setupRegisterOperator(initializedQuorumBitmap, 0);

        // Get a list of valid quorums ending in an invalid quorum number
        bytes memory invalidQuorums = _fuzz_getInvalidQuorums(rand);

        cheats.expectRevert(IStakeRegistryErrors.QuorumDoesNotExist.selector);
        cheats.prank(address(registryCoordinator));
        stakeRegistry.registerOperator(setup.operator, setup.operatorId, invalidQuorums);
    }

    /// @dev Attempt to register for all quorums, selecting one quorum to attempt with
    /// insufficient stake
    function testFuzz_registerOperator_Revert_WhenInsufficientStake(
        uint8 failingQuorum
    ) public fuzzOnlyInitializedQuorums(failingQuorum) {
        (address operator, bytes32 operatorId) = _selectNewOperator();
        bytes memory quorumNumbers = initializedQuorumBytes;
        uint96[] memory minimumStakes = _getMinimumStakes(quorumNumbers);

        // Set the operator's weight to the minimum stake for each quorum
        // ... except the failing quorum, which gets minimum stake - 1
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            uint96 operatorWeight;

            if (quorumNumber == failingQuorum) {
                unchecked {
                    operatorWeight = minimumStakes[i] - 1;
                }
                assertTrue(operatorWeight < minimumStakes[i], "minimum stake underflow");
            } else {
                operatorWeight = minimumStakes[i];
            }

            _setOperatorWeight(operator, quorumNumber, operatorWeight);
        }

        // Attempt to register
        cheats.expectRevert(IStakeRegistryErrors.BelowMinimumStakeRequirement.selector);
        cheats.prank(address(registryCoordinator));
        stakeRegistry.registerOperator(operator, operatorId, quorumNumbers);
    }

    /**
     * @dev Registers an operator for some initialized quorums, adding `additionalStake`
     * to the minimum stake for each quorum.
     *
     * Checks the end result of stake updates rather than the entire history
     */
    function testFuzz_registerOperator_SingleOperator_SingleBlock(
        uint192 quorumBitmap,
        uint16 additionalStake
    ) public {
        /// Setup - select a new operator and set their weight to each quorum's minimum plus some additional
        RegisterSetup memory setup = _fuzz_setupRegisterOperator(quorumBitmap, additionalStake);

        /// registerOperator
        cheats.prank(address(registryCoordinator));
        (uint96[] memory resultingStakes, uint96[] memory totalStakes) =
            stakeRegistry.registerOperator(setup.operator, setup.operatorId, setup.quorumNumbers);

        /// Read ending state
        IStakeRegistry.StakeUpdate[] memory newOperatorStakes =
            _getLatestStakeUpdates(setup.operatorId, setup.quorumNumbers);
        IStakeRegistry.StakeUpdate[] memory newTotalStakes =
            _getLatestTotalStakeUpdates(setup.quorumNumbers);
        uint256[] memory operatorStakeHistoryLengths =
            _getStakeHistoryLengths(setup.operatorId, setup.quorumNumbers);
        IStakeRegistry.StakeUpdate[][] memory newOperatorStakesHistory =
            _getOperatorStakeHistories(setup.operatorId, setup.quorumNumbers);
        IStakeRegistry.StakeUpdate[] memory newStakeUpdatesAtIndex =
            _getOperatorStakeUpdatesAtIndex(setup.operatorId, setup.quorumNumbers, 0);

        /// Check results
        assertTrue(
            resultingStakes.length == setup.quorumNumbers.length,
            "invalid return length for operator stakes"
        );
        assertTrue(
            totalStakes.length == setup.quorumNumbers.length,
            "invalid return length for total stakes"
        );
        assertTrue(
            newOperatorStakesHistory.length == setup.quorumNumbers.length,
            "invalid operator stake history length"
        );
        assertTrue(
            newStakeUpdatesAtIndex.length == setup.quorumNumbers.length,
            "invalid return length for operator stakes at indices"
        );

        for (uint256 i = 0; i < setup.quorumNumbers.length; i++) {
            IStakeRegistry.StakeUpdate memory newOperatorStake = newOperatorStakes[i];
            IStakeRegistry.StakeUpdate memory newTotalStake = newTotalStakes[i];
            IStakeRegistry.StakeUpdate[] memory newOperatorStakeHistory =
                newOperatorStakesHistory[i];
            // Check return value against weights, latest state read, and minimum stake
            assertEq(
                resultingStakes[i],
                setup.operatorWeights[i],
                "stake registry did not return correct stake"
            );
            assertEq(
                resultingStakes[i], newOperatorStake.stake, "invalid latest operator stake update"
            );
            assertTrue(resultingStakes[i] != 0, "registered operator with zero stake");
            assertTrue(
                resultingStakes[i] >= setup.minimumStakes[i],
                "stake registry did not return correct stake"
            );

            // Check stake increase from fuzzed input
            assertEq(
                resultingStakes[i],
                newOperatorStake.stake,
                "did not add additional stake to operator correctly"
            );
            assertEq(
                resultingStakes[i],
                newTotalStake.stake,
                "did not add additional stake to total correctly"
            );

            // Check that we had an update this block
            assertEq(newOperatorStake.updateBlockNumber, uint32(block.number), "");
            assertEq(newOperatorStake.nextUpdateBlockNumber, 0, "");
            assertEq(newTotalStake.updateBlockNumber, uint32(block.number), "");
            assertEq(newTotalStake.nextUpdateBlockNumber, 0, "");

            // Check this is the first entry in the operator stake history
            assertEq(operatorStakeHistoryLengths[i], 1, "invalid total stake history length");
            assertEq(newOperatorStakeHistory.length, 1, "invalid operator stake history length");

            // Index is known for newOperatorStakeHistory, as this is the first entry
            assertEq(newOperatorStakeHistory[0].stake, newOperatorStake.stake, "");
            assertEq(newOperatorStakeHistory[0].updateBlockNumber, uint32(block.number), "");
            assertEq(newOperatorStakeHistory[0].nextUpdateBlockNumber, 0, "");

            // Check this first historical update at index 0
            assertEq(newStakeUpdatesAtIndex[i].stake, newOperatorStake.stake, "");
            assertEq(newStakeUpdatesAtIndex[i].updateBlockNumber, uint32(block.number), "");
            assertEq(
                newStakeUpdatesAtIndex[i].nextUpdateBlockNumber,
                newOperatorStake.nextUpdateBlockNumber,
                ""
            );
        }
    }

    // Track total stake added for each quorum as we register operators
    mapping(uint8 => uint96) _totalStakeAdded;

    /**
     * @dev Register multiple unique operators for the same quorums during a single block,
     * each with a weight of minimumStake + additionalStake.
     *
     * Checks the end result of stake updates rather than the entire history
     */
    function testFuzz_registerOperator_MultiOperator_SingleBlock(
        uint8 numOperators,
        uint192 quorumBitmap,
        uint16 additionalStake
    ) public {
        cheats.assume(numOperators > 1 && numOperators < 20);

        RegisterSetup[] memory setups =
            _fuzz_setupRegisterOperators(quorumBitmap, additionalStake, numOperators);

        // Register each operator one at a time, and check results:
        for (uint256 i = 0; i < numOperators; i++) {
            RegisterSetup memory setup = setups[i];

            cheats.prank(address(registryCoordinator));
            (uint96[] memory resultingStakes, uint96[] memory totalStakes) = stakeRegistry
                .registerOperator(setup.operator, setup.operatorId, setup.quorumNumbers);

            /// Read ending state
            IStakeRegistry.StakeUpdate[] memory newOperatorStakes =
                _getLatestStakeUpdates(setup.operatorId, setup.quorumNumbers);
            uint256[] memory operatorStakeHistoryLengths =
                _getStakeHistoryLengths(setup.operatorId, setup.quorumNumbers);
            IStakeRegistry.StakeUpdate[][] memory operatorStakesHistory =
                _getOperatorStakeHistories(setup.operatorId, setup.quorumNumbers);
            IStakeRegistry.StakeUpdate[] memory stakeUpdatesAtIndex =
                _getOperatorStakeUpdatesAtIndex(setup.operatorId, setup.quorumNumbers, 0);

            // Sum stakes in `_totalStakeAdded` to be checked later
            _tallyTotalStakeAdded(setup.quorumNumbers, resultingStakes);
            /// Check results
            assertTrue(
                resultingStakes.length == setup.quorumNumbers.length,
                "invalid return length for operator stakes"
            );
            assertTrue(
                totalStakes.length == setup.quorumNumbers.length,
                "invalid return length for total stakes"
            );
            assertTrue(
                operatorStakesHistory.length == setup.quorumNumbers.length,
                "invalid operator stake history length"
            );
            assertTrue(
                stakeUpdatesAtIndex.length == setup.quorumNumbers.length,
                "invalid return length for operator stakes at indices"
            );
            for (uint256 j = 0; j < setup.quorumNumbers.length; j++) {
                IStakeRegistry.StakeUpdate[] memory operatorStakeHistory = operatorStakesHistory[j];
                IStakeRegistry.StakeUpdate memory stakeUpdateAtIndex = stakeUpdatesAtIndex[j];
                // Check result against weights and latest state read
                assertEq(
                    resultingStakes[j],
                    setup.operatorWeights[j],
                    "stake registry did not return correct stake"
                );
                assertEq(
                    resultingStakes[j],
                    newOperatorStakes[j].stake,
                    "invalid latest operator stake update"
                );
                assertTrue(resultingStakes[j] != 0, "registered operator with zero stake");

                // Check result against minimum stake
                assertTrue(
                    resultingStakes[j] >= setup.minimumStakes[j],
                    "stake registry did not return correct stake"
                );

                // Check stake increase from fuzzed input
                assertEq(
                    resultingStakes[j],
                    newOperatorStakes[j].stake,
                    "did not add additional stake to operator correctly"
                );
                // Check this is the first entry in the operator stake history
                assertEq(operatorStakeHistoryLengths[j], 1, "invalid total stake history length");
                assertEq(operatorStakeHistory.length, 1, "invalid operator stake history length");

                // Check the first history entry
                assertEq(
                    operatorStakeHistory[0].stake,
                    newOperatorStakes[j].stake,
                    "invalid operator stake"
                );
                assertEq(
                    operatorStakeHistory[0].updateBlockNumber,
                    uint32(block.number),
                    "invalid operator stake update block number"
                );
                assertEq(
                    operatorStakeHistory[0].nextUpdateBlockNumber,
                    0,
                    "invalid operator stake next update block number"
                );

                // Check the update at the first index
                assertEq(
                    stakeUpdateAtIndex.stake, newOperatorStakes[j].stake, "invalid operator stake"
                );
                assertEq(
                    stakeUpdateAtIndex.updateBlockNumber,
                    uint32(block.number),
                    "invalid operator stake update block number"
                );
                assertEq(
                    stakeUpdateAtIndex.nextUpdateBlockNumber,
                    0,
                    "invalid operator stake next update block number"
                );
            }
        }

        // Check total stake results
        bytes memory quorumNumbers = initializedQuorumBytes;
        IStakeRegistry.StakeUpdate[] memory newTotalStakes =
            _getLatestTotalStakeUpdates(quorumNumbers);
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            assertEq(
                newTotalStakes[i].stake,
                _totalStakeAdded[quorumNumber],
                "incorrect latest total stake"
            );
            assertEq(
                newTotalStakes[i].nextUpdateBlockNumber,
                0,
                "incorrect total stake next update block"
            );
            assertEq(
                newTotalStakes[i].updateBlockNumber,
                uint32(block.number),
                "incorrect total stake next update block"
            );
        }
    }

    /**
     * @dev Register multiple unique operators all initialized quorums over multiple blocks,
     * each with a weight equal to the minimum + additionalStake.
     *
     * Since these updates occur over multiple blocks, this is primarily to test
     * that the total stake history is updated correctly over time.
     * @param operatorsPerBlock The number of unique operators registering during a single block
     * @param totalBlocks The number of times we'll register `operatorsPerBlock` (we only move 1 block each time)
     */
    function testFuzz_registerOperator_MultiOperator_MultiBlock(
        uint8 operatorsPerBlock,
        uint8 totalBlocks,
        uint16 additionalStake
    ) public {
        // We want between [1, 4] unique operators to register for all quorums each block,
        // and we want to test this for [2, 5] blocks
        operatorsPerBlock = uint8(bound(operatorsPerBlock, 1, 4));
        totalBlocks = uint8(bound(totalBlocks, 2, 5));

        uint256 startBlock = block.number;
        for (uint256 i = 1; i <= totalBlocks; i++) {
            // Move to current block number
            uint256 currBlock = startBlock + i;
            cheats.roll(currBlock);

            RegisterSetup[] memory setups = _fuzz_setupRegisterOperators(
                initializedQuorumBitmap, additionalStake, operatorsPerBlock
            );

            // Get prior total stake updates
            bytes memory quorumNumbers = setups[0].quorumNumbers;
            uint256[] memory prevHistoryLengths = _getTotalStakeHistoryLengths(quorumNumbers);

            for (uint256 j = 0; j < operatorsPerBlock; j++) {
                RegisterSetup memory setup = setups[j];

                cheats.prank(address(registryCoordinator));
                (uint96[] memory resultingStakes,) = stakeRegistry.registerOperator(
                    setup.operator, setup.operatorId, setup.quorumNumbers
                );

                // Sum stakes in `_totalStakeAdded` to be checked later
                _tallyTotalStakeAdded(setup.quorumNumbers, resultingStakes);
            }

            // Get new total stake updates
            uint256[] memory newHistoryLengths = _getTotalStakeHistoryLengths(quorumNumbers);
            IStakeRegistry.StakeUpdate[] memory newTotalStakes =
                _getLatestTotalStakeUpdates(quorumNumbers);

            for (uint256 j = 0; j < quorumNumbers.length; j++) {
                uint8 quorumNumber = uint8(quorumNumbers[j]);

                // Check that we've added 1 to total stake history length
                assertEq(
                    prevHistoryLengths[j] + 1,
                    newHistoryLengths[j],
                    "total history should have a new entry"
                );
                // Validate latest entry correctness
                assertEq(
                    newTotalStakes[j].stake,
                    _totalStakeAdded[quorumNumber],
                    "latest update should match total stake added"
                );
                assertEq(
                    newTotalStakes[j].updateBlockNumber,
                    currBlock,
                    "latest update should be from current block"
                );
                assertEq(
                    newTotalStakes[j].nextUpdateBlockNumber,
                    0,
                    "latest update should not have next update block"
                );

                // Validate previous entry was updated correctly
                IStakeRegistry.StakeUpdate memory prevUpdate = stakeRegistry
                    .getTotalStakeUpdateAtIndex(quorumNumber, prevHistoryLengths[j] - 1);
                assertTrue(
                    prevUpdate.stake < newTotalStakes[j].stake,
                    "previous update should have lower stake than latest"
                );
                assertEq(
                    prevUpdate.updateBlockNumber + 1,
                    newTotalStakes[j].updateBlockNumber,
                    "prev entry should be from last block"
                );
                assertEq(
                    prevUpdate.nextUpdateBlockNumber,
                    newTotalStakes[j].updateBlockNumber,
                    "prev entry.next should be latest.cur"
                );
            }
        }
    }

    function _tallyTotalStakeAdded(
        bytes memory quorumNumbers,
        uint96[] memory stakeAdded
    ) internal {
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            _totalStakeAdded[quorumNumber] += stakeAdded[i];
        }
    }
}

/// @notice Tests for StakeRegistry.deregisterOperator
contract StakeRegistryUnitTests_Deregister is StakeRegistryUnitTests {
    using BitmapUtils for *;

    /**
     *
     *                           deregisterOperator
     *
     */
    function test_deregisterOperator_Revert_WhenNotRegistryCoordinator() public {
        DeregisterSetup memory setup = _fuzz_setupDeregisterOperator({
            registeredFor: initializedQuorumBitmap,
            fuzzy_toRemove: initializedQuorumBitmap,
            fuzzy_addtlStake: 0
        });

        cheats.expectRevert(IStakeRegistryErrors.OnlySlashingRegistryCoordinator.selector);
        stakeRegistry.deregisterOperator(setup.operatorId, setup.quorumsToRemove);
    }

    function testFuzz_deregisterOperator_Revert_WhenQuorumDoesNotExist(
        bytes32 rand
    ) public {
        // Create a new operator registered for all quorums
        DeregisterSetup memory setup = _fuzz_setupDeregisterOperator({
            registeredFor: initializedQuorumBitmap,
            fuzzy_toRemove: initializedQuorumBitmap,
            fuzzy_addtlStake: 0
        });

        // Get a list of valid quorums ending in an invalid quorum number
        bytes memory invalidQuorums = _fuzz_getInvalidQuorums(rand);

        cheats.expectRevert(IStakeRegistryErrors.QuorumDoesNotExist.selector);
        cheats.prank(address(registryCoordinator));
        stakeRegistry.registerOperator(setup.operator, setup.operatorId, invalidQuorums);
    }

    /**
     * @dev Registers an operator for each initialized quorum, adding `additionalStake`
     * to the minimum stake for each quorum. Tests deregistering the operator for
     * a subset of these quorums.
     */
    function testFuzz_deregisterOperator_SingleOperator_SingleBlock(
        uint192 quorumsToRemove,
        uint16 additionalStake
    ) public {
        // Select a new operator, set their weight equal to the minimum plus some additional,
        // then register them for all initialized quorums and prepare to deregister from some subset
        DeregisterSetup memory setup = _fuzz_setupDeregisterOperator({
            registeredFor: initializedQuorumBitmap,
            fuzzy_toRemove: quorumsToRemove,
            fuzzy_addtlStake: additionalStake
        });

        // deregisterOperator
        cheats.prank(address(registryCoordinator));
        stakeRegistry.deregisterOperator(setup.operatorId, setup.quorumsToRemove);

        IStakeRegistry.StakeUpdate[] memory newOperatorStakes =
            _getLatestStakeUpdates(setup.operatorId, setup.registeredQuorumNumbers);
        IStakeRegistry.StakeUpdate[] memory newTotalStakes =
            _getLatestTotalStakeUpdates(setup.registeredQuorumNumbers);
        IStakeRegistry.StakeUpdate[][] memory newOperatorStakesHistory =
            _getOperatorStakeHistories(setup.operatorId, setup.registeredQuorumNumbers);
        IStakeRegistry.StakeUpdate[] memory newStakesAtIndex =
            _getOperatorStakeUpdatesAtIndex(setup.operatorId, setup.registeredQuorumNumbers, 0);

        for (uint256 i = 0; i < setup.registeredQuorumNumbers.length; i++) {
            uint8 registeredQuorum = uint8(setup.registeredQuorumNumbers[i]);

            IStakeRegistry.StakeUpdate memory prevOperatorStake = setup.prevOperatorStakes[i];
            IStakeRegistry.StakeUpdate memory prevTotalStake = setup.prevTotalStakes[i];

            IStakeRegistry.StakeUpdate memory newOperatorStake = newOperatorStakes[i];
            IStakeRegistry.StakeUpdate memory newTotalStake = newTotalStakes[i];

            IStakeRegistry.StakeUpdate[] memory newOperatorStakeHistory =
                newOperatorStakesHistory[i];
            IStakeRegistry.StakeUpdate memory newStakeAtIndex = newStakesAtIndex[i];

            // Whether the operator was deregistered from this quorum
            bool deregistered = setup.quorumsToRemoveBitmap.isSet(registeredQuorum);

            if (deregistered) {
                // Check that operator's stake was removed from both operator and total
                assertEq(newOperatorStake.stake, 0, "failed to remove stake");
                assertEq(
                    newTotalStake.stake + prevOperatorStake.stake,
                    prevTotalStake.stake,
                    "failed to remove stake from total"
                );

                // Check that we had an update this block
                assertEq(
                    newOperatorStake.updateBlockNumber,
                    uint32(block.number),
                    "operator stake has incorrect update block"
                );
                assertEq(
                    newOperatorStake.nextUpdateBlockNumber,
                    0,
                    "operator stake has incorrect next update block"
                );
                assertEq(
                    newTotalStake.updateBlockNumber,
                    uint32(block.number),
                    "total stake has incorrect update block"
                );
                assertEq(
                    newTotalStake.nextUpdateBlockNumber,
                    0,
                    "total stake has incorrect next update block"
                );
                // Registration and deregistration is done in the same block
                assertEq(newOperatorStakeHistory.length, 1, "invalid operator stake history length");
                assertEq(
                    newOperatorStakeHistory[0].stake, 0, "invalid operator stake history stake"
                );
                assertEq(
                    newOperatorStakeHistory[0].updateBlockNumber,
                    uint32(block.number),
                    "invalid operator stake history update block number"
                );
                assertEq(
                    newOperatorStakeHistory[0].nextUpdateBlockNumber,
                    0,
                    "invalid operator stake history next update block number"
                );

                // Check the update at the first index
                assertEq(newStakeAtIndex.stake, 0, "invalid stake at index");
                assertEq(
                    newStakeAtIndex.updateBlockNumber,
                    uint32(block.number),
                    "invalid update block at index"
                );
                assertEq(
                    newStakeAtIndex.nextUpdateBlockNumber, 0, "invalid next update block at index"
                );
            } else {
                // Ensure no change to operator or total stakes
                assertTrue(
                    _isUnchanged(prevOperatorStake, newOperatorStake),
                    "operator stake incorrectly updated"
                );
                assertTrue(
                    _isUnchanged(prevTotalStake, newTotalStake), "total stake incorrectly updated"
                );
            }
        }
    }

    // Track total stake removed from each quorum as we deregister operators
    mapping(uint8 => uint96) _totalStakeRemoved;

    /**
     * @dev Registers multiple operators for each initialized quorum, adding `additionalStake`
     * to the minimum stake for each quorum. Tests deregistering the operators for
     * a subset of these quorums.
     */
    function testFuzz_deregisterOperator_MultiOperator_SingleBlock(
        uint8 numOperators,
        uint192 quorumsToRemove,
        uint16 additionalStake
    ) public {
        cheats.assume(numOperators > 1 && numOperators < 20);

        // Select multiple new operators, set their weight equal to the minimum plus some additional,
        // then register them for all initialized quorums and prepare to deregister from some subset
        DeregisterSetup[] memory setups = _fuzz_setupDeregisterOperators({
            numOperators: numOperators,
            registeredFor: initializedQuorumBitmap,
            fuzzy_toRemove: quorumsToRemove,
            fuzzy_addtlStake: additionalStake
        });

        bytes memory registeredQuorums = initializedQuorumBytes;
        uint192 quorumsToRemoveBitmap = setups[0].quorumsToRemoveBitmap;

        IStakeRegistry.StakeUpdate[] memory prevTotalStakes =
            _getLatestTotalStakeUpdates(registeredQuorums);

        // Deregister operators one at a time and check results
        for (uint256 i = 0; i < numOperators; i++) {
            DeregisterSetup memory setup = setups[i];
            bytes32 operatorId = setup.operatorId;

            cheats.prank(address(registryCoordinator));
            stakeRegistry.deregisterOperator(setup.operatorId, setup.quorumsToRemove);

            IStakeRegistry.StakeUpdate[] memory newOperatorStakes =
                _getLatestStakeUpdates(operatorId, registeredQuorums);
            IStakeRegistry.StakeUpdate[] memory newTotalStakes =
                _getLatestTotalStakeUpdates(registeredQuorums);

            // Check results for each quorum
            for (uint256 j = 0; j < registeredQuorums.length; j++) {
                uint8 registeredQuorum = uint8(registeredQuorums[j]);

                IStakeRegistry.StakeUpdate memory prevOperatorStake = setup.prevOperatorStakes[j];
                IStakeRegistry.StakeUpdate memory prevTotalStake = prevTotalStakes[j];

                IStakeRegistry.StakeUpdate memory newOperatorStake = newOperatorStakes[j];
                IStakeRegistry.StakeUpdate memory newTotalStake = newTotalStakes[j];

                // Whether the operator was deregistered from this quorum
                bool deregistered = setup.quorumsToRemoveBitmap.isSet(registeredQuorum);

                if (deregistered) {
                    _totalStakeRemoved[registeredQuorum] += prevOperatorStake.stake;

                    // Check that operator's stake was removed from both operator and total
                    assertEq(newOperatorStake.stake, 0, "failed to remove stake");
                    assertEq(
                        newTotalStake.stake + _totalStakeRemoved[registeredQuorum],
                        prevTotalStake.stake,
                        "failed to remove stake from total"
                    );

                    // Check that we had an update this block
                    assertEq(
                        newOperatorStake.updateBlockNumber,
                        uint32(block.number),
                        "operator stake has incorrect update block"
                    );
                    assertEq(
                        newOperatorStake.nextUpdateBlockNumber,
                        0,
                        "operator stake has incorrect next update block"
                    );
                    assertEq(
                        newTotalStake.updateBlockNumber,
                        uint32(block.number),
                        "total stake has incorrect update block"
                    );
                    assertEq(
                        newTotalStake.nextUpdateBlockNumber,
                        0,
                        "total stake has incorrect next update block"
                    );
                } else {
                    // Ensure no change to operator stake
                    assertTrue(
                        _isUnchanged(prevOperatorStake, newOperatorStake),
                        "operator stake incorrectly updated"
                    );
                }
            }
        }

        // Now that we've deregistered all the operators, check the final results
        // For the quorums we chose to deregister from, the total stake should be zero
        IStakeRegistry.StakeUpdate[] memory finalTotalStakes =
            _getLatestTotalStakeUpdates(registeredQuorums);
        for (uint256 i = 0; i < registeredQuorums.length; i++) {
            uint8 registeredQuorum = uint8(registeredQuorums[i]);

            // Whether or not we deregistered operators from this quorum
            bool deregistered = quorumsToRemoveBitmap.isSet(registeredQuorum);

            if (deregistered) {
                assertEq(finalTotalStakes[i].stake, 0, "failed to remove all stake from quorum");
                assertEq(
                    finalTotalStakes[i].updateBlockNumber,
                    uint32(block.number),
                    "failed to remove all stake from quorum"
                );
                assertEq(
                    finalTotalStakes[i].nextUpdateBlockNumber,
                    0,
                    "failed to remove all stake from quorum"
                );
            } else {
                assertTrue(
                    _isUnchanged(finalTotalStakes[i], prevTotalStakes[i]),
                    "incorrectly updated total stake history for unmodified quorum"
                );
            }
        }
    }

    /**
     * @dev Registers multiple operators for all initialized quorums, each with a weight
     * equal to the minimum + additionalStake. This step is done in a single block.
     *
     * Then, deregisters operators for all quorums over multiple blocks and
     * tests that total stake history is updated correctly over time.
     * @param operatorsPerBlock The number of unique operators to deregister during each block
     * @param totalBlocks The number of times we'll deregister `operatorsPerBlock` (we only move 1 block each time)
     */
    function testFuzz_deregisterOperator_MultiOperator_MultiBlock(
        uint8 operatorsPerBlock,
        uint8 totalBlocks,
        uint16 additionalStake
    ) public {
        /// We want between [1, 4] unique operators to register for all quorums each block,
        /// and we want to test this for [2, 5] blocks
        operatorsPerBlock = uint8(bound(operatorsPerBlock, 1, 4));
        totalBlocks = uint8(bound(totalBlocks, 2, 5));

        uint256 numOperators = operatorsPerBlock * totalBlocks;
        uint256 operatorIdx; // track index in setups over test

        // Select multiple new operators, set their weight equal to the minimum plus some additional,
        // then register them for all initialized quorums
        DeregisterSetup[] memory setups = _fuzz_setupDeregisterOperators({
            numOperators: numOperators,
            registeredFor: initializedQuorumBitmap,
            fuzzy_toRemove: initializedQuorumBitmap,
            fuzzy_addtlStake: additionalStake
        });

        // For all operators, we're going to register for and then deregister from all initialized quorums
        bytes memory registeredQuorums = initializedQuorumBytes;

        IStakeRegistry.StakeUpdate[] memory prevTotalStakes =
            _getLatestTotalStakeUpdates(registeredQuorums);
        uint256 startBlock = block.number;

        for (uint256 i = 1; i <= totalBlocks; i++) {
            // Move to current block number
            uint256 currBlock = startBlock + i;
            cheats.roll(currBlock);

            uint256[] memory prevHistoryLengths = _getTotalStakeHistoryLengths(registeredQuorums);

            // Within this block: deregister some operators for all quorums and add the stake removed
            // to `_totalStakeRemoved` for later checks
            for (uint256 j = 0; j < operatorsPerBlock; j++) {
                DeregisterSetup memory setup = setups[operatorIdx];
                operatorIdx++;

                cheats.prank(address(registryCoordinator));
                stakeRegistry.deregisterOperator(setup.operatorId, setup.quorumsToRemove);

                for (uint256 k = 0; k < registeredQuorums.length; k++) {
                    uint8 quorumNumber = uint8(registeredQuorums[k]);
                    _totalStakeRemoved[quorumNumber] += setup.prevOperatorStakes[k].stake;
                }
            }

            uint256[] memory newHistoryLengths = _getTotalStakeHistoryLengths(registeredQuorums);
            IStakeRegistry.StakeUpdate[] memory newTotalStakes =
                _getLatestTotalStakeUpdates(registeredQuorums);

            // Validate the sum of all updates this block:
            // Each quorum should have a new historical entry with the correct update block pointers
            // ... and each quorum's stake should have decreased by `_totalStakeRemoved[quorum]`
            for (uint256 j = 0; j < registeredQuorums.length; j++) {
                uint8 quorumNumber = uint8(registeredQuorums[j]);

                // Check that we've added 1 to total stake history length
                assertEq(
                    prevHistoryLengths[j] + 1,
                    newHistoryLengths[j],
                    "total history should have a new entry"
                );

                // Validate latest entry correctness
                assertEq(
                    newTotalStakes[j].stake + _totalStakeRemoved[quorumNumber],
                    prevTotalStakes[j].stake,
                    "stake not removed correctly from total stake"
                );
                assertEq(
                    newTotalStakes[j].updateBlockNumber,
                    currBlock,
                    "latest update should be from current block"
                );
                assertEq(
                    newTotalStakes[j].nextUpdateBlockNumber,
                    0,
                    "latest update should not have next update block"
                );

                IStakeRegistry.StakeUpdate memory prevUpdate = stakeRegistry
                    .getTotalStakeUpdateAtIndex(quorumNumber, prevHistoryLengths[j] - 1);
                // Validate previous entry was updated correctly
                assertTrue(
                    prevUpdate.stake > newTotalStakes[j].stake,
                    "previous update should have higher stake than latest"
                );
                assertEq(
                    prevUpdate.updateBlockNumber + 1,
                    newTotalStakes[j].updateBlockNumber,
                    "prev entry should be from last block"
                );
                assertEq(
                    prevUpdate.nextUpdateBlockNumber,
                    newTotalStakes[j].updateBlockNumber,
                    "prev entry.next should be latest.cur"
                );
            }
        }

        // Now that we've deregistered all the operators, check the final results
        // Each quorum's stake should be zero
        IStakeRegistry.StakeUpdate[] memory finalTotalStakes =
            _getLatestTotalStakeUpdates(registeredQuorums);
        for (uint256 i = 0; i < registeredQuorums.length; i++) {
            assertEq(finalTotalStakes[i].stake, 0, "failed to remove all stake from quorum");
        }
    }
}

/// @notice Tests for StakeRegistry.updateOperatorStake
contract StakeRegistryUnitTests_StakeUpdates is StakeRegistryUnitTests {
    using BitmapUtils for *;

    function _wrap(
        address operator
    ) internal pure returns (address[] memory) {
        address[] memory operators = new address[](1);
        operators[0] = operator;
        return operators;
    }

    function _wrap(
        bytes32 operatorId
    ) internal pure returns (bytes32[] memory) {
        bytes32[] memory operatorIds = new bytes32[](1);
        operatorIds[0] = operatorId;
        return operatorIds;
    }

    function test_updateOperatorStake_Revert_WhenNotRegistryCoordinator() public {
        UpdateSetup memory setup =
            _fuzz_setupUpdateOperatorStake({registeredFor: initializedQuorumBitmap, fuzzy_Delta: 0});

        cheats.expectRevert(IStakeRegistryErrors.OnlySlashingRegistryCoordinator.selector);
        stakeRegistry.updateOperatorsStake(
            _wrap(setup.operator), _wrap(setup.operatorId), uint8(setup.quorumNumbers[0])
        );
    }

    function testFuzz_updateOperatorStake_Revert_WhenQuorumDoesNotExist(
        bytes32 rand
    ) public {
        // Create a new operator registered for all quorums
        UpdateSetup memory setup =
            _fuzz_setupUpdateOperatorStake({registeredFor: initializedQuorumBitmap, fuzzy_Delta: 0});

        // Get a list of valid quorums ending in an invalid quorum number
        bytes memory invalidQuorums = _fuzz_getInvalidQuorums(rand);
        uint256 length = invalidQuorums.length;

        cheats.expectRevert(IStakeRegistryErrors.QuorumDoesNotExist.selector);
        cheats.prank(address(registryCoordinator));
        stakeRegistry.updateOperatorsStake(
            _wrap(setup.operator), _wrap(setup.operatorId), uint8(invalidQuorums[length - 1])
        );
    }

    /**
     * @dev Registers an operator for all initialized quorums, giving them exactly the minimum stake
     * for each quorum. Then applies `stakeDelta` to their current weight, adding or removing some
     * stake from each quorum.
     *
     * updateOperatorStake should then update the operator's stake using the new weight - we test
     * what happens when the operator remains at/above minimum stake, vs dipping below
     */
    function testFuzz_updateOperatorStake_SingleOperator_SingleBlock(
        int8 stakeDelta
    ) public {
        UpdateSetup memory setup = _fuzz_setupUpdateOperatorStake({
            registeredFor: initializedQuorumBitmap,
            fuzzy_Delta: stakeDelta
        });

        // Get starting state
        IStakeRegistry.StakeUpdate[] memory prevOperatorStakes =
            _getLatestStakeUpdates(setup.operatorId, setup.quorumNumbers);
        IStakeRegistry.StakeUpdate[] memory prevTotalStakes =
            _getLatestTotalStakeUpdates(setup.quorumNumbers);

        // updateOperatorStake
        bool[] memory shouldBeDeregistered = new bool[](setup.quorumNumbers.length);
        for (uint256 i = 0; i < setup.quorumNumbers.length; i++) {
            cheats.prank(address(registryCoordinator));
            bool[] memory shouldBeDeregisteredForQuorum = stakeRegistry.updateOperatorsStake(
                _wrap(setup.operator), _wrap(setup.operatorId), uint8(setup.quorumNumbers[i])
            );
            shouldBeDeregistered[i] = shouldBeDeregisteredForQuorum[0];
        }

        // Get ending state
        IStakeRegistry.StakeUpdate[] memory newOperatorStakes =
            _getLatestStakeUpdates(setup.operatorId, setup.quorumNumbers);
        IStakeRegistry.StakeUpdate[] memory newTotalStakes =
            _getLatestTotalStakeUpdates(setup.quorumNumbers);

        // Check results for each quorum
        for (uint256 i = 0; i < setup.quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(setup.quorumNumbers[i]);

            uint96 minimumStake = setup.minimumStakes[i];
            uint96 endingWeight = setup.endingWeights[i];

            IStakeRegistry.StakeUpdate memory prevOperatorStake = prevOperatorStakes[i];
            IStakeRegistry.StakeUpdate memory prevTotalStake = prevTotalStakes[i];

            IStakeRegistry.StakeUpdate memory newOperatorStake = newOperatorStakes[i];
            IStakeRegistry.StakeUpdate memory newTotalStake = newTotalStakes[i];

            // Sanity-check setup - operator should start with minimumStake
            assertTrue(
                prevOperatorStake.stake == minimumStake, "operator should start with nonzero stake"
            );

            if (endingWeight > minimumStake) {
                // Check updating an operator who has added stake above the minimum:

                // Only updates should be stake added to operator/total stakes
                uint96 stakeAdded = setup.stakeDeltaAbs;
                assertEq(
                    prevOperatorStake.stake + stakeAdded,
                    newOperatorStake.stake,
                    "failed to add delta to operator stake"
                );
                assertEq(
                    prevTotalStake.stake + stakeAdded,
                    newTotalStake.stake,
                    "failed to add delta to total stake"
                );
                // Return value should be empty since we're still above the minimum
                assertTrue(
                    !shouldBeDeregistered[i],
                    "positive stake delta should not lead to deregistration"
                );
            } else if (endingWeight < minimumStake) {
                // Check updating an operator who is now below the minimum:

                // Stake should now be zero, regardless of stake delta
                uint96 stakeRemoved = minimumStake;
                assertEq(
                    prevOperatorStake.stake - stakeRemoved,
                    newOperatorStake.stake,
                    "failed to remove delta from operator stake"
                );
                assertEq(
                    prevTotalStake.stake - stakeRemoved,
                    newTotalStake.stake,
                    "failed to remove delta from total stake"
                );
                assertEq(newOperatorStake.stake, 0, "operator stake should now be zero");
                // IECDSAStakeRegistryTypes.Quorum should be added to return bitmap
                assertTrue(shouldBeDeregistered[i], "operator should be deregistered");
            } else {
                // Check that no update occurs if weight remains the same
                assertTrue(
                    _isUnchanged(prevOperatorStake, newOperatorStake),
                    "neutral stake delta should not have changed operator stake history"
                );
                assertTrue(
                    _isUnchanged(prevTotalStake, newTotalStake),
                    "neutral stake delta should not have changed total stake history"
                );
                // Check that return value is empty - we're still at the minimum, so no quorums should be removed
                assertTrue(
                    !shouldBeDeregistered[i],
                    "neutral stake delta should not lead to deregistration"
                );
            }
        }
    }

    /**
     * @dev Registers multiple operators for all initialized quorums, giving them exactly the minimum stake
     * for each quorum. Then applies `stakeDelta` to their current weight, adding or removing some
     * stake from each quorum.
     *
     * updateOperatorStake should then update each operator's stake using the new weight - we test
     * what happens to the total stake history after all stakes have been updated
     */
    function testFuzz_updateOperatorStake_MultiOperator_SingleBlock(
        uint8 numOperators,
        int8 stakeDelta
    ) public {
        cheats.assume(numOperators > 1 && numOperators < 20);

        // Select multiple new operators, register each for all quorums with weight equal
        // to the quorum's minimum, and then apply `stakeDelta` to their current weight.
        UpdateSetup[] memory setups = _fuzz_setupUpdateOperatorStakes({
            numOperators: numOperators,
            registeredFor: initializedQuorumBitmap,
            fuzzy_Delta: stakeDelta
        });

        bytes memory quorumNumbers = initializedQuorumBytes;
        // Get initial total history state
        uint256[] memory initialHistoryLengths = _getTotalStakeHistoryLengths(quorumNumbers);
        IStakeRegistry.StakeUpdate[] memory initialTotalStakes =
            _getLatestTotalStakeUpdates(quorumNumbers);

        // Call `updateOperatorStake` one by one
        for (uint256 i = 0; i < numOperators; i++) {
            UpdateSetup memory setup = setups[i];

            // updateOperatorStake
            for (uint256 j = 0; j < setup.quorumNumbers.length; j++) {
                cheats.prank(address(registryCoordinator));
                stakeRegistry.updateOperatorsStake(
                    _wrap(setup.operator), _wrap(setup.operatorId), uint8(setup.quorumNumbers[j])
                );
            }
        }

        // Check final results for each quorum
        uint256[] memory finalHistoryLengths = _getTotalStakeHistoryLengths(quorumNumbers);
        IStakeRegistry.StakeUpdate[] memory finalTotalStakes =
            _getLatestTotalStakeUpdates(quorumNumbers);

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            IStakeRegistry.StakeUpdate memory initialTotalStake = initialTotalStakes[i];
            IStakeRegistry.StakeUpdate memory finalTotalStake = finalTotalStakes[i];

            uint96 minimumStake = setups[0].minimumStakes[i];
            uint96 endingWeight = setups[0].endingWeights[i];
            uint96 stakeDeltaAbs = setups[0].stakeDeltaAbs;

            // Sanity-check setup: previous total stake should be minimumStake * numOperators
            assertEq(
                initialTotalStake.stake,
                minimumStake * numOperators,
                "quorum should start with minimum stake from all operators"
            );

            // history lengths should be unchanged
            assertEq(
                initialHistoryLengths[i],
                finalHistoryLengths[i],
                "history lengths should remain unchanged"
            );

            if (endingWeight > minimumStake) {
                // All operators had their stake increased by stakeDelta
                uint96 stakeAdded = numOperators * stakeDeltaAbs;
                assertEq(
                    initialTotalStake.stake + stakeAdded,
                    finalTotalStake.stake,
                    "failed to add delta for all operators"
                );
            } else if (endingWeight < minimumStake) {
                // All operators had their entire stake removed
                uint96 stakeRemoved = numOperators * minimumStake;
                assertEq(
                    initialTotalStake.stake - stakeRemoved,
                    finalTotalStake.stake,
                    "failed to remove delta from total stake"
                );
                assertEq(finalTotalStake.stake, 0, "final total stake should be zero");
            } else {
                // No change in stake for any operator
                assertTrue(
                    _isUnchanged(initialTotalStake, finalTotalStake),
                    "neutral stake delta should result in no change"
                );
            }
        }
    }

    /**
     * @dev Registers an operator for all initialized quorums, giving them exactly the minimum stake
     * for each quorum.
     *
     * Then over multiple blocks, derives a random stake delta and applies it to their weight, testing
     * the result on the operator and total stake histories.
     */
    function testFuzz_updateOperatorStake_SingleOperator_MultiBlocknumberChecks(
        uint8 totalBlocks,
        int8 stakeDelta
    ) public {
        cheats.assume(totalBlocks >= 2 && totalBlocks <= 8);

        uint256 startBlock = block.number;
        for (uint256 j = 1; j <= totalBlocks; j++) {
            UpdateSetup memory setup = _fuzz_setupUpdateOperatorStake({
                registeredFor: initializedQuorumBitmap,
                fuzzy_Delta: stakeDelta
            });

            // Get starting state
            IStakeRegistry.StakeUpdate[] memory prevOperatorStakes =
                _getLatestStakeUpdates(setup.operatorId, setup.quorumNumbers);
            IStakeRegistry.StakeUpdate[] memory prevTotalStakes =
                _getLatestTotalStakeUpdates(setup.quorumNumbers);
            uint256[] memory prevOperatorHistoryLengths =
                _getStakeHistoryLengths(setup.operatorId, setup.quorumNumbers);

            // Move to current block number
            uint256 currBlock = startBlock + j;
            cheats.roll(currBlock);

            // updateOperatorsStake
            bool[] memory shouldBeDeregistered = new bool[](setup.quorumNumbers.length);
            for (uint256 i = 0; i < setup.quorumNumbers.length; i++) {
                cheats.prank(address(registryCoordinator));
                bool[] memory shouldBeDeregisteredForQuorum = stakeRegistry.updateOperatorsStake(
                    _wrap(setup.operator), _wrap(setup.operatorId), uint8(setup.quorumNumbers[i])
                );
                shouldBeDeregistered[i] = shouldBeDeregisteredForQuorum[0];
            }

            // Get ending state
            IStakeRegistry.StakeUpdate[] memory newOperatorStakes =
                _getLatestStakeUpdates(setup.operatorId, setup.quorumNumbers);
            IStakeRegistry.StakeUpdate[] memory newTotalStakes =
                _getLatestTotalStakeUpdates(setup.quorumNumbers);
            uint256[] memory newOperatorHistoryLengths =
                _getStakeHistoryLengths(setup.operatorId, setup.quorumNumbers);

            // Check results for each quorum
            for (uint256 i = 0; i < setup.quorumNumbers.length; i++) {
                uint8 quorumNumber = uint8(setup.quorumNumbers[i]);

                uint96 minimumStake = setup.minimumStakes[i];
                uint96 endingWeight = setup.endingWeights[i];

                IStakeRegistry.StakeUpdate memory prevOperatorStake = prevOperatorStakes[i];
                // IStakeRegistry.StakeUpdate memory prevTotalStake = prevTotalStakes[i];

                IStakeRegistry.StakeUpdate memory newOperatorStake = newOperatorStakes[i];
                // IStakeRegistry.StakeUpdate memory newTotalStake = newTotalStakes[i];

                // Sanity-check setup - operator should start with minimumStake
                assertTrue(
                    prevOperatorStake.stake == minimumStake,
                    "operator should start with nonzero stake"
                );

                if (endingWeight > minimumStake) {
                    // Check updating an operator who has added stake above the minimum:
                    uint96 stakeAdded = setup.stakeDeltaAbs;
                    assertEq(
                        prevOperatorStake.stake + stakeAdded,
                        newOperatorStake.stake,
                        "failed to add delta to operator stake"
                    );
                    assertEq(
                        prevTotalStakes[i].stake + stakeAdded,
                        newTotalStakes[i].stake,
                        "failed to add delta to total stake"
                    );
                    // Return value should be empty since we're still above the minimum
                    assertTrue(
                        !shouldBeDeregistered[i],
                        "positive stake delta should not lead to deregistration"
                    );
                    assertEq(
                        prevOperatorHistoryLengths[i] + 1,
                        newOperatorHistoryLengths[i],
                        "operator should have a new pushed update"
                    );
                } else if (endingWeight < minimumStake) {
                    // Check updating an operator who is now below the minimum:

                    // Stake should now be zero, regardless of stake delta
                    uint96 stakeRemoved = minimumStake;
                    assertEq(
                        prevOperatorStake.stake - stakeRemoved,
                        newOperatorStake.stake,
                        "failed to remove delta from operator stake"
                    );
                    // assertEq(prevTotalStake.stake - stakeRemoved, newTotalStake.stake, "failed to remove delta from total stake");
                    assertEq(newOperatorStake.stake, 0, "operator stake should now be zero");
                    // IECDSAStakeRegistryTypes.Quorum should be added to return bitmap
                    assertTrue(shouldBeDeregistered[i], "operator should be deregistered");
                    if (prevOperatorStake.stake >= minimumStake) {
                        // Total stakes and operator history should be updated
                        assertEq(
                            prevOperatorHistoryLengths[i] + 1,
                            newOperatorHistoryLengths[i],
                            "operator should have a new pushed update"
                        );
                        assertEq(
                            prevTotalStakes[i].stake,
                            newTotalStakes[i].stake + prevOperatorStake.stake,
                            "failed to remove from total stake"
                        );
                    } else {
                        // Total stakes and history should remain unchanged
                        assertEq(
                            prevOperatorHistoryLengths[i],
                            newOperatorHistoryLengths[i],
                            "history lengths should remain unchanged"
                        );
                        assertEq(
                            prevTotalStakes[i].stake,
                            newTotalStakes[i].stake,
                            "total stake should remain unchanged"
                        );
                    }
                } else {
                    // Check that no update occurs if weight remains the same
                    assertTrue(
                        _isUnchanged(prevOperatorStake, newOperatorStake),
                        "neutral stake delta should not have changed operator stake history"
                    );
                    assertTrue(
                        _isUnchanged(prevTotalStakes[i], newTotalStakes[i]),
                        "neutral stake delta should not have changed total stake history"
                    );
                    // Check that return value is empty - we're still at the minimum, so no quorums should be removed
                    assertTrue(
                        !shouldBeDeregistered[i],
                        "neutral stake delta should not remove any quorums"
                    );
                    assertEq(
                        prevOperatorHistoryLengths[i],
                        newOperatorHistoryLengths[i],
                        "history lengths should remain unchanged"
                    );
                }
            }
        }
    }

    /**
     *
     *                        getStakeHistory
     *
     */
    function testFuzz_getStakeHistory(uint192 quorumBitmap, uint16 additionalStake) public {
        // Setup - select a new operator and set their weight to each quorum's minimum plus some additional
        RegisterSetup memory setup = _fuzz_setupRegisterOperator(quorumBitmap, additionalStake);

        // State history should be empty
        {
            IStakeRegistry.StakeUpdate[][] memory stakeHistories =
                _getOperatorStakeHistories(setup.operatorId, setup.quorumNumbers);
            for (uint256 i = 0; i < setup.quorumNumbers.length; i++) {
                assertTrue(stakeHistories[i].length == 0, "invalid operator stake history length");
            }
        }

        // Register the Operator
        cheats.prank(address(registryCoordinator));
        (uint96[] memory resultingStakes, uint96[] memory totalStakes) =
            stakeRegistry.registerOperator(setup.operator, setup.operatorId, setup.quorumNumbers);

        // Check state history after registration
        {
            IStakeRegistry.StakeUpdate[] memory stakeUpdates =
                _getLatestStakeUpdates(setup.operatorId, setup.quorumNumbers);
            IStakeRegistry.StakeUpdate[][] memory stakeHistories =
                _getOperatorStakeHistories(setup.operatorId, setup.quorumNumbers);
            assertEq(
                stakeHistories.length, setup.quorumNumbers.length, "invalid stake histories length"
            );
            for (uint256 i = 0; i < setup.quorumNumbers.length; i++) {
                IStakeRegistry.StakeUpdate[] memory stakeHistory = stakeHistories[i];
                assertTrue(stakeHistory.length == 1, "invalid operator stake history length");
                assertEq(
                    stakeHistory[0].stake,
                    stakeUpdates[i].stake,
                    "invalid operator stake history stake"
                );
                assertEq(
                    stakeHistory[0].updateBlockNumber,
                    stakeUpdates[i].updateBlockNumber,
                    "invalid operator stake history update block number"
                );
                assertEq(
                    stakeHistory[0].nextUpdateBlockNumber,
                    stakeUpdates[i].nextUpdateBlockNumber,
                    "invalid operator stake history next update block number"
                );
            }
        }

        cheats.roll(block.number + 2);

        // Deregister the Operator
        cheats.prank(address(registryCoordinator));
        stakeRegistry.deregisterOperator(setup.operatorId, setup.quorumNumbers);

        // Check state history after deregistration
        {
            IStakeRegistry.StakeUpdate[] memory stakeUpdates =
                _getLatestStakeUpdates(setup.operatorId, setup.quorumNumbers);
            IStakeRegistry.StakeUpdate[][] memory stakeHistories =
                _getOperatorStakeHistories(setup.operatorId, setup.quorumNumbers);
            assertEq(
                stakeHistories.length, setup.quorumNumbers.length, "invalid stake histories length"
            );
            for (uint256 i = 0; i < setup.quorumNumbers.length; i++) {
                IStakeRegistry.StakeUpdate[] memory stakeHistory = stakeHistories[i];
                assertTrue(stakeHistory.length == 2, "invalid operator stake history length");
                assertEq(
                    stakeHistory[1].stake,
                    stakeUpdates[i].stake,
                    "invalid operator stake history stake"
                );
                assertEq(
                    stakeHistory[1].updateBlockNumber,
                    stakeUpdates[i].updateBlockNumber,
                    "invalid operator stake history update block number"
                );
                assertEq(
                    stakeHistory[1].nextUpdateBlockNumber,
                    stakeUpdates[i].nextUpdateBlockNumber,
                    "invalid operator stake history next update block number"
                );
            }
        }
    }

    function testFuzz_getStakeHistory_SingleBlock(
        uint192 quorumsToRemove,
        uint16 additionalStake
    ) public {
        DeregisterSetup memory setup = _fuzz_setupDeregisterOperator({
            registeredFor: initializedQuorumBitmap,
            fuzzy_toRemove: quorumsToRemove,
            fuzzy_addtlStake: additionalStake
        });
        uint32 blockNum = uint32(block.number);

        {
            IStakeRegistry.StakeUpdate[] memory stakeUpdates =
                _getLatestStakeUpdates(setup.operatorId, setup.registeredQuorumNumbers);
            IStakeRegistry.StakeUpdate[][] memory stakeHistories =
                _getOperatorStakeHistories(setup.operatorId, setup.registeredQuorumNumbers);
            assertEq(
                stakeHistories.length,
                setup.registeredQuorumNumbers.length,
                "invalid stake histories length"
            );
            for (uint256 i = 0; i < setup.registeredQuorumNumbers.length; i++) {
                assertTrue(stakeHistories[i].length == 1, "invalid operator stake history length");
                IStakeRegistry.StakeUpdate memory stakeHistory = stakeHistories[i][0];
                assertEq(
                    stakeHistory.stake,
                    stakeUpdates[i].stake,
                    "invalid operator stake history stake2"
                );
                assertEq(
                    stakeHistory.updateBlockNumber,
                    blockNum,
                    "invalid operator stake history update block number"
                );
                assertEq(
                    stakeHistory.nextUpdateBlockNumber,
                    stakeUpdates[i].nextUpdateBlockNumber,
                    "invalid operator stake history next update block number"
                );
            }
        }

        // deregisterOperator
        cheats.prank(address(registryCoordinator));
        stakeRegistry.deregisterOperator(setup.operatorId, setup.quorumsToRemove);

        // Check stake history after deregistration in the same block
        {
            IStakeRegistry.StakeUpdate[] memory stakeUpdates =
                _getLatestStakeUpdates(setup.operatorId, setup.registeredQuorumNumbers);
            IStakeRegistry.StakeUpdate[][] memory stakeHistories =
                _getOperatorStakeHistories(setup.operatorId, setup.registeredQuorumNumbers);
            assertEq(
                stakeHistories.length,
                setup.registeredQuorumNumbers.length,
                "invalid stake histories length"
            );
            for (uint256 i = 0; i < setup.registeredQuorumNumbers.length; i++) {
                assertTrue(stakeHistories[i].length == 1, "invalid operator stake history length");
                IStakeRegistry.StakeUpdate memory stakeHistory = stakeHistories[i][0];
                assertEq(
                    stakeHistory.stake,
                    stakeUpdates[i].stake,
                    "invalid operator stake history stake2"
                );
                assertEq(
                    stakeHistory.updateBlockNumber,
                    blockNum,
                    "invalid operator stake history update block number"
                );
                assertEq(
                    stakeHistory.nextUpdateBlockNumber,
                    stakeUpdates[i].nextUpdateBlockNumber,
                    "invalid operator stake history next update block number"
                );
            }
        }
    }

    /**
     *
     *                        getStakeUpdateAtIndex
     *
     */
    function testFuzz_getStakeUpdateAtIndex(
        uint192 quorumsToRemove,
        uint16 additionalStake
    ) public {
        DeregisterSetup memory setup = _fuzz_setupDeregisterOperator({
            registeredFor: initializedQuorumBitmap,
            fuzzy_toRemove: quorumsToRemove,
            fuzzy_addtlStake: additionalStake
        });

        {
            IStakeRegistry.StakeUpdate[] memory stakeUpdates =
                _getLatestStakeUpdates(setup.operatorId, setup.registeredQuorumNumbers);
            IStakeRegistry.StakeUpdate[] memory indexStakeUpdate =
                _getOperatorStakeUpdatesAtIndex(setup.operatorId, setup.registeredQuorumNumbers, 0);
            assertEq(
                indexStakeUpdate.length,
                setup.registeredQuorumNumbers.length,
                "invalid operator stake history length"
            );
            for (uint256 i = 0; i < setup.registeredQuorumNumbers.length; i++) {
                assertEq(indexStakeUpdate[i].stake, stakeUpdates[i].stake, "invalid operator stake");
                assertEq(
                    indexStakeUpdate[i].updateBlockNumber,
                    uint32(block.number),
                    "invalid operator stake update block number"
                );
                assertEq(
                    indexStakeUpdate[i].nextUpdateBlockNumber,
                    stakeUpdates[i].nextUpdateBlockNumber,
                    "invalid operator stake next update block number"
                );
            }
        }

        // Force block to be mined to ensure new stake update is registered
        cheats.roll(block.number + 2);

        // deregisterOperator
        cheats.prank(address(registryCoordinator));
        stakeRegistry.deregisterOperator(setup.operatorId, setup.quorumsToRemove);

        {
            IStakeRegistry.StakeUpdate[] memory stakeUpdates =
                _getLatestStakeUpdates(setup.operatorId, setup.quorumsToRemove);
            IStakeRegistry.StakeUpdate[] memory indexStakeUpdate =
                _getOperatorStakeUpdatesAtIndex(setup.operatorId, setup.quorumsToRemove, 1);
            assertEq(
                indexStakeUpdate.length,
                setup.quorumsToRemove.length,
                "invalid operator stake history length"
            );
            for (uint256 i = 0; i < setup.quorumsToRemove.length; i++) {
                assertEq(indexStakeUpdate[i].stake, stakeUpdates[i].stake, "invalid operator stake");
                assertEq(
                    indexStakeUpdate[i].updateBlockNumber,
                    uint32(block.number),
                    "invalid operator stake update block number"
                );
                assertEq(
                    indexStakeUpdate[i].nextUpdateBlockNumber,
                    stakeUpdates[i].nextUpdateBlockNumber,
                    "invalid operator stake next update block number"
                );
            }
        }
    }

    function testFuzz_getStakeUpdateAtIndex_SingleBlock(
        uint192 quorumsToRemove,
        uint16 additionalStake
    ) public {
        DeregisterSetup memory setup = _fuzz_setupDeregisterOperator({
            registeredFor: initializedQuorumBitmap,
            fuzzy_toRemove: quorumsToRemove,
            fuzzy_addtlStake: additionalStake
        });
        uint32 blockNum = uint32(block.number);

        {
            IStakeRegistry.StakeUpdate[] memory stakeUpdates =
                _getLatestStakeUpdates(setup.operatorId, setup.registeredQuorumNumbers);
            IStakeRegistry.StakeUpdate[] memory indexStakeUpdate =
                _getOperatorStakeUpdatesAtIndex(setup.operatorId, setup.registeredQuorumNumbers, 0);
            assertEq(
                indexStakeUpdate.length,
                setup.registeredQuorumNumbers.length,
                "invalid operator stake history length"
            );
            for (uint256 i = 0; i < setup.registeredQuorumNumbers.length; i++) {
                assertEq(indexStakeUpdate[i].stake, stakeUpdates[i].stake, "invalid operator stake");
                assertEq(
                    indexStakeUpdate[i].updateBlockNumber,
                    blockNum,
                    "invalid operator stake update block number"
                );
                assertEq(
                    indexStakeUpdate[i].nextUpdateBlockNumber,
                    stakeUpdates[i].nextUpdateBlockNumber,
                    "invalid operator stake next update block number"
                );
            }
        }

        // deregisterOperator
        cheats.prank(address(registryCoordinator));
        stakeRegistry.deregisterOperator(setup.operatorId, setup.quorumsToRemove);

        {
            IStakeRegistry.StakeUpdate[] memory stakeUpdates =
                _getLatestStakeUpdates(setup.operatorId, setup.quorumsToRemove);
            IStakeRegistry.StakeUpdate[] memory operatorStakeUpdatesPost =
                _getOperatorStakeUpdatesAtIndex(setup.operatorId, setup.quorumsToRemove, 0);
            assertEq(
                operatorStakeUpdatesPost.length,
                setup.quorumsToRemove.length,
                "invalid operator stake history length"
            );
            for (uint256 i = 0; i < setup.quorumsToRemove.length; i++) {
                assertEq(
                    operatorStakeUpdatesPost[i].stake,
                    stakeUpdates[i].stake,
                    "invalid operator stake"
                );
                assertEq(
                    operatorStakeUpdatesPost[i].updateBlockNumber,
                    blockNum,
                    "invalid operator stake update block number"
                );
                assertEq(
                    operatorStakeUpdatesPost[i].nextUpdateBlockNumber,
                    stakeUpdates[i].nextUpdateBlockNumber,
                    "invalid operator stake next update block number"
                );
            }
        }
    }
}

/// @notice Tests for StakeRegistry.weightOfOperatorForQuorum view function
contract StakeRegistryUnitTests_weightOfOperatorForQuorum is StakeRegistryUnitTests {
    using BitmapUtils for *;

    /**
     * @dev Initialize a new quorum with fuzzed multipliers and corresponding shares for an operator.
     * The minimum stake for the quorum is 0 so that any fuzzed input shares will register the operator
     * successfully and return a value for weightOfOperatorForQuorum. Fuzz test sets the operator shares
     * and asserts that the summed weight of the operator is correct.
     */
    function testFuzz_weightOfOperatorForQuorum(
        address operator,
        uint96[] memory multipliers,
        uint96[] memory shares
    ) public {
        cheats.assume(0 < multipliers.length && multipliers.length <= MAX_WEIGHING_FUNCTION_LENGTH);
        cheats.assume(shares.length >= multipliers.length);
        cheats.assume(multipliers.length > 3);

        // Initialize quorum with strategies of fuzzed multipliers.
        // Bound multipliers and shares max values to prevent overflows
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](3);
        for (uint256 i = 0; i < strategyParams.length; i++) {
            multipliers[i] = uint96(
                _randUint({
                    rand: bytes32(uint256(multipliers[i])),
                    min: 0,
                    max: 1000 * WEIGHTING_DIVISOR
                })
            );
            shares[i] = uint96(_randUint({rand: bytes32(uint256(shares[i])), min: 0, max: 10e20}));

            IStrategy strat = IStrategy(
                address(uint160(uint256(keccak256(abi.encodePacked("Voteweighing test", i)))))
            );
            strategyParams[i] = IStakeRegistryTypes.StrategyParams(
                strat, uint96(WEIGHTING_DIVISOR) + multipliers[i]
            );
        }
        cheats.prank(address(registryCoordinator));
        uint8 quorumNumber = nextQuorum;
        stakeRegistry.initializeDelegatedStakeQuorum(
            quorumNumber, 0, /* minimumStake */ strategyParams
        );

        // set the operator shares
        for (uint256 i = 0; i < strategyParams.length; i++) {
            delegationMock.setOperatorShares(operator, strategyParams[i].strategy, shares[i]);
        }

        // registerOperator
        uint256 operatorBitmap = uint256(0).setBit(quorumNumber);
        bytes memory quorumNumbers = operatorBitmap.bitmapToBytesArray();
        cheats.prank(address(registryCoordinator));
        stakeRegistry.registerOperator(operator, defaultOperatorId, quorumNumbers);

        // assert weight of the operator
        uint96 expectedWeight = 0;
        for (uint256 i = 0; i < strategyParams.length; i++) {
            expectedWeight += uint96(
                uint256(shares[i]) * uint256(strategyParams[i].multiplier) / WEIGHTING_DIVISOR
            );
        }
        assertEq(stakeRegistry.weightOfOperatorForQuorum(quorumNumber, operator), expectedWeight);
    }

    /// @dev consider multipliers for 3 strategies
    function testFuzz_weightOfOperatorForQuorum_3Strategies(
        address operator,
        uint96[3] memory shares
    ) public {
        // 3 LST Strat multipliers, rETH, stETH, ETH
        uint96[] memory multipliers = new uint96[](3);
        multipliers[0] = uint96(1070136092289993178);
        multipliers[1] = uint96(1071364636818145808);
        multipliers[2] = uint96(1000000000000000000);

        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](3);
        for (uint256 i = 0; i < strategyParams.length; i++) {
            shares[i] = uint96(_randUint({rand: bytes32(uint256(shares[i])), min: 0, max: 1e24}));
            IStrategy strat = IStrategy(
                address(uint160(uint256(keccak256(abi.encodePacked("Voteweighing test", i)))))
            );
            strategyParams[i] = IStakeRegistryTypes.StrategyParams(strat, multipliers[i]);
        }

        // create a valid quorum
        cheats.prank(address(registryCoordinator));
        uint8 quorumNumber = nextQuorum;
        stakeRegistry.initializeDelegatedStakeQuorum(
            quorumNumber, 0, /* minimumStake */ strategyParams
        );

        // set the operator shares
        for (uint256 i = 0; i < strategyParams.length; i++) {
            delegationMock.setOperatorShares(operator, strategyParams[i].strategy, shares[i]);
        }

        // registerOperator
        uint256 operatorBitmap = uint256(0).setBit(quorumNumber);
        bytes memory quorumNumbers = operatorBitmap.bitmapToBytesArray();
        cheats.prank(address(registryCoordinator));
        stakeRegistry.registerOperator(operator, defaultOperatorId, quorumNumbers);

        // assert weight of the operator
        uint96 expectedWeight = 0;
        for (uint256 i = 0; i < strategyParams.length; i++) {
            expectedWeight += uint96(
                uint256(shares[i]) * uint256(strategyParams[i].multiplier) / WEIGHTING_DIVISOR
            );
        }
        assertEq(stakeRegistry.weightOfOperatorForQuorum(quorumNumber, operator), expectedWeight);
    }
}

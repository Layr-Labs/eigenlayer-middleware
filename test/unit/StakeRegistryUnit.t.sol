// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Slasher} from "eigenlayer-contracts/src/contracts/core/Slasher.sol";
import {PauserRegistry} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {ISlasher} from "eigenlayer-contracts/src/contracts/interfaces/ISlasher.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IIndexRegistry} from "src/interfaces/IIndexRegistry.sol";
import {IRegistryCoordinator} from "src/interfaces/IRegistryCoordinator.sol";
import {IBLSApkRegistry} from "src/interfaces/IBLSApkRegistry.sol";
import {IRegistryCoordinator} from "src/interfaces/IRegistryCoordinator.sol";

import {BitmapUtils} from "src/libraries/BitmapUtils.sol";

import {StrategyManagerMock} from "eigenlayer-contracts/src/test/mocks/StrategyManagerMock.sol";
import {EigenPodManagerMock} from "eigenlayer-contracts/src/test/mocks/EigenPodManagerMock.sol";
import {OwnableMock} from "eigenlayer-contracts/src/test/mocks/OwnableMock.sol";
import {DelegationManagerMock} from "eigenlayer-contracts/src/test/mocks/DelegationManagerMock.sol";
import {SlasherMock} from "eigenlayer-contracts/src/test/mocks/SlasherMock.sol";

import {StakeRegistryHarness} from "test/harnesses/StakeRegistryHarness.sol";
import {RegistryCoordinatorHarness} from "test/harnesses/RegistryCoordinatorHarness.sol";

import {StakeRegistry} from "src/StakeRegistry.sol";
import {IStakeRegistry} from "src/interfaces/IStakeRegistry.sol";

import "forge-std/Test.sol";

contract StakeRegistryUnitTests is Test {
    using BitmapUtils for *;

    Vm cheats = Vm(HEVM_ADDRESS);

    ProxyAdmin public proxyAdmin;
    PauserRegistry public pauserRegistry;

    ISlasher public slasher = ISlasher(address(uint160(uint256(keccak256("slasher")))));

    Slasher public slasherImplementation;
    StakeRegistryHarness public stakeRegistryImplementation;
    StakeRegistryHarness public stakeRegistry;
    RegistryCoordinatorHarness public registryCoordinator;

    StrategyManagerMock public strategyManagerMock;
    DelegationManagerMock public delegationMock;
    EigenPodManagerMock public eigenPodManagerMock;

    address public registryCoordinatorOwner = address(uint160(uint256(keccak256("registryCoordinatorOwner"))));
    address public pauser = address(uint160(uint256(keccak256("pauser"))));
    address public unpauser = address(uint160(uint256(keccak256("unpauser"))));
    address public pubkeyRegistry = address(uint160(uint256(keccak256("pubkeyRegistry"))));
    address public indexRegistry = address(uint160(uint256(keccak256("indexRegistry"))));

    uint256 churnApproverPrivateKey = uint256(keccak256("churnApproverPrivateKey"));
    address churnApprover = cheats.addr(churnApproverPrivateKey);
    address ejector = address(uint160(uint256(keccak256("ejector"))));

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

    /// @notice emitted whenever the stake of `operator` is updated
    event OperatorStakeUpdate(
        bytes32 indexed operatorId,
        uint8 quorumNumber,
        uint96 stake
    );

    modifier fuzz_onlyInitializedQuorums(uint8 quorumNumber) {
        cheats.assume(initializedQuorumBitmap.numberIsInBitmap(quorumNumber));
        _;
    }

    function setUp() virtual public {
        proxyAdmin = new ProxyAdmin();

        address[] memory pausers = new address[](1);
        pausers[0] = pauser;
        pauserRegistry = new PauserRegistry(pausers, unpauser);

        delegationMock = new DelegationManagerMock();
        eigenPodManagerMock = new EigenPodManagerMock();
        strategyManagerMock = new StrategyManagerMock();
        slasherImplementation = new Slasher(strategyManagerMock, delegationMock);
        slasher = Slasher(
            address(
                new TransparentUpgradeableProxy(
                    address(slasherImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(Slasher.initialize.selector, msg.sender, pauserRegistry, 0/*initialPausedStatus*/)
                )
            )
        );

        strategyManagerMock.setAddresses(
            delegationMock,
            eigenPodManagerMock,
            slasher
        );

        // Make registryCoordinatorOwner the owner of the registryCoordinator contract
        cheats.startPrank(registryCoordinatorOwner);
        registryCoordinator = new RegistryCoordinatorHarness(
            delegationMock,
            slasher,
            stakeRegistry,
            IBLSApkRegistry(pubkeyRegistry),
            IIndexRegistry(indexRegistry)
        );

        stakeRegistryImplementation = new StakeRegistryHarness(
            IRegistryCoordinator(address(registryCoordinator)),
            delegationMock
        );

        stakeRegistry = StakeRegistryHarness(
            address(
                new TransparentUpgradeableProxy(
                    address(stakeRegistryImplementation),
                    address(proxyAdmin),
                    ""
                )
            )
        );
        cheats.stopPrank();

        // Initialize several quorums with varying minimum stakes
        _initializeQuorum({ minimumStake: uint96(type(uint16).max) });
        _initializeQuorum({ minimumStake: uint96(type(uint24).max) });
        _initializeQuorum({ minimumStake: uint96(type(uint32).max) });
        _initializeQuorum({ minimumStake: uint96(type(uint64).max) });

        _initializeQuorum({ minimumStake: uint96(type(uint16).max) + 1 });
        _initializeQuorum({ minimumStake: uint96(type(uint24).max) + 1 });
        _initializeQuorum({ minimumStake: uint96(type(uint32).max) + 1 });
        _initializeQuorum({ minimumStake: uint96(type(uint64).max) + 1 });
    }

    /*******************************************************************************
                                 initializers
    *******************************************************************************/

    /**
     * @dev Initialize a new quorum with `minimumStake`
     * The new quorum's number is sequential, starting with `nextQuorum`
     */
    function _initializeQuorum(uint96 minimumStake) internal {
        IStakeRegistry.StrategyParams[] memory strategyParams =
                new IStakeRegistry.StrategyParams[](1);
        strategyParams[0] = IStakeRegistry.StrategyParams(
            IStrategy(address(uint160(10000))),
            uint96(1)
        );

        uint8 quorumNumber = nextQuorum;
        nextQuorum++;

        cheats.prank(address(registryCoordinator));
        stakeRegistry.initializeQuorum(quorumNumber, minimumStake, strategyParams);

        // Mark quorum initialized for other tests
        initializedQuorumBitmap = uint192(initializedQuorumBitmap.addNumberToBitmap(quorumNumber));
        initializedQuorumBytes = initializedQuorumBitmap.bitmapToBytesArray();
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

    /*******************************************************************************
                                test setup methods
    *******************************************************************************/

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
    function _fuzz_setupRegisterOperator(uint192 fuzzy_Bitmap, uint16 fuzzy_addtlStake) internal returns (RegisterSetup memory) {
        // Select an unused operator to register
        (address operator, bytes32 operatorId) = _selectNewOperator();
        
        // Pick quorums to register for and get each quorum's minimum stake
        ( , bytes memory quorumNumbers) = _fuzz_getQuorums(fuzzy_Bitmap);
        uint96[] memory minimumStakes = _getMinimumStakes(quorumNumbers);

        // For each quorum, set the operator's weight as the minimum + addtlStake
        uint96[] memory operatorWeights = new uint96[](quorumNumbers.length);
        for (uint i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);

            unchecked { operatorWeights[i] = minimumStakes[i] + fuzzy_addtlStake; }
            cheats.assume(operatorWeights[i] >= minimumStakes[i]);
            cheats.assume(operatorWeights[i] >= fuzzy_addtlStake);

            stakeRegistry.setOperatorWeight(quorumNumber, operator, operatorWeights[i]);
        }

        /// Get starting state
        IStakeRegistry.StakeUpdate[] memory prevOperatorStakes = _getLatestStakeUpdates(operatorId, quorumNumbers);
        IStakeRegistry.StakeUpdate[] memory prevTotalStakes = _getLatestTotalStakeUpdates(quorumNumbers);

        // Ensure that the operator has not previously registered
        for (uint i = 0; i < quorumNumbers.length; i++) {
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

    function _fuzz_setupRegisterOperators(uint192 fuzzy_Bitmap, uint16 fuzzy_addtlStake, uint numOperators) internal returns (RegisterSetup[] memory) {
        RegisterSetup[] memory setups = new RegisterSetup[](numOperators);

        for (uint i = 0; i < numOperators; i++) {
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
        RegisterSetup memory registerSetup = _fuzz_setupRegisterOperator(registeredFor, fuzzy_addtlStake);

        // registerOperator
        cheats.prank(address(registryCoordinator));
        stakeRegistry.registerOperator(registerSetup.operator, registerSetup.operatorId, registerSetup.quorumNumbers);

        // Get state after registering:
        IStakeRegistry.StakeUpdate[] memory operatorStakes = _getLatestStakeUpdates(registerSetup.operatorId, registerSetup.quorumNumbers);
        IStakeRegistry.StakeUpdate[] memory totalStakes = _getLatestTotalStakeUpdates(registerSetup.quorumNumbers);
        
        (uint192 quorumsToRemoveBitmap, bytes memory quorumsToRemove) = _fuzz_getQuorums(fuzzy_toRemove);

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
        uint numOperators
    ) internal returns (DeregisterSetup[] memory) {
        DeregisterSetup[] memory setups = new DeregisterSetup[](numOperators);

        for (uint i = 0; i < numOperators; i++) {
            setups[i] = _fuzz_setupDeregisterOperator(registeredFor, fuzzy_toRemove, fuzzy_addtlStake);
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
    function _fuzz_setupUpdateOperatorStake(uint192 registeredFor, int8 fuzzy_Delta) internal returns (UpdateSetup memory) {
        RegisterSetup memory registerSetup = _fuzz_setupRegisterOperator(registeredFor, 0);

        // registerOperator
        cheats.prank(address(registryCoordinator));
        stakeRegistry.registerOperator(registerSetup.operator, registerSetup.operatorId, registerSetup.quorumNumbers);

        uint96[] memory minimumStakes = _getMinimumStakes(registerSetup.quorumNumbers);
        uint96[] memory endingWeights = new uint96[](minimumStakes.length);

        for (uint i = 0; i < minimumStakes.length; i++) {
            uint8 quorumNumber = uint8(registerSetup.quorumNumbers[i]);

            endingWeights[i] = _applyDelta(minimumStakes[i], int256(fuzzy_Delta));

            // Sanity-check setup:
            if (fuzzy_Delta > 0) {
                assertGt(endingWeights[i], minimumStakes[i], "_fuzz_setupUpdateOperatorStake: overflow during setup");
            } else if (fuzzy_Delta < 0) {
                assertLt(endingWeights[i], minimumStakes[i], "_fuzz_setupUpdateOperatorStake: underflow during setup");
            } else {
                assertEq(endingWeights[i], minimumStakes[i], "_fuzz_setupUpdateOperatorStake: invalid delta during setup");
            }

            // Set operator weights. The next time we call `updateOperatorStake`, these new weights will be used
            stakeRegistry.setOperatorWeight(quorumNumber, registerSetup.operator, endingWeights[i]);
        }

        uint96 stakeDeltaAbs = 
            fuzzy_Delta < 0 ? 
                uint96(-int96(fuzzy_Delta)) :
                uint96(int96(fuzzy_Delta));

        return UpdateSetup({
            operator: registerSetup.operator,
            operatorId: registerSetup.operatorId,
            quorumNumbers: registerSetup.quorumNumbers,
            minimumStakes: minimumStakes,
            endingWeights: endingWeights,
            stakeDeltaAbs: stakeDeltaAbs
        });
    }

    function _fuzz_setupUpdateOperatorStakes(uint8 numOperators, uint192 registeredFor, int8 fuzzy_Delta) internal returns (UpdateSetup[] memory) {
        UpdateSetup[] memory setups = new UpdateSetup[](numOperators);

        for (uint i = 0; i < numOperators; i++) {
            setups[i] = _fuzz_setupUpdateOperatorStake(registeredFor, fuzzy_Delta);
        }

        return setups;
    }

    /*******************************************************************************
                                helpful getters
    *******************************************************************************/

    /// @notice Given a fuzzed bitmap input, returns a bitmap and array of quorum numbers
    /// that are guaranteed to be initialized.
    function _fuzz_getQuorums(uint192 fuzzy_Bitmap) internal view returns (uint192, bytes memory) {
        fuzzy_Bitmap &= initializedQuorumBitmap;
        cheats.assume(!fuzzy_Bitmap.isEmpty());

        return (fuzzy_Bitmap, fuzzy_Bitmap.bitmapToBytesArray());
    }

    /// @notice Returns a list of initialized quorums ending in a non-initialized quorum
    /// @param rand is used to determine how many legitimate quorums to insert, so we can
    /// check this works for lists of varying lengths
    function _fuzz_getInvalidQuorums(bytes32 rand) internal returns (bytes memory) {
        uint length = _randUint({ rand: rand, min: 1, max: initializedQuorumBytes.length + 1 });
        bytes memory invalidQuorums = new bytes(length);

        // Create an invalid quorum number by incrementing the last initialized quorum
        uint8 invalidQuorum = 1 + uint8(initializedQuorumBytes[initializedQuorumBytes.length - 1]);

        // Select real quorums up to the length, then insert an invalid quorum
        for (uint8 quorum = 0; quorum < length - 1; quorum++) {
            // sanity check test setup
            assertTrue(initializedQuorumBitmap.numberIsInBitmap(quorum), "_fuzz_getInvalidQuorums: invalid quorum");
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
            prev.stake == cur.stake &&
            prev.updateBlockNumber == cur.updateBlockNumber &&
            prev.nextUpdateBlockNumber == cur.nextUpdateBlockNumber
        );
    }

    /// @dev Return the minimum stakes required for a list of quorums
    function _getMinimumStakes(bytes memory quorumNumbers) internal view returns (uint96[] memory) {
        uint96[] memory minimumStakes = new uint96[](quorumNumbers.length);
        
        for (uint i = 0; i < quorumNumbers.length; i++) {
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
        
        for (uint i = 0; i < quorumNumbers.length; i++) {
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
        
        for (uint i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);

            uint historyLength = stakeRegistry.getTotalStakeHistoryLength(quorumNumber);
            stakeUpdates[i] = stakeRegistry.getTotalStakeUpdateAtIndex(quorumNumber, historyLength - 1);
        }

        return stakeUpdates;
    }

    /// @dev Return the lengths of the total stake update history
    function _getLatestTotalStakeHistoryLengths(
        bytes memory quorumNumbers
    ) internal view returns (uint[] memory) {
        uint[] memory historyLengths = new uint[](quorumNumbers.length);

        for (uint i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);

            historyLengths[i] = stakeRegistry.getTotalStakeHistoryLength(quorumNumber);
        }

        return historyLengths;
    }

    function _incrementAddress(address start, uint256 inc) internal pure returns(address) {
        return address(uint160(uint256(uint160(start) + inc)));
    }

    function _incrementBytes32(bytes32 start, uint256 inc) internal pure returns(bytes32) {
        return bytes32(uint256(start) + inc);
    }

    function _calculateDelta(uint96 prev, uint96 cur) internal view returns (int256) {
        return stakeRegistry.calculateDelta({
            prev: prev,
            cur: cur
        });
    }

    function _applyDelta(uint96 value, int256 delta) internal view returns (uint96) {
        return stakeRegistry.applyDelta({
            value: value,
            delta: delta
        });
    }

    /// @dev Uses `rand` to return a random uint, with a range given by `min` and `max` (inclusive)
    /// @return `min` <= result <= `max`
    function _randUint(bytes32 rand, uint min, uint max) internal pure returns (uint) {
        // hashing makes for more uniform randomness
        rand = keccak256(abi.encodePacked(rand));
        
        uint range = max - min + 1;

        // calculate the number of bits needed for the range
        uint bitsNeeded = 0;
        uint tempRange = range;
        while (tempRange > 0) {
            bitsNeeded++;
            tempRange >>= 1;
        }

        // create a mask for the required number of bits
        // and extract the value from the hash
        uint mask = (1 << bitsNeeded) - 1;
        uint value = uint(rand) & mask;

        // in case value is out of range, wrap around or retry
        while (value >= range) {
            value = (value - range) & mask;
        }

        return min + value;
    }
}

/// @notice Tests for any nonstandard/permissioned methods
contract StakeRegistryUnitTests_Config is StakeRegistryUnitTests {

    /*******************************************************************************
                            setMinimumStakeForQuorum
    *******************************************************************************/

    function testFuzz_setMinimumStakeForQuorum(uint8 quorumNumber, uint96 minimumStakeForQuorum) public fuzz_onlyInitializedQuorums(quorumNumber) {
        cheats.prank(registryCoordinatorOwner);
        stakeRegistry.setMinimumStakeForQuorum(quorumNumber, minimumStakeForQuorum);

        assertEq(stakeRegistry.minimumStakeForQuorum(quorumNumber), minimumStakeForQuorum, "invalid minimum stake");
    }

    function testFuzz_setMinimumStakeForQuorum_revert_notServiceManager(uint8 quorumNumber, uint96 minimumStakeForQuorum) public fuzz_onlyInitializedQuorums(quorumNumber) {
        cheats.expectRevert("StakeRegistry.onlyCoordinatorOwner: caller is not the owner of the registryCoordinator");
        
        stakeRegistry.setMinimumStakeForQuorum(quorumNumber, minimumStakeForQuorum);
    }
}

/// @notice Tests for StakeRegistry.registerOperator
contract StakeRegistryUnitTests_Register is StakeRegistryUnitTests {

    /*******************************************************************************
                              registerOperator
    *******************************************************************************/

    /**
     * @dev Registers an operator for some initialized quorums, adding `additionalStake`
     * to the minimum stake for each quorum.
     *
     * Checks the end result of stake updates rather than the entire history
     */
    function testFuzz_registerOperator_singleOperator_singleBlock(
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
        IStakeRegistry.StakeUpdate[] memory newOperatorStakes = _getLatestStakeUpdates(setup.operatorId, setup.quorumNumbers);
        IStakeRegistry.StakeUpdate[] memory newTotalStakes = _getLatestTotalStakeUpdates(setup.quorumNumbers);

        /// Check results
        assertTrue(resultingStakes.length == setup.quorumNumbers.length, "invalid return length for operator stakes");
        assertTrue(totalStakes.length == setup.quorumNumbers.length, "invalid return length for total stakes");

        for (uint i = 0; i < setup.quorumNumbers.length; i++) {
            IStakeRegistry.StakeUpdate memory newOperatorStake = newOperatorStakes[i];
            IStakeRegistry.StakeUpdate memory newTotalStake = newTotalStakes[i];

            // Check return value against weights, latest state read, and minimum stake
            assertEq(resultingStakes[i], setup.operatorWeights[i], "stake registry did not return correct stake");
            assertEq(resultingStakes[i], newOperatorStake.stake, "invalid latest operator stake update");
            assertTrue(resultingStakes[i] != 0, "registered operator with zero stake");
            assertTrue(resultingStakes[i] >= setup.minimumStakes[i], "stake registry did not return correct stake");
            
            // Check stake increase from fuzzed input
            assertEq(resultingStakes[i], newOperatorStake.stake, "did not add additional stake to operator correctly");
            assertEq(resultingStakes[i], newTotalStake.stake, "did not add additional stake to total correctly");

            // Check that we had an update this block
            assertEq(newOperatorStake.updateBlockNumber, uint32(block.number), "");
            assertEq(newOperatorStake.nextUpdateBlockNumber, 0, "");
            assertEq(newTotalStake.updateBlockNumber, uint32(block.number), "");
            assertEq(newTotalStake.nextUpdateBlockNumber, 0, "");
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
    function testFuzz_registerOperators_multiOperator_singleBlock(
        uint8 numOperators,
        uint192 quorumBitmap,
        uint16 additionalStake
    ) public {
        cheats.assume(numOperators > 1 && numOperators < 20);

        RegisterSetup[] memory setups = _fuzz_setupRegisterOperators(quorumBitmap, additionalStake, numOperators);

        // Register each operator one at a time, and check results:
        for (uint i = 0; i < numOperators; i++) {
            RegisterSetup memory setup = setups[i];

            cheats.prank(address(registryCoordinator));
            (uint96[] memory resultingStakes, uint96[] memory totalStakes) = 
                stakeRegistry.registerOperator(setup.operator, setup.operatorId, setup.quorumNumbers);
            
            /// Read ending state
            IStakeRegistry.StakeUpdate[] memory newOperatorStakes = _getLatestStakeUpdates(setup.operatorId, setup.quorumNumbers);

            // Sum stakes in `_totalStakeAdded` to be checked later
            _tallyTotalStakeAdded(setup.quorumNumbers, resultingStakes);

            /// Check results
            assertTrue(resultingStakes.length == setup.quorumNumbers.length, "invalid return length for operator stakes");
            assertTrue(totalStakes.length == setup.quorumNumbers.length, "invalid return length for total stakes");

            for (uint j = 0; j < setup.quorumNumbers.length; j++) {
                // Check result against weights and latest state read
                assertEq(resultingStakes[j], setup.operatorWeights[j], "stake registry did not return correct stake");
                assertEq(resultingStakes[j], newOperatorStakes[j].stake, "invalid latest operator stake update");
                assertTrue(resultingStakes[j] != 0, "registered operator with zero stake");

                // Check result against minimum stake
                assertTrue(resultingStakes[j] >= setup.minimumStakes[j], "stake registry did not return correct stake");
            
                // Check stake increase from fuzzed input
                assertEq(resultingStakes[j], newOperatorStakes[j].stake, "did not add additional stake to operator correctly");
            }
        }

        // Check total stake results
        bytes memory quorumNumbers = initializedQuorumBytes;
        IStakeRegistry.StakeUpdate[] memory newTotalStakes = _getLatestTotalStakeUpdates(quorumNumbers);
        for (uint i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            assertEq(newTotalStakes[i].stake, _totalStakeAdded[quorumNumber], "incorrect latest total stake");
            assertEq(newTotalStakes[i].nextUpdateBlockNumber, 0, "incorrect total stake next update block");
            assertEq(newTotalStakes[i].updateBlockNumber, uint32(block.number), "incorrect total stake next update block");
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
    function testFuzz_registerOperators_multiOperator_multiBlock(
        uint8 operatorsPerBlock,
        uint8 totalBlocks,
        uint16 additionalStake
    ) public {
        // We want between [1, 4] unique operators to register for all quorums each block,
        // and we want to test this for [2, 5] blocks
        cheats.assume(operatorsPerBlock >= 1 && operatorsPerBlock <= 4);
        cheats.assume(totalBlocks >= 2 && totalBlocks <= 5);

        uint startBlock = block.number;
        for (uint i = 1; i <= totalBlocks; i++) {
            // Move to current block number
            uint curBlock = startBlock + i;
            cheats.roll(curBlock);

            RegisterSetup[] memory setups = 
                _fuzz_setupRegisterOperators(initializedQuorumBitmap, additionalStake, operatorsPerBlock);

            // Get prior total stake updates
            bytes memory quorumNumbers = setups[0].quorumNumbers;
            uint[] memory prevHistoryLengths = _getLatestTotalStakeHistoryLengths(quorumNumbers);
            
            for (uint j = 0; j < operatorsPerBlock; j++) {
                RegisterSetup memory setup = setups[j];

                cheats.prank(address(registryCoordinator));
                (uint96[] memory resultingStakes, ) = 
                    stakeRegistry.registerOperator(setup.operator, setup.operatorId, setup.quorumNumbers);
                
                // Sum stakes in `_totalStakeAdded` to be checked later
                _tallyTotalStakeAdded(setup.quorumNumbers, resultingStakes);
            }

            // Get new total stake updates
            uint[] memory newHistoryLengths = _getLatestTotalStakeHistoryLengths(quorumNumbers);
            IStakeRegistry.StakeUpdate[] memory newTotalStakes = _getLatestTotalStakeUpdates(quorumNumbers);

            for (uint j = 0; j < quorumNumbers.length; j++) {
                uint8 quorumNumber = uint8(quorumNumbers[j]);

                // Check that we've added 1 to total stake history length
                assertEq(prevHistoryLengths[j] + 1, newHistoryLengths[j], "total history should have a new entry");
                // Validate latest entry correctness
                assertEq(newTotalStakes[j].stake, _totalStakeAdded[quorumNumber], "latest update should match total stake added");
                assertEq(newTotalStakes[j].updateBlockNumber, curBlock, "latest update should be from current block");
                assertEq(newTotalStakes[j].nextUpdateBlockNumber, 0, "latest update should not have next update block");

                // Validate previous entry was updated correctly
                IStakeRegistry.StakeUpdate memory prevUpdate = 
                    stakeRegistry.getTotalStakeUpdateAtIndex(quorumNumber, prevHistoryLengths[j]-1);
                assertTrue(prevUpdate.stake < newTotalStakes[j].stake, "previous update should have lower stake than latest");
                assertEq(prevUpdate.updateBlockNumber + 1, newTotalStakes[j].updateBlockNumber, "prev entry should be from last block");
                assertEq(prevUpdate.nextUpdateBlockNumber, newTotalStakes[j].updateBlockNumber, "prev entry.next should be latest.cur");
            }
        }
    }

    function _tallyTotalStakeAdded(bytes memory quorumNumbers, uint96[] memory stakeAdded) internal {
        for (uint i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            _totalStakeAdded[quorumNumber] += stakeAdded[i];
        }
    }

    function test_registerOperator_revert_notRegistryCoordinator() public {
        (address operator, bytes32 operatorId) = _selectNewOperator();

        cheats.expectRevert("StakeRegistry.onlyRegistryCoordinator: caller is not the RegistryCoordinator");
        stakeRegistry.registerOperator(operator, operatorId, initializedQuorumBytes);
    }

    function testFuzz_registerOperator_revert_quorumDoesNotExist(bytes32 rand) public {
        RegisterSetup memory setup = _fuzz_setupRegisterOperator(initializedQuorumBitmap, 0);

        // Get a list of valid quorums ending in an invalid quorum number
        bytes memory invalidQuorums = _fuzz_getInvalidQuorums(rand);

        cheats.expectRevert("StakeRegistry.registerOperator: quorum does not exist");
        cheats.prank(address(registryCoordinator));
        stakeRegistry.registerOperator(setup.operator, setup.operatorId, invalidQuorums);
    }

    /// @dev Attempt to register for all quorums, selecting one quorum to attempt with
    /// insufficient stake
    function testFuzz_registerOperator_revert_insufficientStake(uint8 failingQuorum) public fuzz_onlyInitializedQuorums(failingQuorum) {
        (address operator, bytes32 operatorId) = _selectNewOperator();
        bytes memory quorumNumbers = initializedQuorumBytes;
        uint96[] memory minimumStakes = _getMinimumStakes(quorumNumbers);

        // Set the operator's weight to the minimum stake for each quorum
        // ... except the failing quorum, which gets minimum stake - 1
        for (uint i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            uint96 operatorWeight;

            if (quorumNumber == failingQuorum) {
                unchecked { operatorWeight = minimumStakes[i] - 1; }
                assertTrue(operatorWeight < minimumStakes[i], "minimum stake underflow");
            } else {
                operatorWeight = minimumStakes[i];
            }

            stakeRegistry.setOperatorWeight(quorumNumber, operator, operatorWeight);
        }

        // Attempt to register
        cheats.expectRevert("StakeRegistry.registerOperator: Operator does not meet minimum stake requirement for quorum");
        cheats.prank(address(registryCoordinator));
        stakeRegistry.registerOperator(operator, operatorId, quorumNumbers);
    }
}

/// @notice Tests for StakeRegistry.deregisterOperator
contract StakeRegistryUnitTests_Deregister is StakeRegistryUnitTests {

    using BitmapUtils for *;

    /*******************************************************************************
                              deregisterOperator
    *******************************************************************************/

    /**
     * @dev Registers an operator for each initialized quorum, adding `additionalStake`
     * to the minimum stake for each quorum. Tests deregistering the operator for
     * a subset of these quorums.
     */
    function testFuzz_deregisterOperator_singleOperator_singleBlock(
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

        IStakeRegistry.StakeUpdate[] memory newOperatorStakes = _getLatestStakeUpdates(setup.operatorId, setup.registeredQuorumNumbers);
        IStakeRegistry.StakeUpdate[] memory newTotalStakes = _getLatestTotalStakeUpdates(setup.registeredQuorumNumbers);

        for (uint i = 0; i < setup.registeredQuorumNumbers.length; i++) {
            uint8 registeredQuorum = uint8(setup.registeredQuorumNumbers[i]);

            IStakeRegistry.StakeUpdate memory prevOperatorStake = setup.prevOperatorStakes[i];
            IStakeRegistry.StakeUpdate memory prevTotalStake = setup.prevTotalStakes[i];

            IStakeRegistry.StakeUpdate memory newOperatorStake = newOperatorStakes[i];
            IStakeRegistry.StakeUpdate memory newTotalStake = newTotalStakes[i];

            // Whether the operator was deregistered from this quorum
            bool deregistered = setup.quorumsToRemoveBitmap.numberIsInBitmap(registeredQuorum);

            if (deregistered) {
                // Check that operator's stake was removed from both operator and total
                assertEq(newOperatorStake.stake, 0, "failed to remove stake");
                assertEq(newTotalStake.stake + prevOperatorStake.stake, prevTotalStake.stake, "failed to remove stake from total");
                
                // Check that we had an update this block
                assertEq(newOperatorStake.updateBlockNumber, uint32(block.number), "operator stake has incorrect update block");
                assertEq(newOperatorStake.nextUpdateBlockNumber, 0, "operator stake has incorrect next update block");
                assertEq(newTotalStake.updateBlockNumber, uint32(block.number), "total stake has incorrect update block");
                assertEq(newTotalStake.nextUpdateBlockNumber, 0, "total stake has incorrect next update block");
            } else {
                // Ensure no change to operator or total stakes
                assertTrue(_isUnchanged(prevOperatorStake, newOperatorStake), "operator stake incorrectly updated");
                assertTrue(_isUnchanged(prevTotalStake, newTotalStake), "total stake incorrectly updated");
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
    function testFuzz_deregisterOperator_multiOperator_singleBlock(
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

        IStakeRegistry.StakeUpdate[] memory prevTotalStakes = _getLatestTotalStakeUpdates(registeredQuorums);

        // Deregister operators one at a time and check results
        for (uint i = 0; i < numOperators; i++) {
            DeregisterSetup memory setup = setups[i];
            bytes32 operatorId = setup.operatorId;

            cheats.prank(address(registryCoordinator));
            stakeRegistry.deregisterOperator(setup.operatorId, setup.quorumsToRemove);

            IStakeRegistry.StakeUpdate[] memory newOperatorStakes = _getLatestStakeUpdates(operatorId, registeredQuorums);
            IStakeRegistry.StakeUpdate[] memory newTotalStakes = _getLatestTotalStakeUpdates(registeredQuorums);

            // Check results for each quorum
            for (uint j = 0; j < registeredQuorums.length; j++) {
                uint8 registeredQuorum = uint8(registeredQuorums[j]);

                IStakeRegistry.StakeUpdate memory prevOperatorStake = setup.prevOperatorStakes[j];
                IStakeRegistry.StakeUpdate memory prevTotalStake = prevTotalStakes[j];

                IStakeRegistry.StakeUpdate memory newOperatorStake = newOperatorStakes[j];
                IStakeRegistry.StakeUpdate memory newTotalStake = newTotalStakes[j];

                // Whether the operator was deregistered from this quorum
                bool deregistered = setup.quorumsToRemoveBitmap.numberIsInBitmap(registeredQuorum);

                if (deregistered) {
                    _totalStakeRemoved[registeredQuorum] += prevOperatorStake.stake;

                    // Check that operator's stake was removed from both operator and total
                    assertEq(newOperatorStake.stake, 0, "failed to remove stake");
                    assertEq(newTotalStake.stake + _totalStakeRemoved[registeredQuorum], prevTotalStake.stake, "failed to remove stake from total");
                    
                    // Check that we had an update this block
                    assertEq(newOperatorStake.updateBlockNumber, uint32(block.number), "operator stake has incorrect update block");
                    assertEq(newOperatorStake.nextUpdateBlockNumber, 0, "operator stake has incorrect next update block");
                    assertEq(newTotalStake.updateBlockNumber, uint32(block.number), "total stake has incorrect update block");
                    assertEq(newTotalStake.nextUpdateBlockNumber, 0, "total stake has incorrect next update block");
                } else {
                    // Ensure no change to operator stake
                    assertTrue(_isUnchanged(prevOperatorStake, newOperatorStake), "operator stake incorrectly updated");
                }
            }
        }

        // Now that we've deregistered all the operators, check the final results
        // For the quorums we chose to deregister from, the total stake should be zero
        IStakeRegistry.StakeUpdate[] memory finalTotalStakes = _getLatestTotalStakeUpdates(registeredQuorums);
        for (uint i = 0; i < registeredQuorums.length; i++) {
            uint8 registeredQuorum = uint8(registeredQuorums[i]);

            // Whether or not we deregistered operators from this quorum
            bool deregistered = quorumsToRemoveBitmap.numberIsInBitmap(registeredQuorum);

            if (deregistered) {
                assertEq(finalTotalStakes[i].stake, 0, "failed to remove all stake from quorum");
                assertEq(finalTotalStakes[i].updateBlockNumber, uint32(block.number), "failed to remove all stake from quorum");
                assertEq(finalTotalStakes[i].nextUpdateBlockNumber, 0, "failed to remove all stake from quorum");
            } else {
                assertTrue(_isUnchanged(finalTotalStakes[i], prevTotalStakes[i]), "incorrectly updated total stake history for unmodified quorum");
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
    function testFuzz_deregisterOperator_multiOperator_multiBlock(
        uint8 operatorsPerBlock,
        uint8 totalBlocks,
        uint16 additionalStake
    ) public {
        /// We want between [1, 4] unique operators to register for all quorums each block,
        /// and we want to test this for [2, 5] blocks
        cheats.assume(operatorsPerBlock >= 1 && operatorsPerBlock <= 4);
        cheats.assume(totalBlocks >= 2 && totalBlocks <= 5);

        uint numOperators = operatorsPerBlock * totalBlocks;
        uint operatorIdx; // track index in setups over test

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

        IStakeRegistry.StakeUpdate[] memory prevTotalStakes = _getLatestTotalStakeUpdates(registeredQuorums);
        uint startBlock = block.number;

        for (uint i = 1; i <= totalBlocks; i++) {
            // Move to current block number
            uint curBlock = startBlock + i;
            cheats.roll(curBlock);

            uint[] memory prevHistoryLengths = _getLatestTotalStakeHistoryLengths(registeredQuorums);

            // Within this block: deregister some operators for all quorums and add the stake removed
            // to `_totalStakeRemoved` for later checks
            for (uint j = 0; j < operatorsPerBlock; j++) {
                DeregisterSetup memory setup = setups[operatorIdx];
                operatorIdx++;

                cheats.prank(address(registryCoordinator));
                stakeRegistry.deregisterOperator(setup.operatorId, setup.quorumsToRemove);

                for (uint k = 0; k < registeredQuorums.length; k++) {
                    uint8 quorumNumber = uint8(registeredQuorums[k]);
                    _totalStakeRemoved[quorumNumber] += setup.prevOperatorStakes[k].stake;
                }
            }

            uint[] memory newHistoryLengths = _getLatestTotalStakeHistoryLengths(registeredQuorums);
            IStakeRegistry.StakeUpdate[] memory newTotalStakes = _getLatestTotalStakeUpdates(registeredQuorums);

            // Validate the sum of all updates this block:
            // Each quorum should have a new historical entry with the correct update block pointers
            // ... and each quorum's stake should have decreased by `_totalStakeRemoved[quorum]`
            for (uint j = 0; j < registeredQuorums.length; j++) {
                uint8 quorumNumber = uint8(registeredQuorums[j]);

                // Check that we've added 1 to total stake history length
                assertEq(prevHistoryLengths[j] + 1, newHistoryLengths[j], "total history should have a new entry");

                // Validate latest entry correctness
                assertEq(newTotalStakes[j].stake + _totalStakeRemoved[quorumNumber], prevTotalStakes[j].stake, "stake not removed correctly from total stake");
                assertEq(newTotalStakes[j].updateBlockNumber, curBlock, "latest update should be from current block");
                assertEq(newTotalStakes[j].nextUpdateBlockNumber, 0, "latest update should not have next update block");

                IStakeRegistry.StakeUpdate memory prevUpdate = 
                    stakeRegistry.getTotalStakeUpdateAtIndex(quorumNumber, prevHistoryLengths[j]-1);
                // Validate previous entry was updated correctly
                assertTrue(prevUpdate.stake > newTotalStakes[j].stake, "previous update should have higher stake than latest");
                assertEq(prevUpdate.updateBlockNumber + 1, newTotalStakes[j].updateBlockNumber, "prev entry should be from last block");
                assertEq(prevUpdate.nextUpdateBlockNumber, newTotalStakes[j].updateBlockNumber, "prev entry.next should be latest.cur");
            }
        }

        // Now that we've deregistered all the operators, check the final results
        // Each quorum's stake should be zero
        IStakeRegistry.StakeUpdate[] memory finalTotalStakes = _getLatestTotalStakeUpdates(registeredQuorums);
        for (uint i = 0; i < registeredQuorums.length; i++) {
            assertEq(finalTotalStakes[i].stake, 0, "failed to remove all stake from quorum");
        }
    }

    function test_deregisterOperator_revert_notRegistryCoordinator() public {
        DeregisterSetup memory setup = _fuzz_setupDeregisterOperator({
            registeredFor: initializedQuorumBitmap,
            fuzzy_toRemove: initializedQuorumBitmap,
            fuzzy_addtlStake: 0
        });

        cheats.expectRevert("StakeRegistry.onlyRegistryCoordinator: caller is not the RegistryCoordinator");
        stakeRegistry.deregisterOperator(setup.operatorId, setup.quorumsToRemove);
    }

    function testFuzz_deregisterOperator_revert_quorumDoesNotExist(bytes32 rand) public {
        // Create a new operator registered for all quorums
        DeregisterSetup memory setup = _fuzz_setupDeregisterOperator({
            registeredFor: initializedQuorumBitmap,
            fuzzy_toRemove: initializedQuorumBitmap,
            fuzzy_addtlStake: 0
        });
        
        // Get a list of valid quorums ending in an invalid quorum number
        bytes memory invalidQuorums = _fuzz_getInvalidQuorums(rand);

        cheats.expectRevert("StakeRegistry.registerOperator: quorum does not exist");
        cheats.prank(address(registryCoordinator));
        stakeRegistry.registerOperator(setup.operator, setup.operatorId, invalidQuorums);
    }
}

contract StakeRegistryUnitTests_StakeUpdates is StakeRegistryUnitTests {

    using BitmapUtils for *;

    /**
     * @dev Registers an operator for all initialized quorums, giving them exactly the minimum stake
     * for each quorum. Then applies `stakeDelta` to their current weight, adding or removing some
     * stake from each quorum.
     *
     * updateOperatorStake should then update the operator's stake using the new weight - we test
     * what happens when the operator remains at/above minimum stake, vs dipping below
     */
    function testFuzz_updateOperatorStake_singleOperator_singleBlock(int8 stakeDelta) public {
        UpdateSetup memory setup = _fuzz_setupUpdateOperatorStake({
            registeredFor: initializedQuorumBitmap,
            fuzzy_Delta: stakeDelta
        });

        // Get starting state
        IStakeRegistry.StakeUpdate[] memory prevOperatorStakes = _getLatestStakeUpdates(setup.operatorId, setup.quorumNumbers);
        IStakeRegistry.StakeUpdate[] memory prevTotalStakes = _getLatestTotalStakeUpdates(setup.quorumNumbers);

        // updateOperatorStake
        cheats.prank(address(registryCoordinator));
        uint192 quorumsToRemove = 
            stakeRegistry.updateOperatorStake(setup.operator, setup.operatorId, setup.quorumNumbers);

        // Get ending state
        IStakeRegistry.StakeUpdate[] memory newOperatorStakes = _getLatestStakeUpdates(setup.operatorId, setup.quorumNumbers);
        IStakeRegistry.StakeUpdate[] memory newTotalStakes = _getLatestTotalStakeUpdates(setup.quorumNumbers);

        // Check results for each quorum
        for (uint i = 0; i < setup.quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(setup.quorumNumbers[i]);

            uint96 minimumStake = setup.minimumStakes[i];
            uint96 endingWeight = setup.endingWeights[i];

            IStakeRegistry.StakeUpdate memory prevOperatorStake = prevOperatorStakes[i];
            IStakeRegistry.StakeUpdate memory prevTotalStake = prevTotalStakes[i];

            IStakeRegistry.StakeUpdate memory newOperatorStake = newOperatorStakes[i];
            IStakeRegistry.StakeUpdate memory newTotalStake = newTotalStakes[i];

            // Sanity-check setup - operator should start with minimumStake
            assertTrue(prevOperatorStake.stake == minimumStake, "operator should start with nonzero stake");

            if (endingWeight > minimumStake) {
                // Check updating an operator who has added stake above the minimum:

                // Only updates should be stake added to operator/total stakes
                uint96 stakeAdded = setup.stakeDeltaAbs;
                assertEq(prevOperatorStake.stake + stakeAdded, newOperatorStake.stake, "failed to add delta to operator stake");
                assertEq(prevTotalStake.stake + stakeAdded, newTotalStake.stake, "failed to add delta to total stake");
                // Return value should be empty since we're still above the minimum
                assertTrue(quorumsToRemove.isEmpty(), "positive stake delta should not remove any quorums");
            } else if (endingWeight < minimumStake) {
                // Check updating an operator who is now below the minimum:

                // Stake should now be zero, regardless of stake delta
                uint96 stakeRemoved = minimumStake;
                assertEq(prevOperatorStake.stake - stakeRemoved, newOperatorStake.stake, "failed to remove delta from operator stake");
                assertEq(prevTotalStake.stake - stakeRemoved, newTotalStake.stake, "failed to remove delta from total stake");
                assertEq(newOperatorStake.stake, 0, "operator stake should now be zero");
                // Quorum should be added to return bitmap
                assertTrue(quorumsToRemove.numberIsInBitmap(quorumNumber), "quorum should be in removal bitmap");
            } else {
                // Check that no update occurs if weight remains the same
                assertTrue(_isUnchanged(prevOperatorStake, newOperatorStake), "neutral stake delta should not have changed operator stake history");
                assertTrue(_isUnchanged(prevTotalStake, newTotalStake), "neutral stake delta should not have changed total stake history");
                // Check that return value is empty - we're still at the minimum, so no quorums should be removed
                assertTrue(quorumsToRemove.isEmpty(), "neutral stake delta should not remove any quorums");
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
    function testFuzz_updateOperatorStake_multiOperator_singleBlock(
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
        uint[] memory initialHistoryLengths = _getLatestTotalStakeHistoryLengths(quorumNumbers);
        IStakeRegistry.StakeUpdate[] memory initialTotalStakes = _getLatestTotalStakeUpdates(quorumNumbers);

        // Call `updateOperatorStake` one by one
        for (uint i = 0; i < numOperators; i++) {
            UpdateSetup memory setup = setups[i];

            // updateOperatorStake
            cheats.prank(address(registryCoordinator));
            stakeRegistry.updateOperatorStake(setup.operator, setup.operatorId, setup.quorumNumbers);
        }

        // Check final results for each quorum
        uint[] memory finalHistoryLengths = _getLatestTotalStakeHistoryLengths(quorumNumbers);
        IStakeRegistry.StakeUpdate[] memory finalTotalStakes = _getLatestTotalStakeUpdates(quorumNumbers);

        for (uint i = 0; i < quorumNumbers.length; i++) {         
            IStakeRegistry.StakeUpdate memory initialTotalStake = initialTotalStakes[i];
            IStakeRegistry.StakeUpdate memory finalTotalStake = finalTotalStakes[i];

            uint96 minimumStake = setups[0].minimumStakes[i];
            uint96 endingWeight = setups[0].endingWeights[i];
            uint96 stakeDeltaAbs = setups[0].stakeDeltaAbs;

            // Sanity-check setup: previous total stake should be minimumStake * numOperators
            assertEq(initialTotalStake.stake, minimumStake * numOperators, "quorum should start with minimum stake from all operators");

            // history lengths should be unchanged
            assertEq(initialHistoryLengths[i], finalHistoryLengths[i], "history lengths should remain unchanged");
            
            if (endingWeight > minimumStake) {
                // All operators had their stake increased by stakeDelta
                uint96 stakeAdded = numOperators * stakeDeltaAbs;
                assertEq(initialTotalStake.stake + stakeAdded, finalTotalStake.stake, "failed to add delta for all operators");
            } else if (endingWeight < minimumStake) {
                // All operators had their entire stake removed
                uint96 stakeRemoved = numOperators * minimumStake;
                assertEq(initialTotalStake.stake - stakeRemoved, finalTotalStake.stake, "failed to remove delta from total stake");
                assertEq(finalTotalStake.stake, 0, "final total stake should be zero");
            } else {
                // No change in stake for any operator
                assertTrue(_isUnchanged(initialTotalStake, finalTotalStake), "neutral stake delta should result in no change");
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
    function testFuzz_updateOperatorStake_singleOperator_multiBlock(
        bytes32 /**rand*/,
        uint8 /**totalBlocks*/
    ) public {
        cheats.skip(true);
    }

    function test_updateOperatorStake_revert_notRegistryCoordinator() public {
        UpdateSetup memory setup = _fuzz_setupUpdateOperatorStake({
            registeredFor: initializedQuorumBitmap,
            fuzzy_Delta: 0
        });

        cheats.expectRevert("StakeRegistry.onlyRegistryCoordinator: caller is not the RegistryCoordinator");
        stakeRegistry.updateOperatorStake(setup.operator, setup.operatorId, setup.quorumNumbers);
    }

    function testFuzz_updateOperatorStake_revert_quorumDoesNotExist(bytes32 rand) public {
        // Create a new operator registered for all quorums
        UpdateSetup memory setup = _fuzz_setupUpdateOperatorStake({
            registeredFor: initializedQuorumBitmap,
            fuzzy_Delta: 0
        });
        
        // Get a list of valid quorums ending in an invalid quorum number
        bytes memory invalidQuorums = _fuzz_getInvalidQuorums(rand);

        cheats.expectRevert("StakeRegistry.updateOperatorStake: quorum does not exist");
        cheats.prank(address(registryCoordinator));
        stakeRegistry.updateOperatorStake(setup.operator, setup.operatorId, invalidQuorums);
    }
}
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
import {IServiceManager} from "src/interfaces/IServiceManager.sol";
import {IIndexRegistry} from "src/interfaces/IIndexRegistry.sol";
import {IRegistryCoordinator} from "src/interfaces/IRegistryCoordinator.sol";
import {IBLSPubkeyRegistry} from "src/interfaces/IBLSPubkeyRegistry.sol";
import {IBLSRegistryCoordinatorWithIndices} from "src/interfaces/IBLSRegistryCoordinatorWithIndices.sol";

import {BitmapUtils} from "src/libraries/BitmapUtils.sol";

import {StrategyManagerMock} from "eigenlayer-contracts/src/test/mocks/StrategyManagerMock.sol";
import {EigenPodManagerMock} from "eigenlayer-contracts/src/test/mocks/EigenPodManagerMock.sol";
import {ServiceManagerMock} from "test/mocks/ServiceManagerMock.sol";
import {OwnableMock} from "eigenlayer-contracts/src/test/mocks/OwnableMock.sol";
import {DelegationManagerMock} from "eigenlayer-contracts/src/test/mocks/DelegationManagerMock.sol";
import {SlasherMock} from "eigenlayer-contracts/src/test/mocks/SlasherMock.sol";

import {StakeRegistryHarness} from "test/harnesses/StakeRegistryHarness.sol";
import {BLSRegistryCoordinatorWithIndicesHarness} from "test/harnesses/BLSRegistryCoordinatorWithIndicesHarness.sol";

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
    BLSRegistryCoordinatorWithIndicesHarness public registryCoordinator;

    ServiceManagerMock public serviceManagerMock;
    StrategyManagerMock public strategyManagerMock;
    DelegationManagerMock public delegationMock;
    EigenPodManagerMock public eigenPodManagerMock;

    address public serviceManagerOwner = address(uint160(uint256(keccak256("serviceManagerOwner"))));
    address public pauser = address(uint160(uint256(keccak256("pauser"))));
    address public unpauser = address(uint160(uint256(keccak256("unpauser"))));
    address public pubkeyRegistry = address(uint160(uint256(keccak256("pubkeyRegistry"))));
    address public indexRegistry = address(uint160(uint256(keccak256("indexRegistry"))));

    uint256 churnApproverPrivateKey = uint256(keccak256("churnApproverPrivateKey"));
    address churnApprover = cheats.addr(churnApproverPrivateKey);
    address ejector = address(uint160(uint256(keccak256("ejector"))));

    address defaultOperator = address(uint160(uint256(keccak256("defaultOperator"))));
    bytes32 defaultOperatorId = keccak256("defaultOperatorId");
    uint8 defaultQuorumNumber = 0;
    uint8 numQuorums = 192;
    uint8 maxQuorumsToRegisterFor = 4;

    address nextOperator = address(1000);
    bytes32 nextOperatorId = bytes32(uint256(1000));

    /**
     * Fuzz input filters:
     */
    mapping(uint8 => bool) initializedQuorums;
    uint192 initializedQuorumBitmap;

    uint256 gasUsed;

    /// @notice emitted whenever the stake of `operator` is updated
    event OperatorStakeUpdate(
        bytes32 indexed operatorId,
        uint8 quorumNumber,
        uint96 stake
    );

    modifier fuzz_onlyInitializedQuorums(uint8 quorumNumber) {
        cheats.assume(initializedQuorums[quorumNumber]);
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

        registryCoordinator = new BLSRegistryCoordinatorWithIndicesHarness(
            slasher,
            serviceManagerMock,
            stakeRegistry,
            IBLSPubkeyRegistry(pubkeyRegistry),
            IIndexRegistry(indexRegistry)
        );

        cheats.startPrank(serviceManagerOwner);
        // make the serviceManagerOwner the owner of the serviceManager contract
        serviceManagerMock = new ServiceManagerMock(slasher);
        stakeRegistryImplementation = new StakeRegistryHarness(
            IRegistryCoordinator(address(registryCoordinator)),
            delegationMock,
            IServiceManager(address(serviceManagerMock))
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

        // Initialize quorums with dummy minimum stake and strategies
        for (uint i = 0; i < maxQuorumsToRegisterFor; i++) {
            uint96 minimumStake = uint96(i + 1);
            IStakeRegistry.StrategyParams[] memory strategyParams =
                new IStakeRegistry.StrategyParams[](1);
            strategyParams[0] = IStakeRegistry.StrategyParams(
                IStrategy(address(uint160(i))),
                uint96(i+1)
            );

            _initializeQuorum(uint8(defaultQuorumNumber + i), minimumStake, strategyParams);
        }

        // Update the reg coord quorum count so updateStakes works
        registryCoordinator.setQuorumCount(maxQuorumsToRegisterFor);
    }

    function _initializeQuorum(
        uint8 quorumNumber, 
        uint96 minimumStake, 
        IStakeRegistry.StrategyParams[] memory strategyParams
    ) internal {
        cheats.prank(address(registryCoordinator));

        stakeRegistry.initializeQuorum(quorumNumber, minimumStake, strategyParams);
        initializedQuorums[quorumNumber] = true;
        initializedQuorumBitmap |= uint192(1 << quorumNumber);
    }

    // utility function for registering an operator with a valid quorumBitmap and stakesForQuorum using provided randomness
    function _registerOperatorRandomValid(
        address operator,
        bytes32 operatorId,
        uint256 psuedoRandomNumber
    ) internal returns(uint256, uint96[] memory){
        // generate uint256 quorumBitmap from psuedoRandomNumber and limit to maxQuorumsToRegisterFor quorums and register for quorum 0
        uint256 quorumBitmap = uint256(keccak256(abi.encodePacked(psuedoRandomNumber, "quorumBitmap"))) & (1 << maxQuorumsToRegisterFor - 1) | 1;
        // generate uint80[] stakesForQuorum from psuedoRandomNumber
        uint80[] memory stakesForQuorum = new uint80[](BitmapUtils.countNumOnes(quorumBitmap));
        for(uint i = 0; i < stakesForQuorum.length; i++) {
            stakesForQuorum[i] = uint80(uint256(keccak256(abi.encodePacked(psuedoRandomNumber, i, "stakesForQuorum"))));
        }

        return (quorumBitmap, _registerOperatorValid(operator, operatorId, quorumBitmap, stakesForQuorum));
    }

    // utility function for registering an operator
    function _registerOperatorValid(
        address operator,
        bytes32 operatorId,
        uint256 quorumBitmap,
        uint80[] memory stakesForQuorum
    ) internal returns(uint96[] memory){
        cheats.assume(quorumBitmap != 0);

        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        // pad the stakesForQuorum array with the minimum stake for the quorums 
        uint96[] memory paddedStakesForQuorum = new uint96[](BitmapUtils.countNumOnes(quorumBitmap));
        for(uint i = 0; i < paddedStakesForQuorum.length; i++) {
            uint96 minimumStakeForQuorum = stakeRegistry.minimumStakeForQuorum(uint8(quorumNumbers[i]));
            // make sure the operator has at least the mininmum stake in each quorum it is registering for
            if (i >= stakesForQuorum.length || stakesForQuorum[i] < minimumStakeForQuorum) {
                paddedStakesForQuorum[i] = minimumStakeForQuorum;
            } else {
                paddedStakesForQuorum[i] = stakesForQuorum[i];
            }
        }

        // set the weights of the operator
        for(uint i = 0; i < paddedStakesForQuorum.length; i++) {
            stakeRegistry.setOperatorWeight(uint8(quorumNumbers[i]), operator, paddedStakesForQuorum[i]);
        }

        // register operator
        uint256 gasleftBefore = gasleft();
        cheats.prank(address(registryCoordinator));
        stakeRegistry.registerOperator(operator, operatorId, quorumNumbers);
        gasUsed = gasleftBefore - gasleft();
        
        return paddedStakesForQuorum;
    }

    // utility function for deregistering an operator
    function _deregisterOperatorValid(
        bytes32 operatorId,
        uint256 quorumBitmap
    ) internal {
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        // deregister operator
        cheats.prank(address(registryCoordinator));
        stakeRegistry.deregisterOperator(operatorId, quorumNumbers);
    }

    function _getInitializedQuorums() internal view returns (bytes memory) {
        return BitmapUtils.bitmapToBytesArray(initializedQuorumBitmap);
    }

    function _getMinimumStakes(bytes memory quorumNumbers) internal view returns (uint96[] memory) {
        uint96[] memory minimumStakes = new uint96[](quorumNumbers.length);
        
        for (uint i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            minimumStakes[i] = stakeRegistry.minimumStakeForQuorum(quorumNumber);
        }

        return minimumStakes;
    }

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

    /// @dev Return a new, unique operator/operatorId pair
    function _selectNewOperator() internal returns (address, bytes32) {
        address operator = nextOperator;
        bytes32 operatorId = nextOperatorId;
        nextOperator = _incrementAddress(nextOperator, 1);
        nextOperatorId = _incrementBytes32(nextOperatorId, 1);
        return (operator, operatorId);
    }

    struct RegisterSetup {
        address operator;
        bytes32 operatorId;
        bytes quorumNumbers;
        uint96[] operatorWeights;
        uint96[] minimumStakes;
        IStakeRegistry.StakeUpdate[] prevOperatorStakes;
        IStakeRegistry.StakeUpdate[] prevTotalStakes;
    }

    /// @dev Multi-operator version of the function below
    function _fuzz_setupRegisterOperators(uint192 fuzzy_Bitmap, uint16 fuzzy_addtlStake, uint numOperators) internal returns (RegisterSetup[] memory) {
        RegisterSetup[] memory setups = new RegisterSetup[](numOperators);

        for (uint i = 0; i < numOperators; i++) {
            setups[i] = _fuzz_setupRegisterOperator(fuzzy_Bitmap, fuzzy_addtlStake);
        }

        return setups;
    }

    /// @dev Utility function set up a new operator to be registered for some quorums
    /// The operator's weight is set to the quorum's minimum, plus fuzzy_addtlStake (overflows are skipped)
    /// This function guarantees at least one quorum, and any quorums returned are initialized
    function _fuzz_setupRegisterOperator(uint192 fuzzy_Bitmap, uint16 fuzzy_addtlStake) internal returns (RegisterSetup memory) {
        // Select an unused operator to register
        (address operator, bytes32 operatorId) = _selectNewOperator();
        
        // Pick quorums to register for and get each quorum's minimum stake
        bytes memory quorumNumbers = _fuzz_getQuorums(fuzzy_Bitmap);
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

    /// @notice Given a fuzzed bitmap input, returns an array of quorum numbers that
    /// are guaranteed to be initialized
    function _fuzz_getQuorums(uint192 fuzzy_Bitmap) internal view returns (bytes memory) {
        fuzzy_Bitmap &= initializedQuorumBitmap;
        cheats.assume(!fuzzy_Bitmap.isEmpty());

        return fuzzy_Bitmap.bitmapToBytesArray();
    }

    function _incrementAddress(address start, uint256 inc) internal pure returns(address) {
        return address(uint160(uint256(uint160(start) + inc)));
    }

    function _incrementBytes32(bytes32 start, uint256 inc) internal pure returns(bytes32) {
        return bytes32(uint256(start) + inc);
    }

    function _calculateDelta(uint96 prev, uint96 cur) internal pure returns (int256) {
        return int256(uint256(cur)) - int256(uint256(prev));
    }
}

/// @notice Tests for any non-registry coordinator permissioned methods
contract StakeRegistryUnitTests_Admin is StakeRegistryUnitTests {

    /*******************************************************************************
                            setMinimumStakeForQuorum
    *******************************************************************************/

    function testFuzz_setMinimumStakeForQuorum(uint8 quorumNumber, uint96 minimumStakeForQuorum) public fuzz_onlyInitializedQuorums(quorumNumber) {
        cheats.prank(serviceManagerOwner);
        stakeRegistry.setMinimumStakeForQuorum(quorumNumber, minimumStakeForQuorum);

        assertEq(stakeRegistry.minimumStakeForQuorum(quorumNumber), minimumStakeForQuorum, "invalid minimum stake");
    }

    function testFuzz_setMinimumStakeForQuorum_revert_notServiceManager(uint8 quorumNumber, uint96 minimumStakeForQuorum) public fuzz_onlyInitializedQuorums(quorumNumber) {
        cheats.expectRevert("StakeRegistry.onlyServiceManagerOwner: caller is not the owner of the serviceManager");
        
        stakeRegistry.setMinimumStakeForQuorum(quorumNumber, minimumStakeForQuorum);
    }
}

/// @notice Tests for StakeRegistry.registerOperator
contract StakeRegistryUnitTests_Register is StakeRegistryUnitTests {

    /*******************************************************************************
                              registerOperator
    *******************************************************************************/

    /**
     * @dev Registers an operator for each initialized quorum, adding `additionalStake`
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
            // Check result against weights and latest state read
            assertEq(resultingStakes[i], setup.operatorWeights[i], "stake registry did not return correct stake");
            assertEq(resultingStakes[i], newOperatorStakes[i].stake, "invalid latest operator stake update");
            assertTrue(resultingStakes[i] != 0, "registered operator with zero stake");

            // Check result against minimum stake
            assertTrue(resultingStakes[i] >= setup.minimumStakes[i], "stake registry did not return correct stake");
            
            // Check stake increase from fuzzed input
            assertEq(resultingStakes[i], newOperatorStakes[i].stake, "did not add additional stake to operator correctly");
            assertEq(resultingStakes[i], newTotalStakes[i].stake, "did not add additional stake to total correctly");
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
    function testFuzz_registerOperators_multipleOperators_singleBlock(
        uint8 numOperators,
        uint192 quorumBitmap,
        uint16 additionalStake
    ) public {
        cheats.assume(numOperators > 1 && numOperators < 20);

        RegisterSetup[] memory setups = new RegisterSetup[](numOperators);
        for (uint i = 0; i < numOperators; i++) {
            setups[i] = _fuzz_setupRegisterOperator(quorumBitmap, additionalStake);
        }

        // Register each operator one at a time, and check results:
        for (uint i = 0; i < numOperators; i++) {
            RegisterSetup memory setup = setups[i];

            cheats.prank(address(registryCoordinator));
            (uint96[] memory resultingStakes, uint96[] memory totalStakes) = 
                stakeRegistry.registerOperator(setup.operator, setup.operatorId, setup.quorumNumbers);
            
            /// Read ending state
            IStakeRegistry.StakeUpdate[] memory newOperatorStakes = _getLatestStakeUpdates(setup.operatorId, setup.quorumNumbers);

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
                
                // Track stake added to each quorum
                uint8 quorumNumber = uint8(setup.quorumNumbers[j]);
                uint96 stakeAdded = resultingStakes[j];
                _totalStakeAdded[quorumNumber] += stakeAdded;
            }
        }

        // Check total stake results
        bytes memory quorumNumbers = _getInitializedQuorums();
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
    function testFuzz_registerOperators_multipleOperators_multiBlock(
        uint8 operatorsPerBlock,
        uint8 totalBlocks,
        uint16 additionalStake
    ) public {
        /// We want between [1, 4] unique operators to register for all quorums each block,
        /// and we want to test this for [2, 5] blocks
        cheats.assume(operatorsPerBlock >= 1 && operatorsPerBlock <= 4);
        cheats.assume(totalBlocks >= 2 && totalBlocks <= 5);

        uint numOperators = operatorsPerBlock * totalBlocks;

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
                (uint96[] memory resultingStakes, uint96[] memory totalStakes) = 
                    stakeRegistry.registerOperator(setup.operator, setup.operatorId, setup.quorumNumbers);
                
                // Track overall stake added for each quorum
                for (uint k = 0; k < setup.quorumNumbers.length; k++) {
                    uint8 quorumNumber = uint8(setup.quorumNumbers[k]);
                    uint96 stakeAdded = resultingStakes[k];
                    _totalStakeAdded[quorumNumber] += stakeAdded;
                }
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

    function test_registerOperator_revert_notRegistryCoordinator() public {
        (address operator, bytes32 operatorId) = _selectNewOperator();
        bytes memory quorumNumbers = _getInitializedQuorums();

        cheats.expectRevert("StakeRegistry.onlyRegistryCoordinator: caller is not the RegistryCoordinator");
        stakeRegistry.registerOperator(operator, operatorId, quorumNumbers);
    }

    function test_registerOperator_revert_quorumDoesNotExist() public {
        (address operator, bytes32 operatorId) = _selectNewOperator();
        
        // Create an invalid quorum by incrementing the last initialized quorum
        bytes memory quorumNumbers = _getInitializedQuorums();
        uint8 invalidQuorum = uint8(quorumNumbers[quorumNumbers.length-1]) + 1;
        quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(invalidQuorum);

        cheats.expectRevert("StakeRegistry.registerOperator: quorum does not exist");
        cheats.prank(address(registryCoordinator));
        stakeRegistry.registerOperator(operator, operatorId, quorumNumbers);
    }

    /// @dev Attempt to register for all quorums, selecting one quorum to attempt with
    /// insufficient stake
    function testFuzz_registerOperator_revert_insufficientStake(uint8 failingQuorum) public fuzz_onlyInitializedQuorums(failingQuorum) {
        (address operator, bytes32 operatorId) = _selectNewOperator();
        bytes memory quorumNumbers = _getInitializedQuorums();
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

contract StakeRegistryUnitTests_Deregister is StakeRegistryUnitTests {

    /*******************************************************************************
                              deregisterOperator
    *******************************************************************************/

    function testDeregisterOperator_Valid(
        uint256 pseudoRandomNumber,
        uint256 quorumBitmap,
        uint256 deregistrationQuorumsFlag,
        uint80[] memory stakesForQuorum
    ) public {
        // modulo so no overflow
        pseudoRandomNumber = pseudoRandomNumber % type(uint128).max;
        // limit to maxQuorumsToRegisterFor quorums and register for quorum 0
        quorumBitmap = quorumBitmap & (1 << maxQuorumsToRegisterFor - 1) | 1;
        // register a bunch of operators
        cheats.roll(100);
        uint32 cumulativeBlockNumber = 100;

        uint8 numOperatorsRegisterBefore = 5;
        uint256 numOperators = 1 + 2*numOperatorsRegisterBefore;
        uint256[] memory quorumBitmaps = new uint256[](numOperators);

        // register
        for (uint i = 0; i < numOperatorsRegisterBefore; i++) {
            (quorumBitmaps[i],) = _registerOperatorRandomValid(_incrementAddress(defaultOperator, i), _incrementBytes32(defaultOperatorId, i), pseudoRandomNumber + i);
            
            cumulativeBlockNumber += 1;
            cheats.roll(cumulativeBlockNumber);
        }

        // register the operator to be deregistered
        quorumBitmaps[numOperatorsRegisterBefore] = quorumBitmap;
        bytes32 operatorIdToDeregister = _incrementBytes32(defaultOperatorId, numOperatorsRegisterBefore);
        uint96[] memory paddedStakesForQuorum;
        {
            address operatorToDeregister = _incrementAddress(defaultOperator, numOperatorsRegisterBefore);
            paddedStakesForQuorum = _registerOperatorValid(operatorToDeregister, operatorIdToDeregister, quorumBitmap, stakesForQuorum);
        }
        // register the rest of the operators
        for (uint i = numOperatorsRegisterBefore + 1; i < 2*numOperatorsRegisterBefore; i++) {
            cumulativeBlockNumber += 1;
            cheats.roll(cumulativeBlockNumber);

            (quorumBitmaps[i],) = _registerOperatorRandomValid(_incrementAddress(defaultOperator, i), _incrementBytes32(defaultOperatorId, i), pseudoRandomNumber + i);
        }

        cumulativeBlockNumber += 1;
        cheats.roll(cumulativeBlockNumber);

        // deregister the operator from a subset of the quorums
        uint256 deregistrationQuroumBitmap = quorumBitmap & deregistrationQuorumsFlag;
        _deregisterOperatorValid(operatorIdToDeregister, deregistrationQuroumBitmap);

        // for each bit in each quorumBitmap, increment the number of operators in that quorum
        uint32[] memory numOperatorsInQuorum = new uint32[](maxQuorumsToRegisterFor);
        for (uint256 i = 0; i < quorumBitmaps.length; i++) {
            for (uint256 j = 0; j < maxQuorumsToRegisterFor; j++) {
                if (quorumBitmaps[i] >> j & 1 == 1) {
                    numOperatorsInQuorum[j]++;
                }
            }
        }

        uint8 quorumNumberIndex = 0;
        for (uint8 i = 0; i < maxQuorumsToRegisterFor; i++) {
            if (deregistrationQuroumBitmap >> i & 1 == 1) {
                // check that the operator has 2 stake updates in the quorum numbers they registered for
                assertEq(stakeRegistry.getStakeHistoryLength(operatorIdToDeregister, i), 2, "testDeregisterFirstOperator_Valid_0");
                // make sure that the last stake update is as expected
                IStakeRegistry.StakeUpdate memory lastStakeUpdate =
                    stakeRegistry.getStakeUpdateAtIndex(i, operatorIdToDeregister, 1);
                assertEq(lastStakeUpdate.stake, 0, "testDeregisterFirstOperator_Valid_1");
                assertEq(lastStakeUpdate.updateBlockNumber, cumulativeBlockNumber, "testDeregisterFirstOperator_Valid_2");
                assertEq(lastStakeUpdate.nextUpdateBlockNumber, 0, "testDeregisterFirstOperator_Valid_3");

                // Get history length for quorum
                uint historyLength = stakeRegistry.getTotalStakeHistoryLength(i);
                // make sure that the last stake update is as expected
                IStakeRegistry.StakeUpdate memory lastTotalStakeUpdate 
                    = stakeRegistry.getTotalStakeUpdateAtIndex(i, historyLength-1);
                assertEq(lastTotalStakeUpdate.stake, 
                    stakeRegistry.getTotalStakeUpdateAtIndex(i, historyLength-2).stake // the previous total stake
                        - paddedStakesForQuorum[quorumNumberIndex], // minus the stake that was deregistered
                    "testDeregisterFirstOperator_Valid_5"    
                );
                assertEq(lastTotalStakeUpdate.updateBlockNumber, cumulativeBlockNumber, "testDeregisterFirstOperator_Valid_6");
                assertEq(lastTotalStakeUpdate.nextUpdateBlockNumber, 0, "testDeregisterFirstOperator_Valid_7");
                quorumNumberIndex++;
            } else if (quorumBitmap >> i & 1 == 1) {
                assertEq(stakeRegistry.getStakeHistoryLength(operatorIdToDeregister, i), 1, "testDeregisterFirstOperator_Valid_8");
                assertEq(stakeRegistry.getTotalStakeHistoryLength(i), numOperatorsInQuorum[i] + 1, "testDeregisterFirstOperator_Valid_9");
                quorumNumberIndex++;
            } else {
                // check that the operator has 0 stake updates in the quorum numbers they did not register for
                assertEq(stakeRegistry.getStakeHistoryLength(operatorIdToDeregister, i), 0, "testDeregisterFirstOperator_Valid_10");
            }
        }
    }
}

contract StakeRegistryUnitTests_StakeUpdates is StakeRegistryUnitTests {

    function testUpdateOperatorStake_Valid(
        uint24[] memory blocksPassed,
        uint96[] memory stakes
    ) public {
        cheats.assume(blocksPassed.length > 0);
        cheats.assume(blocksPassed.length <= stakes.length);
        // initialize at a non-zero block number
        uint32 intialBlockNumber = 100;
        cheats.roll(intialBlockNumber);
        uint32 cumulativeBlockNumber = intialBlockNumber;
        // loop through each one of the blocks passed, roll that many blocks, set the weight in the given quorum to the stake, and trigger a stake update
        uint i = 0;
        for (; i < blocksPassed.length; i++) {
            uint96 weight = stakes[i];
            uint96 minimum = stakeRegistry.minimumStakeForQuorum(uint8(defaultQuorumNumber));
            emit log_named_uint("set weight: ", weight);
            emit log_named_uint("minimum: ", minimum);
            stakeRegistry.setOperatorWeight(defaultQuorumNumber, defaultOperator, stakes[i]);

            bytes memory quorumNumbers = new bytes(1);
            quorumNumbers[0] = bytes1(defaultQuorumNumber);
            cheats.prank(address(registryCoordinator));
            stakeRegistry.updateOperatorStake(defaultOperator, defaultOperatorId, quorumNumbers);

            uint96 curWeight = stakeRegistry.getCurrentStake(defaultOperatorId, defaultQuorumNumber);
            emit log_named_uint("new weight: ", curWeight);

            cumulativeBlockNumber += blocksPassed[i];
            cheats.roll(cumulativeBlockNumber);
        }

        // make sure that the last stake update is as expected
        IStakeRegistry.StakeUpdate memory lastOperatorStakeUpdate = stakeRegistry.getLatestStakeUpdate(defaultOperatorId, defaultQuorumNumber);
        assertEq(lastOperatorStakeUpdate.stake, stakes[i - 1], "1");
        assertEq(lastOperatorStakeUpdate.nextUpdateBlockNumber, uint32(0), "2");
    }

    function testRecordTotalStakeUpdate_Valid(
        uint24 blocksPassed,
        uint96[] memory stakes
    ) public {
        // initialize at a non-zero block number
        uint32 intialBlockNumber = 100;
        cheats.roll(intialBlockNumber);
        uint32 cumulativeBlockNumber = intialBlockNumber;
        // loop through each one of the blocks passed, roll that many blocks, create an Operator Stake Update for total stake, and trigger a total stake update
        for (uint256 i = 0; i < stakes.length; i++) {
            int256 stakeDelta;
            if (i == 0) {
                stakeDelta = _calculateDelta({prev: 0, cur: stakes[i]});
            } else {
                stakeDelta = _calculateDelta({prev: stakes[i-1], cur: stakes[i]});
            }
                

            // Perform the update
            stakeRegistry.recordTotalStakeUpdate(defaultQuorumNumber, stakeDelta);
            
            IStakeRegistry.StakeUpdate memory newStakeUpdate;
            uint historyLength = stakeRegistry.getTotalStakeHistoryLength(defaultQuorumNumber);
            if (historyLength != 0) {
                newStakeUpdate = stakeRegistry.getTotalStakeUpdateAtIndex(defaultQuorumNumber, historyLength-1);
            }
            // Check that the most recent entry reflects the correct stake
            assertEq(newStakeUpdate.stake, stakes[i]);

            cumulativeBlockNumber += blocksPassed;
            cheats.roll(cumulativeBlockNumber);
        }
    }
}

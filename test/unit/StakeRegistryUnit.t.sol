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
import {IStakeRegistry} from "src/interfaces/IStakeRegistry.sol";
import {IServiceManager} from "src/interfaces/IServiceManager.sol";
import {IVoteWeigher} from "src/interfaces/IVoteWeigher.sol";
import {IRegistryCoordinator} from "src/interfaces/IRegistryCoordinator.sol";
import {IBLSPubkeyRegistry} from "src/interfaces/IBLSPubkeyRegistry.sol";
import {IIndexRegistry} from "src/interfaces/IIndexRegistry.sol";

import {BitmapUtils} from "eigenlayer-contracts/src/contracts/libraries/BitmapUtils.sol";

import {StrategyManagerMock} from "eigenlayer-contracts/src/test/mocks/StrategyManagerMock.sol";
import {EigenPodManagerMock} from "eigenlayer-contracts/src/test/mocks/EigenPodManagerMock.sol";
import {ServiceManagerMock} from "test/mocks/ServiceManagerMock.sol";
import {OwnableMock} from "eigenlayer-contracts/src/test/mocks/OwnableMock.sol";
import {DelegationManagerMock} from "eigenlayer-contracts/src/test/mocks/DelegationManagerMock.sol";
import {SlasherMock} from "eigenlayer-contracts/src/test/mocks/SlasherMock.sol";
import {IndexRegistryMock} from "test/mocks/IndexRegistryMock.sol";

import {StakeRegistryHarness} from "test/harnesses/StakeRegistryHarness.sol";
import {StakeRegistry} from "src/StakeRegistry.sol";
import {BLSRegistryCoordinatorWithIndicesHarness} from "test/harnesses/BLSRegistryCoordinatorWithIndicesHarness.sol";
import {StrategyBase} from "eigenlayer-contracts/src/contracts/strategies/StrategyBase.sol";

import "forge-std/Test.sol";

contract StakeRegistryUnitTests is Test {
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
    IndexRegistryMock public indexRegistryMock;

    address public serviceManagerOwner = address(uint160(uint256(keccak256("serviceManagerOwner"))));
    address public pauser = address(uint160(uint256(keccak256("pauser"))));
    address public unpauser = address(uint160(uint256(keccak256("unpauser"))));
    address public pubkeyRegistry = address(uint160(uint256(keccak256("pubkeyRegistry"))));
    address public indexRegistry = address(uint160(uint256(keccak256("indexRegistry"))));

    address defaultOperator = address(uint160(uint256(keccak256("defaultOperator"))));
    bytes32 defaultOperatorId = keccak256("defaultOperatorId");
    uint8 defaultQuorumNumber = 0;
    uint8 numQuorums = 192;
    uint8 maxQuorumsToRegisterFor = 10;

    uint256 gasUsed;

    /// @notice emitted whenever the stake of `operator` is updated
    event StakeUpdate(
        bytes32 indexed operatorId,
        uint8 quorumNumber,
        uint96 stake
    );

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

        indexRegistryMock = new IndexRegistryMock();

        registryCoordinator = new BLSRegistryCoordinatorWithIndicesHarness(
            slasher,
            serviceManagerMock,
            stakeRegistry,
            IBLSPubkeyRegistry(pubkeyRegistry),
            IIndexRegistry(indexRegistryMock)
        );

        cheats.startPrank(serviceManagerOwner);
        // make the serviceManagerOwner the owner of the serviceManager contract
        serviceManagerMock = new ServiceManagerMock(slasher);
        stakeRegistryImplementation = new StakeRegistryHarness(
            IRegistryCoordinator(address(registryCoordinator)),
            IIndexRegistry(indexRegistryMock),
            strategyManagerMock,
            IServiceManager(address(serviceManagerMock))
        );


        // setup the dummy minimum stake for quorum
        uint96[] memory minimumStakeForQuorum = new uint96[](maxQuorumsToRegisterFor);
        for (uint256 i = 0; i < minimumStakeForQuorum.length; i++) {
            minimumStakeForQuorum[i] = uint96(i+1);
        }

        // setup the dummy quorum strategies
        IVoteWeigher.StrategyAndWeightingMultiplier[][] memory quorumStrategiesConsideredAndMultipliers =
            new IVoteWeigher.StrategyAndWeightingMultiplier[][](maxQuorumsToRegisterFor);
        for (uint256 i = 0; i < quorumStrategiesConsideredAndMultipliers.length; i++) {
            quorumStrategiesConsideredAndMultipliers[i] = new IVoteWeigher.StrategyAndWeightingMultiplier[](1);
            quorumStrategiesConsideredAndMultipliers[i][0] = IVoteWeigher.StrategyAndWeightingMultiplier(
                IStrategy(address(uint160(i))),
                uint96(i+1)
            );
        }

        stakeRegistry = StakeRegistryHarness(
            address(
                new TransparentUpgradeableProxy(
                    address(stakeRegistryImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        StakeRegistry.initialize.selector,
                        minimumStakeForQuorum,
                        quorumStrategiesConsideredAndMultipliers
                    )
                )
            )
        );

        cheats.stopPrank();
    }

    function testCorrectConstruction() public {
        // make sure the contract intializers are disabled
        cheats.expectRevert(bytes("Initializable: contract is already initialized"));
        stakeRegistryImplementation.initialize(new uint96[](0), new IVoteWeigher.StrategyAndWeightingMultiplier[][](0));
    }

    function testSetMinimumStakeForQuorum_NotFromServiceManager_Reverts() public {
        cheats.expectRevert("VoteWeigherBase.onlyServiceManagerOwner: caller is not the owner of the serviceManager");
        stakeRegistry.setMinimumStakeForQuorum(defaultQuorumNumber, 0);
    }

    function testSetMinimumStakeForQuorum_Valid(uint8 quorumNumber, uint96 minimumStakeForQuorum) public {
        // set the minimum stake for quorum
        cheats.prank(serviceManagerOwner);
        stakeRegistry.setMinimumStakeForQuorum(quorumNumber, minimumStakeForQuorum);

        // make sure the minimum stake for quorum is as expected
        assertEq(stakeRegistry.minimumStakeForQuorum(quorumNumber), minimumStakeForQuorum);
    }

    function testRegisterOperator_NotFromRegistryCoordinator_Reverts() public {
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        cheats.expectRevert("StakeRegistry.onlyRegistryCoordinator: caller is not the RegistryCoordinator");
        stakeRegistry.registerOperator(defaultOperator, defaultOperatorId, quorumNumbers);
    }

    function testRegisterOperator_MoreQuorumsThanQuorumCount_Reverts() public {
        bytes memory quorumNumbers = new bytes(maxQuorumsToRegisterFor+1);
        for (uint i = 0; i < quorumNumbers.length; i++) {
            quorumNumbers[i] = bytes1(uint8(i));
        }

        // expect that it reverts when you register
        cheats.expectRevert("StakeRegistry._registerOperator: greatest quorumNumber must be less than quorumCount");
        cheats.prank(address(registryCoordinator));
        stakeRegistry.registerOperator(defaultOperator, defaultOperatorId, quorumNumbers);
    }

    function testRegisterOperator_LessThanMinimumStakeForQuorum_Reverts(
        uint96[] memory stakesForQuorum
    ) public {
        cheats.assume(stakesForQuorum.length > 0);

        // set the weights of the operator
        // stakeRegistry.setOperatorWeight()

        bytes memory quorumNumbers = new bytes(stakesForQuorum.length > maxQuorumsToRegisterFor ? maxQuorumsToRegisterFor : stakesForQuorum.length);
        for (uint i = 0; i < quorumNumbers.length; i++) {
            quorumNumbers[i] = bytes1(uint8(i));
        }

        stakesForQuorum[stakesForQuorum.length - 1] = stakeRegistry.minimumStakeForQuorum(uint8(quorumNumbers.length - 1)) - 1;

        // expect that it reverts when you register
        cheats.expectRevert("StakeRegistry._registerOperator: Operator does not meet minimum stake requirement for quorum");
        cheats.prank(address(registryCoordinator));
        stakeRegistry.registerOperator(defaultOperator, defaultOperatorId, quorumNumbers);
    }

    function testRegisterFirstOperator_Valid(
        uint256 quorumBitmap,
        uint80[] memory stakesForQuorum
    ) public {
        // limit to maxQuorumsToRegisterFor quorums and register for quorum 0
        quorumBitmap = quorumBitmap & (1 << maxQuorumsToRegisterFor - 1) | 1;
        uint96[] memory paddedStakesForQuorum = _registerOperatorValid(defaultOperator, defaultOperatorId, quorumBitmap, stakesForQuorum);

        uint8 quorumNumberIndex = 0;
        for (uint8 i = 0; i < maxQuorumsToRegisterFor; i++) {
            if (quorumBitmap >> i & 1 == 1) {
                // check that the operator has 1 stake update in the quorum numbers they registered for
                assertEq(stakeRegistry.getLengthOfOperatorIdStakeHistoryForQuorum(defaultOperatorId, i), 1);
                // make sure that the stake update is as expected
                IStakeRegistry.OperatorStakeUpdate memory stakeUpdate =
                    stakeRegistry.getStakeUpdateForQuorumFromOperatorIdAndIndex(i, defaultOperatorId, 0);
                emit log_named_uint("length  of paddedStakesForQuorum", paddedStakesForQuorum.length);
                assertEq(stakeUpdate.stake, paddedStakesForQuorum[quorumNumberIndex]);
                assertEq(stakeUpdate.updateBlockNumber, uint32(block.number));
                assertEq(stakeUpdate.nextUpdateBlockNumber, 0);

                // make the analogous check for total stake history
                assertEq(stakeRegistry.getLengthOfTotalStakeHistoryForQuorum(i), 1);
                // make sure that the stake update is as expected
                stakeUpdate = stakeRegistry.getTotalStakeUpdateForQuorumFromIndex(i, 0);
                assertEq(stakeUpdate.stake, paddedStakesForQuorum[quorumNumberIndex]);
                assertEq(stakeUpdate.updateBlockNumber, uint32(block.number));
                assertEq(stakeUpdate.nextUpdateBlockNumber, 0);

                quorumNumberIndex++;
            } else {
                // check that the operator has 0 stake updates in the quorum numbers they did not register for
                assertEq(stakeRegistry.getLengthOfOperatorIdStakeHistoryForQuorum(defaultOperatorId, i), 0);
                // make the analogous check for total stake history
                assertEq(stakeRegistry.getLengthOfTotalStakeHistoryForQuorum(i), 0);
            }
        }
    }

    function testRegisterManyOperators_Valid(
        uint256 pseudoRandomNumber,
        uint8 numOperators,
        uint24[] memory blocksPassed
    ) public {
        cheats.assume(numOperators > 0 && numOperators <= 15);
        // modulo so no overflow
        pseudoRandomNumber = pseudoRandomNumber % type(uint128).max;

        uint256[] memory quorumBitmaps = new uint256[](numOperators);

        // append to blocksPassed as needed
        uint24[] memory appendedBlocksPassed = new uint24[](quorumBitmaps.length);
        for (uint256 i = blocksPassed.length; i < quorumBitmaps.length; i++) {
            appendedBlocksPassed[i] = 0;
        }
        blocksPassed = appendedBlocksPassed;
        
        uint32 initialBlockNumber = 100;
        cheats.roll(initialBlockNumber);
        uint32 cumulativeBlockNumber = initialBlockNumber;

        uint96[][] memory paddedStakesForQuorums = new uint96[][](quorumBitmaps.length);
        for (uint256 i = 0; i < quorumBitmaps.length; i++) {
            (quorumBitmaps[i], paddedStakesForQuorums[i]) = _registerOperatorRandomValid(_incrementAddress(defaultOperator, i), _incrementBytes32(defaultOperatorId, i), pseudoRandomNumber + i);

            cumulativeBlockNumber += blocksPassed[i];
            cheats.roll(cumulativeBlockNumber);
        }
        
        // for each bit in each quorumBitmap, increment the number of operators in that quorum
        uint32[] memory numOperatorsInQuorum = new uint32[](maxQuorumsToRegisterFor);
        for (uint256 i = 0; i < quorumBitmaps.length; i++) {
            for (uint256 j = 0; j < maxQuorumsToRegisterFor; j++) {
                if (quorumBitmaps[i] >> j & 1 == 1) {
                    numOperatorsInQuorum[j]++;
                }
            }
        }

        // operatorQuorumIndices is an array of iindices within the quorum numbers that each operator registered for
        // used for accounting in the next loops
        uint32[] memory operatorQuorumIndices = new uint32[](quorumBitmaps.length);

        // for each quorum
        for (uint8 i = 0; i < maxQuorumsToRegisterFor; i++) {
            uint32 operatorCount = 0;
            // reset the cumulative block number
            cumulativeBlockNumber = initialBlockNumber;

            // make sure the number of total stake updates is as expected
            assertEq(stakeRegistry.getLengthOfTotalStakeHistoryForQuorum(i), numOperatorsInQuorum[i]);

            uint96 cumulativeStake = 0;
            // for each operator
            for (uint256 j = 0; j < quorumBitmaps.length; j++) {
                // if the operator is in the quorum
                if (quorumBitmaps[j] >> i & 1 == 1) {
                    cumulativeStake += paddedStakesForQuorums[j][operatorQuorumIndices[j]];
                    // make sure the number of stake updates is as expected
                    assertEq(stakeRegistry.getLengthOfOperatorIdStakeHistoryForQuorum(_incrementBytes32(defaultOperatorId, j), i), 1);

                    // make sure that the stake update is as expected
                    IStakeRegistry.OperatorStakeUpdate memory totalStakeUpdate =
                        stakeRegistry.getTotalStakeUpdateForQuorumFromIndex(i, operatorCount);

                    assertEq(totalStakeUpdate.stake, cumulativeStake);
                    assertEq(totalStakeUpdate.updateBlockNumber, cumulativeBlockNumber);
                    // make sure that the next update block number of the previous stake update is as expected
                    if (operatorCount != 0) {
                        IStakeRegistry.OperatorStakeUpdate memory prevTotalStakeUpdate =
                            stakeRegistry.getTotalStakeUpdateForQuorumFromIndex(i, operatorCount - 1);
                        assertEq(prevTotalStakeUpdate.nextUpdateBlockNumber, cumulativeBlockNumber);
                    }

                    operatorQuorumIndices[j]++;
                    operatorCount++;
                } else {
                    // make sure the number of stake updates is as expected
                    assertEq(stakeRegistry.getLengthOfOperatorIdStakeHistoryForQuorum(_incrementBytes32(defaultOperatorId, j), i), 0);
                }
                cumulativeBlockNumber += blocksPassed[j];
            }   
        }
    }

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

        {
            bool shouldPassBlockBeforeDeregistration  = uint256(keccak256(abi.encodePacked(pseudoRandomNumber, "shouldPassBlockBeforeDeregistration"))) & 1 == 1;
            if (shouldPassBlockBeforeDeregistration) {
                cumulativeBlockNumber += 1;
                cheats.roll(cumulativeBlockNumber);
            }
        }

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
                assertEq(stakeRegistry.getLengthOfOperatorIdStakeHistoryForQuorum(operatorIdToDeregister, i), 2, "testDeregisterFirstOperator_Valid_0");
                // make sure that the last stake update is as expected
                IStakeRegistry.OperatorStakeUpdate memory lastStakeUpdate =
                    stakeRegistry.getStakeUpdateForQuorumFromOperatorIdAndIndex(i, operatorIdToDeregister, 1);
                assertEq(lastStakeUpdate.stake, 0, "testDeregisterFirstOperator_Valid_1");
                assertEq(lastStakeUpdate.updateBlockNumber, cumulativeBlockNumber, "testDeregisterFirstOperator_Valid_2");
                assertEq(lastStakeUpdate.nextUpdateBlockNumber, 0, "testDeregisterFirstOperator_Valid_3");

                // make the analogous check for total stake history
                assertEq(stakeRegistry.getLengthOfTotalStakeHistoryForQuorum(i), numOperatorsInQuorum[i] + 1, "testDeregisterFirstOperator_Valid_4");
                // make sure that the last stake update is as expected
                IStakeRegistry.OperatorStakeUpdate memory lastTotalStakeUpdate 
                    = stakeRegistry.getTotalStakeUpdateForQuorumFromIndex(i, numOperatorsInQuorum[i]);
                assertEq(lastTotalStakeUpdate.stake, 
                    stakeRegistry.getTotalStakeUpdateForQuorumFromIndex(i, numOperatorsInQuorum[i] - 1).stake // the previous total stake
                        - paddedStakesForQuorum[quorumNumberIndex], // minus the stake that was deregistered
                    "testDeregisterFirstOperator_Valid_5"    
                );
                assertEq(lastTotalStakeUpdate.updateBlockNumber, cumulativeBlockNumber, "testDeregisterFirstOperator_Valid_6");
                assertEq(lastTotalStakeUpdate.nextUpdateBlockNumber, 0, "testDeregisterFirstOperator_Valid_7");
                quorumNumberIndex++;
            } else if (quorumBitmap >> i & 1 == 1) {
                assertEq(stakeRegistry.getLengthOfOperatorIdStakeHistoryForQuorum(operatorIdToDeregister, i), 1, "testDeregisterFirstOperator_Valid_8");
                assertEq(stakeRegistry.getLengthOfTotalStakeHistoryForQuorum(i), numOperatorsInQuorum[i], "testDeregisterFirstOperator_Valid_9");
                quorumNumberIndex++;
            } else {
                // check that the operator has 0 stake updates in the quorum numbers they did not register for
                assertEq(stakeRegistry.getLengthOfOperatorIdStakeHistoryForQuorum(operatorIdToDeregister, i), 0, "testDeregisterFirstOperator_Valid_10");
            }
        }
    }
    
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
        for (uint256 i = 0; i < blocksPassed.length; i++) {
            stakeRegistry.setOperatorWeight(defaultQuorumNumber, defaultOperator, stakes[i]);

            cheats.expectEmit(true, true, true, true, address(stakeRegistry));
            emit StakeUpdate(defaultOperatorId, defaultQuorumNumber, stakes[i]);
            stakeRegistry.updateOperatorStake(defaultOperator, defaultOperatorId, defaultQuorumNumber);

            cumulativeBlockNumber += blocksPassed[i];
            cheats.roll(cumulativeBlockNumber);
        }

        // reset for checking indices
        cumulativeBlockNumber = intialBlockNumber;
        // make sure that the stake updates are as expected
        for (uint256 i = 0; i < blocksPassed.length - 1; i++) {
            IStakeRegistry.OperatorStakeUpdate memory operatorStakeUpdate = stakeRegistry.getStakeUpdateForQuorumFromOperatorIdAndIndex(defaultQuorumNumber, defaultOperatorId, i);
            
            uint96 expectedStake = stakes[i];
            if (expectedStake < stakeRegistry.minimumStakeForQuorum(defaultQuorumNumber)) {
                expectedStake = 0;
            }

            assertEq(operatorStakeUpdate.stake, expectedStake);
            assertEq(operatorStakeUpdate.updateBlockNumber, cumulativeBlockNumber);
            cumulativeBlockNumber += blocksPassed[i];
            assertEq(operatorStakeUpdate.nextUpdateBlockNumber, cumulativeBlockNumber);
        }

        // make sure that the last stake update is as expected
        IStakeRegistry.OperatorStakeUpdate memory lastOperatorStakeUpdate = stakeRegistry.getStakeUpdateForQuorumFromOperatorIdAndIndex(defaultQuorumNumber, defaultOperatorId, blocksPassed.length - 1);
        assertEq(lastOperatorStakeUpdate.stake, stakes[blocksPassed.length - 1]);
        assertEq(lastOperatorStakeUpdate.updateBlockNumber, cumulativeBlockNumber);
        assertEq(lastOperatorStakeUpdate.nextUpdateBlockNumber, uint32(0));
    }

    function testRecordTotalStakeUpdate_Valid(
        uint24[] memory blocksPassed,
        uint96[] memory stakes
    ) public {
        cheats.assume(blocksPassed.length > 0);
        cheats.assume(blocksPassed.length <= stakes.length);
        // initialize at a non-zero block number
        uint32 intialBlockNumber = 100;
        cheats.roll(intialBlockNumber);
        uint32 cumulativeBlockNumber = intialBlockNumber;
        // loop through each one of the blocks passed, roll that many blocks, create an Operator Stake Update for total stake, and trigger a total stake update
        for (uint256 i = 0; i < blocksPassed.length; i++) {
            IStakeRegistry.OperatorStakeUpdate memory totalStakeUpdate;
            totalStakeUpdate.stake = stakes[i];

            stakeRegistry.recordTotalStakeUpdate(defaultQuorumNumber, totalStakeUpdate);

            cumulativeBlockNumber += blocksPassed[i];
            cheats.roll(cumulativeBlockNumber);
        }

        // reset for checking indices
        cumulativeBlockNumber = intialBlockNumber;
        // make sure that the total stake updates are as expected
        for (uint256 i = 0; i < blocksPassed.length - 1; i++) {
            IStakeRegistry.OperatorStakeUpdate memory totalStakeUpdate = stakeRegistry.getTotalStakeUpdateForQuorumFromIndex(defaultQuorumNumber, i);

            assertEq(totalStakeUpdate.stake, stakes[i]);
            assertEq(totalStakeUpdate.updateBlockNumber, cumulativeBlockNumber);
            cumulativeBlockNumber += blocksPassed[i];
            assertEq(totalStakeUpdate.nextUpdateBlockNumber, cumulativeBlockNumber);
        }
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

    // utility function for registering an operator with a valid quorumBitmap and stakesForQuorum using provided randomness
    function _registerOperatorSpecificQuorum(
        address operator,
        bytes32 operatorId,
        uint256 quorumNumber
    ) internal returns(uint256, uint96[] memory) {
        // Register for quorumNumber
        uint256 quorumBitmap = 1 << quorumNumber;
        // uint256 quorumBitmap = bound(psuedoRandomNumber, 0, (1<<maxQuorumsToRegisterFor)-1) | 1;
        // generate uint80[] stakesForQuorum from psuedoRandomNumber
        uint80[] memory stakesForQuorum = new uint80[](BitmapUtils.countNumOnes(quorumBitmap));
        for(uint i = 0; i < stakesForQuorum.length; i++) {
            stakesForQuorum[i] = uint80(uint256(keccak256(abi.encodePacked(quorumNumber, i, "stakesForQuorum"))));
        }

        return (quorumBitmap, _registerOperatorValid(operator, operatorId, quorumBitmap, stakesForQuorum));
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

    function _incrementAddress(address start, uint256 inc) internal pure returns(address) {
        return address(uint160(uint256(uint160(start) + inc)));
    }

    function _incrementBytes32(bytes32 start, uint256 inc) internal pure returns(bytes32) {
        return bytes32(uint256(start) + inc);
    }
}

/**
 * Testing updateStakesAllOperators() with StakeRegistry contract rather than using the StakeRegistryHarness
 * We want accurate gas costs instead of overriding the voteWeigher functions.
 */
contract StakeRegistryUnitTests_updateStakesAllOperators is Test {
    Vm cheats = Vm(HEVM_ADDRESS);

    ProxyAdmin public proxyAdmin;
    PauserRegistry public pauserRegistry;

    ISlasher public slasher = ISlasher(address(uint160(uint256(keccak256("slasher")))));

    Slasher public slasherImplementation;
    StakeRegistry public stakeRegistryImplementation;
    StakeRegistry public stakeRegistry;
    BLSRegistryCoordinatorWithIndicesHarness public registryCoordinator;

    ServiceManagerMock public serviceManagerMock;
    StrategyManagerMock public strategyManagerMock;
    DelegationManagerMock public delegationMock;
    EigenPodManagerMock public eigenPodManagerMock;
    IndexRegistryMock public indexRegistryMock;

    address public serviceManagerOwner = address(uint160(uint256(keccak256("serviceManagerOwner"))));
    address public pauser = address(uint160(uint256(keccak256("pauser"))));
    address public unpauser = address(uint160(uint256(keccak256("unpauser"))));
    address public pubkeyRegistry = address(uint160(uint256(keccak256("pubkeyRegistry"))));
    address public indexRegistry = address(uint160(uint256(keccak256("indexRegistry"))));

    address defaultOperator = address(uint160(uint256(keccak256("defaultOperator"))));
    bytes32 defaultOperatorId = keccak256("defaultOperatorId");
    uint8 defaultQuorumNumber = 0;
    uint8 numQuorums = 192;
    uint8 maxQuorumsToRegisterFor = 10;

    uint256 gasUsed;

    /// @notice emitted whenever the stake of `operator` is updated
    event StakeUpdate(
        bytes32 indexed operatorId,
        uint8 quorumNumber,
        uint96 stake
    );

    function setUp() public {
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

        indexRegistryMock = new IndexRegistryMock();

        registryCoordinator = new BLSRegistryCoordinatorWithIndicesHarness(
            slasher,
            serviceManagerMock,
            stakeRegistry,
            IBLSPubkeyRegistry(pubkeyRegistry),
            IIndexRegistry(indexRegistryMock)
        );

        cheats.startPrank(serviceManagerOwner);
        // make the serviceManagerOwner the owner of the serviceManager contract
        serviceManagerMock = new ServiceManagerMock(slasher);
        stakeRegistryImplementation = new StakeRegistry(
            IRegistryCoordinator(address(registryCoordinator)),
            IIndexRegistry(indexRegistryMock),
            strategyManagerMock,
            IServiceManager(address(serviceManagerMock))
        );


        // setup the dummy minimum stake for quorum
        uint96[] memory minimumStakeForQuorum = new uint96[](maxQuorumsToRegisterFor);
        for (uint256 i = 0; i < minimumStakeForQuorum.length; i++) {
            minimumStakeForQuorum[i] = uint96(i+1);
        }

        // setup the dummy quorum strategies
        IVoteWeigher.StrategyAndWeightingMultiplier[][] memory quorumStrategiesConsideredAndMultipliers =
            new IVoteWeigher.StrategyAndWeightingMultiplier[][](maxQuorumsToRegisterFor);
        for (uint256 i = 0; i < quorumStrategiesConsideredAndMultipliers.length; i++) {
            quorumStrategiesConsideredAndMultipliers[i] = new IVoteWeigher.StrategyAndWeightingMultiplier[](1);
            quorumStrategiesConsideredAndMultipliers[i][0] = IVoteWeigher.StrategyAndWeightingMultiplier(
                IStrategy(address(uint160(i))),
                uint96(i+1)
            );
        }

        stakeRegistry = StakeRegistry(
            address(
                new TransparentUpgradeableProxy(
                    address(stakeRegistryImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        StakeRegistry.initialize.selector,
                        minimumStakeForQuorum,
                        quorumStrategiesConsideredAndMultipliers
                    )
                )
            )
        );

        cheats.stopPrank();
    }

    /**
     * @notice Testing gas estimations for 10 quorums, quorum0 has 10 strategies and quorum1-9 have 1 strategy each
     * 200 operators all staked into quorum 0
     * 50 operators are also staked into each of the quorums 1-9
     */
    function testUpdateStakesAllOperators_200OperatorsValid() public {
        // Add 9 additional strategies to quorum 0 which already has 1 strategy
        uint256 numStratsToAdd = 9;
        IVoteWeigher.StrategyAndWeightingMultiplier[] memory quorumStrategiesConsideredAndMultipliers = new IVoteWeigher.StrategyAndWeightingMultiplier[](numStratsToAdd);
        for (uint256 i = 0; i < numStratsToAdd; ++i) {
            quorumStrategiesConsideredAndMultipliers[i] = IVoteWeigher.StrategyAndWeightingMultiplier(
                new StrategyBase(strategyManagerMock),
                uint96(i+1)
            );
        }
        // Set 200 operator addresses
        address[] memory operators = new address[](200);
        for (uint256 i = 0; i < 200; ++i) {
            operators[i] = address(uint160(i + 1000));
        }
        cheats.prank(serviceManagerOwner);
        stakeRegistry.addStrategiesConsideredAndMultipliers(0, quorumStrategiesConsideredAndMultipliers);
        // OperatorsPerQuorum input param
        address[][] memory updateOperators = new address[][](maxQuorumsToRegisterFor);

        // Register 200 operators for quorum0
        updateOperators[0] = new address[](200);
        indexRegistryMock.setTotalOperatorsForQuorum(0, 200);
        for (uint256 i = 0; i < operators.length; ++i) {
            defaultOperator = operators[i];
            bytes32 operatorId = bytes32(i + 1);

            (uint256 quorumBitmap, uint96[] memory stakesForQuorum) = _registerOperatorSpecificQuorum(defaultOperator, operatorId, /*quorumNumber*/ 0);
            require(quorumBitmap == 1, "quorumBitmap should be 1");
            registryCoordinator.setOperatorId(defaultOperator, operatorId);
            registryCoordinator.recordOperatorQuorumBitmapUpdate(operatorId, uint192(quorumBitmap));

            bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);
            _setOperatorQuorumWeight(uint8(quorumNumbers[0]), defaultOperator, stakesForQuorum[0] + 1);
            updateOperators[0][i] = operators[i];
        }
        // For each of the quorums 1-9, register 50 operators
        for (uint256 i = 0; i < 50; ++i) {
            defaultOperator = operators[i];
            bytes32 operatorId = bytes32(i + 1);
            // Register operator for each quorum 1-9
            uint256 newBitmap;
            for (uint256 j = 1; j < 10; j++) {
                // stakesForQuorum has 1 element for quorum j
                (uint256 quorumBitmap, uint96[] memory stakesForQuorum) = _registerOperatorSpecificQuorum(defaultOperator, operatorId, /*quorumNumber*/ j);
                uint256 currentOperatorBitmap = registryCoordinator.getCurrentQuorumBitmapByOperatorId(operatorId);
                newBitmap = currentOperatorBitmap | quorumBitmap;
                registryCoordinator.recordOperatorQuorumBitmapUpdate(operatorId, uint192(newBitmap));
                _setOperatorQuorumWeight(uint8(j), defaultOperator, stakesForQuorum[0] + 1);
            }
            require(newBitmap == (1<<maxQuorumsToRegisterFor)-1, "Should be registered all quorums");
        }
        // Mocking indexRegistry to set total number of operators per quorum
        for (uint256 i = 1; i < maxQuorumsToRegisterFor; i++) {
            updateOperators[i] = new address[](50);
            indexRegistryMock.setTotalOperatorsForQuorum(i, 50);
            for (uint256 j = 0; j < 50; j++) {
                updateOperators[i][j] = operators[j];
            }
        }

        // Check operators' stakehistory length, should be 1 if they registered
        for (uint256 i = 0; i < updateOperators.length; ++i) {
            uint8 quorumNumber = uint8(i);
            for (uint256 j = 0; j < updateOperators[i].length; ++j) {
                bytes32 operatorId = registryCoordinator.getOperatorId(updateOperators[i][j]);
                assertEq(stakeRegistry.getLengthOfOperatorIdStakeHistoryForQuorum(operatorId, quorumNumber), 1);    
            }
        }
        stakeRegistry.updateStakesAllOperators(updateOperators);
        // Check operators' stakehistory length, should be 1 if they registered, 2 if they updated stakes again
        for (uint256 i = 0; i < updateOperators.length; ++i) {
            uint8 quorumNumber = uint8(i);
            for (uint256 j = 0; j < updateOperators[i].length; ++j) {
                bytes32 operatorId = registryCoordinator.getOperatorId(updateOperators[i][j]);
                assertLe(stakeRegistry.getLengthOfOperatorIdStakeHistoryForQuorum(operatorId, quorumNumber), 2);    
            }
        }
    }

    function testUpdateStakesAllOperators_SomeEmptyQuorums(uint256[10] memory psuedoRandomNumbers) external {}

    function testUpdateStakesAllOperators_Reverts_DuplicateAddress() external {
        // Set 5 operator addresses
        address[] memory operators = new address[](5);
        for (uint256 i = 0; i < 5; ++i) {
            operators[i] = address(uint160(i + 1000));
        }
        // OperatorsPerQuorum input param
        address[][] memory updateOperators = new address[][](maxQuorumsToRegisterFor);
        // Register 5 operators for quorum0
        updateOperators[0] = new address[](5);
        indexRegistryMock.setTotalOperatorsForQuorum(0, 5);
        for (uint256 i = 0; i < 5; ++i) {
            defaultOperator = operators[i];
            bytes32 operatorId = bytes32(i + 1);
            (uint256 quorumBitmap, uint96[] memory stakesForQuorum) = _registerOperatorSpecificQuorum(defaultOperator, operatorId, /*quorumNumber*/ 0);
            require(quorumBitmap == 1, "quorumBitmap should be 1");
            registryCoordinator.setOperatorId(defaultOperator, operatorId);
            registryCoordinator.recordOperatorQuorumBitmapUpdate(operatorId, uint192(quorumBitmap));

            bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);
            _setOperatorQuorumWeight(uint8(quorumNumbers[0]), defaultOperator, stakesForQuorum[0] + 1);
            updateOperators[0][i] = operators[i];
        }

        // Create a duplicate address
        updateOperators[0][1] = updateOperators[0][0];
        cheats.expectRevert("StakeRegistry.updateStakesAllOperators: operators array must be sorted in ascending operatorId order");
        stakeRegistry.updateStakesAllOperators(updateOperators);
    }

    function testUpdateStakesAllOperators_Reverts_NonIncreasingOperatorIds(uint256[10] memory psuedoRandomNumbers) external {}

    function testUpdateStakesAllOperators_Reverts_InsufficientQuorumOperatorCount(uint256[10] memory psuedoRandomNumbers) external {}

    // utility function for registering an operator with a valid quorumBitmap and stakesForQuorum using provided randomness
    function _registerOperatorSpecificQuorum(
        address operator,
        bytes32 operatorId,
        uint256 quorumNumber
    ) internal returns(uint256, uint96[] memory) {
        // Register for quorumNumber
        uint256 quorumBitmap = 1 << quorumNumber;
        // uint256 quorumBitmap = bound(psuedoRandomNumber, 0, (1<<maxQuorumsToRegisterFor)-1) | 1;
        // generate uint80[] stakesForQuorum from psuedoRandomNumber
        uint80[] memory stakesForQuorum = new uint80[](BitmapUtils.countNumOnes(quorumBitmap));
        for(uint i = 0; i < stakesForQuorum.length; i++) {
            stakesForQuorum[i] = uint80(uint256(keccak256(abi.encodePacked(quorumNumber, i, "stakesForQuorum"))));
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
            _setOperatorQuorumWeight(uint8(quorumNumbers[i]), operator, paddedStakesForQuorum[i]);
        }

        // register operator
        uint256 gasleftBefore = gasleft();
        cheats.prank(address(registryCoordinator));
        stakeRegistry.registerOperator(operator, operatorId, quorumNumbers);
        gasUsed = gasleftBefore - gasleft();
        
        return paddedStakesForQuorum;
    }

    /// @notice For a given quorum and operator, set all strategies to be the given weight
    function _setOperatorQuorumWeight(
        uint8 quorumNumber,
        address operator,
        uint96 weight
    ) internal {
        uint256 quorumLength = stakeRegistry.strategiesConsideredAndMultipliersLength(quorumNumber);
        for (uint256 i = 0; i < quorumLength; ++i) {
            (IStrategy strategy, ) = stakeRegistry.strategiesConsideredAndMultipliers(quorumNumber, i);
            delegationMock.setOperatorShares(operator, strategy, uint256(weight));
        }
    }
}

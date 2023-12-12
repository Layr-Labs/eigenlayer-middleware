// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Slasher} from "eigenlayer-contracts/src/contracts/core/Slasher.sol";
import {PauserRegistry} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {ISlasher} from "eigenlayer-contracts/src/contracts/interfaces/ISlasher.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IStakeRegistry} from "src/interfaces/IStakeRegistry.sol";
import {IIndexRegistry} from "src/interfaces/IIndexRegistry.sol";
import {IRegistryCoordinator} from "src/interfaces/IRegistryCoordinator.sol";
import {IBLSApkRegistry} from "src/interfaces/IBLSApkRegistry.sol";

import {BitmapUtils} from "eigenlayer-contracts/src/contracts/libraries/BitmapUtils.sol";

import {StrategyManagerMock} from "eigenlayer-contracts/src/test/mocks/StrategyManagerMock.sol";
import {EigenPodManagerMock} from "eigenlayer-contracts/src/test/mocks/EigenPodManagerMock.sol";
import {OwnableMock} from "eigenlayer-contracts/src/test/mocks/OwnableMock.sol";
import {DelegationManagerMock} from "eigenlayer-contracts/src/test/mocks/DelegationManagerMock.sol";
import {SlasherMock} from "eigenlayer-contracts/src/test/mocks/SlasherMock.sol";

import {StakeRegistryHarness} from "test/harnesses/StakeRegistryHarness.sol";
import {StakeRegistry} from "src/StakeRegistry.sol";
import {RegistryCoordinatorHarness} from "test/harnesses/RegistryCoordinatorHarness.sol";

import "forge-std/Test.sol";

contract StakeRegistryUnitTests is Test {
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
    address public apkRegistry = address(uint160(uint256(keccak256("apkRegistry"))));
    address public indexRegistry = address(uint160(uint256(keccak256("indexRegistry"))));

    uint256 churnApproverPrivateKey = uint256(keccak256("churnApproverPrivateKey"));
    address churnApprover = cheats.addr(churnApproverPrivateKey);
    address ejector = address(uint160(uint256(keccak256("ejector"))));

    address defaultOperator = address(uint160(uint256(keccak256("defaultOperator"))));
    bytes32 defaultOperatorId = keccak256("defaultOperatorId");
    uint8 defaultQuorumNumber = 0;
    uint8 numQuorums = 192;
    uint8 maxQuorumsToRegisterFor = 4;

    // Track initialized quorums so we can filter these out when fuzzing
    mapping(uint8 => bool) initializedQuorums;

    uint256 gasUsed;

    /// @notice emitted whenever the stake of `operator` is updated
    event OperatorStakeUpdate(
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

        cheats.startPrank(registryCoordinatorOwner);
        registryCoordinator = new RegistryCoordinatorHarness(
            slasher,
            stakeRegistry,
            IBLSApkRegistry(apkRegistry),
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

    function testSetMinimumStakeForQuorum_NotFromCoordinatorOwner_Reverts() public {
        cheats.expectRevert("StakeRegistry.onlyCoordinatorOwner: caller is not the owner of the registryCoordinator");
        stakeRegistry.setMinimumStakeForQuorum(defaultQuorumNumber, 0);
    }

    function testSetMinimumStakeForQuorum_Valid(uint8 quorumNumber, uint96 minimumStakeForQuorum) public {
        // filter out non-initialized quorums
        cheats.assume(initializedQuorums[quorumNumber]);
        
        // set the minimum stake for quorum
        cheats.prank(registryCoordinatorOwner);
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
        cheats.expectRevert("StakeRegistry.registerOperator: Operator does not meet minimum stake requirement for quorum");
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
                assertEq(stakeRegistry.getStakeHistoryLength(defaultOperatorId, i), 1);
                // make sure that the stake update is as expected
                IStakeRegistry.StakeUpdate memory stakeUpdate =
                    stakeRegistry.getStakeUpdateAtIndex(i, defaultOperatorId, 0);
                emit log_named_uint("length  of paddedStakesForQuorum", paddedStakesForQuorum.length);
                assertEq(stakeUpdate.stake, paddedStakesForQuorum[quorumNumberIndex]);
                assertEq(stakeUpdate.updateBlockNumber, uint32(block.number));
                assertEq(stakeUpdate.nextUpdateBlockNumber, 0);

                // make the analogous check for total stake history
                assertEq(stakeRegistry.getTotalStakeHistoryLength(i), 1);
                // make sure that the stake update is as expected
                stakeUpdate = stakeRegistry.getTotalStakeUpdateAtIndex(i, 0);
                assertEq(stakeUpdate.stake, paddedStakesForQuorum[quorumNumberIndex]);
                assertEq(stakeUpdate.updateBlockNumber, uint32(block.number));
                assertEq(stakeUpdate.nextUpdateBlockNumber, 0);

                quorumNumberIndex++;
            } else {
                // check that the operator has 0 stake updates in the quorum numbers they did not register for
                assertEq(stakeRegistry.getStakeHistoryLength(defaultOperatorId, i), 0);
                // make the analogous check for total stake history
                assertEq(stakeRegistry.getTotalStakeHistoryLength(i), 1);
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

            uint96 cumulativeStake = 0;
            // for each operator
            for (uint256 j = 0; j < quorumBitmaps.length; j++) {
                // if the operator is in the quorum
                if (quorumBitmaps[j] >> i & 1 == 1) {
                    cumulativeStake += paddedStakesForQuorums[j][operatorQuorumIndices[j]];

                    operatorQuorumIndices[j]++;
                    operatorCount++;
                }
                cumulativeBlockNumber += blocksPassed[j];
            }

            uint historyLength = stakeRegistry.getTotalStakeHistoryLength(i);

            // If we don't have stake history, it should be because there is no stake
            if (historyLength == 0) {
                assertEq(cumulativeStake, 0);
                continue;
            }

            // make sure that the stake update is as expected
            IStakeRegistry.StakeUpdate memory totalStakeUpdate =
                stakeRegistry.getTotalStakeUpdateAtIndex(i, historyLength-1);

            assertEq(totalStakeUpdate.stake, cumulativeStake);
            // make sure that the next update block number of the previous stake update is as expected
            if (historyLength >= 2) {
                IStakeRegistry.StakeUpdate memory prevTotalStakeUpdate =
                    stakeRegistry.getTotalStakeUpdateAtIndex(i, historyLength-2);
                assertEq(prevTotalStakeUpdate.nextUpdateBlockNumber, cumulativeBlockNumber);
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

    function _initializeQuorum(
        uint8 quorumNumber, 
        uint96 minimumStake, 
        IStakeRegistry.StrategyParams[] memory strategyParams
    ) internal {
        cheats.prank(address(registryCoordinator));

        stakeRegistry.initializeQuorum(quorumNumber, minimumStake, strategyParams);
        initializedQuorums[quorumNumber] = true;
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

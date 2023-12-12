// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {PauserRegistry} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IEigenPodManager} from "eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {ISlasher} from "eigenlayer-contracts/src/contracts/interfaces/ISlasher.sol";
<<<<<<< HEAD
<<<<<<< HEAD
import {IServiceManager} from "../../src/interfaces/IServiceManager.sol";
import {IVoteWeigher} from "../../src/interfaces/IVoteWeigher.sol";
import {StakeRegistry} from "../../src/StakeRegistry.sol";
=======
import {IServiceManager} from "src/interfaces/IServiceManager.sol";
=======
>>>>>>> ecf7849 (chore: remove ServiceManagerBase and add RegistryCoordinator owner (#98))
import {IStakeRegistry} from "src/interfaces/IStakeRegistry.sol";
import {StakeRegistry} from "src/StakeRegistry.sol";
>>>>>>> 12b09de (fix: fix compilation issues and tests)

import {RegistryCoordinatorMock} from "../mocks/RegistryCoordinatorMock.sol";
import {OwnableMock} from "eigenlayer-contracts/src/test/mocks/OwnableMock.sol";
import {DelegationManagerMock} from "eigenlayer-contracts/src/test/mocks/DelegationManagerMock.sol";

import "forge-std/Test.sol";

contract VoteWeigherBaseUnitTests is Test {
    Vm cheats = Vm(HEVM_ADDRESS);

    ProxyAdmin public proxyAdmin;
    PauserRegistry public pauserRegistry;

    address public registryCoordinatorOwner = address(uint160(uint256(keccak256("registryCoordinatorOwner"))));

    DelegationManagerMock delegationMock;
    RegistryCoordinatorMock registryCoordinatorMock;

    StakeRegistry public voteWeigher;

    StakeRegistry public voteWeigherImplementation;

    address public pauser = address(555);
    address public unpauser = address(999);

    uint256 initialSupply = 1e36;
    address initialOwner = address(this);

    /// @notice emitted when a new quorum is created
    event QuorumCreated(uint8 indexed quorumNumber);
    /// @notice emitted when `strategy` has been added to the array at `strategiesConsideredAndMultipliers[quorumNumber]`
    event StrategyAddedToQuorum(uint8 indexed quorumNumber, IStrategy strategy);
    /// @notice emitted when `strategy` has removed from the array at `strategiesConsideredAndMultipliers[quorumNumber]`
    event StrategyRemovedFromQuorum(uint8 indexed quorumNumber, IStrategy strategy);
    /// @notice emitted when `strategy` has its `multiplier` updated in the array at `strategiesConsideredAndMultipliers[quorumNumber]`
    event StrategyMultiplierUpdated(uint8 indexed quorumNumber, IStrategy strategy, uint256 multiplier);

    // addresses excluded from fuzzing due to abnormal behavior. TODO: @Sidu28 define this better and give it a clearer name
    mapping (address => bool) fuzzedAddressMapping;
    // strategy => is in current array. used for detecting duplicates
    mapping (IStrategy => bool) strategyInCurrentArray;
    // uint256 => is in current array
    mapping (uint256 => bool) uint256InCurrentArray;

    //ensures that a passed in address is not set to true in the fuzzedAddressMapping
    modifier fuzzedAddress(address addr) virtual {
        cheats.assume(fuzzedAddressMapping[addr] == false);
        _;
    }

    function setUp() virtual public {
        proxyAdmin = new ProxyAdmin();

        address[] memory pausers = new address[](1);
        pausers[0] = pauser;
        pauserRegistry = new PauserRegistry(pausers, unpauser);

        cheats.prank(registryCoordinatorOwner);
        registryCoordinatorMock = new RegistryCoordinatorMock();

        delegationMock = new DelegationManagerMock();

        voteWeigherImplementation = new StakeRegistry(registryCoordinatorMock, delegationMock);

        voteWeigher = StakeRegistry(address(new TransparentUpgradeableProxy(address(voteWeigherImplementation), address(proxyAdmin), "")));

        fuzzedAddressMapping[address(proxyAdmin)] = true;
    }

    function testCorrectConstructionParameters() public {
        assertEq(address(voteWeigherImplementation.registryCoordinator()), address(registryCoordinatorMock));
        assertEq(address(voteWeigherImplementation.delegation()), address(delegationMock));
    }

    /// TODO - migrate tests to registry coordinator
    // function testCreateQuorum_Valid(IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers) public {
    //     strategiesAndWeightingMultipliers = _convertToValidStrategiesAndWeightingMultipliers(strategiesAndWeightingMultipliers);
    //     // create a quorum from the serviceManagerOwner
    //     // get the quorum count before the quorum is created
    //     uint8 quorumCountBefore = uint8(voteWeigher.quorumCount());
    //     cheats.prank(serviceManagerOwner);
    //     // expect each strategy to be added to the quorum
    //     for (uint i = 0; i < strategiesAndWeightingMultipliers.length; i++) {
    //         cheats.expectEmit(true, true, true, true, address(voteWeigher));
    //         emit StrategyAddedToQuorum(quorumCountBefore, strategiesAndWeightingMultipliers[i].strategy);
    //     }
    //     // created quorum will have quorum number of the count before it was created
    //     cheats.expectEmit(true, true, true, true, address(voteWeigher));
    //     emit QuorumCreated(quorumCountBefore);
    //     voteWeigher.createQuorum(strategiesAndWeightingMultipliers);
        
    //     assertEq(voteWeigher.quorumCount(), quorumCountBefore + 1);
    //     // check that all of the weights are correct
    //     for (uint i = 0; i < strategiesAndWeightingMultipliers.length; i++) {
    //         IStakeRegistry.StrategyParams memory strategyAndWeightingMultiplier = voteWeigher.strategyAndWeightingMultiplierForQuorumByIndex(quorumCountBefore, i);
    //         assertEq(address(strategyAndWeightingMultiplier.strategy), address(strategiesAndWeightingMultipliers[i].strategy));
    //         assertEq(strategyAndWeightingMultiplier.multiplier, strategiesAndWeightingMultipliers[i].multiplier);
    //     }
    // }

    // function testCreateQuorum_FromNotServiceManagerOwner_Reverts(
    //     address notServiceManagerOwner,
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers
    // ) public fuzzedAddress(notServiceManagerOwner) {
    //     cheats.assume(notServiceManagerOwner != serviceManagerOwner);
    //     cheats.prank(notServiceManagerOwner);
    //     cheats.expectRevert("VoteWeigherBase.onlyServiceManagerOwner: caller is not the owner of the serviceManager");
    //     voteWeigher.createQuorum(strategiesAndWeightingMultipliers);
    // }

    // function testCreateQuorum_StrategiesAndWeightingMultipliers_LengthGreaterThanMaxAllowed_Reverts(
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers
    // ) public {
    //     strategiesAndWeightingMultipliers = _removeDuplicates(strategiesAndWeightingMultipliers);
    //     strategiesAndWeightingMultipliers = _replaceZeroWeights(strategiesAndWeightingMultipliers);

    //     cheats.assume(strategiesAndWeightingMultipliers.length > voteWeigher.MAX_WEIGHING_FUNCTION_LENGTH());
    //     cheats.prank(serviceManagerOwner);
    //     cheats.expectRevert("VoteWeigherBase._addStrategiesConsideredAndMultipliers: exceed MAX_WEIGHING_FUNCTION_LENGTH");
    //     voteWeigher.createQuorum(strategiesAndWeightingMultipliers);
    // }

    // function testCreateQuorum_StrategiesAndWeightingMultipliers_WithDuplicateStrategies_Reverts(
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers,
    //     uint256 indexFromDuplicate,
    //     uint256 indexToDuplicate
    // ) public {
    //     cheats.assume(strategiesAndWeightingMultipliers.length <= voteWeigher.MAX_WEIGHING_FUNCTION_LENGTH());
    //     cheats.assume(strategiesAndWeightingMultipliers.length > 1);
    //     strategiesAndWeightingMultipliers = _replaceZeroWeights(strategiesAndWeightingMultipliers);

    //     // plant a duplicate strategy
    //     indexToDuplicate = indexToDuplicate % strategiesAndWeightingMultipliers.length;
    //     indexFromDuplicate = indexFromDuplicate % strategiesAndWeightingMultipliers.length;
    //     cheats.assume(indexToDuplicate != indexFromDuplicate);
    //     strategiesAndWeightingMultipliers[indexToDuplicate].strategy = strategiesAndWeightingMultipliers[indexFromDuplicate].strategy;

    //     cheats.prank(serviceManagerOwner);
    //     cheats.expectRevert("VoteWeigherBase._addStrategiesConsideredAndMultipliers: cannot add same strategy 2x");
    //     voteWeigher.createQuorum(strategiesAndWeightingMultipliers);
    // }

    // function testCreateQuorum_EmptyStrategiesAndWeightingMultipliers_Reverts() public {
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers;
    //     cheats.prank(serviceManagerOwner);
    //     cheats.expectRevert("VoteWeigherBase._addStrategiesConsideredAndMultipliers: no strategies provided");
    //     voteWeigher.createQuorum(strategiesAndWeightingMultipliers);
    // }

    // function testCreateQuorum_StrategiesAndWeightingMultipliers_WithZeroWeight(
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers,
    //     uint256 indexForZeroMultiplier
    // ) public {
    //     strategiesAndWeightingMultipliers = _removeDuplicates(strategiesAndWeightingMultipliers);
    //     cheats.assume(strategiesAndWeightingMultipliers.length <= voteWeigher.MAX_WEIGHING_FUNCTION_LENGTH());
    //     cheats.assume(strategiesAndWeightingMultipliers.length > 0);
    //     //plant a zero weight
    //     strategiesAndWeightingMultipliers[indexForZeroMultiplier % strategiesAndWeightingMultipliers.length].multiplier = 0;

    //     cheats.prank(serviceManagerOwner);
    //     cheats.expectRevert("VoteWeigherBase._addStrategiesConsideredAndMultipliers: cannot add strategy with zero weight");
    //     voteWeigher.createQuorum(strategiesAndWeightingMultipliers);
    // }

    // function testCreateQuorum_MoreThanMaxQuorums_Reverts() public {
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers = _defaultStrategiesAndWeightingMultipliers();
    //     uint256 maxQuorums = voteWeigher.MAX_QUORUM_COUNT();
            
    //     cheats.startPrank(serviceManagerOwner);
    //     for (uint i = 0; i < maxQuorums; i++) {
    //         voteWeigher.createQuorum(strategiesAndWeightingMultipliers);
    //     }
    //     assertEq(voteWeigher.quorumCount(), maxQuorums);

    //     cheats.expectRevert("VoteWeigherBase._createQuorum: number of quorums cannot exceed MAX_QUORUM_COUNT");
    //     voteWeigher.createQuorum(strategiesAndWeightingMultipliers); 
    // }

    // function testAddStrategiesConsideredAndMultipliers_Valid(
    //     uint256 randomSplit,
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers
    // ) public {
    //     strategiesAndWeightingMultipliers = _convertToValidStrategiesAndWeightingMultipliers(strategiesAndWeightingMultipliers);
    //     // make sure there is at least 2 strategies
    //     cheats.assume(strategiesAndWeightingMultipliers.length > 1);
    //     // we need at least 1 strategy in each side of the split
    //     randomSplit = randomSplit % (strategiesAndWeightingMultipliers.length - 1) + 1;
    //     // create 2 arrays, 1 with the first randomSplit elements and 1 with the rest
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers1 = new IStakeRegistry.StrategyParams[](randomSplit);
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers2 = new IStakeRegistry.StrategyParams[](strategiesAndWeightingMultipliers.length - randomSplit);
    //     for (uint256 i = 0; i < strategiesAndWeightingMultipliers.length; i++) {
    //         if (i < randomSplit) {
    //             strategiesAndWeightingMultipliers1[i] = strategiesAndWeightingMultipliers[i];
    //         } else {
    //             strategiesAndWeightingMultipliers2[i - randomSplit] = strategiesAndWeightingMultipliers[i];
    //         }
    //     }
    //     uint8 quorumNumber = uint8(voteWeigher.quorumCount());
    //     // create quorum with the first randomSplit elements
    //     cheats.startPrank(serviceManagerOwner);
    //     voteWeigher.createQuorum(strategiesAndWeightingMultipliers1);

    //     // add the rest of the strategies
    //     for (uint i = 0; i < strategiesAndWeightingMultipliers2.length; i++) {
    //         cheats.expectEmit(true, true, true, true, address(voteWeigher));
    //         emit StrategyAddedToQuorum(quorumNumber, strategiesAndWeightingMultipliers2[i].strategy);
    //     }
    //     voteWeigher.addStrategiesConsideredAndMultipliers(quorumNumber, strategiesAndWeightingMultipliers2);

    //     // check that the quorum was created and strategies were added correctly
    //     for (uint i = 0; i < strategiesAndWeightingMultipliers.length; i++) {
    //         IStakeRegistry.StrategyParams memory strategyAndWeightingMultiplier = voteWeigher.strategyAndWeightingMultiplierForQuorumByIndex(quorumNumber, i);
    //         assertEq(address(strategyAndWeightingMultiplier.strategy), address(strategiesAndWeightingMultipliers[i].strategy));
    //         assertEq(strategyAndWeightingMultiplier.multiplier, strategiesAndWeightingMultipliers[i].multiplier);
    //     }
    // }

    // function testAddStrategiesConsideredAndMultipliers_NotFromServiceManagerOwner_Reverts(
    //     address notServiceManagerOwner
    // ) public fuzzedAddress(notServiceManagerOwner) {
    //     cheats.assume(notServiceManagerOwner != serviceManagerOwner);
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers = _defaultStrategiesAndWeightingMultipliers();

    //     // create quorum with all but the last element
    //     uint8 quorumNumber = uint8(voteWeigher.quorumCount());
    //     cheats.prank(serviceManagerOwner);
    //     voteWeigher.createQuorum(strategiesAndWeightingMultipliers);

    //     // add the last element
    //     cheats.prank(notServiceManagerOwner);
    //     cheats.expectRevert("VoteWeigherBase.onlyServiceManagerOwner: caller is not the owner of the serviceManager");
    //     voteWeigher.addStrategiesConsideredAndMultipliers(quorumNumber, strategiesAndWeightingMultipliers);
    // }

    // function testAddStrategiesConsideredAndMultipliers_ForNonexistentQuorum_Reverts() public {
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers = _defaultStrategiesAndWeightingMultipliers();

    //     // create quorum with all but the last element
    //     uint8 quorumNumber = uint8(voteWeigher.quorumCount());
    //     cheats.startPrank(serviceManagerOwner);
    //     voteWeigher.createQuorum(strategiesAndWeightingMultipliers);

    //     // add the last element
    //     cheats.expectRevert("VoteWeigherBase.validQuorumNumber: quorumNumber is not valid");
    //     voteWeigher.addStrategiesConsideredAndMultipliers(quorumNumber+1, strategiesAndWeightingMultipliers);        
    // }

    // // this test generates a psudorandom descending order array of indices to remove
    // // removes them, and checks that the strategies were removed correctly by computing
    // // a local copy of the strategies when the removal algorithm is applied and comparing
    // function testRemoveStrategiesConsideredAndMultipliers_Valid(
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers,
    //     uint256 randomness
    // ) public {
    //     strategiesAndWeightingMultipliers = _convertToValidStrategiesAndWeightingMultipliers(strategiesAndWeightingMultipliers);
    //     // generate a bunch of random array of valid descending order indices
    //     uint256[] memory indicesToRemove = _generateRandomUniqueIndices(randomness, strategiesAndWeightingMultipliers.length);

    //     // create the quorum
    //     uint8 quorumNumber = uint8(voteWeigher.quorumCount());
    //     cheats.startPrank(serviceManagerOwner);
    //     voteWeigher.createQuorum(strategiesAndWeightingMultipliers);

    //     // remove certain strategies
    //     // make sure events are emmitted
    //     for (uint i = 0; i < indicesToRemove.length; i++) {
    //         cheats.expectEmit(true, true, true, true, address(voteWeigher));
    //         emit StrategyRemovedFromQuorum(quorumNumber, strategiesAndWeightingMultipliers[indicesToRemove[i]].strategy);
    //     }
    //     voteWeigher.removeStrategiesConsideredAndMultipliers(quorumNumber, indicesToRemove);
        
    //     // check that the strategies that were not removed are still there
    //     // get all strategies and multipliers form the contracts
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliersFromContract = new IStakeRegistry.StrategyParams[](voteWeigher.strategiesConsideredAndMultipliersLength(quorumNumber));
    //     for (uint256 i = 0; i < strategiesAndWeightingMultipliersFromContract.length; i++) {
    //         strategiesAndWeightingMultipliersFromContract[i] = voteWeigher.strategyAndWeightingMultiplierForQuorumByIndex(quorumNumber, i);
    //     }

    //     // remove indicesToRemove from local strategiesAndWeightingMultipliers
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliersLocal = new IStakeRegistry.StrategyParams[](strategiesAndWeightingMultipliers.length - indicesToRemove.length);
        
    //     // run the removal algorithm locally
    //     uint256 endIndex = strategiesAndWeightingMultipliers.length - 1;
    //     for (uint256 i = 0; i < indicesToRemove.length; i++) {
    //         strategiesAndWeightingMultipliers[indicesToRemove[i]] = strategiesAndWeightingMultipliers[endIndex];
    //         if (endIndex > 0) {
    //             endIndex--;
    //         }
    //     }
    //     for (uint256 i = 0; i < strategiesAndWeightingMultipliersLocal.length; i++) {
    //         strategiesAndWeightingMultipliersLocal[i] = strategiesAndWeightingMultipliers[i];
    //     }

    //     // check that the arrays are the same
    //     assertEq(strategiesAndWeightingMultipliersFromContract.length, strategiesAndWeightingMultipliersLocal.length);
    //     for (uint256 i = 0; i < strategiesAndWeightingMultipliersFromContract.length; i++) {
    //         assertEq(address(strategiesAndWeightingMultipliersFromContract[i].strategy), address(strategiesAndWeightingMultipliersLocal[i].strategy));
    //         assertEq(strategiesAndWeightingMultipliersFromContract[i].multiplier, strategiesAndWeightingMultipliersLocal[i].multiplier);
    //     }

    // }

    // function testRemoveStrategiesConsideredAndMultipliers_NotFromServiceManagerOwner_Reverts(
    //     address notServiceManagerOwner
    // ) public fuzzedAddress(notServiceManagerOwner) {
    //     cheats.assume(notServiceManagerOwner != serviceManagerOwner);
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers = _defaultStrategiesAndWeightingMultipliers();

    //     uint256[] memory indicesToRemove = new uint256[](1);

    //     // create a valid quorum
    //     uint8 quorumNumber = uint8(voteWeigher.quorumCount());
    //     cheats.prank(serviceManagerOwner);
    //     voteWeigher.createQuorum(strategiesAndWeightingMultipliers);

    //     // remove certain strategies
    //     cheats.prank(notServiceManagerOwner);
    //     cheats.expectRevert("VoteWeigherBase.onlyServiceManagerOwner: caller is not the owner of the serviceManager");
    //     voteWeigher.removeStrategiesConsideredAndMultipliers(quorumNumber, indicesToRemove);
    // }

    // function testRemoveStrategiesConsideredAndMultipliers_ForNonexistentQuorum_Reverts() public {
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers = _defaultStrategiesAndWeightingMultipliers();

    //     uint256[] memory indicesToRemove = new uint256[](1);

    //     // create a valid quorum
    //     uint8 quorumNumber = uint8(voteWeigher.quorumCount());
    //     cheats.startPrank(serviceManagerOwner);
    //     voteWeigher.createQuorum(strategiesAndWeightingMultipliers);

    //     // remove strategies from a non-existent quorum
    //     cheats.expectRevert("VoteWeigherBase.validQuorumNumber: quorumNumber is not valid");
    //     voteWeigher.removeStrategiesConsideredAndMultipliers(quorumNumber + 1, indicesToRemove);
    // }

    // function testRemoveStrategiesConsideredAndMultipliers_EmptyIndicesToRemove_Reverts() public {
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers = _defaultStrategiesAndWeightingMultipliers();

    //     // create a valid quorum
    //     uint8 quorumNumber = uint8(voteWeigher.quorumCount());
    //     cheats.startPrank(serviceManagerOwner);
    //     voteWeigher.createQuorum(strategiesAndWeightingMultipliers);

    //     // remove no strategies
    //     cheats.expectRevert("VoteWeigherBase.removeStrategiesConsideredAndMultipliers: no indices to remove provided");
    //     voteWeigher.removeStrategiesConsideredAndMultipliers(quorumNumber, new uint256[](0));
    // }

    // function testModifyStrategyWeights_NotFromServiceManagerOwner_Reverts(
    //     address notServiceManagerOwner
    // ) public fuzzedAddress(notServiceManagerOwner) {
    //     cheats.assume(notServiceManagerOwner != serviceManagerOwner);
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers = _defaultStrategiesAndWeightingMultipliers();

    //     uint256[] memory strategyIndices = new uint256[](1);
    //     uint96[] memory newWeights = new uint96[](1);

    //     // create a valid quorum
    //     uint8 quorumNumber = uint8(voteWeigher.quorumCount());
    //     cheats.prank(serviceManagerOwner);
    //     voteWeigher.createQuorum(strategiesAndWeightingMultipliers);

    //     // modify certain strategies
    //     cheats.prank(notServiceManagerOwner);
    //     cheats.expectRevert("VoteWeigherBase.onlyServiceManagerOwner: caller is not the owner of the serviceManager");
    //     voteWeigher.modifyStrategyWeights(quorumNumber, strategyIndices, newWeights);
    // }

    // function testModifyStrategyWeights_Valid(
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers,
    //     uint96[] memory newWeights,
    //     uint256 randomness
    // ) public {
    //     strategiesAndWeightingMultipliers = _convertToValidStrategiesAndWeightingMultipliers(strategiesAndWeightingMultipliers);
    //     uint256[] memory strategyIndices = _generateRandomUniqueIndices(randomness, strategiesAndWeightingMultipliers.length);

    //     // trim the provided weights to the length of the strategyIndices and extend if it is shorter
    //     uint96[] memory newWeightsTrim = new uint96[](strategyIndices.length);
    //     for (uint256 i = 0; i < strategyIndices.length; i++) {
    //         if(i < newWeights.length) {
    //             newWeightsTrim[i] = newWeights[i];
    //         } else {
    //             newWeightsTrim[i] = strategiesAndWeightingMultipliers[strategyIndices[i]].multiplier - 1;
    //         }
    //     }
    //     newWeights = newWeightsTrim;

    //     // create a valid quorum
    //     uint8 quorumNumber = uint8(voteWeigher.quorumCount());
    //     cheats.startPrank(serviceManagerOwner);
    //     voteWeigher.createQuorum(strategiesAndWeightingMultipliers);

    //     // modify certain strategies
    //     for (uint i = 0; i < strategyIndices.length; i++) {
    //         cheats.expectEmit(true, true, true, true, address(voteWeigher));
    //         emit StrategyMultiplierUpdated(quorumNumber, strategiesAndWeightingMultipliers[strategyIndices[i]].strategy, newWeights[i]);
    //     }
    //     voteWeigher.modifyStrategyWeights(quorumNumber, strategyIndices, newWeights);

    //     // convert the strategies and weighting multipliers to the modified
    //     for (uint i = 0; i < strategyIndices.length; i++) {
    //         strategiesAndWeightingMultipliers[strategyIndices[i]].multiplier = newWeights[i];
    //     }
    //     // make sure the quorum strategies and weights have changed
    //     for (uint i = 0; i < strategiesAndWeightingMultipliers.length; i++) {
    //         IStakeRegistry.StrategyParams memory strategyAndWeightingMultiplier = voteWeigher.strategyAndWeightingMultiplierForQuorumByIndex(quorumNumber, i);
    //         assertEq(address(strategyAndWeightingMultiplier.strategy), address(strategiesAndWeightingMultipliers[i].strategy));
    //         assertEq(strategyAndWeightingMultiplier.multiplier, strategiesAndWeightingMultipliers[i].multiplier);
    //     }
    // }

    // function testModifyStrategyWeights_ForNonexistentQuorum_Reverts() public {
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers = _defaultStrategiesAndWeightingMultipliers();

    //     uint256[] memory strategyIndices = new uint256[](1);
    //     uint96[] memory newWeights = new uint96[](1);

    //     // create a valid quorum
    //     uint8 quorumNumber = uint8(voteWeigher.quorumCount());
    //     cheats.startPrank(serviceManagerOwner);
    //     voteWeigher.createQuorum(strategiesAndWeightingMultipliers);

    //     // modify certain strategies of a non-existent quorum
    //     cheats.expectRevert("VoteWeigherBase.validQuorumNumber: quorumNumber is not valid");
    //     voteWeigher.modifyStrategyWeights(quorumNumber + 1, strategyIndices, newWeights);
    // }

    // function testModifyStrategyWeights_InconsistentStrategyAndWeightArrayLengths_Reverts(
    //     uint256[] memory strategyIndices,
    //     uint96[] memory newWeights
    // ) public {
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers = _defaultStrategiesAndWeightingMultipliers();

    //     // make sure the arrays are of different lengths
    //     cheats.assume(strategyIndices.length != newWeights.length);
    //     cheats.assume(strategyIndices.length > 0);

    //     // create a valid quorum
    //     uint8 quorumNumber = uint8(voteWeigher.quorumCount());
    //     cheats.startPrank(serviceManagerOwner);
    //     voteWeigher.createQuorum(strategiesAndWeightingMultipliers);

    //     // modify certain strategies
    //     cheats.expectRevert("VoteWeigherBase.modifyStrategyWeights: input length mismatch");
    //     voteWeigher.modifyStrategyWeights(quorumNumber, strategyIndices, newWeights);
    // }

    // function testModifyStrategyWeights_EmptyStrategyIndicesAndWeights_Reverts() public {
    //     IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers = _defaultStrategiesAndWeightingMultipliers();

    //     // create a valid quorum
    //     uint8 quorumNumber = uint8(voteWeigher.quorumCount());
    //     cheats.startPrank(serviceManagerOwner);
    //     voteWeigher.createQuorum(strategiesAndWeightingMultipliers);

    //     // modify no strategies
    //     cheats.expectRevert("VoteWeigherBase.modifyStrategyWeights: no strategy indices provided");
    //     voteWeigher.modifyStrategyWeights(quorumNumber, new uint256[](0), new uint96[](0));
    // }

    // function testWeightOfOperatorForQuorum(
    //     address operator,
    //     IStakeRegistry.StrategyParams[] memory strategiesAndMultipliers,
    //     uint96[] memory shares
    // ) public {
    //     strategiesAndMultipliers = _convertToValidStrategiesAndWeightingMultipliers(strategiesAndMultipliers);
    //     cheats.assume(shares.length >= strategiesAndMultipliers.length);
    //     for (uint i = 0; i < strategiesAndMultipliers.length; i++) {
    //         if(uint256(shares[i]) * uint256(strategiesAndMultipliers[i].multiplier) > type(uint96).max) {
    //             strategiesAndMultipliers[i].multiplier = 1;
    //         }
    //     }

    //     // set the operator shares
    //     for (uint i = 0; i < strategiesAndMultipliers.length; i++) {
    //         delegationMock.setOperatorShares(operator, strategiesAndMultipliers[i].strategy, shares[i]);
    //     }

    //     // create a valid quorum
    //     uint8 quorumNumber = uint8(voteWeigher.quorumCount());
    //     cheats.startPrank(serviceManagerOwner);
    //     voteWeigher.createQuorum(strategiesAndMultipliers);

    //     // make sure the weight of the operator is correct
    //     uint256 expectedWeight = 0;
    //     for (uint i = 0; i < strategiesAndMultipliers.length; i++) {
    //         expectedWeight += shares[i] * strategiesAndMultipliers[i].multiplier / voteWeigher.WEIGHTING_DIVISOR();
    //     }

    //     assertEq(voteWeigher.weightOfOperatorForQuorum(quorumNumber, operator), expectedWeight);
    // }

    function _removeDuplicates(IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers) 
        internal 
        returns(IStakeRegistry.StrategyParams[] memory)
    {
        IStakeRegistry.StrategyParams[] memory deduplicatedStrategiesAndWeightingMultipliers = new IStakeRegistry.StrategyParams[](strategiesAndWeightingMultipliers.length);
        uint256 numUniqueStrategies = 0;
        // check for duplicates
        for (uint i = 0; i < strategiesAndWeightingMultipliers.length; i++) {
            if(strategyInCurrentArray[strategiesAndWeightingMultipliers[i].strategy]) {
                continue;
            }
            strategyInCurrentArray[strategiesAndWeightingMultipliers[i].strategy] = true;
            deduplicatedStrategiesAndWeightingMultipliers[numUniqueStrategies] = strategiesAndWeightingMultipliers[i];
            numUniqueStrategies++;
        }

        // undo storage changes
        for (uint i = 0; i < strategiesAndWeightingMultipliers.length; i++) {
            strategyInCurrentArray[strategiesAndWeightingMultipliers[i].strategy] = false;
        }

        IStakeRegistry.StrategyParams[] memory trimmedStrategiesAndWeightingMultipliers = new IStakeRegistry.StrategyParams[](numUniqueStrategies);
        for (uint i = 0; i < numUniqueStrategies; i++) {
            trimmedStrategiesAndWeightingMultipliers[i] = deduplicatedStrategiesAndWeightingMultipliers[i];
        }
        return trimmedStrategiesAndWeightingMultipliers;
    }

    function _replaceZeroWeights(IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers) internal pure returns(IStakeRegistry.StrategyParams[] memory) {
        for (uint256 i = 0; i < strategiesAndWeightingMultipliers.length; i++) {
            if (strategiesAndWeightingMultipliers[i].multiplier == 0) {
                strategiesAndWeightingMultipliers[i].multiplier = 1;
            }
        }
        return strategiesAndWeightingMultipliers;
    }

    function _generateRandomUniqueIndices(uint256 randomness, uint256 length) internal pure returns(uint256[] memory) {
        uint256[] memory indices = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            indices[i] = length - i - 1;
        }

        uint256[] memory randomIndices = new uint256[](length);
        uint256 numRandomIndices = 0;
        // take random indices in ascending order
        for (uint256 i = 0; i < length; i++) {
            if (uint256(keccak256(abi.encode(randomness, i))) % length < 10) {
                randomIndices[numRandomIndices] = indices[i];
                numRandomIndices++;
            }
        }

        // trim the array
        uint256[] memory trimmedRandomIndices = new uint256[](numRandomIndices);
        for (uint256 i = 0; i < numRandomIndices; i++) {
            trimmedRandomIndices[i] = randomIndices[i];
        }
        
        return trimmedRandomIndices;
    }

    function _convertToValidStrategiesAndWeightingMultipliers(IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers) internal returns (IStakeRegistry.StrategyParams[] memory) {
        strategiesAndWeightingMultipliers = _removeDuplicates(strategiesAndWeightingMultipliers);
        cheats.assume(strategiesAndWeightingMultipliers.length <= voteWeigher.MAX_WEIGHING_FUNCTION_LENGTH());
        cheats.assume(strategiesAndWeightingMultipliers.length > 0);
        return _replaceZeroWeights(strategiesAndWeightingMultipliers);
    }

    function _defaultStrategiesAndWeightingMultipliers() internal pure returns (IStakeRegistry.StrategyParams[] memory) {
        IStakeRegistry.StrategyParams[] memory strategiesAndWeightingMultipliers = new IStakeRegistry.StrategyParams[](2);
        strategiesAndWeightingMultipliers[0] = IStakeRegistry.StrategyParams({
            strategy: IStrategy(address(uint160(uint256(keccak256("strategy1"))))),
            multiplier: 1.04 ether
        });
        strategiesAndWeightingMultipliers[1] = IStakeRegistry.StrategyParams({
            strategy: IStrategy(address(uint160(uint256(keccak256("strategy2"))))),
            multiplier: 1.69 ether
        });
        return strategiesAndWeightingMultipliers;
    }
}

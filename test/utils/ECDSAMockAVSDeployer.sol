// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Slasher} from "eigenlayer-contracts/src/contracts/core/Slasher.sol";
import {ISlasher} from "eigenlayer-contracts/src/contracts/interfaces/ISlasher.sol";
import {PauserRegistry} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {BitmapUtils} from "../../src/libraries/BitmapUtils.sol";

import {OperatorStateRetriever} from "../../src/OperatorStateRetriever.sol";
import {ECDSAServiceManagerMock} from "../mocks/ECDSAServiceManagerMock.sol";
import {ECDSAStakeRegistry} from "../../src/unaudited/ECDSAStakeRegistry.sol";
import {Quorum, StrategyParams} from "../../src/interfaces/IECDSAStakeRegistryEventsAndErrors.sol";
import {IStakeRegistry} from "../../src/interfaces/IStakeRegistry.sol";
import {IServiceManager} from "../../src/interfaces/IServiceManager.sol";

import {StrategyManagerMock} from "eigenlayer-contracts/src/test/mocks/StrategyManagerMock.sol";
import {EigenPodManagerMock} from "eigenlayer-contracts/src/test/mocks/EigenPodManagerMock.sol";
import {AVSDirectoryMock} from "../mocks/AVSDirectoryMock.sol";
import {DelegationMock} from "../mocks/DelegationMock.sol";
import {AVSDirectory} from "eigenlayer-contracts/src/contracts/core/AVSDirectory.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";

import {RewardsCoordinatorMock} from "../mocks/RewardsCoordinatorMock.sol";
import {RewardsCoordinator} from "eigenlayer-contracts/src/contracts/core/RewardsCoordinator.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";

import {EmptyContract} from "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";

import {ECDSAStakeRegistryHarness} from "../harnesses/ECDSAStakeRegistryHarness.sol";

import "forge-std/Test.sol";

contract MockECDSAAVSDeployer is Test {
    Vm cheats = Vm(VM_ADDRESS);

    ProxyAdmin public proxyAdmin;
    PauserRegistry public pauserRegistry;

    ISlasher public slasher = ISlasher(address(uint160(uint256(keccak256("slasher")))));
    Slasher public slasherImplementation;

    EmptyContract public emptyContract;

    ECDSAStakeRegistryHarness public stakeRegistryImplementation;
    ECDSAServiceManagerMock public serviceManagerImplementation;

    OperatorStateRetriever public operatorStateRetriever;
    ECDSAStakeRegistryHarness public stakeRegistry;
    ECDSAServiceManagerMock public serviceManager;

    StrategyManagerMock public strategyManagerMock;
    DelegationMock public delegationMock;
    EigenPodManagerMock public eigenPodManagerMock;
    AVSDirectory public avsDirectory;
    AVSDirectory public avsDirectoryImplementation;
    AVSDirectoryMock public avsDirectoryMock;
    RewardsCoordinator public rewardsCoordinator;
    RewardsCoordinator public rewardsCoordinatorImplementation;
    RewardsCoordinatorMock public rewardsCoordinatorMock;

    /// @notice StakeRegistry, Constant used as a divisor in calculating weights.
    uint256 public constant WEIGHTING_DIVISOR = 1e18;

    address public proxyAdminOwner = address(uint160(uint256(keccak256("proxyAdminOwner"))));
    address public registryCoordinatorOwner =
        address(uint160(uint256(keccak256("registryCoordinatorOwner"))));
    address public pauser = address(uint160(uint256(keccak256("pauser"))));
    address public unpauser = address(uint160(uint256(keccak256("unpauser"))));

    uint256 churnApproverPrivateKey = uint256(keccak256("churnApproverPrivateKey"));
    address churnApprover = cheats.addr(churnApproverPrivateKey);
    bytes32 defaultSalt = bytes32(uint256(keccak256("defaultSalt")));

    address ejector = address(uint160(uint256(keccak256("ejector"))));

    address defaultOperator = address(uint160(uint256(keccak256("defaultOperator"))));
    bytes32 defaultOperatorId;
    uint96 defaultStake = 1 ether;
    uint8 defaultQuorumNumber = 0;

    uint32 defaultMaxOperatorCount = 10;
    uint16 defaultKickBIPsOfOperatorStake = 15_000;
    uint16 defaultKickBIPsOfTotalStake = 150;
    uint8 numQuorums = 192;

    StrategyParams[] strategies;
    IStrategy strategy;

    uint8 maxQuorumsToRegisterFor = 4;
    uint256 maxOperatorsToRegister = 4;
    uint32 registrationBlockNumber = 100;
    uint32 blocksBetweenRegistrations = 10;

    struct OperatorMetadata {
        uint256 quorumBitmap;
        address operator;
        bytes32 operatorId;
        uint96[] stakes; // in every quorum for simplicity
    }

    uint256 MAX_QUORUM_BITMAP = type(uint192).max;

    function _deployMockEigenLayerAndAVS() internal {
        _deployMockEigenLayerAndAVS(numQuorums);
    }

    function _deployMockEigenLayerAndAVS(uint8 numQuorumsToAdd) internal {
        emptyContract = new EmptyContract();

        cheats.startPrank(proxyAdminOwner);
        proxyAdmin = new ProxyAdmin();

        address[] memory pausers = new address[](1);
        pausers[0] = pauser;
        pauserRegistry = new PauserRegistry(pausers, unpauser);

        delegationMock = new DelegationMock();
        avsDirectoryMock = new AVSDirectoryMock();
        eigenPodManagerMock = new EigenPodManagerMock();
        strategyManagerMock = new StrategyManagerMock();
        slasherImplementation = new Slasher(strategyManagerMock, delegationMock);
        slasher = Slasher(
            address(
                new TransparentUpgradeableProxy(
                    address(slasherImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        Slasher.initialize.selector,
                        msg.sender,
                        pauserRegistry,
                        0 /*initialPausedStatus*/
                    )
                )
            )
        );
        avsDirectoryMock = new AVSDirectoryMock();
        avsDirectoryImplementation = new AVSDirectory(delegationMock);
        avsDirectory = AVSDirectory(
            address(
                new TransparentUpgradeableProxy(
                    address(avsDirectoryImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        AVSDirectory.initialize.selector,
                        msg.sender,
                        pauserRegistry,
                        0 /*initialPausedStatus*/
                    )
                )
            )
        );
        rewardsCoordinatorMock = new RewardsCoordinatorMock();

        strategyManagerMock.setAddresses(delegationMock, eigenPodManagerMock, slasher);
        cheats.stopPrank();

        cheats.startPrank(registryCoordinatorOwner);
        stakeRegistry = ECDSAStakeRegistryHarness(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        serviceManager = ECDSAServiceManagerMock(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        cheats.stopPrank();

        cheats.startPrank(proxyAdminOwner);

        stakeRegistryImplementation =
            new ECDSAStakeRegistryHarness(delegationMock);

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(stakeRegistry))),
            address(stakeRegistryImplementation)
        );

        serviceManagerImplementation = new ECDSAServiceManagerMock(
            address(avsDirectoryMock),
            address(stakeRegistry),
            address(rewardsCoordinatorMock),
            address(delegationMock)
        );

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(serviceManager))),
            address(serviceManagerImplementation)
        );

        serviceManager.initialize({
            initialOwner: registryCoordinatorOwner
        });

        // setup the dummy minimum stake for quorum
        uint96[] memory minimumStakeForQuorum = new uint96[](numQuorumsToAdd);
        for (uint256 i = 0; i < minimumStakeForQuorum.length; i++) {
            minimumStakeForQuorum[i] = uint96(i + 1);
        }

        // setup the dummy quorum strategies
        strategies = new StrategyParams[](numQuorumsToAdd);
        for (uint256 i = 0; i < strategies.length; i++) {
            strategies[i] = StrategyParams(
                IStrategy(address(uint160(i))), uint96(WEIGHTING_DIVISOR)
            );
        }

        Quorum memory quorum = Quorum(
            strategies
        );

        proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(
                payable(address(stakeRegistry))
            ),
            address(stakeRegistryImplementation),
            abi.encodeWithSelector(
                ECDSAStakeRegistry.initialize.selector,
                address(serviceManager),
                1,
                quorum
            )
        );

        cheats.stopPrank();
    }

    /**
     * @notice registers operator with coordinator
     */
    function _registerOperatorWithCoordinator(
        address operator,
        uint256 quorumBitmap
    ) internal {
        _registerOperatorWithCoordinator(operator, quorumBitmap, defaultStake);
    }

    /**
     * @notice registers operator with coordinator
     */
    function _registerOperatorWithCoordinator(
        address operator,
        uint256 quorumBitmap,
        uint96 stake
    ) internal {
        // quorumBitmap can only have 192 least significant bits
        quorumBitmap &= MAX_QUORUM_BITMAP;

        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            _setOperatorWeight(operator, uint8(quorumNumbers[i]), stake);
        }

        ISignatureUtils.SignatureWithSaltAndExpiry memory emptySignatureAndExpiry;
        cheats.prank(operator);
        stakeRegistry.registerOperatorWithSignature(emptySignatureAndExpiry, operator);
    }

    /**
     * @notice registers operator with coordinator
     */
    function _registerOperatorWithCoordinator(
        address operator,
        uint256 quorumBitmap,
        uint96[] memory stakes
    ) internal {
        // quorumBitmap can only have 192 least significant bits
        quorumBitmap &= MAX_QUORUM_BITMAP;

        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            _setOperatorWeight(operator, uint8(quorumNumbers[i]), stakes[uint8(quorumNumbers[i])]);
        }

        ISignatureUtils.SignatureWithSaltAndExpiry memory emptySignatureAndExpiry;
        cheats.prank(operator);
        stakeRegistry.registerOperatorWithSignature(emptySignatureAndExpiry, operator);
    }

    function _registerRandomOperators(uint256 pseudoRandomNumber)
        internal
        returns (OperatorMetadata[] memory, uint256[][] memory)
    {
        OperatorMetadata[] memory operatorMetadatas = new OperatorMetadata[](maxOperatorsToRegister);
        for (uint256 i = 0; i < operatorMetadatas.length; i++) {
            // limit to 16 quorums so we don't run out of gas, make them all register for quorum 0 as well
            operatorMetadatas[i].quorumBitmap = uint256(
                keccak256(abi.encodePacked("quorumBitmap", pseudoRandomNumber, i))
            ) & (1 << maxQuorumsToRegisterFor - 1) | 1;
            operatorMetadatas[i].operator = _incrementAddress(defaultOperator, i);
            operatorMetadatas[i].operatorId = keccak256(abi.encodePacked("operatorId", pseudoRandomNumber, i));
            operatorMetadatas[i].stakes = new uint96[](maxQuorumsToRegisterFor);
            for (uint256 j = 0; j < maxQuorumsToRegisterFor; j++) {
                operatorMetadatas[i].stakes[j] = uint96(
                    uint64(uint256(keccak256(abi.encodePacked("stakes", pseudoRandomNumber, i, j))))
                );
            }
        }

        // get the index in quorumBitmaps of each operator in each quorum in the order they will register
        uint256[][] memory expectedOperatorOverallIndices = new uint256[][](numQuorums);
        for (uint256 i = 0; i < numQuorums; i++) {
            uint32 numOperatorsInQuorum;
            // for each quorumBitmap, check if the i'th bit is set
            for (uint256 j = 0; j < operatorMetadatas.length; j++) {
                if (operatorMetadatas[j].quorumBitmap >> i & 1 == 1) {
                    numOperatorsInQuorum++;
                }
            }
            expectedOperatorOverallIndices[i] = new uint256[](numOperatorsInQuorum);
            uint256 numOperatorCounter;
            for (uint256 j = 0; j < operatorMetadatas.length; j++) {
                if (operatorMetadatas[j].quorumBitmap >> i & 1 == 1) {
                    expectedOperatorOverallIndices[i][numOperatorCounter] = j;
                    numOperatorCounter++;
                }
            }
        }

        // register operators
        for (uint256 i = 0; i < operatorMetadatas.length; i++) {
            cheats.roll(registrationBlockNumber + blocksBetweenRegistrations * i);

            _registerOperatorWithCoordinator(
                operatorMetadatas[i].operator,
                operatorMetadatas[i].quorumBitmap,
                operatorMetadatas[i].stakes
            );
        }

        return (operatorMetadatas, expectedOperatorOverallIndices);
    }

    /**
     * @dev Set the operator weight for a given quorum. Note we have to do this by setting delegationMock operatorShares
     * Given each quorum must have at least one strategy, we set operatorShares for this strategy to this weight
     * Returns actual weight calculated set for operator shares in DelegationMock since multiplier and WEIGHTING_DIVISOR calculations
     * can give small rounding errors.
     */
    function _setOperatorWeight(
        address operator,
        uint8 quorumNumber,
        uint96 weight
    ) internal returns (uint96) {
        delegationMock.setOperatorShares(operator, strategy, weight);
        return uint96(weight);
    }

    function _incrementAddress(address start, uint256 inc) internal pure returns (address) {
        return address(uint160(uint256(uint160(start) + inc)));
    }

    function _incrementBytes32(bytes32 start, uint256 inc) internal pure returns (bytes32) {
        return bytes32(uint256(start) + inc);
    }

    function _signOperatorChurnApproval(
        address registeringOperator,
        bytes32 registeringOperatorId,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature,
        bytes32 salt,
        uint256 expiry
    ) internal view returns (ISignatureUtils.SignatureWithSaltAndExpiry memory) {}
}

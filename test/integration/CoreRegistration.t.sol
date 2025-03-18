// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../utils/MockAVSDeployer.sol";
import {AVSDirectory} from "eigenlayer-contracts/src/contracts/core/AVSDirectory.sol";
import {
    IAVSDirectory,
    IAVSDirectoryTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {DelegationManager} from "eigenlayer-contracts/src/contracts/core/DelegationManager.sol";
import {
    IDelegationManager,
    IDelegationManagerTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {RewardsCoordinator} from "eigenlayer-contracts/src/contracts/core/RewardsCoordinator.sol";
import {IRewardsCoordinator} from
    "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {PermissionController} from
    "eigenlayer-contracts/src/contracts/permissions/PermissionController.sol";
import {ITransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";

contract Test_CoreRegistration is MockAVSDeployer {
    // Contracts
    DelegationManager public delegationManager;

    // Operator info
    uint256 operatorPrivateKey = 420;
    address operator;

    // Dummy vals used across tests
    bytes32 emptySalt;
    uint256 maxExpiry = type(uint256).max;
    string emptyStringForMetadataURI;

    function setUp() public {
        _deployMockEigenLayerAndAVS();

        // Deploy New DelegationManager
        PermissionController permissionController; // TODO: Fix
        DelegationManager delegationManagerImplementation = new DelegationManager(
            IStrategyManager(address(strategyManagerMock)),
            eigenPodManagerMock,
            allocationManagerMock,
            pauserRegistry,
            permissionController,
            0,
            "v0.0.1"
        );
        IStrategy[] memory initializeStrategiesToSetDelayBlocks = new IStrategy[](0);
        uint256[] memory initializeWithdrawalDelayBlocks = new uint256[](0);
        delegationManager = DelegationManager(
            address(
                new TransparentUpgradeableProxy(
                    address(delegationManagerImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        DelegationManager.initialize.selector,
                        address(this),
                        pauserRegistry,
                        0, // 0 is initialPausedStatus
                        50400, // Initial withdrawal delay blocks
                        initializeStrategiesToSetDelayBlocks,
                        initializeWithdrawalDelayBlocks
                    )
                )
            )
        );

        // Deploy New AVS Directory
        AVSDirectory avsDirectoryImplementation =
            new AVSDirectory(delegationManager, pauserRegistry, "v0.0.1"); // TODO: Fix Config
        avsDirectory = AVSDirectory(
            address(
                new TransparentUpgradeableProxy(
                    address(avsDirectoryImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        AVSDirectory.initialize.selector,
                        address(this), // owner
                        pauserRegistry,
                        0 // 0 is initialPausedStatus
                    )
                )
            )
        );

        // Deploy Mock RewardsCoordinator
        rewardsCoordinatorMock = new RewardsCoordinatorMock();

        // Deploy New ServiceManager & RegistryCoordinator implementations
        serviceManagerImplementation = new ServiceManagerMock(
            avsDirectory,
            rewardsCoordinatorMock,
            registryCoordinator,
            stakeRegistry,
            permissionController,
            allocationManager
        );

        registryCoordinatorImplementation = new RegistryCoordinatorHarness(
            serviceManager,
            stakeRegistry,
            blsApkRegistry,
            indexRegistry,
            socketRegistry,
            allocationManager,
            pauserRegistry,
            "v0.0.1"
        );

        // Upgrade Registry Coordinator & ServiceManager
        cheats.startPrank(proxyAdminOwner);
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(payable(address(registryCoordinator))),
            address(registryCoordinatorImplementation)
        );
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(payable(address(serviceManager))),
            address(serviceManagerImplementation)
        );
        cheats.stopPrank();

        // Set operator address
        operator = cheats.addr(operatorPrivateKey);
        blsApkRegistry.setBLSPublicKey(operator, defaultPubKey);

        // Register operator to EigenLayer
        cheats.prank(operator);
        delegationManager.registerAsOperator(
            operator,
            // TODO: fix or parameterize
            0,
            emptyStringForMetadataURI
        );

        // Set operator weight in single quorum
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(MAX_QUORUM_BITMAP);
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            _setOperatorWeight(operator, uint8(quorumNumbers[i]), defaultStake);
        }
    }

    function test_registerOperator_coreStateChanges() public {
        bytes memory quorumNumbers = new bytes(1);

        // Get operator signature
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature =
        _getOperatorSignature(
            operatorPrivateKey, operator, address(serviceManager), emptySalt, maxExpiry
        );

        // set operator as registered in Eigenlayer
        delegationMock.setIsOperator(operator, true);

        // Register operator
        cheats.prank(operator);
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, operatorSignature
        );

        // Check operator is registered
        IAVSDirectoryTypes.OperatorAVSRegistrationStatus operatorStatus =
            avsDirectory.avsOperatorStatus(address(serviceManager), operator);
        assertEq(
            uint8(operatorStatus),
            uint8(IAVSDirectoryTypes.OperatorAVSRegistrationStatus.REGISTERED)
        );
    }

    function test_deregisterOperator_coreStateChanges() public {
        // Register operator
        bytes memory quorumNumbers = new bytes(1);
        _registerOperator(quorumNumbers);

        // Deregister Operator
        cheats.prank(operator);
        registryCoordinator.deregisterOperator(quorumNumbers);

        // Check operator is deregistered
        IAVSDirectoryTypes.OperatorAVSRegistrationStatus operatorStatus =
            avsDirectory.avsOperatorStatus(address(serviceManager), operator);
        assertEq(
            uint8(operatorStatus),
            uint8(IAVSDirectoryTypes.OperatorAVSRegistrationStatus.UNREGISTERED)
        );
    }

    function test_deregisterOperator_notGloballyDeregistered() public {
        // Register operator with all quorums
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(MAX_QUORUM_BITMAP);
        emit log_named_bytes("quorumNumbers", quorumNumbers);
        _registerOperator(quorumNumbers);

        IAVSDirectoryTypes.OperatorAVSRegistrationStatus operatorStatus =
            avsDirectory.avsOperatorStatus(address(serviceManager), operator);
        assertEq(
            uint8(operatorStatus),
            uint8(IAVSDirectoryTypes.OperatorAVSRegistrationStatus.REGISTERED)
        );

        // Deregister Operator with single quorum
        quorumNumbers = new bytes(1);
        cheats.prank(operator);
        registryCoordinator.deregisterOperator(quorumNumbers);

        // Check operator is still registered
        operatorStatus = avsDirectory.avsOperatorStatus(address(serviceManager), operator);
        assertEq(
            uint8(operatorStatus),
            uint8(IAVSDirectoryTypes.OperatorAVSRegistrationStatus.REGISTERED)
        );
    }

    function test_setMetadataURI_fail_notServiceManagerOwner() public {
        require(operator != serviceManager.owner(), "bad test setup");
        cheats.prank(operator);
        cheats.expectRevert("Ownable: caller is not the owner");
        serviceManager.updateAVSMetadataURI("Test MetadataURI");
    }

    event AVSMetadataURIUpdated(address indexed avs, string metadataURI);

    function test_setMetadataURI() public {
        address toPrankFrom = serviceManager.owner();
        cheats.prank(toPrankFrom);
        cheats.expectEmit(true, true, true, true);
        emit AVSMetadataURIUpdated(address(serviceManager), "Test MetadataURI");
        serviceManager.updateAVSMetadataURI("Test MetadataURI");
    }

    // Utils
    function _registerOperator(
        bytes memory quorumNumbers
    ) internal {
        // Get operator signature
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature =
        _getOperatorSignature(
            operatorPrivateKey, operator, address(serviceManager), emptySalt, maxExpiry
        );

        // set operator as registered in Eigenlayer
        delegationMock.setIsOperator(operator, true);

        // Register operator
        cheats.prank(operator);
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, operatorSignature
        );
    }

    function _getOperatorSignature(
        uint256 _operatorPrivateKey,
        address operatorToSign,
        address avs,
        bytes32 salt,
        uint256 expiry
    )
        internal
        view
        returns (ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature)
    {
        operatorSignature.salt = salt;
        operatorSignature.expiry = expiry;
        {
            bytes32 digestHash = avsDirectory.calculateOperatorAVSRegistrationDigestHash(
                operatorToSign, avs, salt, expiry
            );
            (uint8 v, bytes32 r, bytes32 s) = cheats.sign(_operatorPrivateKey, digestHash);
            operatorSignature.signature = abi.encodePacked(r, s, v);
        }
        return operatorSignature;
    }
}

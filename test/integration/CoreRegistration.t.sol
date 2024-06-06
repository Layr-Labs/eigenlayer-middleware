// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "../utils/MockAVSDeployer.sol";
import { AVSDirectory } from "eigenlayer-contracts/src/contracts/core/AVSDirectory.sol";
import { IAVSDirectory } from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import { DelegationManager } from "eigenlayer-contracts/src/contracts/core/DelegationManager.sol";
import { IDelegationManager } from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import { RewardsCoordinator } from "eigenlayer-contracts/src/contracts/core/RewardsCoordinator.sol";
import { IRewardsCoordinator } from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";

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
        DelegationManager delegationManagerImplementation = new DelegationManager(strategyManagerMock, slasher, eigenPodManagerMock);
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
        AVSDirectory avsDirectoryImplementation = new AVSDirectory(delegationManager);
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
            stakeRegistry
        );

        registryCoordinatorImplementation = new RegistryCoordinatorHarness(
            serviceManager,
            stakeRegistry,
            blsApkRegistry,
            indexRegistry
        );

        // Upgrade Registry Coordinator & ServiceManager
        cheats.startPrank(proxyAdminOwner);
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(registryCoordinator))),
            address(registryCoordinatorImplementation)
        );
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(serviceManager))),
            address(serviceManagerImplementation)
        );
        cheats.stopPrank();

        // Set operator address
        operator = cheats.addr(operatorPrivateKey);
        blsApkRegistry.setBLSPublicKey(operator, defaultPubKey);

        // Register operator to EigenLayer
        cheats.prank(operator);
        delegationManager.registerAsOperator(
            IDelegationManager.OperatorDetails({
                __deprecated_earningsReceiver: operator,
                delegationApprover: address(0),
                stakerOptOutWindowBlocks: 0
            }),
            emptyStringForMetadataURI
        );

        // Set operator weight in single quorum
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(MAX_QUORUM_BITMAP);
        for (uint i = 0; i < quorumNumbers.length; i++) {
            _setOperatorWeight(operator, uint8(quorumNumbers[i]), defaultStake);
        }
    }

    function test_registerOperator_coreStateChanges() public {
        bytes memory quorumNumbers = new bytes(1);

        // Get operator signature
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature = _getOperatorSignature(
            operatorPrivateKey,
            operator,
            address(serviceManager),
            emptySalt,
            maxExpiry
        );

        // set operator as registered in Eigenlayer
        delegationMock.setIsOperator(operator, true);

        // Register operator
        cheats.prank(operator);
        registryCoordinator.registerOperator(quorumNumbers, defaultSocket, pubkeyRegistrationParams, operatorSignature);

        // Check operator is registered
        IAVSDirectory.OperatorAVSRegistrationStatus operatorStatus = avsDirectory.avsOperatorStatus(address(serviceManager), operator);
        assertEq(uint8(operatorStatus), uint8(IAVSDirectory.OperatorAVSRegistrationStatus.REGISTERED));
    }

    function test_deregisterOperator_coreStateChanges() public {
        // Register operator
        bytes memory quorumNumbers = new bytes(1);
        _registerOperator(quorumNumbers);

        // Deregister Operator
        cheats.prank(operator);
        registryCoordinator.deregisterOperator(quorumNumbers);

        // Check operator is deregistered
        IAVSDirectory.OperatorAVSRegistrationStatus operatorStatus = avsDirectory.avsOperatorStatus(address(serviceManager), operator);
        assertEq(uint8(operatorStatus), uint8(IAVSDirectory.OperatorAVSRegistrationStatus.UNREGISTERED));
    }

    function test_deregisterOperator_notGloballyDeregistered() public {
        // Register operator with all quorums
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(MAX_QUORUM_BITMAP);
        emit log_named_bytes("quorumNumbers", quorumNumbers);
        _registerOperator(quorumNumbers);

        // Deregister Operator with single quorum
        quorumNumbers = new bytes(1);
        cheats.prank(operator);
        registryCoordinator.deregisterOperator(quorumNumbers);

        // Check operator is still registered
        IAVSDirectory.OperatorAVSRegistrationStatus operatorStatus = avsDirectory.avsOperatorStatus(address(serviceManager), operator);
        assertEq(uint8(operatorStatus), uint8(IAVSDirectory.OperatorAVSRegistrationStatus.REGISTERED));
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
    function _registerOperator(bytes memory quorumNumbers) internal {
        // Get operator signature
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature = _getOperatorSignature(
            operatorPrivateKey,
            operator,
            address(serviceManager),
            emptySalt,
            maxExpiry
        );

        // set operator as registered in Eigenlayer
        delegationMock.setIsOperator(operator, true);

        // Register operator
        cheats.prank(operator);
        registryCoordinator.registerOperator(quorumNumbers, defaultSocket, pubkeyRegistrationParams, operatorSignature);
    }

    function _getOperatorSignature(
        uint256 _operatorPrivateKey,
        address operatorToSign,
        address avs,
        bytes32 salt,
        uint256 expiry
    ) internal view returns (ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature) {
        operatorSignature.salt = salt;
        operatorSignature.expiry = expiry;
        {
            bytes32 digestHash = avsDirectory.calculateOperatorAVSRegistrationDigestHash(operatorToSign, avs, salt, expiry);
            (uint8 v, bytes32 r, bytes32 s) = cheats.sign(_operatorPrivateKey, digestHash);
            operatorSignature.signature = abi.encodePacked(r, s, v);
        }
        return operatorSignature;
    }

}

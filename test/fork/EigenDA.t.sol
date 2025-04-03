// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {UpgradeableProxyLib} from "../unit/UpgradeableProxyLib.sol";
import {BN254} from "../../src/libraries/BN254.sol";
import {Pausable} from "eigenlayer-contracts/src/contracts/permissions/Pausable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

import {IRegistryCoordinator} from "../../src/interfaces/IRegistryCoordinator.sol";
import {IServiceManager} from "../../src/interfaces/IServiceManager.sol";
import {IStakeRegistry} from "../../src/interfaces/IStakeRegistry.sol";
import {IBLSApkRegistry} from "../../src/interfaces/IBLSApkRegistry.sol";
import {IIndexRegistry} from "../../src/interfaces/IIndexRegistry.sol";
import {ISlashingRegistryCoordinator} from "../../src/interfaces/ISlashingRegistryCoordinator.sol";
import {ISocketRegistry} from "../../src/interfaces/ISocketRegistry.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from
    "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {
    IAllocationManager,
    OperatorSet,
    IAllocationManagerTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

// Import concrete implementation for deployment
import {RegistryCoordinator, IRegistryCoordinatorTypes} from "../../src/RegistryCoordinator.sol";
import {ISlashingRegistryCoordinatorTypes} from
    "../../src/interfaces/ISlashingRegistryCoordinator.sol";
import {ServiceManagerBase} from "../../src/ServiceManagerBase.sol";
import {BLSApkRegistry} from "../../src/BLSApkRegistry.sol";
import {IndexRegistry} from "../../src/IndexRegistry.sol";
import {StakeRegistry, IStakeRegistryTypes} from "../../src/StakeRegistry.sol";
import {SocketRegistry} from "../../src/SocketRegistry.sol";

// Extended interface to get addresses of other contracts
interface IServiceManagerExtended {
    function avsDirectory() external view returns (IAVSDirectory);
}

interface StakeRegistryExtended {
    function delegation() external view returns (IDelegationManager);
}

interface IDelegationManagerExtended {
    function allocationManager() external view returns (IAllocationManager);
}

interface IAllocationManagerExtended {
    function permissionController() external view returns (IPermissionController);
}

contract EigenDA_SM_Gap {
    uint256[50] private __EigenDASM_GAP;
}

contract BLSSignatureChecker_Pausable_GAP {
    uint256[100] private __GAP;
}

// EigenDAServiceManagerStorage, ServiceManagerBase, BLSSignatureChecker, Pausable
contract TestServiceManager is
    EigenDA_SM_Gap,
    ServiceManagerBase,
    BLSSignatureChecker_Pausable_GAP
{
    constructor(
        IAVSDirectory __avsDirectory,
        IRewardsCoordinator __rewardsCoordinator,
        ISlashingRegistryCoordinator __registryCoordinator,
        IStakeRegistry __stakeRegistry,
        IPermissionController __permissionController,
        IAllocationManager __allocationManager
    )
        ServiceManagerBase(
            __avsDirectory,
            __rewardsCoordinator,
            __registryCoordinator,
            __stakeRegistry,
            __permissionController,
            __allocationManager
        )
    {}
}

contract EigenDATest is Test {
    using stdJson for string;

    struct EigenDADeploymentData {
        address blsApkRegistry;
        address eigenDAProxyAdmin;
        address eigenDAServiceManager;
        address indexRegistry;
        address mockDispatcher;
        address operatorStateRetriever;
        address registryCoordinator;
        address serviceManagerRouter;
        address stakeRegistry;
    }

    struct EigenDAChainInfo {
        uint256 chainId;
        uint256 deploymentBlock;
    }

    struct EigenDAPermissionsData {
        address eigenDABatchConfirmer;
        address eigenDAChurner;
        address eigenDAEjector;
        address eigenDAOwner;
        address eigenDAUpgrader;
        address pauserRegistry;
    }

    struct EigenDAData {
        EigenDADeploymentData addresses;
        EigenDAChainInfo chainInfo;
        EigenDAPermissionsData permissions;
    }

    struct RegistryCoordinatorState {
        uint32 operatorSetUpdateNonce;
        uint8 numQuorums;
    }

    struct ServiceManagerState {
        uint256 paused;
        address owner;
    }

    struct BlsApkRegistryState {
        bytes32[] currentApkHashes;
    }

    struct IndexRegistryState {
        uint32[] operatorCounts;
    }

    struct StakeRegistryState {
        uint32[] numStrategies;
    }

    struct ContractStates {
        RegistryCoordinatorState registryCoordinator;
        ServiceManagerState serviceManager;
        BlsApkRegistryState blsApkRegistry;
        IndexRegistryState indexRegistry;
        StakeRegistryState stakeRegistry;
    }

    // Variables to hold our data
    EigenDAData public eigenDAData;
    ContractStates public preUpgradeStates;

    // Core contract addresses from StakeRegistry
    address public delegationManagerAddr;
    address public avsDirectoryAddr;
    address public allocationManagerAddr;
    address public permissionControllerAddr;
    address public rewardsCoordinatorAddr;

    // New implementation addresses for upgrade
    address public newRegistryCoordinatorImpl;
    address public newServiceManagerImpl;
    address public newBlsApkRegistryImpl;
    address public newIndexRegistryImpl;
    address public newStakeRegistryImpl;
    address public socketRegistry;

    // Contract instances
    ISlashingRegistryCoordinator public registryCoordinator;
    IBLSApkRegistry public apkRegistry;
    IIndexRegistry public indexRegistry;
    IStakeRegistry public stakeRegistry;
    IServiceManager public serviceManager;
    IAllocationManager public allocationManager;
    IAVSDirectory public avsDirectory;
    IDelegationManagerExtended public delegationManager;
    IPermissionController public permissionController;

    // Test setup function that runs before each test
    function setUp() public virtual {
        // Setup the Holesky fork and load EigenDA deployment data
        eigenDAData = _setupEigenDAFork("test/utils");

        // Store contract addresses
        delegationManagerAddr =
            address(StakeRegistryExtended(eigenDAData.addresses.stakeRegistry).delegation());
        avsDirectoryAddr = address(
            IServiceManagerExtended(eigenDAData.addresses.eigenDAServiceManager).avsDirectory()
        );
        allocationManagerAddr =
            address(IDelegationManagerExtended(delegationManagerAddr).allocationManager());
        permissionControllerAddr =
            address(IAllocationManagerExtended(allocationManagerAddr).permissionController());
        /// TODO:
        rewardsCoordinatorAddr = address(0);

        // Store contract instances
        registryCoordinator =
            ISlashingRegistryCoordinator(eigenDAData.addresses.registryCoordinator);
        apkRegistry = IBLSApkRegistry(eigenDAData.addresses.blsApkRegistry);
        indexRegistry = IIndexRegistry(eigenDAData.addresses.indexRegistry);
        stakeRegistry = IStakeRegistry(eigenDAData.addresses.stakeRegistry);
        serviceManager = IServiceManager(eigenDAData.addresses.eigenDAServiceManager);
        allocationManager = IAllocationManager(allocationManagerAddr);
        avsDirectory = IAVSDirectory(avsDirectoryAddr);
        delegationManager = IDelegationManagerExtended(delegationManagerAddr);
        permissionController = IPermissionController(permissionControllerAddr);

        _verifyInitialSetup();

        _captureAndStorePreUpgradeState();

        _deployNewImplementations();
    }

    function test_Upgrade() public {
        _upgradeContracts();
    }

    function test_ValidatePostUpgradeState() public {
        _upgradeContracts();
        console.log("Validating post-upgrade contract states");

        // Verify quorum count is maintained
        uint8 quorumCount = registryCoordinator.quorumCount();
        console.log("quorum count:", quorumCount);
        require(
            quorumCount == preUpgradeStates.registryCoordinator.numQuorums,
            "Quorum count changed after upgrade"
        );

        // Verify each quorum's data is maintained across all registries
        for (uint8 i = 0; i < quorumCount; i++) {
            // 1. Verify BLSApkRegistry state
            bytes32 currentApkHash = BN254.hashG1Point(apkRegistry.getApk(i));
            require(
                currentApkHash == preUpgradeStates.blsApkRegistry.currentApkHashes[i],
                "BLSApkRegistry: APK hash changed after upgrade"
            );

            // 2. Verify IndexRegistry state
            uint32 operatorCount = indexRegistry.totalOperatorsForQuorum(i);
            require(
                operatorCount == preUpgradeStates.indexRegistry.operatorCounts[i],
                "IndexRegistry: Operator count changed after upgrade"
            );

            // 3. Verify StakeRegistry state - only if quorum exists in StakeRegistry
            if (stakeRegistry.getTotalStakeHistoryLength(i) > 0) {
                uint256 strategyCount = stakeRegistry.strategyParamsLength(i);
                require(
                    uint32(strategyCount) == preUpgradeStates.stakeRegistry.numStrategies[i],
                    "StakeRegistry: Strategy count changed after upgrade"
                );
            }
        }

        console.log("Post-upgrade validation successful");
    }

    function test_PostUpgrade_CreateOperatorSet() public {
        _upgradeContracts();

        // Verify the owner remained the same post-upgrade (sanity check)
        require(
            preUpgradeStates.serviceManager.owner
                == OwnableUpgradeable(address(serviceManager)).owner(),
            "Service Manager owner mismatch post-upgrade"
        );

        console.log("Configuring permissions for operator set creation...");

        address serviceManagerOwner = preUpgradeStates.serviceManager.owner;
        vm.startPrank(serviceManagerOwner);

        serviceManager.setAppointee(
            address(registryCoordinator),
            allocationManagerAddr,
            IAllocationManager.createOperatorSets.selector
        );

        console.log("Appointee set for createOperatorSets");

        serviceManager.setAppointee(
            serviceManagerOwner, // Grant permission to the owner itself
            allocationManagerAddr,
            IAllocationManager.updateAVSMetadataURI.selector
        );
        console.log("Appointee set for updateAVSMetadataURI");

        // Update AVS metadata URI - required before creating operator sets
        string memory metadataURI = "https://eigenda.xyz/metadata";
        console.log("Updating AVS metadata URI to:", metadataURI);
        allocationManager.updateAVSMetadataURI(address(serviceManager), metadataURI);

        vm.stopPrank();

        // Set the AVS address in the Registry Coordinator (requires RC owner) - required before creating operator sets
        address registryCoordinatorOwner =
            OwnableUpgradeable(eigenDAData.addresses.registryCoordinator).owner();
        console.log("Setting AVS address in Registry Coordinator...");
        vm.startPrank(registryCoordinatorOwner);
        registryCoordinator.setAVS(address(serviceManager));
        vm.stopPrank(); // Stop impersonating registryCoordinatorOwner

        console.log("Creating a new slashable stake quorum (quorum 1)...");
        vm.startPrank(serviceManagerOwner);

        // Define parameters for the new quorum
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParam =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 100,
            kickBIPsOfOperatorStake: 10500, // 105%
            kickBIPsOfTotalStake: 100 // 1%
        });

        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] = IStakeRegistryTypes.StrategyParams({
            strategy: IStrategy(address(0)), // TODO: Placeholder
            multiplier: 1 * 1e18
        });

        uint96 minimumStake = uint96(1 ether);
        uint32 lookAheadPeriod = 10;

        registryCoordinator.createSlashableStakeQuorum(
            operatorSetParam, minimumStake, strategyParams, lookAheadPeriod
        );

        vm.stopPrank();

        // Verify that operator sets are enabled in the Registry Coordinator
        console.log("Verifying operator sets are enabled...");
        bool operatorSetsEnabled =
            IRegistryCoordinator(address(registryCoordinator)).operatorSetsEnabled();
        assertTrue(
            operatorSetsEnabled,
            "Operator sets should be enabled after creating a slashable stake quorum"
        );

        console.log("Successfully created new operator set quorum.");
    }

    function _captureAndStorePreUpgradeState() internal {
        preUpgradeStates.registryCoordinator.numQuorums = registryCoordinator.quorumCount();

        OwnableUpgradeable serviceManagerOwnable = OwnableUpgradeable(address(serviceManager));
        preUpgradeStates.serviceManager.owner = serviceManagerOwnable.owner();

        Pausable serviceManagerPausable = Pausable(address(serviceManager));
        preUpgradeStates.serviceManager.paused = serviceManagerPausable.paused();

        uint8 quorumCount = registryCoordinator.quorumCount();
        preUpgradeStates.blsApkRegistry.currentApkHashes = new bytes32[](quorumCount);
        preUpgradeStates.indexRegistry.operatorCounts = new uint32[](quorumCount);
        preUpgradeStates.stakeRegistry.numStrategies = new uint32[](quorumCount);

        // For each quorum, gather data from all registries
        for (uint8 quorumIndex = 0; quorumIndex < quorumCount; quorumIndex++) {
            // Get operator count for each quorum from IndexRegistry
            uint32 operatorCount = indexRegistry.totalOperatorsForQuorum(quorumIndex);
            preUpgradeStates.indexRegistry.operatorCounts[quorumIndex] = operatorCount;

            // Get APK hash for each quorum from BLSApkRegistry
            // Store the hash of the APK as bytes32
            preUpgradeStates.blsApkRegistry.currentApkHashes[quorumIndex] =
                BN254.hashG1Point(apkRegistry.getApk(quorumIndex));

            // Get strategy count for each quorum from StakeRegistry
            uint256 strategyCount = 0;
            // Check if quorum exists in StakeRegistry before querying
            if (stakeRegistry.getTotalStakeHistoryLength(quorumIndex) > 0) {
                strategyCount = stakeRegistry.strategyParamsLength(quorumIndex);
            }
            preUpgradeStates.stakeRegistry.numStrategies[quorumIndex] = uint32(strategyCount);
        }
    }

    function _deployNewImplementations() internal {
        socketRegistry = address(
            new SocketRegistry(
                ISlashingRegistryCoordinator(eigenDAData.addresses.registryCoordinator)
            )
        );

        IRegistryCoordinatorTypes.SlashingRegistryParams memory slashingParams =
        IRegistryCoordinatorTypes.SlashingRegistryParams({
            stakeRegistry: stakeRegistry,
            blsApkRegistry: apkRegistry,
            indexRegistry: indexRegistry,
            socketRegistry: ISocketRegistry(socketRegistry),
            allocationManager: allocationManager,
            pauserRegistry: IPauserRegistry(eigenDAData.permissions.pauserRegistry)
        });

        IRegistryCoordinatorTypes.RegistryCoordinatorParams memory params =
        IRegistryCoordinatorTypes.RegistryCoordinatorParams({
            serviceManager: serviceManager,
            slashingParams: slashingParams
        });

        newRegistryCoordinatorImpl = address(new RegistryCoordinator(params));

        IRewardsCoordinator rewardsCoordinator = IRewardsCoordinator(rewardsCoordinatorAddr);

        // Assert all addresses are not zero before deployment
        assertTrue(permissionControllerAddr != address(0), "PermissionController address not found");
        assertTrue(address(avsDirectory) != address(0), "AVSDirectory address is zero");
        // assertTrue(address(rewardsCoordinator) != address(0), "RewardsCoordinator address is zero"); //TODO:
        assertTrue(
            address(registryCoordinator) != address(0), "RegistryCoordinator address is zero"
        );
        assertTrue(address(stakeRegistry) != address(0), "StakeRegistry address is zero");
        assertTrue(
            address(permissionController) != address(0), "PermissionController address is zero"
        );
        assertTrue(address(allocationManager) != address(0), "AllocationManager address is zero");
        assertTrue(delegationManagerAddr != address(0), "DelegationManager address is zero");
        assertTrue(address(avsDirectory) != address(0), "AVSDirectory address is zero");
        assertTrue(address(allocationManager) != address(0), "AllocationManager address is zero");

        newServiceManagerImpl = address(
            new TestServiceManager(
                avsDirectory,
                rewardsCoordinator,
                registryCoordinator,
                stakeRegistry,
                permissionController,
                allocationManager
            )
        );
        newBlsApkRegistryImpl = address(new BLSApkRegistry(registryCoordinator));
        newIndexRegistryImpl = address(new IndexRegistry(registryCoordinator));

        newStakeRegistryImpl = address(
            new StakeRegistry(
                registryCoordinator,
                IDelegationManager(address(delegationManager)),
                avsDirectory,
                allocationManager
            )
        );
    }

    function _setupEigenDAFork(
        string memory jsonPath
    ) internal returns (EigenDAData memory) {
        string memory rpcUrl = vm.envString("HOLESKY_RPC_URL");

        vm.createSelectFork(rpcUrl);

        EigenDAData memory data = _readEigenDADeploymentJson(jsonPath, 17000);

        /// Recent block post ALM upgrade
        vm.rollFork(3592349);

        return data;
    }

    function _upgradeContracts() internal {
        vm.startPrank(eigenDAData.permissions.eigenDAUpgrader);

        UpgradeableProxyLib.upgrade(
            eigenDAData.addresses.registryCoordinator, newRegistryCoordinatorImpl
        );
        UpgradeableProxyLib.upgrade(
            eigenDAData.addresses.eigenDAServiceManager, newServiceManagerImpl
        );
        UpgradeableProxyLib.upgrade(eigenDAData.addresses.blsApkRegistry, newBlsApkRegistryImpl);
        UpgradeableProxyLib.upgrade(eigenDAData.addresses.indexRegistry, newIndexRegistryImpl);
        UpgradeableProxyLib.upgrade(eigenDAData.addresses.stakeRegistry, newStakeRegistryImpl);

        vm.stopPrank();
    }

    function _readEigenDADeploymentJson(
        string memory path,
        uint256 chainId
    ) internal returns (EigenDAData memory) {
        string memory filePath = string(abi.encodePacked(path, "/EigenDA_Holesky.json"));
        return _loadEigenDAJson(filePath);
    }

    function _loadEigenDAJson(
        string memory filePath
    ) internal returns (EigenDAData memory) {
        string memory json = vm.readFile(filePath);
        require(vm.exists(filePath), "EigenDA deployment file does not exist");

        EigenDAData memory data;

        // Parse addresses section
        data.addresses.blsApkRegistry = json.readAddress(".addresses.blsApkRegistry");
        data.addresses.eigenDAProxyAdmin = json.readAddress(".addresses.eigenDAProxyAdmin");
        data.addresses.eigenDAServiceManager = json.readAddress(".addresses.eigenDAServiceManager");
        data.addresses.indexRegistry = json.readAddress(".addresses.indexRegistry");
        data.addresses.mockDispatcher = json.readAddress(".addresses.mockRollup");
        data.addresses.operatorStateRetriever =
            json.readAddress(".addresses.operatorStateRetriever");
        data.addresses.registryCoordinator = json.readAddress(".addresses.registryCoordinator");
        data.addresses.serviceManagerRouter = json.readAddress(".addresses.serviceManagerRouter");
        data.addresses.stakeRegistry = json.readAddress(".addresses.stakeRegistry");

        // Parse chainInfo section
        data.chainInfo.chainId = json.readUint(".chainInfo.chainId");
        data.chainInfo.deploymentBlock = json.readUint(".chainInfo.deploymentBlock");

        // Parse permissions section
        data.permissions.eigenDABatchConfirmer =
            json.readAddress(".permissions.eigenDABatchConfirmer");
        data.permissions.eigenDAChurner = json.readAddress(".permissions.eigenDAChurner");
        data.permissions.eigenDAEjector = json.readAddress(".permissions.eigenDAEjector");
        data.permissions.eigenDAOwner = json.readAddress(".permissions.eigenDAOwner");
        data.permissions.eigenDAUpgrader = json.readAddress(".permissions.eigenDAUpgrader");
        data.permissions.pauserRegistry = json.readAddress(".permissions.pauserRegistry");

        // Label all addresses for better debugging and tracing
        vm.label(data.addresses.blsApkRegistry, "BLSApkRegistry");
        vm.label(data.addresses.eigenDAProxyAdmin, "EigenDAProxyAdmin");
        vm.label(data.addresses.eigenDAServiceManager, "EigenDAServiceManager");
        vm.label(data.addresses.indexRegistry, "IndexRegistry");
        vm.label(data.addresses.mockDispatcher, "MockDispatcher");
        vm.label(data.addresses.operatorStateRetriever, "OperatorStateRetriever");
        vm.label(data.addresses.registryCoordinator, "RegistryCoordinator");
        vm.label(data.addresses.serviceManagerRouter, "ServiceManagerRouter");
        vm.label(data.addresses.stakeRegistry, "StakeRegistry");

        // Label permissioned addresses
        vm.label(data.permissions.eigenDABatchConfirmer, "EigenDABatchConfirmer");
        vm.label(data.permissions.eigenDAChurner, "EigenDAChurner");
        vm.label(data.permissions.eigenDAEjector, "EigenDAEjector");
        vm.label(data.permissions.eigenDAOwner, "EigenDAOwner");
        vm.label(data.permissions.eigenDAUpgrader, "EigenDAUpgrader");
        vm.label(data.permissions.pauserRegistry, "PauserRegistry");

        return data;
    }

    function _verifyInitialSetup() internal view {
        // Verify that contracts are deployed and at least not null
        require(
            eigenDAData.addresses.registryCoordinator != address(0),
            "Registry Coordinator should be deployed"
        );
        require(
            eigenDAData.addresses.eigenDAServiceManager != address(0),
            "Service Manager should be deployed"
        );
        require(
            eigenDAData.addresses.blsApkRegistry != address(0),
            "BLS APK Registry should be deployed"
        );
        require(
            eigenDAData.addresses.indexRegistry != address(0), "Index Registry should be deployed"
        );
        require(
            eigenDAData.addresses.stakeRegistry != address(0), "Stake Registry should be deployed"
        );

        require(
            eigenDAData.permissions.eigenDAUpgrader != address(0),
            "EigenDA Upgrader should be defined"
        );
        require(
            eigenDAData.permissions.pauserRegistry != address(0),
            "Pauser Registry should be defined"
        );
    }
}

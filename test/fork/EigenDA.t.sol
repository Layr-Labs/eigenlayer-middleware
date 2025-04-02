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

interface IAVSDirectoryExtended {
    function permissionController() external view returns (IPermissionController);
}

interface StakeRegistryExtended {
    function delegation() external view returns (IDelegationManager);
}

interface IDelegationManagerExtended {
    function allocationManager() external view returns (IAllocationManager);
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

    struct ConfigData {
        address admin;
        address proxyAdmin;
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
    ConfigData public config;
    ContractStates public preUpgradeStates;

    // Core contract addresses from StakeRegistry
    address public delegationManagerAddr;
    address public avsDirectoryAddr;
    address public allocationManagerAddr;
    address public permissionControllerAddr; // Will need to be fetched separately
    address public rewardsCoordinatorAddr; // Will need to be fetched separately

    // New implementation addresses for upgrade
    address public newRegistryCoordinatorImpl;
    address public newServiceManagerImpl;
    address public newBlsApkRegistryImpl;
    address public newIndexRegistryImpl;
    address public newStakeRegistryImpl;
    address public socketRegistry;

    // Test setup function that runs before each test
    function setUp() public virtual {
        // Setup the Holesky fork and load EigenDA deployment data
        eigenDAData = _setupEigenDAFork("test/utils");

        // Set the admin to the test contract address (this)
        config.admin = address(this);

        // Deploy a proxy admin for potential upgrades
        config.proxyAdmin = UpgradeableProxyLib.deployProxyAdmin();
    }

    function testEigenDAUpgradeSetup() public {
        // 1. Verify initial setup
        console.log("Verifying initial EigenDA setup on fork");
        _verifyInitialSetup();

        // 2. Capture pre-upgrade state
        console.log("Capturing pre-upgrade contract states");
        _capturePreUpgradeState();

        // 3. Deploy new implementations
        _deployNewImplementations();

        // 4. Perform upgrades
        _performUpgrades(
            newRegistryCoordinatorImpl,
            newServiceManagerImpl,
            newBlsApkRegistryImpl,
            newIndexRegistryImpl,
            newStakeRegistryImpl,
            socketRegistry
        );

        console.log("Contract upgrades completed. Ready for validation testing.");
    }

    function _verifyInitialSetup() internal view {
        // Verify that contracts are deployed at the expected addresses
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

        // Verify permissions
        require(
            eigenDAData.permissions.eigenDAUpgrader != address(0),
            "EigenDA Upgrader should be defined"
        );
        require(
            eigenDAData.permissions.pauserRegistry != address(0),
            "Pauser Registry should be defined"
        );
    }

    function _capturePreUpgradeState() internal {
        // Registry Coordinator
        ISlashingRegistryCoordinator rc =
            ISlashingRegistryCoordinator(eigenDAData.addresses.registryCoordinator);
        preUpgradeStates.registryCoordinator.numQuorums = rc.quorumCount();

        // Service Manager
        address payable smAddr = payable(eigenDAData.addresses.eigenDAServiceManager);
        OwnableUpgradeable sm_ownable = OwnableUpgradeable(smAddr);
        preUpgradeStates.serviceManager.owner = sm_ownable.owner();

        // Check if service manager is paused
        Pausable sm_pausable = Pausable(smAddr);
        preUpgradeStates.serviceManager.paused = sm_pausable.paused();

        // BLS Apk Registry
        IBLSApkRegistry bls = IBLSApkRegistry(eigenDAData.addresses.blsApkRegistry);

        // Index Registry
        IIndexRegistry idx = IIndexRegistry(eigenDAData.addresses.indexRegistry);

        // Initialize arrays for each quorum
        uint8 quorumCount = rc.quorumCount();
        preUpgradeStates.blsApkRegistry.currentApkHashes = new bytes32[](quorumCount);
        preUpgradeStates.indexRegistry.operatorCounts = new uint32[](quorumCount);
        preUpgradeStates.stakeRegistry.numStrategies = new uint32[](quorumCount);

        // Stake Registry
        IStakeRegistry stake = IStakeRegistry(eigenDAData.addresses.stakeRegistry);

        // For each quorum, gather data from all registries
        for (uint8 i = 0; i < quorumCount; i++) {
            // Get operator count for each quorum from IndexRegistry
            uint32 operatorCount = idx.totalOperatorsForQuorum(i);
            preUpgradeStates.indexRegistry.operatorCounts[i] = operatorCount;

            // Get APK hash for each quorum from BLSApkRegistry
            // Store the hash of the APK as bytes32
            preUpgradeStates.blsApkRegistry.currentApkHashes[i] = BN254.hashG1Point(bls.getApk(i));

            // Get strategy count for each quorum from StakeRegistry
            // Check if we can get total stake history for this quorum
            // If getTotalStakeHistoryLength doesn't revert, the quorum exists in StakeRegistry
            uint256 strategyCount = 0;

            // First check if we can get the total stake history length, which confirms quorum exists
            if (stake.getTotalStakeHistoryLength(i) > 0) {
                // Now it's safe to get strategy params length
                strategyCount = stake.strategyParamsLength(i);
            }

            preUpgradeStates.stakeRegistry.numStrategies[i] = uint32(strategyCount);
        }
    }

    function _deployNewImplementations() internal {
        // Deploy SocketRegistry first
        socketRegistry = address(
            new SocketRegistry(
                ISlashingRegistryCoordinator(eigenDAData.addresses.registryCoordinator)
            )
        );
        console.log("Deployed new SocketRegistry instance at:", socketRegistry);

        IRegistryCoordinatorTypes.SlashingRegistryParams memory slashingParams =
        IRegistryCoordinatorTypes.SlashingRegistryParams({
            stakeRegistry: IStakeRegistry(eigenDAData.addresses.stakeRegistry),
            blsApkRegistry: IBLSApkRegistry(eigenDAData.addresses.blsApkRegistry),
            indexRegistry: IIndexRegistry(eigenDAData.addresses.indexRegistry),
            socketRegistry: ISocketRegistry(socketRegistry),
            allocationManager: IAllocationManager(allocationManagerAddr),
            pauserRegistry: IPauserRegistry(eigenDAData.permissions.pauserRegistry)
        });

        // Populate RegistryCoordinatorParams
        IRegistryCoordinatorTypes.RegistryCoordinatorParams memory params =
        IRegistryCoordinatorTypes.RegistryCoordinatorParams({
            serviceManager: IServiceManager(payable(eigenDAData.addresses.eigenDAServiceManager)),
            slashingParams: slashingParams
        });

        // Deploy RegistryCoordinator
        newRegistryCoordinatorImpl = address(new RegistryCoordinator(params));
        console.log(
            "Deployed new RegistryCoordinator implementation at:", newRegistryCoordinatorImpl
        );

        // Deploy ServiceManagerBase
        // Use extracted addresses for core dependencies
        address registryCoordinatorAddr = eigenDAData.addresses.registryCoordinator;
        address stakeRegistryAddr = eigenDAData.addresses.stakeRegistry;

        // Use extracted addresses where available
        IAVSDirectory avsDirectory = IAVSDirectory(avsDirectoryAddr);
        IRewardsCoordinator rewardsCoordinator = IRewardsCoordinator(rewardsCoordinatorAddr);
        ISlashingRegistryCoordinator registryCoordinator =
            ISlashingRegistryCoordinator(registryCoordinatorAddr);
        IStakeRegistry stakeRegistry = IStakeRegistry(stakeRegistryAddr);
        // Fetch PermissionController from AVS Directory
        permissionControllerAddr =
            address(IAVSDirectoryExtended(allocationManagerAddr).permissionController());
        require(permissionControllerAddr != address(0), "PermissionController address not found");
        console.log("PermissionController address:", permissionControllerAddr);

        IPermissionController permissionController = IPermissionController(permissionControllerAddr);
        IAllocationManager allocationManager = IAllocationManager(allocationManagerAddr);

        // Assert all addresses are not zero before deployment
        assertTrue(address(avsDirectory) != address(0), "AVSDirectory address is zero");
        // assertTrue(address(rewardsCoordinator) != address(0), "RewardsCoordinator address is zero");
        assertTrue(
            address(registryCoordinator) != address(0), "RegistryCoordinator address is zero"
        );
        assertTrue(address(stakeRegistry) != address(0), "StakeRegistry address is zero");
        assertTrue(
            address(permissionController) != address(0), "PermissionController address is zero"
        );
        assertTrue(address(allocationManager) != address(0), "AllocationManager address is zero");

        // Deploy TestServiceManager (concrete implementation)
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
        console.log("Deployed new ServiceManager implementation at:", newServiceManagerImpl);

        // Deploy BLSApkRegistry
        newBlsApkRegistryImpl = address(new BLSApkRegistry(registryCoordinator));
        console.log("Deployed new BLSApkRegistry implementation at:", newBlsApkRegistryImpl);

        // Deploy IndexRegistry
        newIndexRegistryImpl = address(new IndexRegistry(registryCoordinator));
        console.log("Deployed new IndexRegistry implementation at:", newIndexRegistryImpl);

        // Deploy StakeRegistry
        // Use extracted address for delegationManager
        IDelegationManager delegationManager = IDelegationManager(delegationManagerAddr);

        assertTrue(
            address(registryCoordinator) != address(0), "RegistryCoordinator address is zero"
        );
        assertTrue(address(delegationManager) != address(0), "DelegationManager address is zero");
        assertTrue(address(avsDirectory) != address(0), "AVSDirectory address is zero");
        assertTrue(address(allocationManager) != address(0), "AllocationManager address is zero");

        newStakeRegistryImpl = address(
            new StakeRegistry(
                registryCoordinator, delegationManager, avsDirectory, allocationManager
            )
        );
        console.log("Deployed new StakeRegistry implementation at:", newStakeRegistryImpl);
    }

    function _setupEigenDAFork(
        string memory jsonPath
    ) internal returns (EigenDAData memory) {
        // Get the Holesky RPC URL from environment variables
        string memory rpcUrl = vm.envString("HOLESKY_RPC_URL");

        vm.createSelectFork(rpcUrl);

        EigenDAData memory data = _readEigenDADeploymentJson(jsonPath, 17000);

        vm.rollFork(3592349);

        /// Recent block post ALM upgrade

        delegationManagerAddr =
            address(StakeRegistryExtended(data.addresses.stakeRegistry).delegation());
        avsDirectoryAddr =
            address(IServiceManagerExtended(data.addresses.eigenDAServiceManager).avsDirectory());
        allocationManagerAddr =
            address(IDelegationManagerExtended(delegationManagerAddr).allocationManager());
        console.log("DelegationManager address:", delegationManagerAddr);
        console.log("AVSDirectory address:", avsDirectoryAddr);
        console.log("Allocation Manager address:", allocationManagerAddr);

        return data;
    }

    function _performUpgrades(
        address newRegistryCoordinator,
        address newServiceManager,
        address newBlsApkRegistry,
        address newIndexRegistry,
        address newStakeRegistry,
        address socketRegistry
    ) internal {
        // Impersonate the upgrader account
        vm.startPrank(eigenDAData.permissions.eigenDAUpgrader);

        // Upgrade each contract using the proxyAdmin
        if (newRegistryCoordinator != address(0)) {
            UpgradeableProxyLib.upgrade(
                eigenDAData.addresses.registryCoordinator, newRegistryCoordinator
            );
        }

        if (newServiceManager != address(0)) {
            UpgradeableProxyLib.upgrade(
                eigenDAData.addresses.eigenDAServiceManager, newServiceManager
            );
        }

        if (newBlsApkRegistry != address(0)) {
            UpgradeableProxyLib.upgrade(eigenDAData.addresses.blsApkRegistry, newBlsApkRegistry);
        }

        if (newIndexRegistry != address(0)) {
            UpgradeableProxyLib.upgrade(eigenDAData.addresses.indexRegistry, newIndexRegistry);
        }

        if (newStakeRegistry != address(0)) {
            UpgradeableProxyLib.upgrade(eigenDAData.addresses.stakeRegistry, newStakeRegistry);
        }

        // Deploy and use the new SocketRegistry instance
        if (socketRegistry != address(0)) {
            // Since this is a new deployment, not an upgrade
            console.log("Using new SocketRegistry instance at:", socketRegistry);
        }

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

        // Label permission addresses
        vm.label(data.permissions.eigenDABatchConfirmer, "EigenDABatchConfirmer");
        vm.label(data.permissions.eigenDAChurner, "EigenDAChurner");
        vm.label(data.permissions.eigenDAEjector, "EigenDAEjector");
        vm.label(data.permissions.eigenDAOwner, "EigenDAOwner");
        vm.label(data.permissions.eigenDAUpgrader, "EigenDAUpgrader");
        vm.label(data.permissions.pauserRegistry, "PauserRegistry");

        return data;
    }

    function testValidatePostUpgradeState() public {
        testEigenDAUpgradeSetup();

        console.log("Validating post-upgrade contract states");

        ISlashingRegistryCoordinator rc =
            ISlashingRegistryCoordinator(eigenDAData.addresses.registryCoordinator);
        IBLSApkRegistry bls = IBLSApkRegistry(eigenDAData.addresses.blsApkRegistry);
        IIndexRegistry idx = IIndexRegistry(eigenDAData.addresses.indexRegistry);
        IStakeRegistry stake = IStakeRegistry(eigenDAData.addresses.stakeRegistry);

        // Verify quorum count is maintained
        uint8 quorumCount = rc.quorumCount();
        console.log("quorum count:", quorumCount);
        require(
            quorumCount == preUpgradeStates.registryCoordinator.numQuorums,
            "Quorum count changed after upgrade"
        );

        // Verify each quorum's data is maintained across all registries
        for (uint8 i = 0; i < quorumCount; i++) {
            // 1. Verify BLSApkRegistry state
            bytes32 currentApkHash = BN254.hashG1Point(bls.getApk(i));
            require(
                currentApkHash == preUpgradeStates.blsApkRegistry.currentApkHashes[i],
                "BLSApkRegistry: APK hash changed after upgrade"
            );

            // 2. Verify IndexRegistry state
            uint32 operatorCount = idx.totalOperatorsForQuorum(i);
            require(
                operatorCount == preUpgradeStates.indexRegistry.operatorCounts[i],
                "IndexRegistry: Operator count changed after upgrade"
            );

            // 3. Verify StakeRegistry state - only if quorum exists in StakeRegistry
            if (stake.getTotalStakeHistoryLength(i) > 0) {
                uint256 strategyCount = stake.strategyParamsLength(i);
                require(
                    uint32(strategyCount) == preUpgradeStates.stakeRegistry.numStrategies[i],
                    "StakeRegistry: Strategy count changed after upgrade"
                );
            }
        }

        console.log("Post-upgrade validation successful");
    }

    function testPostUpgrade_CreateOperatorSet() public {
        // Run the upgrade setup first
        testEigenDAUpgradeSetup();

        console.log("Setting up operator sets post-upgrade...");

        // Get contract instances
        IRegistryCoordinator rc = IRegistryCoordinator(eigenDAData.addresses.registryCoordinator);
        IAllocationManager allocationManager = IAllocationManager(allocationManagerAddr);

        address avs = eigenDAData.addresses.eigenDAServiceManager; // Service Manager is the account
        assert(preUpgradeStates.serviceManager.owner == OwnableUpgradeable(avs).owner());

        console.log("Setting appointee for createOperatorSets...");

        // Define appointee parameters
        vm.startPrank(preUpgradeStates.serviceManager.owner);
        ServiceManagerBase(avs).setAppointee(
            address(rc), allocationManagerAddr, IAllocationManager.createOperatorSets.selector
        );

        ServiceManagerBase(avs).setAppointee(
            preUpgradeStates.serviceManager.owner,
            allocationManagerAddr,
            IAllocationManager.updateAVSMetadataURI.selector
        );

        // Update AVS metadata URI so we can create operator sets
        string memory metadataURI = "https://eigenda.xyz/metadata";
        console.log("Updating AVS metadata URI...");
        allocationManager.updateAVSMetadataURI(avs, metadataURI);

        vm.stopPrank();

        address registryCoordinatorOwner =
            OwnableUpgradeable(eigenDAData.addresses.registryCoordinator).owner();
        vm.startPrank(registryCoordinatorOwner);

        rc.setAVS(avs);

        console.log("Creating a new slashable stake quorum (quorum 1)...");
        // Create a new quorum with the SlashingRegistryCoordinator
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] = IStakeRegistryTypes.StrategyParams({
            strategy: IStrategy(address(0)), // Replace with actual strategy address
            multiplier: 1
        });

        ISlashingRegistryCoordinatorTypes.OperatorSetParam[] memory operatorSetParams =
            new ISlashingRegistryCoordinatorTypes.OperatorSetParam[](1);
        operatorSetParams[0] = ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 100,
            kickBIPsOfOperatorStake: 10500,
            kickBIPsOfTotalStake: 100
        });

        rc.createSlashableStakeQuorum(
            operatorSetParams[0],
            1 ether, // minimumStake
            strategyParams,
            10 // lookAheadPeriod
        );

        vm.stopPrank();

        console.log("Post-upgrade creation of operator set quorums");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {UpgradeableProxyLib} from "../unit/UpgradeableProxyLib.sol";
import {BN254} from "../../src/libraries/BN254.sol";

import {IRegistryCoordinator} from "../../src/interfaces/IRegistryCoordinator.sol";
import {IServiceManager} from "../../src/interfaces/IServiceManager.sol";
import {IStakeRegistry} from "../../src/interfaces/IStakeRegistry.sol";
import {IBLSApkRegistry} from "../../src/interfaces/IBLSApkRegistry.sol";
import {IIndexRegistry} from "../../src/interfaces/IIndexRegistry.sol";

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
        bool paused;
        address owner;
    }

    struct BlsApkRegistryState {
        uint32 nextOperatorId;
    }

    struct IndexRegistryState {
        uint32 nextOperatorId;
    }

    struct StakeRegistryState {
        uint32 numStrategies;
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

    // New implementation addresses for upgrade
    address public newRegistryCoordinatorImpl;
    address public newServiceManagerImpl;
    address public newBlsApkRegistryImpl;
    address public newIndexRegistryImpl;
    address public newStakeRegistryImpl;

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

        _deployNewImplementations();

        _performUpgrades(
            newRegistryCoordinatorImpl,
            newServiceManagerImpl,
            newBlsApkRegistryImpl,
            newIndexRegistryImpl,
            newStakeRegistryImpl
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
            eigenDAData.addresses.indexRegistry != address(0),
            "Index Registry should be deployed"
        );
        require(
            eigenDAData.addresses.stakeRegistry != address(0),
            "Stake Registry should be deployed"
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

    function _deployNewImplementations() internal {
        /// TODO: Placeholder for upgrading
    }

    function _setupEigenDAFork(
        string memory jsonPath
    ) internal returns (EigenDAData memory) {
        // Get the Holesky RPC URL from environment variables
        string memory rpcUrl = vm.envString("HOLESKY_RPC_URL");

        vm.createSelectFork(rpcUrl);

        EigenDAData memory data = _readEigenDADeploymentJson(jsonPath, 17000);

        vm.rollFork(data.chainInfo.deploymentBlock);

        return data;
    }

    function _performUpgrades(
        address newRegistryCoordinator,
        address newServiceManager,
        address newBlsApkRegistry,
        address newIndexRegistry,
        address newStakeRegistry
    ) internal {
        // Impersonate the upgrader account
        vm.startPrank(eigenDAData.permissions.eigenDAUpgrader);

        // Upgrade each contract using the proxyAdmin
        if (newRegistryCoordinator != address(0)) {
            UpgradeableProxyLib.upgrade(
                eigenDAData.addresses.registryCoordinator,
                newRegistryCoordinator
            );
        }

        if (newServiceManager != address(0)) {
            UpgradeableProxyLib.upgrade(
                eigenDAData.addresses.eigenDAServiceManager,
                newServiceManager
            );
        }

        if (newBlsApkRegistry != address(0)) {
            UpgradeableProxyLib.upgrade(
                eigenDAData.addresses.blsApkRegistry,
                newBlsApkRegistry
            );
        }

        if (newIndexRegistry != address(0)) {
            UpgradeableProxyLib.upgrade(
                eigenDAData.addresses.indexRegistry,
                newIndexRegistry
            );
        }

        if (newStakeRegistry != address(0)) {
            UpgradeableProxyLib.upgrade(
                eigenDAData.addresses.stakeRegistry,
                newStakeRegistry
            );
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
        data.addresses.operatorStateRetriever = json.readAddress(".addresses.operatorStateRetriever");
        data.addresses.registryCoordinator = json.readAddress(".addresses.registryCoordinator");
        data.addresses.serviceManagerRouter = json.readAddress(".addresses.serviceManagerRouter");
        data.addresses.stakeRegistry = json.readAddress(".addresses.stakeRegistry");

        // Parse chainInfo section
        data.chainInfo.chainId = json.readUint(".chainInfo.chainId");
        data.chainInfo.deploymentBlock = json.readUint(".chainInfo.deploymentBlock");

        // Parse permissions section
        data.permissions.eigenDABatchConfirmer = json.readAddress(".permissions.eigenDABatchConfirmer");
        data.permissions.eigenDAChurner = json.readAddress(".permissions.eigenDAChurner");
        data.permissions.eigenDAEjector = json.readAddress(".permissions.eigenDAEjector");
        data.permissions.eigenDAOwner = json.readAddress(".permissions.eigenDAOwner");
        data.permissions.eigenDAUpgrader = json.readAddress(".permissions.eigenDAUpgrader");
        data.permissions.pauserRegistry = json.readAddress(".permissions.pauserRegistry");

        return data;
    }
}

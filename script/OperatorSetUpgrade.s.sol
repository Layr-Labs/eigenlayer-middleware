// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import {OperatorSetUpgradeLib} from "./utils/UpgradeLib.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ServiceManagerMock, IServiceManager} from "../test/mocks/ServiceManagerMock.sol";
import {StakeRegistry, IStakeRegistry} from "../src/StakeRegistry.sol";
import {RegistryCoordinator, IRegistryCoordinator} from "../src/RegistryCoordinator.sol";
import {AVSDirectory} from "eigenlayer-contracts/src/contracts/core/AVSDirectory.sol";
import {IBLSApkRegistry} from "../src/interfaces/IBLSApkRegistry.sol";
import {IIndexRegistry} from "../src/interfaces/IIndexRegistry.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
interface IServiceManagerMigration {
    function getOperatorsToMigrate()
        external
        view
        returns (
            uint32[] memory operatorSetIdsToCreate,
            uint32[][] memory operatorSetIds,
            address[] memory allOperators
        );
    function migrateAndCreateOperatorSetIds(uint32[] memory operatorSetsToCreate) external;
    function migrateToOperatorSets(uint32[][] memory operatorSetIds, address[] memory operators) external;
    function finalizeMigration() external;
    function migrationFinalized() external returns (bool);
}


import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract OperatorSetUpgradeScript is Script {
    using stdJson for string;

    address private constant DEFAULT_FORGE_SENDER = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    address public proxyAdminOwner;
    address public serviceManagerOwner;
    address public serviceManager;
    address public stakeRegistry;
    address public registryCoordinator;
    address public avsDirectory;
    address public rewardsCoordinator;
    address public delegationManager;
    address public blsApkRegistry;
    address public indexRegistry;

    function setUp() public {
        vm.label(DEFAULT_FORGE_SENDER, "DEFAULT FORGE SENDER");

        // Note: Ensure that the following environment variables are set before running the script:
        // - PROXY_ADMIN_OWNER: The private key of the proxy admin owner.
        // - SERVICE_MANAGER_OWNER: The private key of the service manager owner.
        // These environment variables are crucial for the proper execution of the upgrade and migration processes.
        /// TODO: improve DEVX of gnosis safe.  Would like to do an tx service integration for SafeAPI
        proxyAdminOwner = vm.rememberKey(vm.envUint("PROXY_ADMIN_OWNER"));
        serviceManagerOwner = vm.rememberKey(vm.envUint("PROXY_ADMIN_OWNER"));

        string memory middlewareJson = vm.readFile(vm.envString("MIDDLEWARE_JSON_PATH"));
        string memory coreJson = vm.readFile(vm.envString("CORE_JSON_PATH"));

        /*
         * Note: Ensure that the structure of the configuration JSON files matches the structure 
         * of `core_testdata.json`. If you rename any of the files, you will need to update the 
         * corresponding key values in the code.
         */
        loadAddressesSetup(middlewareJson, coreJson);
        labelAndLogAddressesSetup();
    }

    function run() public {
        vm.startBroadcast(proxyAdminOwner);

        _upgrade();

        vm.stopBroadcast();

        vm.startBroadcast(serviceManagerOwner);

        _migrateToOperatorSets();

        vm.stopBroadcast();
    }
    // forge script script/OperatorSetUpgrade.s.sol --sig "simulateUpgrade()" -vvv
    function simulateUpgrade() public {

        address proxyAdmin = OperatorSetUpgradeLib.getAdmin(serviceManager);
        proxyAdminOwner = Ownable(proxyAdmin).owner();
        vm.startPrank(proxyAdminOwner);

        _upgrade();

        vm.stopPrank();

    }

    // forge script script/OperatorSetUpgrade.s.sol --sig "simulateMigrate()" -vvv
    function simulateMigrate() public {
        _upgradeAvsDirectory(); /// Workaround since this isn't on pre-prod yet

        serviceManagerOwner = Ownable(serviceManager).owner();
        vm.startPrank(serviceManagerOwner);

        _migrateToOperatorSets();

        vm.stopPrank();
    }

    // forge script script/OperatorSetUpgrade.s.sol --sig "simulateUpgradeAndMigrate()" -vvv
    function simulateUpgradeAndMigrate() public {
        _upgradeAvsDirectory(); /// Workaround since this isn't on pre-prod yet

        address proxyAdmin = OperatorSetUpgradeLib.getAdmin(serviceManager);
        proxyAdminOwner = Ownable(proxyAdmin).owner();

        console2.log(proxyAdminOwner, "Pranker");
        vm.startPrank(proxyAdminOwner);

        _upgrade();

        vm.stopPrank();

        serviceManagerOwner = Ownable(serviceManager).owner();
        vm.startPrank(serviceManagerOwner);

        _migrateToOperatorSets();

        vm.stopPrank();

        // Assert that serviceManager is an operatorSetAVS
        require(
            IAVSDirectory(avsDirectory).isOperatorSetAVS(serviceManager),
            "simulateUpgradeAndMigrate: serviceManager is not an operatorSetAVS"
        );

        // Assert that the migration is finalized
        require(
            IServiceManagerMigration(serviceManager).migrationFinalized(),
            "simulateUpgradeAndMigrate: Migration is not finalized"
        );
    }

    function _upgradeAvsDirectory() internal {
        address proxyAdmin = OperatorSetUpgradeLib.getAdmin(avsDirectory);
        address avsDirectoryOwner = Ownable(proxyAdmin).owner();
        AVSDirectory avsDirectoryImpl = new AVSDirectory(IDelegationManager(delegationManager), 0); // TODO: config

        vm.startPrank(avsDirectoryOwner);
        OperatorSetUpgradeLib.upgrade(avsDirectory, address(avsDirectoryImpl));
        vm.stopPrank();
    }

    function labelAndLogAddressesSetup() internal virtual {
        vm.label(proxyAdminOwner, "Proxy Admin Owner Account");
        vm.label(serviceManagerOwner, "Service Manager Owner Account");
        vm.label(serviceManager, "Service Manager Proxy");
        vm.label(stakeRegistry, "Stake Registry Proxy");
        vm.label(registryCoordinator, "Registry Coordinator Proxy");
        vm.label(indexRegistry, "Index Registry Proxy");
        vm.label(blsApkRegistry, "BLS APK Registry Proxy");
        vm.label(avsDirectory, "AVS Directory Proxy");
        vm.label(delegationManager, "Delegation Manager Proxy");
        vm.label(rewardsCoordinator, "Rewards Coordinator Proxy");

        console2.log("Proxy Admin Owner Account", proxyAdminOwner);
        console2.log("ServiceManager Owner Account", serviceManagerOwner);
        console2.log("Service Manager:", serviceManager);
        console2.log("Stake Registry:", stakeRegistry);
        console2.log("Registry Coordinator:", registryCoordinator);
        console2.log("Index Registry:", indexRegistry);
        console2.log("BLS APK Registry:", blsApkRegistry);
        console2.log("AVS Directory:", avsDirectory);
        console2.log("Delegation Manager:", delegationManager);
        console2.log("Rewards Coordinator:", rewardsCoordinator);

        address oldServiceManagerImpl = OperatorSetUpgradeLib.getImplementation(serviceManager);
        address oldStakeRegistryImpl = OperatorSetUpgradeLib.getImplementation(stakeRegistry);
        address oldRegistryCoordinatorImpl = OperatorSetUpgradeLib.getImplementation(registryCoordinator);
        address oldAvsDirectoryImpl = OperatorSetUpgradeLib.getImplementation(avsDirectory);
        address oldDelegationManagerImpl = OperatorSetUpgradeLib.getImplementation(delegationManager);

        vm.label(oldServiceManagerImpl, "Old Service Manager Implementation");
        vm.label(oldStakeRegistryImpl, "Old Stake Registry Implementation");
        vm.label(oldRegistryCoordinatorImpl, "Old Registry Coordinator Implementation");
        vm.label(oldAvsDirectoryImpl, "Old AVS Directory Implementation");
        vm.label(oldDelegationManagerImpl, "Old Delegation Manager Implementation");

        console2.log("Old Service Manager Implementation:", oldServiceManagerImpl);
        console2.log("Old Stake Registry Implementation:", oldStakeRegistryImpl);
        console2.log("Old Registry Coordinator Implementation:", oldRegistryCoordinatorImpl);
        console2.log("Old AVS Directory Implementation:", oldAvsDirectoryImpl);
        console2.log("Old Delegation Manager Implementation:", oldDelegationManagerImpl);
    }

    function loadAddressesSetup(string memory middlewareJson, string memory coreJson) internal virtual {
        serviceManager = middlewareJson.readAddress(".addresses.eigenDAServiceManager");
        stakeRegistry = middlewareJson.readAddress(".addresses.stakeRegistry");
        registryCoordinator = middlewareJson.readAddress(".addresses.registryCoordinator");
        blsApkRegistry = middlewareJson.readAddress(".addresses.blsApkRegistry");
        indexRegistry = middlewareJson.readAddress(".addresses.indexRegistry");

        avsDirectory = coreJson.readAddress(".addresses.avsDirectory");
        delegationManager = coreJson.readAddress(".addresses.delegationManager");
        rewardsCoordinator = coreJson.readAddress(".addresses.rewardsCoordinator");
    }

    function _upgrade() internal virtual {
        address newServiceManagerImpl = address(new ServiceManagerMock(
            IAVSDirectory(avsDirectory),
            IRewardsCoordinator(rewardsCoordinator),
            IRegistryCoordinator(registryCoordinator),
            IStakeRegistry(stakeRegistry)
        ));
        address newRegistryCoordinatorImpl = address(new RegistryCoordinator(
            IServiceManager(serviceManager),
            IStakeRegistry(stakeRegistry),
            IBLSApkRegistry(blsApkRegistry),
            IIndexRegistry(indexRegistry),
            IAVSDirectory(avsDirectory)
        ));
        address newStakeRegistryImpl = address(new StakeRegistry(
            IRegistryCoordinator(registryCoordinator),
            IDelegationManager(delegationManager),
            IAVSDirectory(avsDirectory),
            IServiceManager(serviceManager)
        ));

        console2.log("New Service Manager Implementation:", newServiceManagerImpl);
        console2.log("New Registry Coordinator Implementation:", newRegistryCoordinatorImpl);
        console2.log("New Stake Registry Implementation:", newStakeRegistryImpl);

        vm.label(newServiceManagerImpl, "New Service Manager Implementation");
        vm.label(newRegistryCoordinatorImpl, "New Registry Coordinator Implementation");
        vm.label(newStakeRegistryImpl, "New Stake Registry Implementation");

        OperatorSetUpgradeLib.upgrade(serviceManager, newServiceManagerImpl);
        OperatorSetUpgradeLib.upgrade(registryCoordinator, newRegistryCoordinatorImpl);
        OperatorSetUpgradeLib.upgrade(stakeRegistry, newStakeRegistryImpl);
    }

    function _migrateToOperatorSets() internal virtual {
        IServiceManagerMigration serviceManager = IServiceManagerMigration(serviceManager);
        (
            uint32[] memory operatorSetsToCreate,
            uint32[][] memory operatorSetIdsToMigrate,
            address[] memory operators
        ) = serviceManager.getOperatorsToMigrate();
    
        serviceManager.migrateAndCreateOperatorSetIds(operatorSetsToCreate);
        serviceManager.migrateToOperatorSets(operatorSetIdsToMigrate, operators);
        serviceManager.finalizeMigration();
    }
}
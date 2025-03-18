// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {PermissionController} from
    "eigenlayer-contracts/src/contracts/permissions/PermissionController.sol";
import {InstantSlasher} from "../../src/slashers/InstantSlasher.sol";
import {SlashingRegistryCoordinator} from "../../src/SlashingRegistryCoordinator.sol";
import {SocketRegistry} from "../../src/SocketRegistry.sol";
import {IndexRegistry} from "../../src/IndexRegistry.sol";
import {StakeRegistry} from "../../src/StakeRegistry.sol";
import {BLSApkRegistry} from "../../src/BLSApkRegistry.sol";
import {IStakeRegistry, IStakeRegistryTypes} from "../../src/interfaces/IStakeRegistry.sol";
import {IBLSApkRegistry} from "../../src/interfaces/IBLSApkRegistry.sol";
import {IIndexRegistry} from "../../src/interfaces/IIndexRegistry.sol";
import {ISocketRegistry} from "../../src/interfaces/ISocketRegistry.sol";
import {ISlashingRegistryCoordinator} from "../../src/interfaces/ISlashingRegistryCoordinator.sol";

import {UpgradeableProxyLib} from "../unit/UpgradeableProxyLib.sol";
import {OperatorStateRetriever} from "../../src/OperatorStateRetriever.sol";
import {
    PauserRegistry,
    IPauserRegistry
} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import {ServiceManagerMock} from "../mocks/ServiceManagerMock.sol";
import {CoreDeployLib} from "./CoreDeployLib.sol";
import {
    RegistryCoordinator,
    IRegistryCoordinator,
    IRegistryCoordinatorTypes
} from "../../src/RegistryCoordinator.sol";
import {IRewardsCoordinator} from
    "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {IServiceManager} from "../../src/interfaces/IServiceManager.sol";

library MiddlewareDeployLib {
    using UpgradeableProxyLib for address;

    struct InstantSlasherConfig {
        address initialOwner;
        address slasher;
    }

    struct SlashingRegistryCoordinatorConfig {
        address initialOwner;
        address churnApprover;
        address ejector;
        uint256 initPausedStatus;
        address serviceManager;
    }

    struct SocketRegistryConfig {
        address initialOwner;
    }

    struct IndexRegistryConfig {
        address initialOwner;
    }

    struct StakeRegistryConfig {
        address initialOwner;
        uint256 minimumStake;
        uint32 strategyParams;
        address delegationManager;
        address avsDirectory;
        IStakeRegistryTypes.StrategyParams[] strategyParamsArray;
        uint32 lookAheadPeriod;
        IStakeRegistryTypes.StakeType stakeType;
    }

    struct BLSApkRegistryConfig {
        address initialOwner;
    }

    struct MiddlewareDeployConfig {
        InstantSlasherConfig instantSlasher;
        SlashingRegistryCoordinatorConfig slashingRegistryCoordinator;
        SocketRegistryConfig socketRegistry;
        IndexRegistryConfig indexRegistry;
        StakeRegistryConfig stakeRegistry;
        BLSApkRegistryConfig blsApkRegistry;
    }

    struct MiddlewareDeployData {
        address instantSlasher;
        address slashingRegistryCoordinator;
        address socketRegistry;
        address indexRegistry;
        address stakeRegistry;
        address blsApkRegistry;
        address operatorStateRetriever;
        address registryCoordinator;
        address serviceManager;
        address pauserRegistry;
        address permissionController;
    }

    function deployMiddleware(
        address proxyAdmin,
        address allocationManager,
        address pauserRegistry,
        MiddlewareDeployConfig memory config
    ) internal returns (MiddlewareDeployData memory result) {
        result = deployEmptyProxies(proxyAdmin);

        upgradeRegistries(result, allocationManager, pauserRegistry, config);
        upgradeCoordinator(
            result, allocationManager, pauserRegistry, config.slashingRegistryCoordinator
        );
        upgradeInstantSlasher(result, allocationManager, config.instantSlasher);

        return result;
    }

    function deployEmptyProxies(
        address proxyAdmin
    ) internal returns (MiddlewareDeployData memory proxies) {
        proxies.instantSlasher = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.slashingRegistryCoordinator = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.registryCoordinator = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.socketRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.indexRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.stakeRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.blsApkRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.serviceManager = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        return proxies;
    }

    function upgradeRegistries(
        MiddlewareDeployData memory deployments,
        address allocationManager,
        address pauserRegistry,
        MiddlewareDeployConfig memory config
    ) internal {
        address blsApkRegistryImpl = address(
            new BLSApkRegistry(
                ISlashingRegistryCoordinator(deployments.slashingRegistryCoordinator)
            )
        );
        UpgradeableProxyLib.upgrade(deployments.blsApkRegistry, blsApkRegistryImpl);

        address indexRegistryImpl = address(
            new IndexRegistry(ISlashingRegistryCoordinator(deployments.slashingRegistryCoordinator))
        );
        UpgradeableProxyLib.upgrade(deployments.indexRegistry, indexRegistryImpl);

        address socketRegistryImpl = address(
            new SocketRegistry(
                ISlashingRegistryCoordinator(deployments.slashingRegistryCoordinator)
            )
        );
        UpgradeableProxyLib.upgrade(deployments.socketRegistry, socketRegistryImpl);

        // StakeRegistry upgrade
        address stakeRegistryImpl = address(
            new StakeRegistry(
                ISlashingRegistryCoordinator(deployments.slashingRegistryCoordinator),
                IDelegationManager(config.stakeRegistry.delegationManager),
                IAVSDirectory(config.stakeRegistry.avsDirectory),
                IAllocationManager(allocationManager)
            )
        );
        UpgradeableProxyLib.upgrade(deployments.stakeRegistry, stakeRegistryImpl);
    }

    function upgradeRegistriesM2Coordinator(
        address delegationManager,
        address avsDirectory,
        address allocationManager,
        MiddlewareDeployData memory deployments
    ) internal {
        address stakeRegistryImpl = address(
            new StakeRegistry(
                IRegistryCoordinator(deployments.registryCoordinator),
                IDelegationManager(delegationManager),
                IAVSDirectory(avsDirectory),
                IAllocationManager(allocationManager)
            )
        );
        UpgradeableProxyLib.upgrade(deployments.stakeRegistry, stakeRegistryImpl);

        address blsApkRegistryImpl =
            address(new BLSApkRegistry(IRegistryCoordinator(deployments.registryCoordinator)));
        UpgradeableProxyLib.upgrade(deployments.blsApkRegistry, blsApkRegistryImpl);

        address indexRegistryImpl =
            address(new IndexRegistry(IRegistryCoordinator(deployments.registryCoordinator)));
        UpgradeableProxyLib.upgrade(deployments.indexRegistry, indexRegistryImpl);

        address socketRegistryImpl =
            address(new SocketRegistry(IRegistryCoordinator(deployments.registryCoordinator)));
        UpgradeableProxyLib.upgrade(deployments.socketRegistry, socketRegistryImpl);
    }

    function upgradeServiceManager(
        address avsDirectory,
        address rewardsCoordinator,
        address allocationManager,
        MiddlewareDeployData memory deployment,
        address admin
    ) internal {
        address impl = address(
            new ServiceManagerMock(
                IAVSDirectory(avsDirectory),
                IRewardsCoordinator(rewardsCoordinator),
                IRegistryCoordinator(deployment.registryCoordinator),
                IStakeRegistry(deployment.stakeRegistry),
                IPermissionController(deployment.permissionController),
                IAllocationManager(allocationManager)
            )
        );
        bytes memory serviceManagerUpgradeCall =
            abi.encodeCall(ServiceManagerMock.initialize, (admin, admin));

        UpgradeableProxyLib.upgradeAndCall(
            deployment.serviceManager, impl, serviceManagerUpgradeCall
        );
    }

    function upgradeServiceManager(
        CoreDeployLib.DeploymentData memory core,
        MiddlewareDeployData memory deployment,
        address admin
    ) internal {
        address impl = address(
            new ServiceManagerMock(
                IAVSDirectory(core.avsDirectory),
                IRewardsCoordinator(core.rewardsCoordinator),
                IRegistryCoordinator(deployment.registryCoordinator),
                IStakeRegistry(deployment.stakeRegistry),
                IPermissionController(deployment.permissionController),
                IAllocationManager(core.allocationManager)
            )
        );
        bytes memory serviceManagerUpgradeCall =
            abi.encodeCall(ServiceManagerMock.initialize, (admin, admin));

        UpgradeableProxyLib.upgradeAndCall(
            deployment.serviceManager, impl, serviceManagerUpgradeCall
        );
    }

    function upgradeM2Coordinator(
        address allocationManager,
        MiddlewareDeployData memory deployment,
        address admin
    ) internal {
        IRegistryCoordinatorTypes.SlashingRegistryParams memory slashingParams =
        IRegistryCoordinatorTypes.SlashingRegistryParams({
            stakeRegistry: IStakeRegistry(deployment.stakeRegistry),
            blsApkRegistry: IBLSApkRegistry(deployment.blsApkRegistry),
            indexRegistry: IIndexRegistry(deployment.indexRegistry),
            socketRegistry: ISocketRegistry(deployment.socketRegistry),
            allocationManager: IAllocationManager(allocationManager),
            pauserRegistry: IPauserRegistry(deployment.pauserRegistry)
        });

        IRegistryCoordinatorTypes.RegistryCoordinatorParams memory params =
        IRegistryCoordinatorTypes.RegistryCoordinatorParams({
            serviceManager: IServiceManager(deployment.serviceManager),
            slashingParams: slashingParams
        });

        address impl = address(new RegistryCoordinator(params));
        bytes memory registryCoordinatorUpgradeCall = abi.encodeCall(
            SlashingRegistryCoordinator.initialize,
            (admin, admin, admin, 0, deployment.serviceManager)
        );

        UpgradeableProxyLib.upgradeAndCall(
            deployment.registryCoordinator, impl, registryCoordinatorUpgradeCall
        );
    }

    function upgradeCoordinator(
        MiddlewareDeployData memory deployments,
        address allocationManager,
        address pauserRegistry,
        SlashingRegistryCoordinatorConfig memory coordinatorConfig
    ) internal {
        address coordinatorImpl = address(
            new SlashingRegistryCoordinator(
                IStakeRegistry(deployments.stakeRegistry),
                IBLSApkRegistry(deployments.blsApkRegistry),
                IIndexRegistry(deployments.indexRegistry),
                ISocketRegistry(deployments.socketRegistry),
                IAllocationManager(allocationManager),
                IPauserRegistry(pauserRegistry),
                "v0.0.1"
            )
        );
        bytes memory upgradeCall = abi.encodeCall(
            SlashingRegistryCoordinator.initialize,
            (
                coordinatorConfig.initialOwner,
                coordinatorConfig.churnApprover,
                coordinatorConfig.ejector,
                coordinatorConfig.initPausedStatus,
                coordinatorConfig.serviceManager
            )
        );
        UpgradeableProxyLib.upgradeAndCall(
            deployments.slashingRegistryCoordinator, coordinatorImpl, upgradeCall
        );
    }

    // Upgrade and initialize InstantSlasher with its config data
    function upgradeInstantSlasher(
        MiddlewareDeployData memory deployments,
        address allocationManager,
        InstantSlasherConfig memory slasherConfig
    ) internal {
        address instantSlasherImpl = address(
            new InstantSlasher(
                IAllocationManager(allocationManager),
                ISlashingRegistryCoordinator(deployments.slashingRegistryCoordinator),
                slasherConfig.slasher
            )
        );
        UpgradeableProxyLib.upgrade(deployments.instantSlasher, instantSlasherImpl);
    }

    function deployPauserRegistry(
        address admin
    ) internal returns (address) {
        address[] memory pausers = new address[](2);
        pausers[0] = admin;
        pausers[1] = admin;
        return address(new PauserRegistry(pausers, admin));
    }
}

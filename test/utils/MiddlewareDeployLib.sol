// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

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
        proxies.socketRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.indexRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.stakeRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.blsApkRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
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
                IPauserRegistry(pauserRegistry)
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
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
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
        uint256 initPausedStatus;
        address initialOwner;
        address churnApprover;
        address ejector;
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

    struct DeploymentConfigData {
        InstantSlasherConfig instantSlasher;
        SlashingRegistryCoordinatorConfig slashingRegistryCoordinator;
        SocketRegistryConfig socketRegistry;
        IndexRegistryConfig indexRegistry;
        StakeRegistryConfig stakeRegistry;
        BLSApkRegistryConfig blsApkRegistry;
    }

    struct DeploymentData {
        address instantSlasher;
        address slashingRegistryCoordinator;
        address socketRegistry;
        address indexRegistry;
        address stakeRegistry;
        address blsApkRegistry;
    }

    function deployContracts(
        address proxyAdmin,
        address allocationManager,
        address pauserRegistry,
        DeploymentConfigData memory configData
    ) internal returns (DeploymentData memory result) {
        result = deployEmptyProxies(proxyAdmin);

        // First, deploy and configure registries
        deployAndConfigureRegistries(
            result,
            allocationManager,
            pauserRegistry,
            configData
        );

        // Now, deploy and initialize SlashingRegistryCoordinator
        address slashingRegistryCoordinatorImpl = address(
            new SlashingRegistryCoordinator(
                IStakeRegistry(result.stakeRegistry),
                IBLSApkRegistry(result.blsApkRegistry),
                IIndexRegistry(result.indexRegistry),
                ISocketRegistry(result.socketRegistry),
                IAllocationManager(allocationManager),
                IPauserRegistry(pauserRegistry)
            )
        );
        bytes memory upgradeCall = abi.encodeCall(
            SlashingRegistryCoordinator.initialize,
            (
                configData.slashingRegistryCoordinator.initialOwner,
                configData.slashingRegistryCoordinator.churnApprover,
                configData.slashingRegistryCoordinator.ejector,
                configData.slashingRegistryCoordinator.initPausedStatus,
                configData.slashingRegistryCoordinator.serviceManager
            )
        );
        UpgradeableProxyLib.upgradeAndCall(
            result.slashingRegistryCoordinator,
            slashingRegistryCoordinatorImpl,
            upgradeCall
        );

        deployAndConfigureSlasher(result, allocationManager, configData);

        return result;
    }

    function deployEmptyProxies(address proxyAdmin) internal returns (DeploymentData memory proxies) {
        proxies.instantSlasher = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.slashingRegistryCoordinator = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.socketRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.indexRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.stakeRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.blsApkRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        return proxies;
    }

    function deployAndConfigureRegistries(
        DeploymentData memory deployments,
        address allocationManager,
        address pauserRegistry,
        DeploymentConfigData memory config
    ) internal {
        address blsApkRegistryImpl = address(
            new BLSApkRegistry(
                ISlashingRegistryCoordinator(deployments.slashingRegistryCoordinator)
            )
        );
        UpgradeableProxyLib.upgrade(deployments.blsApkRegistry, blsApkRegistryImpl);

        address indexRegistryImpl = address(
            new IndexRegistry(
                ISlashingRegistryCoordinator(deployments.slashingRegistryCoordinator)
            )
        );
        UpgradeableProxyLib.upgrade(deployments.indexRegistry, indexRegistryImpl);

        address socketRegistryImpl = address(
            new SocketRegistry(
                ISlashingRegistryCoordinator(deployments.slashingRegistryCoordinator)
            )
        );
        UpgradeableProxyLib.upgrade(deployments.socketRegistry, socketRegistryImpl);

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

    function deployAndConfigureSlasher(
        DeploymentData memory deployments,
        address allocationManager,
        DeploymentConfigData memory config
    ) internal {
        address instantSlasherImpl = address(
            new InstantSlasher(
                IAllocationManager(allocationManager),
                ISlashingRegistryCoordinator(deployments.slashingRegistryCoordinator),
                config.instantSlasher.slasher
            )
        );

        bytes memory upgradeCall = abi.encodeCall(
            InstantSlasher.initialize,
            (config.instantSlasher.slasher)
        );
        UpgradeableProxyLib.upgradeAndCall(
            deployments.instantSlasher,
            instantSlasherImpl,
            upgradeCall
        );
    }
}
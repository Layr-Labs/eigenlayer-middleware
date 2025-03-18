// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {DelegationManager} from "eigenlayer-contracts/src/contracts/core/DelegationManager.sol";
import {StrategyManager} from "eigenlayer-contracts/src/contracts/core/StrategyManager.sol";
import {AVSDirectory} from "eigenlayer-contracts/src/contracts/core/AVSDirectory.sol";
import {EigenPodManager} from "eigenlayer-contracts/src/contracts/pods/EigenPodManager.sol";
import {RewardsCoordinator} from "eigenlayer-contracts/src/contracts/core/RewardsCoordinator.sol";
import {StrategyBase} from "eigenlayer-contracts/src/contracts/strategies/StrategyBase.sol";
import {EigenPod} from "eigenlayer-contracts/src/contracts/pods/EigenPod.sol";
import {IETHPOSDeposit} from "eigenlayer-contracts/src/contracts/interfaces/IETHPOSDeposit.sol";
import {StrategyBaseTVLLimits} from
    "eigenlayer-contracts/src/contracts/strategies/StrategyBaseTVLLimits.sol";
import {PauserRegistry} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IEigenPodManager} from "eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {StrategyFactory} from "eigenlayer-contracts/src/contracts/strategies/StrategyFactory.sol";
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {AllocationManager} from "eigenlayer-contracts/src/contracts/core/AllocationManager.sol";
import {PermissionController} from
    "eigenlayer-contracts/src/contracts/permissions/PermissionController.sol";
import {IRewardsCoordinatorTypes} from
    "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";

import {UpgradeableProxyLib} from "../unit/UpgradeableProxyLib.sol";

library CoreDeployLib {
    using stdJson for string;
    using UpgradeableProxyLib for address;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct StrategyManagerConfig {
        uint256 initPausedStatus;
        address initialOwner;
        address initialStrategyWhitelister;
    }

    struct DelegationManagerConfig {
        uint256 initPausedStatus;
        address initialOwner;
        uint32 minWithdrawalDelayBlocks;
    }

    struct EigenPodManagerConfig {
        uint256 initPausedStatus;
        address initialOwner;
    }

    struct AllocationManagerConfig {
        uint256 initPausedStatus;
        address initialOwner;
        uint32 deallocationDelay;
        uint32 allocationConfigurationDelay;
    }

    struct StrategyFactoryConfig {
        uint256 initPausedStatus;
        address initialOwner;
    }

    struct AVSDirectoryConfig {
        uint256 initPausedStatus;
        address initialOwner;
    }

    struct RewardsCoordinatorConfig {
        uint256 initPausedStatus;
        address initialOwner;
        address rewardsUpdater;
        uint32 activationDelay;
        uint16 defaultSplitBips;
        uint32 calculationIntervalSeconds;
        uint32 maxRewardsDuration;
        uint32 maxRetroactiveLength;
        uint32 maxFutureLength;
        uint32 genesisRewardsTimestamp;
    }

    struct ETHPOSDepositConfig {
        address ethPOSDepositAddress;
    }

    struct EigenPodConfig {
        uint64 genesisTimestamp;
    }

    struct DeploymentConfigData {
        StrategyManagerConfig strategyManager;
        DelegationManagerConfig delegationManager;
        EigenPodManagerConfig eigenPodManager;
        AllocationManagerConfig allocationManager;
        StrategyFactoryConfig strategyFactory;
        RewardsCoordinatorConfig rewardsCoordinator;
        AVSDirectoryConfig avsDirectory;
        ETHPOSDepositConfig ethPOSDeposit;
        EigenPodConfig eigenPod;
    }

    struct DeploymentData {
        address delegationManager;
        address avsDirectory;
        address strategyManager;
        address eigenPodManager;
        address allocationManager;
        address eigenPodBeacon;
        address pauserRegistry;
        address strategyFactory;
        address strategyBeacon;
        address rewardsCoordinator;
        address permissionController;
    }

    function deployContracts(
        address proxyAdmin,
        DeploymentConfigData memory configData
    ) internal returns (DeploymentData memory result) {
        result = deployEmptyProxies(proxyAdmin);

        deployAndConfigureCore(result, configData);
        deployAndConfigurePods(result, configData);
        deployAndConfigureStrategies(result, configData);
        deployAndConfigureRewards(result, configData);

        return result;
    }

    function deployEmptyProxies(
        address proxyAdmin
    ) internal returns (DeploymentData memory proxies) {
        proxies.delegationManager = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.avsDirectory = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.strategyManager = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.eigenPodManager = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.allocationManager = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.eigenPodBeacon = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.pauserRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.strategyFactory = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.rewardsCoordinator = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        proxies.permissionController = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        return proxies;
    }

    function deployAndConfigureCore(
        DeploymentData memory deployments,
        DeploymentConfigData memory config
    ) internal {
        // Deploy core implementations
        address permissionControllerImpl = address(new PermissionController("1.0.0"));

        address strategyManagerImpl = address(
            new StrategyManager(
                IDelegationManager(deployments.delegationManager),
                IPauserRegistry(deployments.pauserRegistry),
                "1.0.0"
            )
        );

        address allocationManagerImpl = address(
            new AllocationManager(
                IDelegationManager(deployments.delegationManager),
                IPauserRegistry(deployments.pauserRegistry),
                IPermissionController(deployments.permissionController),
                config.allocationManager.deallocationDelay,
                config.allocationManager.allocationConfigurationDelay,
                "1.0.0"
            )
        );

        address delegationManagerImpl = address(
            new DelegationManager(
                IStrategyManager(deployments.strategyManager),
                IEigenPodManager(deployments.eigenPodManager),
                IAllocationManager(deployments.allocationManager),
                IPauserRegistry(deployments.pauserRegistry),
                IPermissionController(deployments.permissionController),
                config.delegationManager.minWithdrawalDelayBlocks,
                "1.0.0"
            )
        );

        address avsDirectoryImpl = address(
            new AVSDirectory(
                IDelegationManager(deployments.delegationManager),
                IPauserRegistry(deployments.pauserRegistry),
                "1.0.0"
            )
        );

        // Initialize core contracts
        UpgradeableProxyLib.upgrade(deployments.permissionController, permissionControllerImpl);

        bytes memory upgradeCall = abi.encodeCall(
            StrategyManager.initialize,
            (
                config.strategyManager.initialOwner,
                config.strategyManager.initialStrategyWhitelister,
                config.strategyManager.initPausedStatus
            )
        );
        UpgradeableProxyLib.upgradeAndCall(
            deployments.strategyManager, strategyManagerImpl, upgradeCall
        );

        upgradeCall = abi.encodeCall(
            DelegationManager.initialize,
            (config.delegationManager.initialOwner, config.delegationManager.initPausedStatus)
        );
        UpgradeableProxyLib.upgradeAndCall(
            deployments.delegationManager, delegationManagerImpl, upgradeCall
        );

        upgradeCall = abi.encodeCall(
            AllocationManager.initialize,
            (config.allocationManager.initialOwner, config.allocationManager.initPausedStatus)
        );
        UpgradeableProxyLib.upgradeAndCall(
            deployments.allocationManager, allocationManagerImpl, upgradeCall
        );

        upgradeCall = abi.encodeCall(
            AVSDirectory.initialize,
            (config.avsDirectory.initialOwner, config.avsDirectory.initPausedStatus)
        );
        UpgradeableProxyLib.upgradeAndCall(deployments.avsDirectory, avsDirectoryImpl, upgradeCall);
    }

    function deployAndConfigurePods(
        DeploymentData memory deployments,
        DeploymentConfigData memory config
    ) internal {
        address ethPOSDeposit = config.ethPOSDeposit.ethPOSDepositAddress;
        if (ethPOSDeposit == address(0)) {
            if (block.chainid == 1) {
                ethPOSDeposit = 0x00000000219ab540356cBB839Cbe05303d7705Fa;
            } else {
                revert("DEPLOY_MOCK_ETHPOS_CONTRACT");
            }
        }

        address eigenPodImpl = address(
            new EigenPod(
                IETHPOSDeposit(ethPOSDeposit),
                IEigenPodManager(deployments.eigenPodManager),
                config.eigenPod.genesisTimestamp == 0
                    ? uint64(block.timestamp)
                    : config.eigenPod.genesisTimestamp,
                "1.0.0"
            )
        );

        address eigenPodBeaconImpl = address(new UpgradeableBeacon(eigenPodImpl));
        UpgradeableProxyLib.upgrade(deployments.eigenPodBeacon, eigenPodBeaconImpl);

        address eigenPodManagerImpl = address(
            new EigenPodManager(
                IETHPOSDeposit(ethPOSDeposit),
                IBeacon(deployments.eigenPodBeacon),
                IDelegationManager(deployments.delegationManager),
                IPauserRegistry(deployments.pauserRegistry),
                "1.0.0"
            )
        );

        bytes memory upgradeCall = abi.encodeCall(
            EigenPodManager.initialize,
            (config.eigenPodManager.initialOwner, config.eigenPodManager.initPausedStatus)
        );
        UpgradeableProxyLib.upgradeAndCall(
            deployments.eigenPodManager, eigenPodManagerImpl, upgradeCall
        );
    }

    function deployAndConfigureStrategies(
        DeploymentData memory deployments,
        DeploymentConfigData memory config
    ) internal {
        address baseStrategyImpl = address(
            new StrategyBase(
                IStrategyManager(deployments.strategyManager),
                IPauserRegistry(deployments.pauserRegistry),
                "1.0.0"
            )
        );

        deployments.strategyBeacon = address(new UpgradeableBeacon(baseStrategyImpl));

        address strategyFactoryImpl = address(
            new StrategyFactory(
                IStrategyManager(deployments.strategyManager),
                IPauserRegistry(deployments.pauserRegistry),
                "1.0.0"
            )
        );

        bytes memory upgradeCall = abi.encodeCall(
            StrategyFactory.initialize,
            (
                config.strategyFactory.initialOwner,
                config.strategyFactory.initPausedStatus,
                IBeacon(deployments.strategyBeacon)
            )
        );
        UpgradeableProxyLib.upgradeAndCall(
            deployments.strategyFactory, strategyFactoryImpl, upgradeCall
        );
    }

    function deployAndConfigureRewards(
        DeploymentData memory deployments,
        DeploymentConfigData memory config
    ) internal {
        address rewardsCoordinatorImpl = address(
            new RewardsCoordinator(
                IRewardsCoordinatorTypes.RewardsCoordinatorConstructorParams({
                    delegationManager: IDelegationManager(deployments.delegationManager),
                    strategyManager: IStrategyManager(deployments.strategyManager),
                    allocationManager: IAllocationManager(deployments.allocationManager),
                    pauserRegistry: IPauserRegistry(deployments.pauserRegistry),
                    permissionController: IPermissionController(deployments.permissionController),
                    CALCULATION_INTERVAL_SECONDS: config.rewardsCoordinator.calculationIntervalSeconds,
                    MAX_REWARDS_DURATION: config.rewardsCoordinator.maxRewardsDuration,
                    MAX_RETROACTIVE_LENGTH: config.rewardsCoordinator.maxRetroactiveLength,
                    MAX_FUTURE_LENGTH: config.rewardsCoordinator.maxFutureLength,
                    GENESIS_REWARDS_TIMESTAMP: config.rewardsCoordinator.genesisRewardsTimestamp,
                    version: "1.0.0"
                })
            )
        );

        bytes memory upgradeCall = abi.encodeCall(
            RewardsCoordinator.initialize,
            (
                config.rewardsCoordinator.initialOwner,
                config.rewardsCoordinator.initPausedStatus,
                config.rewardsCoordinator.rewardsUpdater,
                config.rewardsCoordinator.activationDelay,
                config.rewardsCoordinator.defaultSplitBips
            )
        );

        UpgradeableProxyLib.upgradeAndCall(
            deployments.rewardsCoordinator, rewardsCoordinatorImpl, upgradeCall
        );
    }
}

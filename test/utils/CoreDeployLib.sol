// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {DelegationManager} from "eigenlayer-contracts/src/contracts/core/DelegationManager.sol";
import {StrategyManager} from "eigenlayer-contracts/src/contracts/core/StrategyManager.sol";
import {AVSDirectory} from "eigenlayer-contracts/src/contracts/core/AVSDirectory.sol";
import {EigenPodManager} from "eigenlayer-contracts/src/contracts/pods/EigenPodManager.sol";
import {RewardsCoordinator} from "eigenlayer-contracts/src/contracts/core/RewardsCoordinator.sol";
import {StrategyBase} from "eigenlayer-contracts/src/contracts/strategies/StrategyBase.sol";
import {EigenPod} from "eigenlayer-contracts/src/contracts/pods/EigenPod.sol";
import {IETHPOSDeposit} from "eigenlayer-contracts/src/contracts/interfaces/IETHPOSDeposit.sol";
import {StrategyBaseTVLLimits} from "eigenlayer-contracts/src/contracts/strategies/StrategyBaseTVLLimits.sol";
import {PauserRegistry} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IEigenPodManager} from "eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {StrategyFactory} from "eigenlayer-contracts/src/contracts/strategies/StrategyFactory.sol";
import {IPermissionController} from "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {AllocationManager} from "eigenlayer-contracts/src/contracts/core/AllocationManager.sol";
import {PermissionController} from "eigenlayer-contracts/src/contracts/permissions/PermissionController.sol";

import {UpgradeableProxyLib} from "../unit/UpgradeableProxyLib.sol";

library CoreDeploymentLib {
    using UpgradeableProxyLib for address;

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

    struct DeploymentConfigData {
        StrategyManagerConfig strategyManager;
        DelegationManagerConfig delegationManager;
        EigenPodManagerConfig eigenPodManager;
        AllocationManagerConfig allocationManager;
        StrategyFactoryConfig strategyFactory;
        RewardsCoordinatorConfig rewardsCoordinator;
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
    ) internal returns (DeploymentData memory) {
        DeploymentData memory result;

        // Deploy proxy contracts
        result.delegationManager = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.avsDirectory = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.strategyManager = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.eigenPodManager = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.allocationManager = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.eigenPodBeacon = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.pauserRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.strategyFactory = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.rewardsCoordinator = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.permissionController = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);

        // Deploy implementation contracts
        address permissionControllerImpl = address(new PermissionController());


        address strategyManagerImpl = address(
            new StrategyManager(
                IDelegationManager(result.delegationManager),
                IPauserRegistry(result.pauserRegistry)
            )
        );

        address allocationManagerImpl = address(
            new AllocationManager(
                IDelegationManager(result.delegationManager),
                IPauserRegistry(result.pauserRegistry),
                IPermissionController(result.permissionController),
                configData.allocationManager.deallocationDelay,
                configData.allocationManager.allocationConfigurationDelay
            )
        );

        address delegationManagerImpl = address(
            new DelegationManager(
                IStrategyManager(result.strategyManager),
                IEigenPodManager(result.eigenPodManager),
                IAllocationManager(result.allocationManager),
                IPauserRegistry(result.pauserRegistry),
                IPermissionController(result.permissionController),
                configData.delegationManager.minWithdrawalDelayBlocks
            )
        );

        address avsDirectoryImpl = address(
            new AVSDirectory(
                IDelegationManager(result.delegationManager),
                IPauserRegistry(result.pauserRegistry)
            )
        );

        address ethPOSDeposit;
        if (block.chainid == 1) {
            ethPOSDeposit = 0x00000000219ab540356cBB839Cbe05303d7705Fa;
        } else {
            // For non-mainnet chains, deploy a mock
            /// TODO: Handle Eth pos deposit contract
            ethPOSDeposit = address(0);
        }

        address eigenPodManagerImpl = address(
            new EigenPodManager(
                IETHPOSDeposit(ethPOSDeposit),
                IBeacon(result.eigenPodBeacon),
                IDelegationManager(result.delegationManager),
                IPauserRegistry(result.pauserRegistry)
            )
        );

        address eigenPodImpl = address(
            new EigenPod(
                IETHPOSDeposit(ethPOSDeposit),
                IEigenPodManager(result.eigenPodManager),
                uint64(block.timestamp) // Use current timestamp as genesis time for testing
            )
        );

        address eigenPodBeaconImpl = address(new UpgradeableBeacon(eigenPodImpl));

        address baseStrategyImpl = address(
            new StrategyBase(
                IStrategyManager(result.strategyManager),
                IPauserRegistry(result.pauserRegistry)
            )
        );

        address strategyFactoryImpl = address(
            new StrategyFactory(
                IStrategyManager(result.strategyManager),
                IPauserRegistry(result.pauserRegistry)
            )
        );

        address rewardsCoordinatorImpl = address(
            new RewardsCoordinator(
                IDelegationManager(result.delegationManager),
                IStrategyManager(result.strategyManager),
                IAllocationManager(result.allocationManager),
                IPauserRegistry(result.pauserRegistry),
                IPermissionController(result.permissionController),
                configData.rewardsCoordinator.calculationIntervalSeconds,
                configData.rewardsCoordinator.maxRewardsDuration,
                configData.rewardsCoordinator.maxRetroactiveLength,
                configData.rewardsCoordinator.maxFutureLength,
                configData.rewardsCoordinator.genesisRewardsTimestamp
            )
        );

        // Deploy and configure the strategy beacon
        result.strategyBeacon = address(new UpgradeableBeacon(baseStrategyImpl));

        UpgradeableProxyLib.upgrade(result.permissionController, permissionControllerImpl);
        // Initialize contracts
        bytes memory upgradeCall;

        upgradeCall = abi.encodeCall(
            StrategyManager.initialize,
            (
                configData.strategyManager.initialOwner,
                configData.strategyManager.initialStrategyWhitelister,
                configData.strategyManager.initPausedStatus
            )
        );

        // Upgrade the eigenPodBeacon with the eigenPodBeaconImpl
        UpgradeableProxyLib.upgrade(result.eigenPodBeacon, eigenPodBeaconImpl);

        UpgradeableProxyLib.upgradeAndCall(result.strategyManager, strategyManagerImpl, upgradeCall);

        upgradeCall = abi.encodeCall(
            DelegationManager.initialize,
            (
                configData.delegationManager.initialOwner,
                configData.delegationManager.initPausedStatus
            )
        );
        UpgradeableProxyLib.upgradeAndCall(result.delegationManager, delegationManagerImpl, upgradeCall);

        upgradeCall = abi.encodeCall(
            AllocationManager.initialize,
            (
                configData.allocationManager.initialOwner,
                configData.allocationManager.initPausedStatus
            )
        );
        UpgradeableProxyLib.upgradeAndCall(result.allocationManager, allocationManagerImpl, upgradeCall);

        upgradeCall = abi.encodeCall(
            AVSDirectory.initialize,
            (
                proxyAdmin, // initialOwner
                0 // initialPausedStatus
            )
        );
        UpgradeableProxyLib.upgradeAndCall(result.avsDirectory, avsDirectoryImpl, upgradeCall);

        upgradeCall = abi.encodeCall(
            EigenPodManager.initialize,
            (
                configData.eigenPodManager.initialOwner,
                configData.eigenPodManager.initPausedStatus
            )
        );
        UpgradeableProxyLib.upgradeAndCall(result.eigenPodManager, eigenPodManagerImpl, upgradeCall);

        upgradeCall = abi.encodeCall(
            StrategyFactory.initialize,
            (
                configData.strategyFactory.initialOwner,
                configData.strategyFactory.initPausedStatus,
                IBeacon(result.strategyBeacon)
            )
        );
        UpgradeableProxyLib.upgradeAndCall(result.strategyFactory, strategyFactoryImpl, upgradeCall);

        upgradeCall = abi.encodeCall(
            RewardsCoordinator.initialize,
            (
                configData.rewardsCoordinator.initialOwner,
                configData.rewardsCoordinator.initPausedStatus,
                configData.rewardsCoordinator.rewardsUpdater,
                configData.rewardsCoordinator.activationDelay,
                configData.rewardsCoordinator.defaultSplitBips
            )
        );
        UpgradeableProxyLib.upgradeAndCall(result.rewardsCoordinator, rewardsCoordinatorImpl, upgradeCall);

        return result;
    }
}

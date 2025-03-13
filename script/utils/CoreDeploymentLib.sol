// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Vm} from "forge-std/Vm.sol";
import {console2 as console} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {UpgradeableProxyLib} from "./UpgradeableProxyLib.sol";
import {StakeRegistry} from "../../src/StakeRegistry.sol";
import {BLSApkRegistry} from "../../src/BLSApkRegistry.sol";
import {IndexRegistry} from "../../src/IndexRegistry.sol";
import {RegistryCoordinator} from "../../src/RegistryCoordinator.sol";
import {IRegistryCoordinator} from "../../src/interfaces/IRegistryCoordinator.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

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
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IPermissionController} from "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IEigenPodManager} from "eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {StrategyFactory} from "eigenlayer-contracts/src/contracts/strategies/StrategyFactory.sol";

library CoreDeploymentLib {
    using stdJson for string;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct AVSDirectoryConfig {
        uint256 initialPausedStatus;
    }

    struct StrategyManagerConfig {
        uint256 initPausedStatus;
        uint256 initWithdrawalDelayBlocks;
    }

    struct SlasherConfig {
        uint256 initPausedStatus;
    }

    struct DelegationManagerConfig {
        uint256 initPausedStatus;
        uint256 withdrawalDelayBlocks;
        uint256 globalOperatorCommissionBips;
    }

    struct EigenPodManagerConfig {
        uint256 initPausedStatus;
        uint64 genesisTime;
    }

    struct RewardsCoordinatorConfig {
        address rewardsUpdater;
        uint256 initPausedStatus;
        uint256 maxRewardsDuration;
        uint256 maxRetroactiveLength;
        uint256 maxFutureLength;
        uint256 genesisRewardsTimestamp;
        uint256 defaultOperatorSplitBips;
        address updater;
        uint256 activationDelay;
        uint256 calculationIntervalSeconds;
        uint256 globalOperatorCommissionBips;
    }

    struct StrategyFactoryConfig {
        uint256 initPausedStatus;
    }

    struct DeploymentConfig {
        StrategyManagerConfig strategyManager;
        AVSDirectoryConfig avsDirectory;
        SlasherConfig slasher;
        DelegationManagerConfig delegationManager;
        EigenPodManagerConfig eigenPodManager;
        RewardsCoordinatorConfig rewardsCoordinator;
        StrategyFactoryConfig strategyFactory;
    }

    struct DeploymentData {
        address delegationManager;
        address avsDirectory;
        address allocationManager;
        address strategyManager;
        address eigenPodManager;
        address rewardsCoordinator;
        address eigenPodBeacon;
        address pauserRegistry;
        address strategyFactory;
        address strategyBeacon;
        address eigenStrategy;
        address eigen;
        address backingEigen;
        address permissionController;
    }

    struct DeploymentAddresses {
        address delegationManagerImpl;
        address avsDirectoryImpl;
        address strategyManagerImpl;
        address strategyFactoryImpl;
        address eigenPodManagerImpl;
        address rewardsCoordinatorImpl;
        address eigenPodImpl;
        address eigenPodBeaconImpl;
        address baseStrategyImpl;
        address pauserRegistryImpl;
    }

    function deployCoreFromScratch(
        address proxyAdmin,
        DeploymentConfig memory config
    ) internal returns (DeploymentData memory) {
        DeploymentData memory result;
        DeploymentAddresses memory addrs;

        // Deploy empty proxies
        result = _deployEmptyProxies(proxyAdmin, result);

        // Deploy implementations
        (
            addrs.delegationManagerImpl,
            addrs.avsDirectoryImpl,
            addrs.strategyManagerImpl,
            addrs.strategyFactoryImpl
        ) = _deployMainImplementations(result, config);

        address ethPOSDeposit = _getEthPOSDeposit();

        (
            addrs.eigenPodManagerImpl,
            addrs.rewardsCoordinatorImpl,
            addrs.eigenPodImpl,
            addrs.eigenPodBeaconImpl,
            addrs.baseStrategyImpl,
            addrs.pauserRegistryImpl
        ) = _deployRemainingImplementations(result, config, ethPOSDeposit);

        // Deploy strategy beacon
        result.strategyBeacon = address(new UpgradeableBeacon(addrs.baseStrategyImpl));

        // Upgrade all contracts
        _upgradeAllContracts(
            result,
            config,
            proxyAdmin,
            addrs
        );

        return result;
    }

    function _deployEmptyProxies(address proxyAdmin, DeploymentData memory result) private returns (DeploymentData memory) {
        result.delegationManager = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.avsDirectory = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.strategyManager = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.eigenPodManager = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.rewardsCoordinator = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.eigenPodBeacon = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.pauserRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.strategyFactory = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        return result;
    }

    function _deployMainImplementations(DeploymentData memory result, DeploymentConfig memory config) private returns (
        address delegationManagerImpl,
        address avsDirectoryImpl,
        address strategyManagerImpl,
        address strategyFactoryImpl
    ) {
        delegationManagerImpl = address(
            new DelegationManager(
                IStrategyManager(result.strategyManager),
                IEigenPodManager(result.eigenPodManager),
                IAllocationManager(result.allocationManager),
                IPauserRegistry(result.pauserRegistry),
                IPermissionController(result.permissionController),
                uint32(config.delegationManager.initPausedStatus)
            )
        );

        avsDirectoryImpl = address(
            new AVSDirectory(
                IDelegationManager(result.delegationManager),
                IPauserRegistry(result.pauserRegistry)
            )
        );

        strategyManagerImpl = address(
            new StrategyManager(
                IDelegationManager(result.delegationManager),
                IPauserRegistry(result.pauserRegistry)
            )
        );

        strategyFactoryImpl = address(new StrategyFactory(
            IStrategyManager(result.strategyManager),
            IPauserRegistry(result.pauserRegistry)
        ));

        return (delegationManagerImpl, avsDirectoryImpl, strategyManagerImpl, strategyFactoryImpl);
    }

    function _getEthPOSDeposit() private view returns (address) {
        if (block.chainid == 1) {
            return 0x00000000219ab540356cBB839Cbe05303d7705Fa;
        }
        // Handle non-mainnet chains
        /// TODO: Handle Eth pos
        return address(0);
    }

    function _deployRemainingImplementations(
        DeploymentData memory result,
        DeploymentConfig memory config,
        address ethPOSDeposit
    ) private returns (
        address eigenPodManagerImpl,
        address rewardsCoordinatorImpl,
        address eigenPodImpl,
        address eigenPodBeaconImpl,
        address baseStrategyImpl,
        address pauserRegistryImpl
    ) {
        eigenPodManagerImpl = address(
            new EigenPodManager(
                IETHPOSDeposit(ethPOSDeposit),
                IBeacon(result.eigenPodBeacon),
                IDelegationManager(result.delegationManager),
                IPauserRegistry(result.pauserRegistry)
            )
        );

        rewardsCoordinatorImpl = address(
            new RewardsCoordinator(
                IDelegationManager(result.delegationManager),
                IStrategyManager(result.strategyManager),
                IAllocationManager(result.allocationManager),
                IPauserRegistry(result.pauserRegistry),
                IPermissionController(result.permissionController),
                uint32(config.rewardsCoordinator.calculationIntervalSeconds),
                uint32(config.rewardsCoordinator.maxRewardsDuration),
                uint32(config.rewardsCoordinator.maxRetroactiveLength),
                uint32(config.rewardsCoordinator.maxFutureLength),
                uint32(config.rewardsCoordinator.genesisRewardsTimestamp)
            )
        );

        eigenPodImpl = address(
            new EigenPod(
                IETHPOSDeposit(ethPOSDeposit),
                IEigenPodManager(result.eigenPodManager),
                config.eigenPodManager.genesisTime
            )
        );

        eigenPodBeaconImpl = address(new UpgradeableBeacon(eigenPodImpl));
        baseStrategyImpl = address(new StrategyBase(IStrategyManager(result.strategyManager), IPauserRegistry(result.pauserRegistry)));

        /// TODO: PauserRegistry isn't upgradeable
        pauserRegistryImpl = address(
            new PauserRegistry(
                new address[](0), // Empty array for pausers
                result.permissionController // ProxyAdmin as the unpauser
            )
        );

        return (
            eigenPodManagerImpl,
            rewardsCoordinatorImpl,
            eigenPodImpl,
            eigenPodBeaconImpl,
            baseStrategyImpl,
            pauserRegistryImpl
        );
    }

    function _upgradeAllContracts(
        DeploymentData memory result,
        DeploymentConfig memory config,
        address proxyAdmin,
        DeploymentAddresses memory addrs
    ) private {
        bytes memory upgradeCall;

        upgradeCall = abi.encodeCall(
            DelegationManager.initialize,
            (proxyAdmin, config.delegationManager.initPausedStatus)
        );
        UpgradeableProxyLib.upgradeAndCall(result.delegationManager, addrs.delegationManagerImpl, upgradeCall);

        upgradeCall = abi.encodeCall(
            StrategyManager.initialize,
            (proxyAdmin, result.strategyFactory, config.strategyManager.initPausedStatus)
        );
        UpgradeableProxyLib.upgradeAndCall(result.strategyManager, addrs.strategyManagerImpl, upgradeCall);

        upgradeCall = abi.encodeCall(
            StrategyFactory.initialize,
            (proxyAdmin, config.strategyFactory.initPausedStatus, IBeacon(result.strategyBeacon))
        );
        UpgradeableProxyLib.upgradeAndCall(result.strategyFactory, addrs.strategyFactoryImpl, upgradeCall);

        upgradeCall = abi.encodeCall(
            EigenPodManager.initialize,
            (proxyAdmin, config.eigenPodManager.initPausedStatus)
        );
        UpgradeableProxyLib.upgradeAndCall(result.eigenPodManager, addrs.eigenPodManagerImpl, upgradeCall);

        upgradeCall = abi.encodeCall(
            AVSDirectory.initialize,
            (proxyAdmin, config.avsDirectory.initialPausedStatus)
        );
        UpgradeableProxyLib.upgradeAndCall(result.avsDirectory, addrs.avsDirectoryImpl, upgradeCall);

        upgradeCall = abi.encodeCall(
            RewardsCoordinator.initialize,
            (
                proxyAdmin,
                config.rewardsCoordinator.initPausedStatus,
                config.rewardsCoordinator.rewardsUpdater,
                uint32(config.rewardsCoordinator.activationDelay),
                uint16(config.rewardsCoordinator.defaultOperatorSplitBips)
            )
        );
        UpgradeableProxyLib.upgradeAndCall(result.rewardsCoordinator, addrs.rewardsCoordinatorImpl, upgradeCall);

        upgradeCall = abi.encodeCall(EigenPod.initialize, (address(result.eigenPodManager)));
        UpgradeableProxyLib.upgradeAndCall(result.eigenPodBeacon, addrs.eigenPodImpl, upgradeCall);
    }

    function readCoreDeploymentJson(string memory path, uint256 chainId) internal returns (CoreDeploymentLib.DeploymentData memory) {
        string memory filePath = string(abi.encodePacked(path, "/", vm.toString(chainId), ".json"));
        return parseZeusJson(filePath);
    }

    function readCoreDeploymentJson(string memory path, uint256 chainId, string memory environment) internal returns (CoreDeploymentLib.DeploymentData memory) {
        string memory filePath = string(abi.encodePacked(path, "/", vm.toString(chainId), "-", environment, ".json"));
        return parseZeusJson(filePath);
    }

    function parseZeusJson(string memory filePath) internal returns (CoreDeploymentLib.DeploymentData memory) {
        string memory json = vm.readFile(filePath);
        require(vm.exists(filePath), "Deployment file does not exist");
        CoreDeploymentLib.DeploymentData memory deploymentData;

        deploymentData.delegationManager = json.readAddress(".ZEUS_DEPLOYED_DelegationManager_Proxy");
        deploymentData.avsDirectory = json.readAddress(".ZEUS_DEPLOYED_AVSDirectory_Proxy");
        deploymentData.allocationManager = json.readAddress(".ZEUS_DEPLOYED_AllocationManager_Proxy");
        deploymentData.strategyManager = json.readAddress(".ZEUS_DEPLOYED_StrategyManager_Proxy");
        deploymentData.eigenPodManager = json.readAddress(".ZEUS_DEPLOYED_EigenPodManager_Proxy");
        deploymentData.rewardsCoordinator = json.readAddress(".ZEUS_DEPLOYED_RewardsCoordinator_Proxy");
        deploymentData.eigenPodBeacon = json.readAddress(".ZEUS_DEPLOYED_EigenPod_Beacon");
        deploymentData.pauserRegistry = json.readAddress(".ZEUS_DEPLOYED_PauserRegistry_Impl");
        deploymentData.strategyFactory = json.readAddress(".ZEUS_DEPLOYED_StrategyFactory_Proxy");
        deploymentData.strategyBeacon = json.readAddress(".ZEUS_DEPLOYED_StrategyBase_Beacon");
        deploymentData.eigenStrategy = json.readAddress(".ZEUS_DEPLOYED_EigenStrategy_Proxy");
        deploymentData.eigen = json.readAddress(".ZEUS_DEPLOYED_Eigen_Proxy");
        deploymentData.backingEigen = json.readAddress(".ZEUS_DEPLOYED_BackingEigen_Proxy");
        deploymentData.permissionController = json.readAddress(".ZEUS_DEPLOYED_PermissionController_Proxy");

        return deploymentData;
    }
}
// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.0;

// import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
// import {TransparentUpgradeableProxy} from
//     "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
// import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
// import {DelegationManager} from "eigenlayer-contracts/src/contracts/core/DelegationManager.sol";
// import {StrategyManager} from "eigenlayer-contracts/src/contracts/core/StrategyManager.sol";
// import {AVSDirectory} from "eigenlayer-contracts/src/contracts/core/AVSDirectory.sol";
// import {EigenPodManager} from "eigenlayer-contracts/src/contracts/pods/EigenPodManager.sol";
// import {RewardsCoordinator} from "eigenlayer-contracts/src/contracts/core/RewardsCoordinator.sol";
// import {StrategyBase} from "eigenlayer-contracts/src/contracts/strategies/StrategyBase.sol";
// import {EigenPod} from "eigenlayer-contracts/src/contracts/pods/EigenPod.sol";
// import {IETHPOSDeposit} from "eigenlayer-contracts/src/contracts/interfaces/IETHPOSDeposit.sol";
// import {StrategyBaseTVLLimits} from "eigenlayer-contracts/src/contracts/strategies/StrategyBaseTVLLimits.sol";
// import {PauserRegistry} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
// import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
// import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
// import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
// import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
// import {IEigenPodManager} from "eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
// import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
// import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
// import {StrategyFactory} from "eigenlayer-contracts/src/contracts/strategies/StrategyFactory.sol";

// import {UpgradeableProxyLib} from "../unit/UpgradeableProxyLib.sol";

// library CoreDeploymentLib {
//     using UpgradeableProxyLib for address;

//     struct StrategyManagerConfig {
//         uint256 initPausedStatus;
//         uint256 initWithdrawalDelayBlocks;
//     }

//     struct DelegationManagerConfig {
//         uint256 initPausedStatus;
//         IStrategy[] strategies;
//         uint256 minWithdrawalDelayBlocks;
//         uint256[] withdrawalDelayBlocks;

//     }

//     struct EigenPodManagerConfig {
//         uint256 initPausedStatus;
//     }

//     struct RewardsCoordinatorConfig {
//         uint256 initPausedStatus;
//         uint256 maxRewardsDuration;
//         uint256 maxRetroactiveLength;
//         uint256 maxFutureLength;
//         uint256 genesisRewardsTimestamp;
//         address updater;
//         uint256 activationDelay;
//         uint256 calculationIntervalSeconds;
//         uint256 globalOperatorCommissionBips;
//     }

//     struct StrategyFactoryConfig {
//         uint256 initPausedStatus;
//     }

//     struct DeploymentConfigData {
//         StrategyManagerConfig strategyManager;
//         DelegationManagerConfig delegationManager;
//         EigenPodManagerConfig eigenPodManager;
//         RewardsCoordinatorConfig rewardsCoordinator;
//         StrategyFactoryConfig strategyFactory;
//     }

//     struct DeploymentData {
//         address delegationManager;
//         address avsDirectory;
//         address strategyManager;
//         address eigenPodManager;
//         address rewardsCoordinator;
//         address eigenPodBeacon;
//         address pauserRegistry;
//         address strategyFactory;
//         address strategyBeacon;
//     }

//     function deployContracts(
//         address proxyAdmin,
//         DeploymentConfigData memory configData
//     ) internal returns (DeploymentData memory) {
//         DeploymentData memory result;

//         result.delegationManager = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
//         result.avsDirectory = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
//         result.strategyManager = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
//         result.eigenPodManager = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
//         result.rewardsCoordinator = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
//         result.eigenPodBeacon = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
//         result.pauserRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
//         result.strategyFactory = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);

//         // Deploy the implementation contracts, using the proxy contracts as inputs
//         address delegationManagerImpl = address(
//             new DelegationManager(
//                 IStrategyManager(result.strategyManager),
//                 IEigenPodManager(result.eigenPodManager)
//             )
//         );
//         address avsDirectoryImpl =
//             address(new AVSDirectory(IDelegationManager(result.delegationManager)));

//         address strategyManagerImpl = address(
//             new StrategyManager(
//                 IDelegationManager(result.delegationManager),
//                 IEigenPodManager(result.eigenPodManager)
//             )
//         );

//         address strategyFactoryImpl =
//             address(new StrategyFactory(IStrategyManager(result.strategyManager)));

//         address ethPOSDeposit;
//         if (block.chainid == 1) {
//             ethPOSDeposit = 0x00000000219ab540356cBB839Cbe05303d7705Fa;
//         } else {
//             // For non-mainnet chains, you might want to deploy a mock or read from a config
//             // This assumes you have a similar config setup as in M2_Deploy_From_Scratch.s.sol
//             /// TODO: Handle Eth pos
//         }

//         address eigenPodManagerImpl = address(
//             new EigenPodManager(
//                 IETHPOSDeposit(ethPOSDeposit),
//                 IBeacon(result.eigenPodBeacon),
//                 IStrategyManager(result.strategyManager),
//                 IDelegationManager(result.delegationManager)
//             )
//         );

//         /// TODO: Get actual values
//         uint32 CALCULATION_INTERVAL_SECONDS = 1 days;
//         uint32 MAX_REWARDS_DURATION = 1 days;
//         uint32 MAX_RETROACTIVE_LENGTH = 1;
//         uint32 MAX_FUTURE_LENGTH = 1;
//         uint32 GENESIS_REWARDS_TIMESTAMP = 10 days;
//         address rewardsCoordinatorImpl = address(
//             new RewardsCoordinator(
//                 IDelegationManager(result.delegationManager),
//                 IStrategyManager(result.strategyManager),
//                 CALCULATION_INTERVAL_SECONDS,
//                 MAX_REWARDS_DURATION,
//                 MAX_RETROACTIVE_LENGTH,
//                 MAX_FUTURE_LENGTH,
//                 GENESIS_REWARDS_TIMESTAMP
//             )
//         );

//         /// TODO: Get actual genesis time
//         uint64 GENESIS_TIME = 1_564_000;

//         address eigenPodImpl = address(
//             new EigenPod(
//                 IETHPOSDeposit(ethPOSDeposit),
//                 IEigenPodManager(result.eigenPodManager),
//                 GENESIS_TIME
//             )
//         );
//         address eigenPodBeaconImpl = address(new UpgradeableBeacon(eigenPodImpl));
//         address baseStrategyImpl =
//             address(new StrategyBase(IStrategyManager(result.strategyManager)));
//         /// TODO: PauserRegistry isn't upgradeable
//         address pauserRegistryImpl = address(
//             new PauserRegistry(
//                 new address[](0), // Empty array for pausers
//                 proxyAdmin // ProxyAdmin as the unpauser
//             )
//         );

//         // Deploy and configure the strategy beacon
//         result.strategyBeacon = address(new UpgradeableBeacon(baseStrategyImpl));

//         // Upgrade contracts
//         /// TODO: Get from config
//         bytes memory upgradeCall = abi.encodeWithSelector( /// TODO: Fix abi.encodeCall was failing Cannot implicitly convert component at position 4 from "IStrategy[]" to "IStrategy[]"
//             DelegationManager.initialize.selector,
//                 proxyAdmin, // initialOwner
//                 IPauserRegistry(result.pauserRegistry), // _pauserRegistry
//                 configData.delegationManager.initPausedStatus, // initialPausedStatus
//                 configData.delegationManager.minWithdrawalDelayBlocks, // _minWithdrawalDelayBlocks
//                 configData.delegationManager.strategies, // _strategies
//                 configData.delegationManager.withdrawalDelayBlocks // _withdrawalDelayBlocks
//         );
//         UpgradeableProxyLib.upgradeAndCall(
//             result.delegationManager, delegationManagerImpl, upgradeCall
//         );

//         // Upgrade StrategyManager contract
//         upgradeCall = abi.encodeCall(
//             StrategyManager.initialize,
//             (
//                 proxyAdmin, // initialOwner
//                 result.strategyFactory, // initialStrategyWhitelister
//                 IPauserRegistry(result.pauserRegistry), // _pauserRegistry
//                 configData.strategyManager.initPausedStatus // initialPausedStatus
//             )
//         );
//         UpgradeableProxyLib.upgradeAndCall(result.strategyManager, strategyManagerImpl, upgradeCall);

//         // Upgrade StrategyFactory contract
//         upgradeCall = abi.encodeCall(
//             StrategyFactory.initialize,
//             (
//                 proxyAdmin, // initialOwner
//                 IPauserRegistry(result.pauserRegistry), // _pauserRegistry
//                 configData.strategyFactory.initPausedStatus, // initialPausedStatus
//                 IBeacon(result.strategyBeacon)
//             )
//         );
//         UpgradeableProxyLib.upgradeAndCall(result.strategyFactory, strategyFactoryImpl, upgradeCall);

//         // Upgrade EigenPodManager contract
//         upgradeCall = abi.encodeCall(
//             EigenPodManager.initialize,
//             (
//                 proxyAdmin, // initialOwner
//                 IPauserRegistry(result.pauserRegistry), // _pauserRegistry
//                 configData.eigenPodManager.initPausedStatus // initialPausedStatus
//             )
//         );
//         UpgradeableProxyLib.upgradeAndCall(result.eigenPodManager, eigenPodManagerImpl, upgradeCall);

//         // Upgrade AVSDirectory contract
//         upgradeCall = abi.encodeCall(
//             AVSDirectory.initialize,
//             (
//                 proxyAdmin, // initialOwner
//                 IPauserRegistry(result.pauserRegistry), // _pauserRegistry
//                 0 // TODO: AVS Missing configinitialPausedStatus
//             )
//         );
//         UpgradeableProxyLib.upgradeAndCall(result.avsDirectory, avsDirectoryImpl, upgradeCall);

//         // Upgrade RewardsCoordinator contract
//         upgradeCall = abi.encodeCall(
//             RewardsCoordinator.initialize,
//             (
//                 proxyAdmin, // initialOwner
//                 IPauserRegistry(result.pauserRegistry), // _pauserRegistry
//                 configData.rewardsCoordinator.initPausedStatus, // initialPausedStatus
//                 /// TODO: is there a setter and is this expected?
//                 address(0), // rewards updater
//                 uint32(configData.rewardsCoordinator.activationDelay), // _activationDelay
//                 uint16(configData.rewardsCoordinator.globalOperatorCommissionBips) // _globalCommissionBips
//             )
//         );
//         UpgradeableProxyLib.upgradeAndCall(
//             result.rewardsCoordinator, rewardsCoordinatorImpl, upgradeCall
//         );

//         // Upgrade EigenPod contract
//         upgradeCall = abi.encodeCall(
//             EigenPod.initialize,
//             // TODO: Double check this
//             (address(result.eigenPodManager)) // _podOwner
//         );
//         UpgradeableProxyLib.upgradeAndCall(result.eigenPodBeacon, eigenPodImpl, upgradeCall);

//         return result;
//     }

// }

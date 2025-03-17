// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Vm} from "forge-std/Vm.sol";
import {console2 as console} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IRewardsCoordinator} from
    "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {BLSApkRegistry} from "../../src/BLSApkRegistry.sol";
import {IBLSApkRegistry} from "../../src/interfaces/IBLSApkRegistry.sol";
import {IndexRegistry} from "../../src/IndexRegistry.sol";
import {SocketRegistry} from "../../src/SocketRegistry.sol";
import {ISocketRegistry} from "../../src/interfaces/ISocketRegistry.sol";
import {IIndexRegistry} from "../../src/interfaces/IIndexRegistry.sol";
import {IServiceManager} from "../../src/interfaces/IServiceManager.sol";
import {RegistryCoordinator} from "../../src/RegistryCoordinator.sol";
import {StakeRegistry} from "../../src/StakeRegistry.sol";
import {IStakeRegistry, IStakeRegistryTypes} from "../../src/interfaces/IStakeRegistry.sol";
import {IRegistryCoordinator} from "../../src/RegistryCoordinator.sol";
import {SlashingRegistryCoordinator} from "../../src/SlashingRegistryCoordinator.sol";
import {
    ISlashingRegistryCoordinator,
    ISlashingRegistryCoordinatorTypes
} from "../../src/interfaces/ISlashingRegistryCoordinator.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategyFactory} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyFactory.sol";
import {ServiceManagerMock} from "../../test/mocks/ServiceManagerMock.sol";
import {
    PauserRegistry,
    IPauserRegistry
} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import {PermissionController} from
    "eigenlayer-contracts/src/contracts/permissions/PermissionController.sol";
import {OperatorStateRetriever} from "../../src/OperatorStateRetriever.sol";
import {UpgradeableProxyLib} from "./UpgradeableProxyLib.sol";
import {CoreDeploymentLibs} from "./CoreDeploymentLib.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "eigenlayer-contracts/src/contracts/core/AllocationManager.sol";

contract ERC20Mock is ERC20 {
    constructor() ERC20("", "") {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}

library MiddlewareDeploymentLib {
    using stdJson for *;
    using Strings for *;
    using UpgradeableProxyLib for address;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct DeploymentData {
        address registryCoordinator;
        address serviceManager;
        address operatorStateRetriever;
        address blsapkRegistry;
        address indexRegistry;
        address stakeRegistry;
        address strategy;
        address token;
        address pauserRegistry;
        address permissionController;
        address socketRegistry;
    }

    struct ConfigData {
        address admin;
        uint256 numQuorums;
        uint256[] operatorParams;
    }

    struct ImplementationAddresses {
        address serviceManagerImpl;
        address stakeRegistryImpl;
        address blsApkRegistryImpl;
        address indexRegistryImpl;
        address registryCoordinatorImpl;
        address allocationManagerImpl;
    }

    struct QuorumParams {
        IRegistryCoordinator.OperatorSetParam[] quorumsOperatorSetParams;
        uint96[] quorumsMinimumStake;
        IStakeRegistryTypes.StrategyParams[][] quorumsStrategyParams;
    }

    function deployContracts(
        address proxyAdmin,
        CoreDeploymentLibs.DeploymentData memory core,
        ConfigData memory config
    ) internal returns (DeploymentData memory) {
        DeploymentData memory result;

        // Deploy pauser registry
        result.pauserRegistry = _deployPauserRegistry(config.admin);

        // Deploy proxies
        result.stakeRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.registryCoordinator = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.blsapkRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.indexRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        result.serviceManager = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);

        // Deploy operator state retriever
        result.operatorStateRetriever = address(new OperatorStateRetriever());

        // Deploy token and strategy
        (result.token, result.strategy) = _deployTokenAndStrategy(core.strategyFactory);

        // Deploy permission controller
        result.permissionController = address(new PermissionController());

        // Deploy socket registry
        result.socketRegistry =
            address(new SocketRegistry(ISlashingRegistryCoordinator(result.registryCoordinator)));

        return result;
    }

    function upgradeContracts(
        DeploymentData memory deployment,
        ConfigData memory config,
        CoreDeploymentLibs.DeploymentData memory core
    ) internal {
        // Deploy implementation contracts
        ImplementationAddresses memory impls = _deployImplementations(deployment, core);

        // Prepare upgrade data
        (bytes memory registryCoordinatorUpgradeCall, bytes memory serviceManagerUpgradeCall) =
            _prepareUpgradeCalls(deployment, config);

        // Execute upgrades
        _executeUpgrades(
            deployment, impls, registryCoordinatorUpgradeCall, serviceManagerUpgradeCall
        );
    }

    function _deployPauserRegistry(
        address admin
    ) private returns (address) {
        address[] memory pausers = new address[](2);
        pausers[0] = admin;
        pausers[1] = admin;
        return address(new PauserRegistry(pausers, admin));
    }

    function _deployTokenAndStrategy(
        address strategyFactory
    ) private returns (address token, address strategy) {
        ERC20Mock tokenContract = new ERC20Mock();
        token = address(tokenContract);
        strategy = address(IStrategyFactory(strategyFactory).deployNewStrategy(IERC20(token)));
    }

    function _deployImplementations(
        DeploymentData memory deployment,
        CoreDeploymentLibs.DeploymentData memory core
    ) private returns (ImplementationAddresses memory impls) {
        impls.serviceManagerImpl = address(
            new ServiceManagerMock(
                IAVSDirectory(core.avsDirectory),
                IRewardsCoordinator(core.rewardsCoordinator),
                IRegistryCoordinator(deployment.registryCoordinator),
                IStakeRegistry(deployment.stakeRegistry),
                IPermissionController(deployment.permissionController),
                IAllocationManager(core.allocationManager)
            )
        );

        impls.stakeRegistryImpl = address(
            new StakeRegistry(
                IRegistryCoordinator(deployment.registryCoordinator),
                IDelegationManager(core.delegationManager),
                IAVSDirectory(core.avsDirectory),
                IAllocationManager(core.allocationManager)
            )
        );

        impls.blsApkRegistryImpl =
            address(new BLSApkRegistry(IRegistryCoordinator(deployment.registryCoordinator)));
        impls.indexRegistryImpl =
            address(new IndexRegistry(IRegistryCoordinator(deployment.registryCoordinator)));

        impls.registryCoordinatorImpl = address(
            new RegistryCoordinator(
                IServiceManager(deployment.serviceManager),
                IStakeRegistry(deployment.stakeRegistry),
                IBLSApkRegistry(deployment.blsapkRegistry),
                IIndexRegistry(deployment.indexRegistry),
                ISocketRegistry(deployment.socketRegistry),
                IAllocationManager(core.allocationManager),
                IPauserRegistry(deployment.pauserRegistry)
            )
        );
    }

    function _prepareUpgradeCalls(
        DeploymentData memory deployment,
        ConfigData memory config
    )
        private
        pure
        returns (
            bytes memory registryCoordinatorUpgradeCall,
            bytes memory serviceManagerUpgradeCall
        )
    {
        serviceManagerUpgradeCall =
            abi.encodeCall(ServiceManagerMock.initialize, (config.admin, config.admin));

        registryCoordinatorUpgradeCall = abi.encodeCall(
            SlashingRegistryCoordinator.initialize,
            (config.admin, config.admin, config.admin, 0, deployment.serviceManager)
        );
    }

    function _prepareQuorumParams(
        ConfigData memory config,
        IStrategy[1] memory deployedStrategyArray
    ) private pure returns (QuorumParams memory params) {
        uint256 numQuorums = config.numQuorums;
        uint256 numStrategies = deployedStrategyArray.length;

        params.quorumsOperatorSetParams =
            new ISlashingRegistryCoordinatorTypes.OperatorSetParam[](numQuorums);
        uint256[] memory operator_params = config.operatorParams;

        for (uint256 i = 0; i < numQuorums; i++) {
            params.quorumsOperatorSetParams[i] = ISlashingRegistryCoordinatorTypes.OperatorSetParam({
                maxOperatorCount: uint32(operator_params[i]),
                kickBIPsOfOperatorStake: uint16(operator_params[i + 1]),
                kickBIPsOfTotalStake: uint16(operator_params[i + 2])
            });
        }

        params.quorumsMinimumStake = new uint96[](numQuorums);
        params.quorumsStrategyParams = new IStakeRegistry.StrategyParams[][](numQuorums);

        for (uint256 i = 0; i < numQuorums; i++) {
            params.quorumsStrategyParams[i] = new IStakeRegistry.StrategyParams[](numStrategies);
            for (uint256 j = 0; j < numStrategies; j++) {
                params.quorumsStrategyParams[i][j] = IStakeRegistryTypes.StrategyParams({
                    strategy: deployedStrategyArray[j],
                    multiplier: 1 ether
                });
            }
        }
    }

    function _executeUpgrades(
        DeploymentData memory deployment,
        ImplementationAddresses memory impls,
        bytes memory registryCoordinatorUpgradeCall,
        bytes memory serviceManagerUpgradeCall
    ) private {
        UpgradeableProxyLib.upgradeAndCall(
            deployment.serviceManager, impls.serviceManagerImpl, serviceManagerUpgradeCall
        );
        UpgradeableProxyLib.upgrade(deployment.stakeRegistry, impls.stakeRegistryImpl);
        UpgradeableProxyLib.upgrade(deployment.blsapkRegistry, impls.blsApkRegistryImpl);
        UpgradeableProxyLib.upgrade(deployment.indexRegistry, impls.indexRegistryImpl);
        UpgradeableProxyLib.upgradeAndCall(
            deployment.registryCoordinator,
            impls.registryCoordinatorImpl,
            registryCoordinatorUpgradeCall
        );
    }

    function upgradeContracts(
        DeploymentData memory deployment,
        CoreDeploymentLibs.DeploymentData memory core
    ) internal {
        ImplementationAddresses memory impls = _deployImplementations(deployment, core);

        _executeUpgrades(deployment, impls);
    }

    function _executeUpgrades(
        DeploymentData memory deployment,
        ImplementationAddresses memory impls
    ) private {
        UpgradeableProxyLib.upgrade(deployment.serviceManager, impls.serviceManagerImpl);
        UpgradeableProxyLib.upgrade(deployment.stakeRegistry, impls.stakeRegistryImpl);
        UpgradeableProxyLib.upgrade(deployment.blsapkRegistry, impls.blsApkRegistryImpl);
        UpgradeableProxyLib.upgrade(deployment.indexRegistry, impls.indexRegistryImpl);
        UpgradeableProxyLib.upgrade(deployment.registryCoordinator, impls.registryCoordinatorImpl);
    }

    function readDeploymentJson(
        string memory path,
        uint256 chainId
    ) internal returns (DeploymentData memory) {
        string memory filePath = string(abi.encodePacked(path, "/", vm.toString(chainId), ".json"));
        return parseDeploymentJson(filePath);
    }

    function readDeploymentJson(
        string memory path,
        uint256 chainId,
        string memory environment
    ) internal returns (DeploymentData memory) {
        string memory filePath =
            string(abi.encodePacked(path, "/", vm.toString(chainId), "-", environment, ".json"));
        return parseDeploymentJson(filePath);
    }

    function parseDeploymentJson(
        string memory filePath
    ) internal returns (DeploymentData memory) {
        string memory json = vm.readFile(filePath);
        require(vm.exists(filePath), "Deployment file does not exist");
        DeploymentData memory deploymentData;

        deploymentData.serviceManager = json.readAddress(".serviceManager");
        deploymentData.registryCoordinator = json.readAddress(".registryCoordinator");
        deploymentData.blsapkRegistry = json.readAddress(".blsapkRegistry");
        deploymentData.indexRegistry = json.readAddress(".indexRegistry");
        deploymentData.stakeRegistry = json.readAddress(".stakeRegistry");
        deploymentData.operatorStateRetriever = json.readAddress(".operatorStateRetriever");
        deploymentData.token = json.readAddress(".token");
        deploymentData.strategy = json.readAddress(".strategy");

        return deploymentData;
    }
}

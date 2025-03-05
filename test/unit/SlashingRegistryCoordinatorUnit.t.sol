// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, console2 as console} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {InstantSlasher} from "../../src/slashers/InstantSlasher.sol";
import {
    IAllocationManager,
    IAllocationManagerTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IRegistryCoordinator} from "../../src/interfaces/IRegistryCoordinator.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ISlasher, ISlasherTypes, ISlasherErrors} from "../../src/interfaces/ISlasher.sol";
import {ISlashingRegistryCoordinator} from "../../src/interfaces/ISlashingRegistryCoordinator.sol";
import {IStakeRegistry, IStakeRegistryTypes} from "../../src/interfaces/IStakeRegistry.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {EmptyContract} from "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";
import {AllocationManager} from "eigenlayer-contracts/src/contracts/core/AllocationManager.sol";
import {PermissionController} from
    "eigenlayer-contracts/src/contracts/permissions/PermissionController.sol";
import {PauserRegistry} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {DelegationMock} from "../mocks/DelegationMock.sol";
import {SlashingRegistryCoordinator} from "../../src/SlashingRegistryCoordinator.sol";
import {ISlashingRegistryCoordinatorTypes} from
    "../../src/interfaces/ISlashingRegistryCoordinator.sol";
import {IBLSApkRegistry, IBLSApkRegistryTypes} from "../../src/interfaces/IBLSApkRegistry.sol";
import {IIndexRegistry} from "../../src/interfaces/IIndexRegistry.sol";
import {ISocketRegistry} from "../../src/interfaces/ISocketRegistry.sol";
import {CoreDeploymentLib} from "../utils/CoreDeployLib.sol";
import {
    OperatorWalletLib,
    Operator,
    Wallet,
    BLSWallet,
    SigningKeyOperationsLib
} from "../utils/OperatorWalletLib.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {StrategyFactory} from "eigenlayer-contracts/src/contracts/strategies/StrategyFactory.sol";
import {StakeRegistry} from "../../src/StakeRegistry.sol";
import {BLSApkRegistry} from "../../src/BLSApkRegistry.sol";
import {IndexRegistry} from "../../src/IndexRegistry.sol";
import {SocketRegistry} from "../../src/SocketRegistry.sol";
import {MiddlewareDeployLib} from "../utils/MiddlewareDeployLib.sol";

contract SlashingRegistryCoordinatorUnitTest is Test {
    InstantSlasher public instantSlasher;
    ProxyAdmin public proxyAdmin;
    EmptyContract public emptyContract;
    SlashingRegistryCoordinator public slashingRegistryCoordinator;
    CoreDeploymentLib.DeploymentData public coreDeployment;
    PauserRegistry public pauserRegistry;
    ERC20Mock public mockToken;
    StrategyFactory public strategyFactory;
    StakeRegistry public stakeRegistry;
    BLSApkRegistry public blsApkRegistry;
    IndexRegistry public indexRegistry;
    SocketRegistry public socketRegistry;

    address public slasher;
    address public serviceManager;
    Operator public operatorWallet;
    IStrategy public mockStrategy;
    address public proxyAdminOwner = address(uint160(uint256(keccak256("proxyAdminOwner"))));
    address public pauser = address(uint160(uint256(keccak256("pauser"))));
    address public unpauser = address(uint160(uint256(keccak256("unpauser"))));
    address public churnApprover = address(uint160(uint256(keccak256("churnApprover"))));
    address public ejector = address(uint160(uint256(keccak256("ejector"))));

    uint32 constant DEALLOCATION_DELAY = 7 days;
    uint32 constant ALLOCATION_CONFIGURATION_DELAY = 1 days;

    function setUp() public {
        serviceManager = address(0x2);
        slasher = address(0x3);
        operatorWallet = OperatorWalletLib.createOperator("operator");

        mockToken = new ERC20Mock("Mock Token", "MOCK", address(this), 0);

        vm.startPrank(proxyAdminOwner);
        proxyAdmin = new ProxyAdmin();
        emptyContract = new EmptyContract();

        address[] memory pausers = new address[](1);
        pausers[0] = pauser;
        pauserRegistry = new PauserRegistry(pausers, unpauser);

        CoreDeploymentLib.DeploymentConfigData memory configData;
        configData.strategyManager.initialOwner = proxyAdminOwner;
        configData.strategyManager.initialStrategyWhitelister = proxyAdminOwner;
        configData.strategyManager.initPausedStatus = 0;

        configData.delegationManager.initialOwner = proxyAdminOwner;
        configData.delegationManager.minWithdrawalDelayBlocks = 50400;
        configData.delegationManager.initPausedStatus = 0;

        configData.eigenPodManager.initialOwner = proxyAdminOwner;
        configData.eigenPodManager.initPausedStatus = 0;

        configData.allocationManager.initialOwner = proxyAdminOwner;
        configData.allocationManager.deallocationDelay = DEALLOCATION_DELAY;
        configData.allocationManager.allocationConfigurationDelay = ALLOCATION_CONFIGURATION_DELAY;
        configData.allocationManager.initPausedStatus = 0;

        configData.strategyFactory.initialOwner = proxyAdminOwner;
        configData.strategyFactory.initPausedStatus = 0;

        configData.avsDirectory.initialOwner = proxyAdminOwner;
        configData.avsDirectory.initPausedStatus = 0;

        configData.rewardsCoordinator.initialOwner = proxyAdminOwner;
        configData.rewardsCoordinator.rewardsUpdater =
            address(0x14dC79964da2C08b23698B3D3cc7Ca32193d9955);
        configData.rewardsCoordinator.initPausedStatus = 0;
        configData.rewardsCoordinator.activationDelay = 0;
        configData.rewardsCoordinator.defaultSplitBips = 1000;
        configData.rewardsCoordinator.calculationIntervalSeconds = 86400;
        configData.rewardsCoordinator.maxRewardsDuration = 864000;
        configData.rewardsCoordinator.maxRetroactiveLength = 86400;
        configData.rewardsCoordinator.maxFutureLength = 86400;
        configData.rewardsCoordinator.genesisRewardsTimestamp = 1672531200;

        configData.ethPOSDeposit.ethPOSDepositAddress = address(0x123);

        coreDeployment = CoreDeploymentLib.deployContracts(address(proxyAdmin), configData);

        address strategyManagerOwner = Ownable(coreDeployment.strategyManager).owner();
        vm.stopPrank();

        vm.startPrank(strategyManagerOwner);
        IStrategyManager(coreDeployment.strategyManager).setStrategyWhitelister(
            coreDeployment.strategyFactory
        );
        vm.stopPrank();

        vm.startPrank(proxyAdminOwner);
        mockStrategy = IStrategy(
            StrategyFactory(coreDeployment.strategyFactory).deployNewStrategy(
                IERC20(address(mockToken))
            )
        );
        vm.stopPrank();

        MiddlewareDeployLib.MiddlewareDeployConfig memory middlewareConfig;
        middlewareConfig.instantSlasher.initialOwner = proxyAdminOwner;
        middlewareConfig.instantSlasher.slasher = slasher;
        middlewareConfig.slashingRegistryCoordinator.initialOwner = proxyAdminOwner;
        middlewareConfig.slashingRegistryCoordinator.churnApprover = churnApprover;
        middlewareConfig.slashingRegistryCoordinator.ejector = ejector;
        middlewareConfig.slashingRegistryCoordinator.initPausedStatus = 0;
        middlewareConfig.slashingRegistryCoordinator.serviceManager = serviceManager;
        middlewareConfig.socketRegistry.initialOwner = proxyAdminOwner;
        middlewareConfig.indexRegistry.initialOwner = proxyAdminOwner;
        middlewareConfig.stakeRegistry.initialOwner = proxyAdminOwner;
        middlewareConfig.stakeRegistry.minimumStake = 1 ether;
        middlewareConfig.stakeRegistry.strategyParams = 0;
        middlewareConfig.stakeRegistry.delegationManager = coreDeployment.delegationManager;
        middlewareConfig.stakeRegistry.avsDirectory = coreDeployment.avsDirectory;
        middlewareConfig.instantSlasher.slasher = slasher;
        {
            IStakeRegistryTypes.StrategyParams[] memory stratParams =
                new IStakeRegistryTypes.StrategyParams[](1);
            stratParams[0] =
                IStakeRegistryTypes.StrategyParams({strategy: mockStrategy, multiplier: 1 ether});
            middlewareConfig.stakeRegistry.strategyParamsArray = stratParams;
        }
        middlewareConfig.stakeRegistry.lookAheadPeriod = 0;
        middlewareConfig.stakeRegistry.stakeType = IStakeRegistryTypes.StakeType(1);
        middlewareConfig.blsApkRegistry.initialOwner = proxyAdminOwner;

        vm.startPrank(proxyAdminOwner);
        MiddlewareDeployLib.MiddlewareDeployData memory middlewareDeployments = MiddlewareDeployLib
            .deployMiddleware(
            address(proxyAdmin),
            coreDeployment.allocationManager,
            address(pauserRegistry),
            middlewareConfig
        );
        vm.stopPrank();

        vm.startPrank(serviceManager);
        PermissionController(coreDeployment.permissionController).setAppointee(
            address(serviceManager),
            address(instantSlasher),
            coreDeployment.allocationManager,
            AllocationManager.slashOperator.selector
        );

        slashingRegistryCoordinator =
            SlashingRegistryCoordinator(middlewareDeployments.slashingRegistryCoordinator);
        instantSlasher = InstantSlasher(middlewareDeployments.instantSlasher);

        PermissionController(coreDeployment.permissionController).setAppointee(
            address(serviceManager),
            address(slashingRegistryCoordinator),
            coreDeployment.allocationManager,
            AllocationManager.createOperatorSets.selector
        );

        PermissionController(coreDeployment.permissionController).setAppointee(
            address(serviceManager),
            address(instantSlasher),
            coreDeployment.allocationManager,
            AllocationManager.slashOperator.selector
        );

        PermissionController(coreDeployment.permissionController).setAppointee(
            address(serviceManager),
            proxyAdminOwner,
            coreDeployment.allocationManager,
            AllocationManager.updateAVSMetadataURI.selector
        );

        vm.stopPrank();

        uint8 quorumNumber = 0;
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = mockStrategy;

        uint96[] memory minimumStakes = new uint96[](1);
        minimumStakes[0] = 1 ether;

        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] =
            IStakeRegistryTypes.StrategyParams({strategy: mockStrategy, multiplier: 1 ether});

        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 0,
            kickBIPsOfTotalStake: 0
        });

        vm.startPrank(proxyAdminOwner);
        IAllocationManager(coreDeployment.allocationManager).updateAVSMetadataURI(
            serviceManager, "fake-avs-metadata"
        );
        slashingRegistryCoordinator.createSlashableStakeQuorum(
            operatorSetParams, 1 ether, strategyParams, 0
        );
        vm.stopPrank();

        vm.label(address(instantSlasher), "InstantSlasher Proxy");
        vm.label(address(slashingRegistryCoordinator), "SlashingRegistryCoordinator Proxy");
        vm.label(address(proxyAdmin), "ProxyAdmin");
        vm.label(coreDeployment.allocationManager, "AllocationManager Proxy");
    }

    function test_initialization() public {
        assertEq(slashingRegistryCoordinator.churnApprover(), churnApprover);
        assertEq(slashingRegistryCoordinator.avs(), serviceManager);
        assertEq(slashingRegistryCoordinator.ejector(), ejector);
    }
}

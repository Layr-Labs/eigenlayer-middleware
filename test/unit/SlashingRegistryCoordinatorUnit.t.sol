// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, console2 as console} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {InstantSlasher} from "../../src/slashers/InstantSlasher.sol";
import {
    IAllocationManager,
    IAllocationManagerTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {OperatorSetLib} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IRegistryCoordinator} from "../../src/interfaces/IRegistryCoordinator.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ISlasher, ISlasherTypes, ISlasherErrors} from "../../src/interfaces/ISlasher.sol";
import {ISlashingRegistryCoordinator} from "../../src/interfaces/ISlashingRegistryCoordinator.sol";
import {IServiceManager} from "../../src/interfaces/IServiceManager.sol";
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
import {IPermissionController} from "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategyFactory} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyFactory.sol";
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
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {BN254} from "../../src/libraries/BN254.sol";
import {
    ISlashingRegistryCoordinatorEvents,
    ISlashingRegistryCoordinatorErrors
} from "../../src/interfaces/ISlashingRegistryCoordinator.sol";

contract SlashingRegistryCoordinatorUnitTestSetup is Test, ISlashingRegistryCoordinatorEvents, ISlashingRegistryCoordinatorErrors {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    EnumerableSet.Bytes32Set internal operatorIds;
    mapping(bytes32 => Operator) internal operatorsByID;

    InstantSlasher internal instantSlasher;
    ProxyAdmin internal proxyAdmin;
    EmptyContract internal emptyContract;
    SlashingRegistryCoordinator internal slashingRegistryCoordinator;
    CoreDeploymentLib.DeploymentData internal coreDeployment;
    PauserRegistry internal pauserRegistry;
    ERC20Mock internal mockToken;
    StrategyFactory internal strategyFactory;
    StakeRegistry internal stakeRegistry;
    BLSApkRegistry internal blsApkRegistry;
    IndexRegistry internal indexRegistry;
    SocketRegistry internal socketRegistry;

    address internal slasher;
    address internal serviceManager;
    Operator internal operatorWallet;
    IStrategy internal mockStrategy;
    address internal proxyAdminOwner = address(uint160(uint256(keccak256("proxyAdminOwner"))));
    address internal pauser = address(uint160(uint256(keccak256("pauser"))));
    address internal unpauser = address(uint160(uint256(keccak256("unpauser"))));
    address internal churnApprover = address(uint160(uint256(keccak256("churnApprover"))));
    address internal ejector = address(uint160(uint256(keccak256("ejector"))));

    uint32 internal constant DEALLOCATION_DELAY = 7 days;
    uint32 internal constant ALLOCATION_CONFIGURATION_DELAY = 1 days;
    uint256 internal NUMBER_OF_OPERATORS = 10;
    uint256 constant STAKE_AMOUNT = 10 ether;

    function createPubkeyRegistrationParams(Operator memory operator, address operatorAddress) internal view returns (IBLSApkRegistryTypes.PubkeyRegistrationParams memory) {
        bytes32 messageHash = slashingRegistryCoordinator.calculatePubkeyRegistrationMessageHash(operatorAddress);
        BN254.G1Point memory signature = SigningKeyOperationsLib.sign(operator.signingKey, messageHash);

        return IBLSApkRegistryTypes.PubkeyRegistrationParams(
            signature,
            operator.signingKey.publicKeyG1,
            operator.signingKey.publicKeyG2
        );
    }

    function getStrategyParams() internal view returns (IStakeRegistryTypes.StrategyParams[] memory) {
        IStakeRegistryTypes.StrategyParams[] memory strategyParams = new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] = IStakeRegistryTypes.StrategyParams({
            strategy: mockStrategy,
            multiplier: 1 ether
        });
        return strategyParams;
    }

    function getDefaultOperatorSetParams() internal pure returns (ISlashingRegistryCoordinatorTypes.OperatorSetParam memory) {
        return ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 0,
            kickBIPsOfTotalStake: 0
        });
    }

    function setUp() public virtual {
        serviceManager = address(0x2);
        slasher = address(0x3);

        for (uint256 i = 0; i < NUMBER_OF_OPERATORS; i++) {
            string memory operatorName = string(abi.encodePacked("operator_", vm.toString(i)));
            Operator memory operator = OperatorWalletLib.createOperator(operatorName);

            bytes32 operatorId = BN254.hashG1Point(operator.signingKey.publicKeyG1);
            operatorsByID[operatorId] = operator;
            operatorIds.add(operatorId);

            if (i == 0) {
                operatorWallet = operator;
            }
        }

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
        socketRegistry = SocketRegistry(middlewareDeployments.socketRegistry);

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
        slashingRegistryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams, 1 ether, strategyParams
        );
        vm.stopPrank();

        vm.label(address(instantSlasher), "InstantSlasher Proxy");
        vm.label(address(slashingRegistryCoordinator), "SlashingRegistryCoordinator Proxy");
        vm.label(address(proxyAdmin), "ProxyAdmin");
        vm.label(coreDeployment.allocationManager, "AllocationManager Proxy");

        vm.prank(serviceManager);
        IAllocationManager(coreDeployment.allocationManager).setAVSRegistrar(
            address(serviceManager),
            IAVSRegistrar(address(slashingRegistryCoordinator))
        );

        for (uint i = 0; i < operatorIds.length(); i++) {
            bytes32 operatorId = operatorIds.at(i);
            Operator memory operator = operatorsByID[operatorId];

            mockToken.mint(operator.key.addr, STAKE_AMOUNT);

            vm.startPrank(operator.key.addr);

            mockToken.approve(address(coreDeployment.strategyManager), STAKE_AMOUNT);
            IStrategyManager(coreDeployment.strategyManager).depositIntoStrategy(
                mockStrategy,
                mockToken,
                STAKE_AMOUNT
            );

            IDelegationManager(coreDeployment.delegationManager).registerAsOperator(
                address(0), // no delegation approver
                0, // no allocation delay
                string.concat("operator-metadata_", vm.toString(i))
            );

            vm.stopPrank();
        }
    }

    // Helper function to register an operator in the SlashingRegistryCoordinator
    function registerOperatorInSlashingRegistryCoordinator(
        Operator memory operator,
        string memory socket
    ) internal {
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams = createPubkeyRegistrationParams(
            operator,
            operator.key.addr
        );

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes.RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: new uint32[](1),
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL,
                socket,
                pubkeyParams
            )
        });
        registerParams.operatorSetIds[0] = 0;

        vm.prank(operator.key.addr);
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            operator.key.addr,
            registerParams
        );
    }
}

contract SlashingRegistryCoordinator_Initialize is SlashingRegistryCoordinatorUnitTestSetup {
    function test_initialization() public {
        assertEq(slashingRegistryCoordinator.churnApprover(), churnApprover);
        assertEq(slashingRegistryCoordinator.avs(), serviceManager);
        assertEq(slashingRegistryCoordinator.ejector(), ejector);
        assertEq(slashingRegistryCoordinator.owner(), proxyAdminOwner);
        assertEq(slashingRegistryCoordinator.paused(), 0);
    }

    function test_RevertsWhen_AlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        slashingRegistryCoordinator.initialize(
            proxyAdminOwner,
            churnApprover,
            ejector,
            0,
            serviceManager
        );
    }
}

contract SlashingRegistryCoordinator_SetChurnApprover is SlashingRegistryCoordinatorUnitTestSetup {
    address newChurnApprover = address(0x123);

    function test_setChurnApprover() public {
        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.setChurnApprover(newChurnApprover);

        assertEq(slashingRegistryCoordinator.churnApprover(), newChurnApprover);
    }

    function test_RevertsWhen_CallerNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");

        vm.prank(address(0xdead));
        slashingRegistryCoordinator.setChurnApprover(newChurnApprover);
    }

    function test_emitsChurnApproverUpdatedEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ChurnApproverUpdated(churnApprover, newChurnApprover);

        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.setChurnApprover(newChurnApprover);
    }
}

contract SlashingRegistryCoordinator_SetEjectionCooldown is SlashingRegistryCoordinatorUnitTestSetup {
    uint256 newEjectionCooldown = 7 days;

    function test_setEjectionCooldown() public {
        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.setEjectionCooldown(newEjectionCooldown);

        assertEq(slashingRegistryCoordinator.ejectionCooldown(), newEjectionCooldown);
    }

    function test_RevertsWhen_CallerNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");

        vm.prank(address(0xdead));
        slashingRegistryCoordinator.setEjectionCooldown(newEjectionCooldown);
    }

    function test_emitsEjectionCooldownUpdatedEvent() public {
        vm.expectEmit(true, true, true, true);
        emit EjectionCooldownUpdated(slashingRegistryCoordinator.ejectionCooldown(), newEjectionCooldown);

        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.setEjectionCooldown(newEjectionCooldown);
    }
}

contract SlashingRegistryCoordinator_SetEjector is SlashingRegistryCoordinatorUnitTestSetup {
    address newEjector = address(0x456);

    function test_setEjector() public {
        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.setEjector(newEjector);

        assertEq(slashingRegistryCoordinator.ejector(), newEjector);
    }

    function test_RevertsWhen_CallerNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");

        vm.prank(address(0xdead));
        slashingRegistryCoordinator.setEjector(newEjector);
    }

    function test_emitsEjectorUpdatedEvent() public {
        vm.expectEmit(true, true, true, true);
        emit EjectorUpdated(ejector, newEjector);

        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.setEjector(newEjector);
    }
}

contract SlashingRegistryCoordinator_SetAVS is SlashingRegistryCoordinatorUnitTestSetup {
    address newAVS = address(0x789);

    function test_setAVS() public {
        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.setAVS(newAVS);

        assertEq(slashingRegistryCoordinator.avs(), newAVS);
    }

    function test_RevertsWhen_CallerNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");

        vm.prank(address(0xdead));
        slashingRegistryCoordinator.setAVS(newAVS);
    }
}

contract SlashingRegistryCoordinator_CreateSlashableStakeQuorum is SlashingRegistryCoordinatorUnitTestSetup {
    OperatorSetParam operatorSetParams;
    uint96 minimumStake = 100 ether;
    uint32 lookAheadPeriod = 100;

    function setUp() public override {
        super.setUp();

        operatorSetParams = ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 5000,
            kickBIPsOfTotalStake: 100
        });
    }

    function test_createSlashableStakeQuorum() public {
        uint8 initialQuorumCount = slashingRegistryCoordinator.quorumCount();

        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.createSlashableStakeQuorum(
            operatorSetParams,
            minimumStake,
            getStrategyParams(),
            lookAheadPeriod
        );

        assertEq(slashingRegistryCoordinator.quorumCount(), initialQuorumCount + 1);
    }

    function test_emitsQuorumCreatedEvent() public {
        uint8 quorumNumber = slashingRegistryCoordinator.quorumCount();
        IStakeRegistryTypes.StrategyParams[] memory strategyParams = getStrategyParams();

        vm.expectEmit(true, true, true, true);
        emit QuorumCreated({
            quorumNumber: quorumNumber,
            operatorSetParams: operatorSetParams,
            minimumStake: minimumStake,
            strategyParams: strategyParams,
            stakeType: IStakeRegistryTypes.StakeType.TOTAL_SLASHABLE,
            lookAheadPeriod: lookAheadPeriod
        });

        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.createSlashableStakeQuorum(
            operatorSetParams,
            minimumStake,
            strategyParams,
            lookAheadPeriod
        );

        assertEq(slashingRegistryCoordinator.quorumCount(), quorumNumber + 1);
        OperatorSetParam memory params = slashingRegistryCoordinator.getOperatorSetParams(quorumNumber);
        assertEq(params.maxOperatorCount, operatorSetParams.maxOperatorCount);
        assertEq(params.kickBIPsOfOperatorStake, operatorSetParams.kickBIPsOfOperatorStake);
        assertEq(params.kickBIPsOfTotalStake, operatorSetParams.kickBIPsOfTotalStake);
    }

    function test_RevertsWhen_CallerNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");

        vm.prank(address(0xdead));
        slashingRegistryCoordinator.createSlashableStakeQuorum(
            operatorSetParams,
            minimumStake,
            getStrategyParams(),
            lookAheadPeriod
        );
    }

    function test_RevertsWhen_MaxQuorumsReached() public {
        vm.startPrank(proxyAdminOwner);

        // MAX_QUORUM_COUNT is 192, but we already have one quorum from setup
        // So we need to create 191 more
        for (uint8 i = 0; i < 191; i++) {
            slashingRegistryCoordinator.createSlashableStakeQuorum(
                operatorSetParams,
                minimumStake,
                getStrategyParams(),
                lookAheadPeriod
            );
        }

        vm.expectRevert(MaxQuorumsReached.selector);
        slashingRegistryCoordinator.createSlashableStakeQuorum(
            operatorSetParams,
            minimumStake,
            getStrategyParams(),
            lookAheadPeriod
        );

        vm.stopPrank();
    }
}

contract SlashingRegistryCoordinator_CreateTotalDelegatedStakeQuorum is SlashingRegistryCoordinatorUnitTestSetup {
    ISlashingRegistryCoordinatorTypes.OperatorSetParam operatorSetParams;
    uint96 minimumStake = 100 ether;

    function setUp() public override {
        super.setUp();
        operatorSetParams = getDefaultOperatorSetParams();
    }

    function test_createTotalDelegatedStakeQuorum() public {
        uint8 initialQuorumCount = slashingRegistryCoordinator.quorumCount();

        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams,
            minimumStake,
            getStrategyParams()
        );

        assertEq(slashingRegistryCoordinator.quorumCount(), initialQuorumCount + 1);
    }

    function test_emitsQuorumCreatedEvent() public {
        uint8 quorumNumber = slashingRegistryCoordinator.quorumCount();
        IStakeRegistryTypes.StrategyParams[] memory strategyParams = getStrategyParams();

        vm.expectEmit(true, true, true, true);
        emit QuorumCreated({
            quorumNumber: quorumNumber,
            operatorSetParams: operatorSetParams,
            minimumStake: minimumStake,
            strategyParams: strategyParams,
            stakeType: IStakeRegistryTypes.StakeType.TOTAL_DELEGATED,
            lookAheadPeriod: 0
        });

        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams,
            minimumStake,
            strategyParams
        );

        assertEq(slashingRegistryCoordinator.quorumCount(), quorumNumber + 1);
        OperatorSetParam memory params = slashingRegistryCoordinator.getOperatorSetParams(quorumNumber);
        assertEq(params.maxOperatorCount, operatorSetParams.maxOperatorCount);
        assertEq(params.kickBIPsOfOperatorStake, operatorSetParams.kickBIPsOfOperatorStake);
        assertEq(params.kickBIPsOfTotalStake, operatorSetParams.kickBIPsOfTotalStake);
    }

    function test_RevertsWhen_CallerNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");

        vm.prank(address(0xdead));
        slashingRegistryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams,
            minimumStake,
            getStrategyParams()
        );
    }

    function test_RevertsWhen_MaxQuorumsReached() public {
        vm.startPrank(proxyAdminOwner);

        // MAX_QUORUM_COUNT is 192, but we already have one quorum from setup
        // So we need to create 191 more
        for (uint8 i = 0; i < 191; i++) {
            slashingRegistryCoordinator.createTotalDelegatedStakeQuorum(
                operatorSetParams,
                minimumStake,
                getStrategyParams()
            );
        }

        vm.expectRevert(MaxQuorumsReached.selector);
        slashingRegistryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams,
            minimumStake,
            getStrategyParams()
        );

        vm.stopPrank();
    }
}

contract SlashingRegistryCoordinator_RegisterOperator is SlashingRegistryCoordinatorUnitTestSetup {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    Operator internal testOperator;

    function setUp() public override {
        super.setUp();
        testOperator = operatorsByID[operatorIds.at(0)];
    }

    function test_registerOperator() public {
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams = createPubkeyRegistrationParams(
            testOperator,
            testOperator.key.addr
        );

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes.RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: new uint32[](1),
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL,
                "socket:8545",
                pubkeyParams
            )
        });
        registerParams.operatorSetIds[0] = 0; // Use quorum 0

        vm.prank(testOperator.key.addr);
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr,
            registerParams
        );

        ISlashingRegistryCoordinator.OperatorInfo memory operatorInfo = slashingRegistryCoordinator.getOperator(testOperator.key.addr);
        assertEq(uint(operatorInfo.status), uint(ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED));
    }

    function test_RevertsWhen_Paused() public {
        vm.prank(pauser);
        slashingRegistryCoordinator.pause(1); // Pause registration

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams = createPubkeyRegistrationParams(
            testOperator,
            testOperator.key.addr
        );

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes.RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: new uint32[](1),
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL,
                "socket:8545",
                pubkeyParams
            )
        });
        registerParams.operatorSetIds[0] = 0; // Use quorum 0

        vm.prank(testOperator.key.addr);
        vm.expectRevert(bytes4(keccak256("CurrentlyPaused()")));
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr,
            registerParams
        );
    }

    function test_RevertsWhen_EmptyQuorumNumbers() public {
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams = createPubkeyRegistrationParams(
            testOperator,
            testOperator.key.addr
        );

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes.RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: new uint32[](0), // Empty array
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL,
                "socket:8545",
                pubkeyParams
            )
        });

        vm.prank(testOperator.key.addr);
        vm.expectRevert(); // Should revert due to empty quorum numbers
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr,
            registerParams
        );
    }

    function test_RevertsWhen_InvalidQuorum() public {
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams = createPubkeyRegistrationParams(
            testOperator,
            testOperator.key.addr
        );

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes.RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: new uint32[](1),
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL,
                "socket:8545",
                pubkeyParams
            )
        });
        registerParams.operatorSetIds[0] = 99; // Use non-existent quorum

        vm.prank(testOperator.key.addr);
        vm.expectRevert(); // Should revert due to invalid quorum
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr,
            registerParams
        );
    }

    function test_RevertsWhen_AlreadyRegisteredForQuorum() public {
        registerOperatorInSlashingRegistryCoordinator(testOperator, "socket:8545");

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams = createPubkeyRegistrationParams(
            testOperator,
            testOperator.key.addr
        );

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes.RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: new uint32[](1),
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL,
                "socket:8545",
                pubkeyParams
            )
        });
        registerParams.operatorSetIds[0] = 0; // Use quorum 0

        vm.prank(testOperator.key.addr);
        vm.expectRevert(); // Should revert because operator is already registered for this quorum
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr,
            registerParams
        );
    }

    function test_RevertsWhen_NotAllocationManager() public {
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams = createPubkeyRegistrationParams(
            testOperator,
            testOperator.key.addr
        );

        vm.prank(testOperator.key.addr);
        vm.expectRevert(bytes4(keccak256("OnlyAllocationManager()")));
        slashingRegistryCoordinator.registerOperator(
            testOperator.key.addr,
            address(serviceManager),
            new uint32[](1),
            abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL,
                "socket:8545",
                pubkeyParams
            )
        );
    }
}

contract SlashingRegistryCoordinator_DeregisterOperator is SlashingRegistryCoordinatorUnitTestSetup {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    Operator internal testOperator;
    bytes32 internal testOperatorId;
    uint32[] internal operatorSetIds;
    bytes internal quorumNumbers;

    function setUp() public override {
        super.setUp();
        testOperator = operatorsByID[operatorIds.at(0)];
        testOperatorId = operatorIds.at(0);

        operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 0;
        quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(uint8(0));

        registerOperatorInSlashingRegistryCoordinator(testOperator, "socket:8545");
    }

    function test_deregisterOperator() public {
        IAllocationManagerTypes.DeregisterParams memory deregisterParams = IAllocationManagerTypes.DeregisterParams({
            operator: testOperator.key.addr,
            avs: address(serviceManager),
            operatorSetIds: operatorSetIds
        });

        vm.prank(testOperator.key.addr);
        IAllocationManager(coreDeployment.allocationManager).deregisterFromOperatorSets(deregisterParams);

        ISlashingRegistryCoordinator.OperatorInfo memory operatorInfo = slashingRegistryCoordinator.getOperator(testOperator.key.addr);
        assertEq(uint(operatorInfo.status), uint(ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED));
    }

    function test_emitsDeregisteredEvent() public {
        IAllocationManagerTypes.DeregisterParams memory deregisterParams = IAllocationManagerTypes.DeregisterParams({
            operator: testOperator.key.addr,
            avs: address(serviceManager),
            operatorSetIds: operatorSetIds
        });

        vm.expectEmit(true, true, true, true);
        emit OperatorDeregistered(testOperator.key.addr, testOperatorId);

        vm.prank(testOperator.key.addr);
        IAllocationManager(coreDeployment.allocationManager).deregisterFromOperatorSets(deregisterParams);
    }

    function test_RevertsWhen_Paused() public {
        vm.prank(pauser);
        slashingRegistryCoordinator.pause(2); // PAUSED_DEREGISTER_OPERATOR = 2

        IAllocationManagerTypes.DeregisterParams memory deregisterParams = IAllocationManagerTypes.DeregisterParams({
            operator: testOperator.key.addr,
            avs: address(serviceManager),
            operatorSetIds: operatorSetIds
        });

        vm.prank(testOperator.key.addr);
        vm.expectRevert(bytes4(keccak256("CurrentlyPaused()")));
        IAllocationManager(coreDeployment.allocationManager).deregisterFromOperatorSets(deregisterParams);
    }

    function test_RevertsWhen_NotRegistered() public {
        address nonRegisteredOperator = address(0xdead);

        IAllocationManagerTypes.DeregisterParams memory deregisterParams = IAllocationManagerTypes.DeregisterParams({
            operator: nonRegisteredOperator,
            avs: address(serviceManager),
            operatorSetIds: operatorSetIds
        });

        vm.prank(nonRegisteredOperator);
        vm.expectRevert(bytes4(keccak256("NotMemberOfSet()")));
        IAllocationManager(coreDeployment.allocationManager).deregisterFromOperatorSets(deregisterParams);
    }

    function test_RevertsWhen_IncorrectQuorums() public {
        // Create deregister params with incorrect quorum
        uint32[] memory incorrectOperatorSetIds = new uint32[](1);
        incorrectOperatorSetIds[0] = 99; // Non-existent quorum

        IAllocationManagerTypes.DeregisterParams memory deregisterParams = IAllocationManagerTypes.DeregisterParams({
            operator: testOperator.key.addr,
            avs: address(serviceManager),
            operatorSetIds: incorrectOperatorSetIds
        });

        vm.prank(testOperator.key.addr);
        vm.expectRevert();
        IAllocationManager(coreDeployment.allocationManager).deregisterFromOperatorSets(deregisterParams);
    }

    function test_RevertsWhen_NotAllocationManager() public {
        vm.prank(testOperator.key.addr);
        vm.expectRevert(bytes4(keccak256("OnlyAllocationManager()")));
        slashingRegistryCoordinator.deregisterOperator(
            testOperator.key.addr,
            address(serviceManager),
            operatorSetIds
        );
    }

    function test_deregisterOperatorFromSingleQuorum() public {
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams = getDefaultOperatorSetParams();

        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams,
            1 ether,
            getStrategyParams()
        );

        // Register for second quorum
        uint32[] memory additionalOperatorSetIds = new uint32[](1);
        additionalOperatorSetIds[0] = 1;

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams = createPubkeyRegistrationParams(
            testOperator,
            testOperator.key.addr
        );

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes.RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: additionalOperatorSetIds,
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL,
                "socket:8545",
                pubkeyParams
            )
        });

        vm.prank(testOperator.key.addr);
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr,
            registerParams
        );

        IAllocationManagerTypes.DeregisterParams memory deregisterParams = IAllocationManagerTypes.DeregisterParams({
            operator: testOperator.key.addr,
            avs: address(serviceManager),
            operatorSetIds: operatorSetIds // Contains only quorum 0
        });

        vm.prank(testOperator.key.addr);
        IAllocationManager(coreDeployment.allocationManager).deregisterFromOperatorSets(deregisterParams);

        ISlashingRegistryCoordinator.OperatorInfo memory operatorInfo = slashingRegistryCoordinator.getOperator(testOperator.key.addr);
        assertEq(uint(operatorInfo.status), uint(ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED));

        // Verify operator is no longer in quorum 0 but still in quorum 1
        uint192 currentBitmap = slashingRegistryCoordinator.getCurrentQuorumBitmap(testOperatorId);
        assertEq(currentBitmap, uint192(2)); // Binary 10 means registered in quorum 1 but not in quorum 0
    }
}

contract SlashingRegistryCoordinator_UpdateSocket is SlashingRegistryCoordinatorUnitTestSetup {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    string socket = "localhost:8545";
    Operator internal testOperator;
    bytes32 testOperatorId;

    function setUp() public override {
        super.setUp();
        testOperatorId = operatorIds.at(0);
        testOperator = operatorsByID[testOperatorId];
        registerOperatorInSlashingRegistryCoordinator(testOperator, socket);
    }

    function test_updateSocket() public {
        string memory newSocket = "localhost:9545";

        vm.prank(testOperator.key.addr);
        slashingRegistryCoordinator.updateSocket(newSocket);

        string memory updatedSocket = socketRegistry.getOperatorSocket(testOperatorId);
        assertEq(updatedSocket, newSocket);
    }

    function test_emitsSocketUpdateEvent() public {
        string memory newSocket = "localhost:9545";

        vm.expectEmit(true, true, true, true);
        emit OperatorSocketUpdate(testOperatorId, newSocket);

        vm.prank(testOperator.key.addr);
        slashingRegistryCoordinator.updateSocket(newSocket);
    }

    function test_RevertsWhen_NotRegistered() public {
        address nonRegisteredOperator = address(0xdead);

        vm.prank(nonRegisteredOperator);
        vm.expectRevert(NotRegistered.selector);
        slashingRegistryCoordinator.updateSocket("new-socket:8545");
    }
}

contract SlashingRegistryCoordinator_SetOperatorSetParams is SlashingRegistryCoordinatorUnitTestSetup {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    uint8 internal quorumNumber;
    ISlashingRegistryCoordinatorTypes.OperatorSetParam internal defaultOperatorSetParams;

    function setUp() public override {
        super.setUp();
        quorumNumber = 0;
        defaultOperatorSetParams = getDefaultOperatorSetParams();
    }

    function test_setOperatorSetParams() public {
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory newParams = ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 20,
            kickBIPsOfOperatorStake: 1000, // 10%
            kickBIPsOfTotalStake: 500 // 5%
        });

        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.setOperatorSetParams(quorumNumber, newParams);

        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory updatedParams = slashingRegistryCoordinator.getOperatorSetParams(quorumNumber);
        assertEq(updatedParams.maxOperatorCount, newParams.maxOperatorCount);
        assertEq(updatedParams.kickBIPsOfOperatorStake, newParams.kickBIPsOfOperatorStake);
        assertEq(updatedParams.kickBIPsOfTotalStake, newParams.kickBIPsOfTotalStake);
    }

    function test_RevertsWhen_CallerNotOwner() public {
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory newParams = ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 20,
            kickBIPsOfOperatorStake: 1000,
            kickBIPsOfTotalStake: 500
        });

        vm.prank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        slashingRegistryCoordinator.setOperatorSetParams(quorumNumber, newParams);
    }

    function test_emitsOperatorSetParamsUpdatedEvent() public {
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory newParams = ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 20,
            kickBIPsOfOperatorStake: 1000,
            kickBIPsOfTotalStake: 500
        });

        vm.expectEmit(true, true, true, true);
        emit OperatorSetParamsUpdated(quorumNumber, newParams);

        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.setOperatorSetParams(quorumNumber, newParams);
    }
}

contract SlashingRegistryCoordinator_EjectOperator is SlashingRegistryCoordinatorUnitTestSetup {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    Operator internal testOperator;
    bytes32 internal testOperatorId;
    uint32[] internal operatorSetIds;
    bytes internal quorumNumbers;

    function setUp() public override {
        super.setUp();
        testOperator = operatorsByID[operatorIds.at(0)];
        testOperatorId = operatorIds.at(0);
        operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 0;
        quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(uint8(0));

        vm.prank(serviceManager);
        IPermissionController(coreDeployment.permissionController).setAppointee(
            address(serviceManager),
            address(slashingRegistryCoordinator),
            address(coreDeployment.allocationManager),
            IAllocationManager.deregisterFromOperatorSets.selector
        );

        registerOperatorInSlashingRegistryCoordinator(testOperator, "socket:8545");
    }

    function test_ejectOperator() public {
        vm.prank(ejector);
        slashingRegistryCoordinator.ejectOperator(testOperator.key.addr, quorumNumbers);

        ISlashingRegistryCoordinator.OperatorInfo memory operatorInfo = slashingRegistryCoordinator.getOperator(testOperator.key.addr);
        assertEq(uint256(operatorInfo.status), uint256(ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED));

        assertEq(slashingRegistryCoordinator.lastEjectionTimestamp(testOperator.key.addr), block.timestamp);

        uint192 currentBitmap = slashingRegistryCoordinator.getCurrentQuorumBitmap(testOperatorId);
        assertEq(currentBitmap, 0);
    }

    function test_RevertsWhen_CallerNotEjector() public {
        vm.prank(address(0xdead));
        vm.expectRevert(bytes4(keccak256("OnlyEjector()")));
        slashingRegistryCoordinator.ejectOperator(testOperator.key.addr, quorumNumbers);
    }

    function test_RevertsWhen_OperatorNotRegistered() public {
        address nonRegisteredOperator = address(0xdead);

        vm.prank(ejector);
        vm.expectRevert(bytes4(keccak256("OperatorNotRegistered()")));
        slashingRegistryCoordinator.ejectOperator(nonRegisteredOperator, quorumNumbers);
    }

    function test_RevertsWhen_EjectionCooldownNotElapsed() public {
        vm.skip(true);
        vm.prank(ejector);
        slashingRegistryCoordinator.ejectOperator(testOperator.key.addr, quorumNumbers);

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams = createPubkeyRegistrationParams(
            testOperator,
            testOperator.key.addr
        );

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes.RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: operatorSetIds,
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL,
                "socket:8545",
                pubkeyParams
            )
        });

        vm.prank(testOperator.key.addr);
        vm.expectRevert(bytes4(keccak256("EjectionCooldownNotElapsed()")));
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr,
            registerParams
        );
    }

    function test_CanRegisterAfterEjectionCooldown() public {
        vm.prank(ejector);
        slashingRegistryCoordinator.ejectOperator(testOperator.key.addr, quorumNumbers);

        vm.warp(block.timestamp + slashingRegistryCoordinator.ejectionCooldown() + 1);

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams = createPubkeyRegistrationParams(
            testOperator,
            testOperator.key.addr
        );

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes.RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: operatorSetIds,
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL,
                "socket:8545",
                pubkeyParams
            )
        });
        vm.roll(block.number + 1800000);
        vm.warp(block.timestamp + 25 days);
        // Check registration status before registering
        OperatorSet memory operatorSet = OperatorSet(address(serviceManager), operatorSetIds[0]);
        bytes32 operatorSetKey = OperatorSetLib.key(operatorSet);
        (bool registered, uint256 slashableUntil)=
            AllocationManager(coreDeployment.allocationManager).registrationStatus(testOperator.key.addr, operatorSetKey);
        console.log("Before registration - registered:", registered);
        console.log("Before registration - slashableUntil:", slashableUntil);

        vm.prank(testOperator.key.addr);
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr,
            registerParams
        );

        (registered, slashableUntil)=
            AllocationManager(coreDeployment.allocationManager).registrationStatus(testOperator.key.addr, operatorSetKey);
        console.log("After registration - registered:", registered);
        console.log("After registration - slashableUntil:", slashableUntil);

        ISlashingRegistryCoordinator.OperatorInfo memory operatorInfo = slashingRegistryCoordinator.getOperator(testOperator.key.addr);
        assertEq(uint(operatorInfo.status), uint(ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED));
    }

    function test_ejectOperatorFromMultipleQuorums() public {
        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.createTotalDelegatedStakeQuorum(
            getDefaultOperatorSetParams(),
            1 ether,
            getStrategyParams()
        );

        uint32[] memory additionalOperatorSetIds = new uint32[](1);
        additionalOperatorSetIds[0] = 1;

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams = createPubkeyRegistrationParams(
            testOperator,
            testOperator.key.addr
        );

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes.RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: additionalOperatorSetIds,
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL,
                "socket:8545",
                pubkeyParams
            )
        });

        vm.prank(testOperator.key.addr);
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr,
            registerParams
        );

        bytes memory multiQuorumNumbers = new bytes(2);
        multiQuorumNumbers[0] = bytes1(uint8(0));
        multiQuorumNumbers[1] = bytes1(uint8(1));

        vm.prank(ejector);
        slashingRegistryCoordinator.ejectOperator(testOperator.key.addr, multiQuorumNumbers);

        uint192 currentBitmap = slashingRegistryCoordinator.getCurrentQuorumBitmap(testOperatorId);
        assertEq(currentBitmap, 0);

        ISlashingRegistryCoordinator.OperatorInfo memory operatorInfo = slashingRegistryCoordinator.getOperator(testOperator.key.addr);
        assertEq(uint(operatorInfo.status), uint(ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED));
    }

    function test_emitsOperatorDeregisteredEvent() public {
        vm.expectEmit(true, true, true, true);
        emit OperatorDeregistered(testOperator.key.addr, testOperatorId);

        vm.prank(ejector);
        slashingRegistryCoordinator.ejectOperator(testOperator.key.addr, quorumNumbers);
    }
}

contract SlashingRegistryCoordinator_RegisterWithChurn is SlashingRegistryCoordinatorUnitTestSetup {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    Operator internal testOperator;
    bytes32 internal testOperatorId;
    uint32[] internal operatorSetIds;
    bytes internal quorumNumbers;

    function setUp() public override {
        super.setUp();
    }
}

contract SlashingRegistryCoordinator_UpdateOperators is SlashingRegistryCoordinatorUnitTestSetup {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    Operator internal testOperator;
    bytes32 internal testOperatorId;
    uint32[] internal operatorSetIds;
    bytes internal quorumNumbers;

    function setUp() public override {
        super.setUp();
    }
}

contract SlashingRegistryCoordinator_UpdateOperatorsForQuorum is SlashingRegistryCoordinatorUnitTestSetup {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    Operator internal testOperator;
    bytes32 internal testOperatorId;
    uint32[] internal operatorSetIds;
    bytes internal quorumNumbers;

    function setUp() public override {
        super.setUp();
    }
}
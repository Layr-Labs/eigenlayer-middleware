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
import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
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
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategyFactory} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyFactory.sol";
import {IEigenPodManager} from "eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {DelegationManagerHarness} from "../mocks/DelegationManagerHarness.sol";
import {SlashingRegistryCoordinator} from "../../src/SlashingRegistryCoordinator.sol";
import {ISlashingRegistryCoordinatorTypes} from
    "../../src/interfaces/ISlashingRegistryCoordinator.sol";
import {IBLSApkRegistry, IBLSApkRegistryTypes} from "../../src/interfaces/IBLSApkRegistry.sol";
import {BitmapUtils} from "../../src/libraries/BitmapUtils.sol";
import {IIndexRegistry} from "../../src/interfaces/IIndexRegistry.sol";
import {ISocketRegistry} from "../../src/interfaces/ISocketRegistry.sol";
import {CoreDeployLib} from "../utils/CoreDeployLib.sol";
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
import {UpgradeableProxyLib} from "./UpgradeableProxyLib.sol";

contract SlashingRegistryCoordinatorUnitTestSetup is
    Test,
    ISlashingRegistryCoordinatorEvents,
    ISlashingRegistryCoordinatorErrors
{
    using EnumerableSet for EnumerableSet.Bytes32Set;

    EnumerableSet.Bytes32Set internal operatorIds;
    mapping(bytes32 => Operator) internal operatorsByID;

    InstantSlasher internal instantSlasher;
    ProxyAdmin internal proxyAdmin;
    EmptyContract internal emptyContract;
    SlashingRegistryCoordinator internal slashingRegistryCoordinator;
    CoreDeployLib.DeploymentData internal coreDeployment;
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
    uint256 internal churnApproverPrivateKey =
        0x123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef;
    address internal churnApprover = vm.addr(churnApproverPrivateKey);
    address internal ejector = address(uint160(uint256(keccak256("ejector"))));

    uint32 internal constant DEALLOCATION_DELAY = 7 days;
    uint32 internal constant ALLOCATION_CONFIGURATION_DELAY = 1 days;
    uint256 internal NUMBER_OF_OPERATORS = 10;
    uint256 constant STAKE_AMOUNT = 10 ether;

    function createPubkeyRegistrationParams(
        Operator memory operator,
        address operatorAddress
    ) internal view returns (IBLSApkRegistryTypes.PubkeyRegistrationParams memory) {
        bytes32 messageHash =
            slashingRegistryCoordinator.calculatePubkeyRegistrationMessageHash(operatorAddress);
        BN254.G1Point memory signature =
            SigningKeyOperationsLib.sign(operator.signingKey, messageHash);

        return IBLSApkRegistryTypes.PubkeyRegistrationParams(
            signature, operator.signingKey.publicKeyG1, operator.signingKey.publicKeyG2
        );
    }

    function getStrategyParams()
        internal
        view
        returns (IStakeRegistryTypes.StrategyParams[] memory)
    {
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] =
            IStakeRegistryTypes.StrategyParams({strategy: mockStrategy, multiplier: 1 ether});
        return strategyParams;
    }

    function getDefaultOperatorSetParams()
        internal
        pure
        returns (ISlashingRegistryCoordinatorTypes.OperatorSetParam memory)
    {
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

        mockToken = new ERC20Mock();

        vm.startPrank(proxyAdminOwner);
        proxyAdmin = new ProxyAdmin();
        emptyContract = new EmptyContract();

        address[] memory pausers = new address[](1);
        pausers[0] = pauser;
        pauserRegistry = new PauserRegistry(pausers, unpauser);

        CoreDeployLib.DeploymentConfigData memory configData;
        configData.strategyManager.initialOwner = proxyAdminOwner;
        configData.strategyManager.initialStrategyWhitelister = proxyAdminOwner;
        configData.strategyManager.initPausedStatus = 0;

        configData.delegationManager.initialOwner = proxyAdminOwner;
        configData.delegationManager.minWithdrawalDelayBlocks = 100800;
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

        coreDeployment = CoreDeployLib.deployContracts(address(proxyAdmin), configData);

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
        stakeRegistry = StakeRegistry(middlewareDeployments.stakeRegistry);
        blsApkRegistry = BLSApkRegistry(middlewareDeployments.blsApkRegistry);
        indexRegistry = IndexRegistry(middlewareDeployments.indexRegistry);

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
            address(serviceManager), IAVSRegistrar(address(slashingRegistryCoordinator))
        );

        for (uint256 i = 0; i < operatorIds.length(); i++) {
            bytes32 operatorId = operatorIds.at(i);
            Operator memory operator = operatorsByID[operatorId];

            mockToken.mint(operator.key.addr, STAKE_AMOUNT);

            vm.startPrank(operator.key.addr);

            mockToken.approve(address(coreDeployment.strategyManager), STAKE_AMOUNT);
            IStrategyManager(coreDeployment.strategyManager).depositIntoStrategy(
                mockStrategy, mockToken, STAKE_AMOUNT
            );

            IDelegationManager(coreDeployment.delegationManager).registerAsOperator(
                address(0), // no delegation approver
                0, // no allocation delay
                string.concat("operator-metadata_", vm.toString(i))
            );

            vm.stopPrank();
        }
    }

    function registerOperatorInSlashingRegistryCoordinator(
        Operator memory operator,
        string memory socket,
        uint32[] memory operatorSetIds
    ) internal {
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams =
            createPubkeyRegistrationParams(operator, operator.key.addr);

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: operatorSetIds,
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL, socket, pubkeyParams
            )
        });

        vm.prank(operator.key.addr);
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            operator.key.addr, registerParams
        );
    }

    // Helper function to register an operator in the SlashingRegistryCoordinator for a single quorum
    function registerOperatorInSlashingRegistryCoordinator(
        Operator memory operator,
        string memory socket,
        uint32 operatorSetId
    ) internal {
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = operatorSetId;

        registerOperatorInSlashingRegistryCoordinator(operator, socket, operatorSetIds);
    }

    function _setOperatorWeight(address operator, uint96 weight) internal {
        DelegationManagerHarness(address(coreDeployment.delegationManager)).setOperatorShares(
            operator, mockStrategy, weight
        );
        DelegationManagerHarness(address(coreDeployment.delegationManager)).setIsOperator(
            operator, true
        );
    }

    function _useDelegationManagerHarness() internal {
        uint32 minWithdrawDelayBlocks =
            IDelegationManager(coreDeployment.delegationManager).minWithdrawalDelayBlocks();
        DelegationManagerHarness delegationManagerHarness = new DelegationManagerHarness(
            IStrategyManager(coreDeployment.strategyManager),
            IEigenPodManager(coreDeployment.eigenPodManager),
            IAllocationManager(coreDeployment.allocationManager),
            IPauserRegistry(coreDeployment.pauserRegistry),
            IPermissionController(coreDeployment.permissionController),
            minWithdrawDelayBlocks
        );

        vm.prank(proxyAdminOwner);
        UpgradeableProxyLib.upgrade(
            address(coreDeployment.delegationManager), address(delegationManagerHarness)
        );
    }

    function _createOperatorArray(
        Operator[] memory operators
    ) internal pure returns (address[] memory) {
        address[] memory operatorAddresses = new address[](operators.length);
        for (uint256 i = 0; i < operators.length; i++) {
            operatorAddresses[i] = operators[i].key.addr;
        }
        return operatorAddresses;
    }

    function _createOperatorIdArray(
        bytes32[] memory operatorIds
    ) internal pure returns (bytes32[] memory) {
        bytes32[] memory operatorIdArray = new bytes32[](operatorIds.length);
        for (uint256 i = 0; i < operatorIds.length; i++) {
            operatorIdArray[i] = operatorIds[i];
        }
        return operatorIdArray;
    }

    function _verifyOperatorStatus(
        address operator,
        ISlashingRegistryCoordinatorTypes.OperatorStatus expectedStatus
    ) internal view {
        ISlashingRegistryCoordinator.OperatorInfo memory operatorInfo =
            slashingRegistryCoordinator.getOperator(operator);
        assertEq(
            uint256(operatorInfo.status),
            uint256(expectedStatus),
            "Operator status does not match expected status"
        );
    }

    function _verifyOperatorBitmap(bytes32 operatorId, uint192 expectedBitmap) internal view {
        uint192 currentBitmap = slashingRegistryCoordinator.getCurrentQuorumBitmap(operatorId);
        assertEq(currentBitmap, expectedBitmap, "Operator bitmap does not match expected bitmap");
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
            proxyAdminOwner, churnApprover, ejector, 0, serviceManager
        );
    }
}

contract SlashingRegistryCoordinator_SetChurnApprover is
    SlashingRegistryCoordinatorUnitTestSetup
{
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

contract SlashingRegistryCoordinator_SetEjectionCooldown is
    SlashingRegistryCoordinatorUnitTestSetup
{
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
        emit EjectionCooldownUpdated(
            slashingRegistryCoordinator.ejectionCooldown(), newEjectionCooldown
        );

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

    function test_emitsAVSUpdatedEvent() public {
        vm.expectEmit(true, true, true, true);
        emit AVSUpdated(serviceManager, newAVS);

        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.setAVS(newAVS);
    }
}

contract SlashingRegistryCoordinator_AVSSupport is SlashingRegistryCoordinatorUnitTestSetup {
    address internal oldAVS;
    Operator internal testOperator;

    function setUp() public virtual override {
        super.setUp();
        testOperator = OperatorWalletLib.createOperator("test_operator");
        _useDelegationManagerHarness();
        DelegationManagerHarness(address(coreDeployment.delegationManager)).setOperatorShares(
            testOperator.key.addr, mockStrategy, STAKE_AMOUNT
        );
        DelegationManagerHarness(address(coreDeployment.delegationManager)).setIsOperator(
            testOperator.key.addr, true
        );

        // Store the original AVS and set new AVS
        oldAVS = slashingRegistryCoordinator.avs();
        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.setAVS(address(0x123));
    }

    function test_RevertsWhen_RegisterOldAVS() public {
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams =
            createPubkeyRegistrationParams(testOperator, testOperator.key.addr);

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: oldAVS, // Using old AVS that no longer matches
            operatorSetIds: new uint32[](1),
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL, "socket:8545", pubkeyParams
            )
        });
        registerParams.operatorSetIds[0] = 0;

        vm.prank(testOperator.key.addr);
        vm.expectRevert(bytes4(keccak256("InvalidAVS()")));
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr, registerParams
        );
    }

    function test_RevertsWhen_DeregisterOldAVS() public {
        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.setAVS(oldAVS);

        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 0;
        registerOperatorInSlashingRegistryCoordinator(testOperator, "socket:8545", operatorSetIds);

        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.setAVS(address(0x123));

        IAllocationManagerTypes.DeregisterParams memory deregisterParams = IAllocationManagerTypes
            .DeregisterParams({
            operator: testOperator.key.addr,
            avs: oldAVS, // Using old AVS that no longer matches
            operatorSetIds: operatorSetIds
        });

        vm.prank(testOperator.key.addr);
        vm.expectRevert(bytes4(keccak256("InvalidAVS()")));
        IAllocationManager(coreDeployment.allocationManager).deregisterFromOperatorSets(
            deregisterParams
        );
    }
}

contract SlashingRegistryCoordinator_CreateSlashableStakeQuorum is
    SlashingRegistryCoordinatorUnitTestSetup
{
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
            operatorSetParams, minimumStake, getStrategyParams(), lookAheadPeriod
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
            operatorSetParams, minimumStake, strategyParams, lookAheadPeriod
        );

        assertEq(slashingRegistryCoordinator.quorumCount(), quorumNumber + 1);
        OperatorSetParam memory params =
            slashingRegistryCoordinator.getOperatorSetParams(quorumNumber);
        assertEq(params.maxOperatorCount, operatorSetParams.maxOperatorCount);
        assertEq(params.kickBIPsOfOperatorStake, operatorSetParams.kickBIPsOfOperatorStake);
        assertEq(params.kickBIPsOfTotalStake, operatorSetParams.kickBIPsOfTotalStake);
    }

    function test_RevertsWhen_CallerNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");

        vm.prank(address(0xdead));
        slashingRegistryCoordinator.createSlashableStakeQuorum(
            operatorSetParams, minimumStake, getStrategyParams(), lookAheadPeriod
        );
    }

    function test_RevertsWhen_MaxQuorumsReached() public {
        vm.startPrank(proxyAdminOwner);

        // MAX_QUORUM_COUNT is 192, but we already have one quorum from setup
        // So we need to create 191 more
        for (uint8 i = 0; i < 191; i++) {
            slashingRegistryCoordinator.createSlashableStakeQuorum(
                operatorSetParams, minimumStake, getStrategyParams(), lookAheadPeriod
            );
        }

        vm.expectRevert(MaxQuorumsReached.selector);
        slashingRegistryCoordinator.createSlashableStakeQuorum(
            operatorSetParams, minimumStake, getStrategyParams(), lookAheadPeriod
        );

        vm.stopPrank();
    }

    function test_RevertsWhen_LookAheadPeriodTooLong() public {
        uint32 deallocationDelay =
            AllocationManager(address(coreDeployment.allocationManager)).DEALLOCATION_DELAY();

        uint32 tooLongLookAheadPeriod = deallocationDelay;

        vm.prank(proxyAdminOwner);
        vm.expectRevert(LookAheadPeriodTooLong.selector);
        slashingRegistryCoordinator.createSlashableStakeQuorum(
            operatorSetParams, minimumStake, getStrategyParams(), tooLongLookAheadPeriod
        );
    }
}

contract SlashingRegistryCoordinator_CreateTotalDelegatedStakeQuorum is
    SlashingRegistryCoordinatorUnitTestSetup
{
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
            operatorSetParams, minimumStake, getStrategyParams()
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
            operatorSetParams, minimumStake, strategyParams
        );

        assertEq(slashingRegistryCoordinator.quorumCount(), quorumNumber + 1);
        OperatorSetParam memory params =
            slashingRegistryCoordinator.getOperatorSetParams(quorumNumber);
        assertEq(params.maxOperatorCount, operatorSetParams.maxOperatorCount);
        assertEq(params.kickBIPsOfOperatorStake, operatorSetParams.kickBIPsOfOperatorStake);
        assertEq(params.kickBIPsOfTotalStake, operatorSetParams.kickBIPsOfTotalStake);
    }

    function test_RevertsWhen_CallerNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");

        vm.prank(address(0xdead));
        slashingRegistryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams, minimumStake, getStrategyParams()
        );
    }

    function test_RevertsWhen_MaxQuorumsReached() public {
        vm.startPrank(proxyAdminOwner);

        // MAX_QUORUM_COUNT is 192, but we already have one quorum from setup
        // So we need to create 191 more
        for (uint8 i = 0; i < 191; i++) {
            slashingRegistryCoordinator.createTotalDelegatedStakeQuorum(
                operatorSetParams, minimumStake, getStrategyParams()
            );
        }

        vm.expectRevert(MaxQuorumsReached.selector);
        slashingRegistryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams, minimumStake, getStrategyParams()
        );

        vm.stopPrank();
    }
}

contract SlashingRegistryCoordinator_RegisterOperator is
    SlashingRegistryCoordinatorUnitTestSetup
{
    using EnumerableSet for EnumerableSet.Bytes32Set;

    Operator internal testOperator;
    uint32 internal quorumNumber;

    function setUp() public override {
        super.setUp();
        testOperator = operatorsByID[operatorIds.at(0)];
        quorumNumber = 0;
    }

    function test_registerOperator() public {
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams =
            createPubkeyRegistrationParams(testOperator, testOperator.key.addr);

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: new uint32[](1),
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL, "socket:8545", pubkeyParams
            )
        });
        registerParams.operatorSetIds[0] = 0; // Use quorum 0

        vm.prank(testOperator.key.addr);
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr, registerParams
        );

        ISlashingRegistryCoordinator.OperatorInfo memory operatorInfo =
            slashingRegistryCoordinator.getOperator(testOperator.key.addr);
        assertEq(
            uint256(operatorInfo.status),
            uint256(ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED)
        );
    }

    function test_RevertsWhen_Paused() public {
        vm.prank(pauser);
        slashingRegistryCoordinator.pause(1); // Pause registration

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams =
            createPubkeyRegistrationParams(testOperator, testOperator.key.addr);

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: new uint32[](1),
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL, "socket:8545", pubkeyParams
            )
        });
        registerParams.operatorSetIds[0] = 0; // Use quorum 0

        vm.prank(testOperator.key.addr);
        vm.expectRevert(bytes4(keccak256("CurrentlyPaused()")));
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr, registerParams
        );
    }

    function test_RevertsWhen_EmptyQuorumNumbers() public {
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams =
            createPubkeyRegistrationParams(testOperator, testOperator.key.addr);

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: new uint32[](0), // Empty array
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL, "socket:8545", pubkeyParams
            )
        });

        vm.prank(testOperator.key.addr);
        vm.expectRevert(); // Should revert due to empty quorum numbers
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr, registerParams
        );
    }

    function test_RevertsWhen_InvalidQuorum() public {
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams =
            createPubkeyRegistrationParams(testOperator, testOperator.key.addr);

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: new uint32[](1),
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL, "socket:8545", pubkeyParams
            )
        });
        registerParams.operatorSetIds[0] = 99; // Use non-existent quorum

        vm.prank(testOperator.key.addr);
        vm.expectRevert(); // Should revert due to invalid quorum
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr, registerParams
        );
    }

    function test_RevertsWhen_AlreadyRegisteredForQuorum() public {
        registerOperatorInSlashingRegistryCoordinator(testOperator, "socket:8545", quorumNumber);

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams =
            createPubkeyRegistrationParams(testOperator, testOperator.key.addr);

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: new uint32[](1),
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL, "socket:8545", pubkeyParams
            )
        });
        registerParams.operatorSetIds[0] = 0; // Use quorum 0

        vm.prank(testOperator.key.addr);
        vm.expectRevert(); // Should revert because operator is already registered for this quorum
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr, registerParams
        );
    }

    function test_RevertsWhen_NotAllocationManager() public {
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams =
            createPubkeyRegistrationParams(testOperator, testOperator.key.addr);

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

    function test_RevertsWhen_MaxOperatorCountReached() public {
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 2, // Only allow 2 operators
            kickBIPsOfOperatorStake: 0,
            kickBIPsOfTotalStake: 0
        });

        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams,
            1 ether, // minimum stake
            getStrategyParams()
        );

        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 1; // Use the newly created quorum

        Operator memory operator1 = operatorsByID[operatorIds.at(0)];
        registerOperatorInSlashingRegistryCoordinator(operator1, "socket1:8545", operatorSetIds);

        Operator memory operator2 = operatorsByID[operatorIds.at(1)];
        registerOperatorInSlashingRegistryCoordinator(operator2, "socket2:8545", operatorSetIds);

        // Try to register third operator (should fail)
        Operator memory operator3 = operatorsByID[operatorIds.at(2)];
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams =
            createPubkeyRegistrationParams(operator3, operator3.key.addr);

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: operatorSetIds,
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL, "socket3:8545", pubkeyParams
            )
        });

        vm.prank(operator3.key.addr);
        vm.expectRevert(MaxOperatorCountReached.selector);
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            operator3.key.addr, registerParams
        );

        _verifyOperatorStatus(
            operator1.key.addr, ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
        );
        _verifyOperatorStatus(
            operator2.key.addr, ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
        );
        _verifyOperatorStatus(
            operator3.key.addr, ISlashingRegistryCoordinatorTypes.OperatorStatus.NEVER_REGISTERED
        );
    }
}

contract SlashingRegistryCoordinator_DeregisterOperator is
    SlashingRegistryCoordinatorUnitTestSetup
{
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

        registerOperatorInSlashingRegistryCoordinator(testOperator, "socket:8545", operatorSetIds);
    }

    function test_deregisterOperator() public {
        IAllocationManagerTypes.DeregisterParams memory deregisterParams = IAllocationManagerTypes
            .DeregisterParams({
            operator: testOperator.key.addr,
            avs: address(serviceManager),
            operatorSetIds: operatorSetIds
        });

        vm.prank(testOperator.key.addr);
        IAllocationManager(coreDeployment.allocationManager).deregisterFromOperatorSets(
            deregisterParams
        );

        ISlashingRegistryCoordinator.OperatorInfo memory operatorInfo =
            slashingRegistryCoordinator.getOperator(testOperator.key.addr);
        assertEq(
            uint256(operatorInfo.status),
            uint256(ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED)
        );
    }

    function test_emitsDeregisteredEvent() public {
        IAllocationManagerTypes.DeregisterParams memory deregisterParams = IAllocationManagerTypes
            .DeregisterParams({
            operator: testOperator.key.addr,
            avs: address(serviceManager),
            operatorSetIds: operatorSetIds
        });

        vm.expectEmit(true, true, true, true);
        emit OperatorDeregistered(testOperator.key.addr, testOperatorId);

        vm.prank(testOperator.key.addr);
        IAllocationManager(coreDeployment.allocationManager).deregisterFromOperatorSets(
            deregisterParams
        );
    }

    function test_RevertsWhen_Paused() public {
        vm.prank(pauser);
        slashingRegistryCoordinator.pause(2); // PAUSED_DEREGISTER_OPERATOR = 2

        IAllocationManagerTypes.DeregisterParams memory deregisterParams = IAllocationManagerTypes
            .DeregisterParams({
            operator: testOperator.key.addr,
            avs: address(serviceManager),
            operatorSetIds: operatorSetIds
        });

        vm.prank(testOperator.key.addr);
        vm.expectRevert(bytes4(keccak256("CurrentlyPaused()")));
        IAllocationManager(coreDeployment.allocationManager).deregisterFromOperatorSets(
            deregisterParams
        );
    }

    function test_RevertsWhen_NotRegistered() public {
        address nonRegisteredOperator = address(0xdead);

        IAllocationManagerTypes.DeregisterParams memory deregisterParams = IAllocationManagerTypes
            .DeregisterParams({
            operator: nonRegisteredOperator,
            avs: address(serviceManager),
            operatorSetIds: operatorSetIds
        });

        vm.prank(nonRegisteredOperator);
        vm.expectRevert(bytes4(keccak256("NotMemberOfSet()")));
        IAllocationManager(coreDeployment.allocationManager).deregisterFromOperatorSets(
            deregisterParams
        );
    }

    function test_RevertsWhen_IncorrectQuorums() public {
        // Create deregister params with incorrect quorum
        uint32[] memory incorrectOperatorSetIds = new uint32[](1);
        incorrectOperatorSetIds[0] = 99; // Non-existent quorum

        IAllocationManagerTypes.DeregisterParams memory deregisterParams = IAllocationManagerTypes
            .DeregisterParams({
            operator: testOperator.key.addr,
            avs: address(serviceManager),
            operatorSetIds: incorrectOperatorSetIds
        });

        vm.prank(testOperator.key.addr);
        vm.expectRevert();
        IAllocationManager(coreDeployment.allocationManager).deregisterFromOperatorSets(
            deregisterParams
        );
    }

    function test_RevertsWhen_NotAllocationManager() public {
        vm.prank(testOperator.key.addr);
        vm.expectRevert(bytes4(keccak256("OnlyAllocationManager()")));
        slashingRegistryCoordinator.deregisterOperator(
            testOperator.key.addr, address(serviceManager), operatorSetIds
        );
    }

    function test_deregisterOperatorFromSingleQuorum() public {
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams =
            getDefaultOperatorSetParams();

        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams, 1 ether, getStrategyParams()
        );

        uint32[] memory additionalOperatorSetIds = new uint32[](1);
        additionalOperatorSetIds[0] = 1;

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams =
            createPubkeyRegistrationParams(testOperator, testOperator.key.addr);

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: additionalOperatorSetIds,
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL, "socket:8545", pubkeyParams
            )
        });

        vm.prank(testOperator.key.addr);
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr, registerParams
        );

        IAllocationManagerTypes.DeregisterParams memory deregisterParams = IAllocationManagerTypes
            .DeregisterParams({
            operator: testOperator.key.addr,
            avs: address(serviceManager),
            operatorSetIds: operatorSetIds // Contains only quorum 0
        });

        vm.prank(testOperator.key.addr);
        IAllocationManager(coreDeployment.allocationManager).deregisterFromOperatorSets(
            deregisterParams
        );

        ISlashingRegistryCoordinator.OperatorInfo memory operatorInfo =
            slashingRegistryCoordinator.getOperator(testOperator.key.addr);
        assertEq(
            uint256(operatorInfo.status),
            uint256(ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED)
        );

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
    uint32 internal operatorSetId;

    function setUp() public override {
        super.setUp();
        testOperatorId = operatorIds.at(0);
        testOperator = operatorsByID[testOperatorId];
        operatorSetId = 0;
        registerOperatorInSlashingRegistryCoordinator(testOperator, socket, operatorSetId);
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

contract SlashingRegistryCoordinator_SetOperatorSetParams is
    SlashingRegistryCoordinatorUnitTestSetup
{
    using EnumerableSet for EnumerableSet.Bytes32Set;

    uint8 internal quorumNumber;
    ISlashingRegistryCoordinatorTypes.OperatorSetParam internal defaultOperatorSetParams;

    function setUp() public override {
        super.setUp();
        quorumNumber = 0;
        defaultOperatorSetParams = getDefaultOperatorSetParams();
    }

    function test_setOperatorSetParams() public {
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory newParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 20,
            kickBIPsOfOperatorStake: 1000, // 10%
            kickBIPsOfTotalStake: 500 // 5%
        });

        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.setOperatorSetParams(quorumNumber, newParams);

        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory updatedParams =
            slashingRegistryCoordinator.getOperatorSetParams(quorumNumber);
        assertEq(updatedParams.maxOperatorCount, newParams.maxOperatorCount);
        assertEq(updatedParams.kickBIPsOfOperatorStake, newParams.kickBIPsOfOperatorStake);
        assertEq(updatedParams.kickBIPsOfTotalStake, newParams.kickBIPsOfTotalStake);
    }

    function test_RevertsWhen_CallerNotOwner() public {
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory newParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 20,
            kickBIPsOfOperatorStake: 1000,
            kickBIPsOfTotalStake: 500
        });

        vm.prank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        slashingRegistryCoordinator.setOperatorSetParams(quorumNumber, newParams);
    }

    function test_emitsOperatorSetParamsUpdatedEvent() public {
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory newParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 20,
            kickBIPsOfOperatorStake: 1000,
            kickBIPsOfTotalStake: 500
        });

        vm.expectEmit(true, true, true, true);
        emit OperatorSetParamsUpdated(quorumNumber, newParams);

        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.setOperatorSetParams(quorumNumber, newParams);
    }

    function test_RevertsWhen_QuorumDoesNotExist() public {
        // Define new operator set params
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory newParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 20,
            kickBIPsOfOperatorStake: 1000,
            kickBIPsOfTotalStake: 500
        });

        /// Quorum 1 doesn't exist yet
        vm.prank(proxyAdminOwner);
        vm.expectRevert(QuorumDoesNotExist.selector);
        slashingRegistryCoordinator.setOperatorSetParams(1, newParams);
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

        registerOperatorInSlashingRegistryCoordinator(testOperator, "socket:8545", operatorSetIds);
    }

    function test_ejectOperator() public {
        vm.prank(ejector);
        slashingRegistryCoordinator.ejectOperator(testOperator.key.addr, quorumNumbers);

        ISlashingRegistryCoordinator.OperatorInfo memory operatorInfo =
            slashingRegistryCoordinator.getOperator(testOperator.key.addr);
        assertEq(
            uint256(operatorInfo.status),
            uint256(ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED)
        );

        assertEq(
            slashingRegistryCoordinator.lastEjectionTimestamp(testOperator.key.addr),
            block.timestamp
        );

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

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams =
            createPubkeyRegistrationParams(testOperator, testOperator.key.addr);

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: operatorSetIds,
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL, "socket:8545", pubkeyParams
            )
        });

        vm.prank(testOperator.key.addr);
        vm.expectRevert(bytes4(keccak256("EjectionCooldownNotElapsed()")));
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr, registerParams
        );
    }

    function test_CanRegisterAfterEjectionCooldown() public {
        vm.prank(ejector);
        slashingRegistryCoordinator.ejectOperator(testOperator.key.addr, quorumNumbers);

        vm.warp(block.timestamp + slashingRegistryCoordinator.ejectionCooldown() + 1);

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams =
            createPubkeyRegistrationParams(testOperator, testOperator.key.addr);

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: operatorSetIds,
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL, "socket:8545", pubkeyParams
            )
        });

        /// TODO: EjectionCooldown is somewhat pointless based on this
        uint32 deallocationDelay =
            AllocationManager(coreDeployment.allocationManager).DEALLOCATION_DELAY();
        vm.roll(block.number + deallocationDelay + 1);

        OperatorSet memory operatorSet = OperatorSet(address(serviceManager), operatorSetIds[0]);
        bool isMember = IAllocationManager(coreDeployment.allocationManager).isMemberOfOperatorSet(
            testOperator.key.addr, operatorSet
        );
        assertFalse(isMember);

        vm.prank(testOperator.key.addr);
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr, registerParams
        );

        isMember = IAllocationManager(coreDeployment.allocationManager).isMemberOfOperatorSet(
            testOperator.key.addr, operatorSet
        );
        assertTrue(isMember);

        ISlashingRegistryCoordinator.OperatorInfo memory operatorInfo =
            slashingRegistryCoordinator.getOperator(testOperator.key.addr);
        assertEq(
            uint256(operatorInfo.status),
            uint256(ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED)
        );
    }

    function test_ejectOperatorFromMultipleQuorums() public {
        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.createTotalDelegatedStakeQuorum(
            getDefaultOperatorSetParams(), 1 ether, getStrategyParams()
        );

        uint32[] memory additionalOperatorSetIds = new uint32[](1);
        additionalOperatorSetIds[0] = 1;

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams =
            createPubkeyRegistrationParams(testOperator, testOperator.key.addr);

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: additionalOperatorSetIds,
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL, "socket:8545", pubkeyParams
            )
        });

        vm.prank(testOperator.key.addr);
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr, registerParams
        );

        bytes memory multiQuorumNumbers = new bytes(2);
        multiQuorumNumbers[0] = bytes1(uint8(0));
        multiQuorumNumbers[1] = bytes1(uint8(1));

        vm.prank(ejector);
        slashingRegistryCoordinator.ejectOperator(testOperator.key.addr, multiQuorumNumbers);

        uint192 currentBitmap = slashingRegistryCoordinator.getCurrentQuorumBitmap(testOperatorId);
        assertEq(currentBitmap, 0);

        ISlashingRegistryCoordinator.OperatorInfo memory operatorInfo =
            slashingRegistryCoordinator.getOperator(testOperator.key.addr);
        assertEq(
            uint256(operatorInfo.status),
            uint256(ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED)
        );
    }

    function test_emitsOperatorDeregisteredEvent() public {
        vm.expectEmit(true, true, true, true);
        emit OperatorDeregistered(testOperator.key.addr, testOperatorId);

        vm.prank(ejector);
        slashingRegistryCoordinator.ejectOperator(testOperator.key.addr, quorumNumbers);
    }
}

contract SlashingRegistryCoordinator_RegisterWithChurn is
    SlashingRegistryCoordinatorUnitTestSetup
{
    using EnumerableSet for EnumerableSet.Bytes32Set;

    OperatorSetParam operatorSetParams;
    Operator internal testOperator;
    Operator internal operatorToKick;
    Operator internal extraOperator1;
    Operator internal extraOperator2;
    Operator internal extraOperator3;
    bytes32 internal testOperatorId;
    bytes32 internal operatorToKickId;
    bytes internal quorumNumbers;
    uint96 internal registeringStake;
    uint96 internal operatorToKickStake;
    bytes32 internal defaultSalt;
    uint256 internal defaultExpiry;

    function setUp() public override {
        super.setUp();

        _useDelegationManagerHarness();
        operatorSetParams = ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 4,
            kickBIPsOfOperatorStake: 5000,
            kickBIPsOfTotalStake: 5000
        });
        testOperator = operatorsByID[operatorIds.at(0)];
        operatorToKick = operatorsByID[operatorIds.at(1)];
        extraOperator1 = operatorsByID[operatorIds.at(2)];
        extraOperator2 = operatorsByID[operatorIds.at(3)];
        extraOperator3 = operatorsByID[operatorIds.at(4)];
        testOperatorId = operatorIds.at(0);
        operatorToKickId = operatorIds.at(1);

        testOperator = operatorsByID[operatorIds.at(0)];
        operatorToKick = operatorsByID[operatorIds.at(1)];

        quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(uint8(1));

        registeringStake = 20 ether; // Higher stake for the registering operator
        operatorToKickStake = 10 ether; // Lower stake for the operator to be kicked

        defaultSalt = bytes32(uint256(1));
        defaultExpiry = block.timestamp + 1 days;

        /// precondition
        uint192 initialBitmap = slashingRegistryCoordinator.getCurrentQuorumBitmap(operatorToKickId);
        assertEq(initialBitmap, 0, "Operator should not be registered to any quorum initially");

        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] =
            IStakeRegistryTypes.StrategyParams({strategy: mockStrategy, multiplier: 1 ether});

        vm.startPrank(proxyAdminOwner);
        slashingRegistryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams,
            1 ether, // minimum stake
            strategyParams
        );

        vm.stopPrank();
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 1;
        registerOperatorInSlashingRegistryCoordinator(operatorToKick, "socket:8545", operatorSetIds);
        registerOperatorInSlashingRegistryCoordinator(extraOperator1, "socket:8545", operatorSetIds);
        registerOperatorInSlashingRegistryCoordinator(extraOperator2, "socket:8545", operatorSetIds);
        registerOperatorInSlashingRegistryCoordinator(extraOperator3, "socket:8545", operatorSetIds);

        vm.prank(serviceManager);
        IPermissionController(coreDeployment.permissionController).setAppointee(
            address(serviceManager),
            address(slashingRegistryCoordinator),
            address(coreDeployment.allocationManager),
            IAllocationManager.deregisterFromOperatorSets.selector
        );
    }

    function _signChurnApproval(
        address registeringOperator,
        bytes32 registeringOperatorId,
        ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory operatorKickParams,
        bytes32 salt,
        uint256 expiry
    ) internal view returns (ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory) {
        bytes32 digestHash = slashingRegistryCoordinator.calculateOperatorChurnApprovalDigestHash(
            registeringOperator, registeringOperatorId, operatorKickParams, salt, expiry
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(churnApproverPrivateKey, digestHash);
        return ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry({
            signature: abi.encodePacked(r, s, v),
            salt: salt,
            expiry: expiry
        });
    }

    function _createOperatorKickParams(
        address operatorToKick,
        bytes memory quorumNumbers
    ) internal pure returns (ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory) {
        ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory operatorKickParams =
            new ISlashingRegistryCoordinatorTypes.OperatorKickParam[](quorumNumbers.length);

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            operatorKickParams[i] = ISlashingRegistryCoordinatorTypes.OperatorKickParam({
                operator: operatorToKick,
                quorumNumber: uint8(quorumNumbers[i])
            });
        }

        return operatorKickParams;
    }

    function _registerOperatorWithChurn(
        Operator memory operator,
        ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory operatorKickParams,
        string memory socket,
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory churnApproverSignature
    ) internal {
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams =
            createPubkeyRegistrationParams(operator, operator.key.addr);

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: new uint32[](quorumNumbers.length),
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.CHURN,
                socket,
                pubkeyParams,
                operatorKickParams,
                churnApproverSignature
            )
        });

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            registerParams.operatorSetIds[i] = uint8(quorumNumbers[i]);
        }

        vm.prank(operator.key.addr);
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            operator.key.addr, registerParams
        );
    }

    function _setupChurnTest(
        uint96 registeringOperatorStake,
        uint96 operatorToKickStake
    )
        internal
        returns (
            ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory operatorKickParams,
            ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory churnApproverSignature
        )
    {
        _setOperatorWeight(testOperator.key.addr, registeringOperatorStake);
        _setOperatorWeight(operatorToKick.key.addr, operatorToKickStake);

        operatorKickParams = _createOperatorKickParams(operatorToKick.key.addr, quorumNumbers);

        churnApproverSignature = _signChurnApproval(
            testOperator.key.addr, testOperatorId, operatorKickParams, defaultSalt, defaultExpiry
        );

        return (operatorKickParams, churnApproverSignature);
    }

    function test_registerOperatorWithChurn() public {
        (
            ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory operatorKickParams,
            ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory churnApproverSignature
        ) = _setupChurnTest(registeringStake, operatorToKickStake);

        _registerOperatorWithChurn(
            testOperator, operatorKickParams, "socket:8545", churnApproverSignature
        );

        ISlashingRegistryCoordinator.OperatorInfo memory operatorInfo =
            slashingRegistryCoordinator.getOperator(testOperator.key.addr);
        assertEq(
            uint256(operatorInfo.status),
            uint256(ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED),
            "Registering operator should have REGISTERED status"
        );

        ISlashingRegistryCoordinator.OperatorInfo memory kickedOperatorInfo =
            slashingRegistryCoordinator.getOperator(operatorToKick.key.addr);
        assertEq(
            uint256(kickedOperatorInfo.status),
            uint256(ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED),
            "Kicked operator should have DEREGISTERED status"
        );

        uint192 currentBitmap = slashingRegistryCoordinator.getCurrentQuorumBitmap(testOperatorId);
        assertEq(currentBitmap, uint192(2), "Registered operator should be in quorum 0");

        uint192 kickedBitmap = slashingRegistryCoordinator.getCurrentQuorumBitmap(operatorToKickId);
        assertEq(kickedBitmap, uint192(0), "Kicked operator should be removed from all quorums");
    }

    function test_registerOperatorWithChurn_revert_inputLengthMismatch() public {
        bytes memory twoQuorumNumbers = new bytes(2);
        twoQuorumNumbers[0] = bytes1(uint8(1));
        twoQuorumNumbers[1] = bytes1(uint8(0));

        ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory operatorKickParams =
            new ISlashingRegistryCoordinatorTypes.OperatorKickParam[](1);
        operatorKickParams[0] = ISlashingRegistryCoordinatorTypes.OperatorKickParam({
            operator: operatorToKick.key.addr,
            quorumNumber: uint8(1)
        });

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory churnApproverSignature =
        _signChurnApproval(
            testOperator.key.addr, testOperatorId, operatorKickParams, defaultSalt, defaultExpiry
        );

        _setOperatorWeight(testOperator.key.addr, registeringStake);
        _setOperatorWeight(operatorToKick.key.addr, operatorToKickStake);

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams =
            createPubkeyRegistrationParams(testOperator, testOperator.key.addr);

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: new uint32[](twoQuorumNumbers.length),
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.CHURN,
                "socket:8545",
                pubkeyParams,
                operatorKickParams,
                churnApproverSignature
            )
        });

        for (uint256 i = 0; i < twoQuorumNumbers.length; i++) {
            registerParams.operatorSetIds[i] = uint8(twoQuorumNumbers[i]);
        }

        vm.prank(testOperator.key.addr);
        vm.expectRevert(abi.encodeWithSignature("InputLengthMismatch()"));
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr, registerParams
        );
    }

    function test_registerOperatorWithChurn_revert_churnApproverSaltUsed() public {
        _setOperatorWeight(testOperator.key.addr, registeringStake);
        _setOperatorWeight(operatorToKick.key.addr, operatorToKickStake);

        ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory operatorKickParams =
            new ISlashingRegistryCoordinatorTypes.OperatorKickParam[](quorumNumbers.length);
        operatorKickParams[0] = ISlashingRegistryCoordinatorTypes.OperatorKickParam({
            operator: operatorToKick.key.addr,
            quorumNumber: uint8(quorumNumbers[0])
        });

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory churnApproverSignature =
        _signChurnApproval(
            testOperator.key.addr,
            testOperatorId,
            operatorKickParams,
            bytes32(uint256(1)), // Salt 1
            defaultExpiry
        );

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams =
            createPubkeyRegistrationParams(testOperator, testOperator.key.addr);

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: new uint32[](quorumNumbers.length),
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.CHURN,
                "socket:8545",
                pubkeyParams,
                operatorKickParams,
                churnApproverSignature
            )
        });

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            registerParams.operatorSetIds[i] = uint8(quorumNumbers[i]);
        }

        vm.prank(testOperator.key.addr);
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr, registerParams
        );

        Operator memory anotherOperator = extraOperator1;
        _setOperatorWeight(anotherOperator.key.addr, registeringStake * 2);

        operatorKickParams[0] = ISlashingRegistryCoordinatorTypes.OperatorKickParam({
            operator: operatorToKick.key.addr,
            quorumNumber: uint8(quorumNumbers[0])
        });

        churnApproverSignature = _signChurnApproval(
            anotherOperator.key.addr,
            bytes32(uint256(0)), // Operator ID doesn't matter for the test
            operatorKickParams,
            bytes32(uint256(1)), // Same salt as before
            defaultExpiry + 1 days
        );

        pubkeyParams = createPubkeyRegistrationParams(anotherOperator, anotherOperator.key.addr);

        registerParams = IAllocationManagerTypes.RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: new uint32[](quorumNumbers.length),
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.CHURN,
                "socket:8546",
                pubkeyParams,
                operatorKickParams,
                churnApproverSignature
            )
        });

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            registerParams.operatorSetIds[i] = uint8(quorumNumbers[i]);
        }

        vm.prank(anotherOperator.key.addr);
        vm.expectRevert(abi.encodeWithSignature("AlreadyMemberOfSet()"));
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            anotherOperator.key.addr, registerParams
        );
    }

    function test_registerOperatorWithChurn_revert_cannotChurnSelf() public {
        _setOperatorWeight(testOperator.key.addr, registeringStake);
        _setOperatorWeight(operatorToKick.key.addr, operatorToKickStake);

        ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory operatorKickParams =
            new ISlashingRegistryCoordinatorTypes.OperatorKickParam[](quorumNumbers.length);
        operatorKickParams[0] = ISlashingRegistryCoordinatorTypes.OperatorKickParam({
            operator: testOperator.key.addr, // Trying to kick itself
            quorumNumber: uint8(quorumNumbers[0])
        });

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory churnApproverSignature =
        _signChurnApproval(
            testOperator.key.addr, testOperatorId, operatorKickParams, defaultSalt, defaultExpiry
        );

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams =
            createPubkeyRegistrationParams(testOperator, testOperator.key.addr);

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: new uint32[](quorumNumbers.length),
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.CHURN,
                "socket:8545",
                pubkeyParams,
                operatorKickParams,
                churnApproverSignature
            )
        });

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            registerParams.operatorSetIds[i] = uint8(quorumNumbers[i]);
        }

        vm.prank(testOperator.key.addr);
        vm.expectRevert(abi.encodeWithSignature("CannotChurnSelf()"));
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr, registerParams
        );
    }

    function test_registerOperatorWithChurn_revert_quorumOperatorCountMismatch() public {
        _setOperatorWeight(testOperator.key.addr, registeringStake);
        _setOperatorWeight(operatorToKick.key.addr, operatorToKickStake);

        ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory operatorKickParams =
            new ISlashingRegistryCoordinatorTypes.OperatorKickParam[](quorumNumbers.length);
        operatorKickParams[0] = ISlashingRegistryCoordinatorTypes.OperatorKickParam({
            operator: operatorToKick.key.addr,
            quorumNumber: 0 // Mismatched quorum number (quorumNumbers[0] is 1)
        });

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory churnApproverSignature =
        _signChurnApproval(
            testOperator.key.addr,
            testOperatorId,
            operatorKickParams,
            bytes32(uint256(2)), // Different salt from previous tests
            defaultExpiry
        );

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams =
            createPubkeyRegistrationParams(testOperator, testOperator.key.addr);

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: new uint32[](quorumNumbers.length),
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.CHURN,
                "socket:8545",
                pubkeyParams,
                operatorKickParams,
                churnApproverSignature
            )
        });

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            registerParams.operatorSetIds[i] = uint8(quorumNumbers[i]);
        }

        vm.prank(testOperator.key.addr);
        vm.expectRevert(abi.encodeWithSignature("QuorumOperatorCountMismatch()"));
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr, registerParams
        );
    }

    function test_registerOperatorWithChurn_revert_notRegisteredForQuorum() public {
        _setOperatorWeight(testOperator.key.addr, registeringStake);

        Operator memory unregisteredOperator = operatorsByID[operatorIds.at(5)];
        _setOperatorWeight(unregisteredOperator.key.addr, operatorToKickStake);

        ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory operatorKickParams =
            new ISlashingRegistryCoordinatorTypes.OperatorKickParam[](quorumNumbers.length);
        operatorKickParams[0] = ISlashingRegistryCoordinatorTypes.OperatorKickParam({
            operator: unregisteredOperator.key.addr,
            quorumNumber: uint8(quorumNumbers[0])
        });

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory churnApproverSignature =
        _signChurnApproval(
            testOperator.key.addr,
            testOperatorId,
            operatorKickParams,
            bytes32(uint256(3)), // Different salt from previous tests
            defaultExpiry
        );

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams =
            createPubkeyRegistrationParams(testOperator, testOperator.key.addr);

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: new uint32[](quorumNumbers.length),
            data: abi.encode(
                ISlashingRegistryCoordinatorTypes.RegistrationType.CHURN,
                "socket:8545",
                pubkeyParams,
                operatorKickParams,
                churnApproverSignature
            )
        });

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            registerParams.operatorSetIds[i] = uint8(quorumNumbers[i]);
        }

        vm.prank(testOperator.key.addr);
        vm.expectRevert(abi.encodeWithSignature("OperatorNotRegistered()"));
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            testOperator.key.addr, registerParams
        );
    }
}

contract SlashingRegistryCoordinator_UpdateOperators is SlashingRegistryCoordinatorUnitTestSetup {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    Operator internal testOperator1;
    Operator internal testOperator2;
    Operator internal testOperator3;
    bytes32 internal testOperator1Id;
    bytes32 internal testOperator2Id;
    bytes32 internal testOperator3Id;
    uint96 internal defaultStake;
    uint96 internal minimumStake;

    uint8 internal constant QUORUM_0 = 0;
    uint8 internal constant QUORUM_1 = 1;
    uint192 internal constant BITMAP_QUORUM_0 = 1; // 2^0 = 1
    uint192 internal constant BITMAP_QUORUM_1 = 2; // 2^1 = 2
    uint192 internal constant BITMAP_BOTH_QUORUMS = 3; // 2^0 + 2^1 = 3
    uint192 internal constant PAUSED_UPDATE_OPERATORS = 4; // 2^2 - Bit flag position 2

    function setUp() public override {
        super.setUp();

        // Use DelegationManagerHarness for this test so we can manipulate their shares
        _useDelegationManagerHarness();

        testOperator1 = operatorsByID[operatorIds.at(0)];
        testOperator2 = operatorsByID[operatorIds.at(1)];
        testOperator3 = operatorsByID[operatorIds.at(2)];

        testOperator1Id = operatorIds.at(0);
        testOperator2Id = operatorIds.at(1);
        testOperator3Id = operatorIds.at(2);

        defaultStake = 10 ether;
        minimumStake = 1 ether; // Minimum stake set in the setup

        registerOperatorInSlashingRegistryCoordinator(
            testOperator1, "socket1:8545", uint32(QUORUM_0)
        );
        registerOperatorInSlashingRegistryCoordinator(
            testOperator2, "socket2:8545", uint32(QUORUM_0)
        );

        _setOperatorWeight(testOperator1.key.addr, defaultStake);
        _setOperatorWeight(testOperator2.key.addr, defaultStake);

        vm.prank(serviceManager);
        IPermissionController(coreDeployment.permissionController).setAppointee(
            address(serviceManager),
            address(slashingRegistryCoordinator),
            address(coreDeployment.allocationManager),
            IAllocationManager.deregisterFromOperatorSets.selector
        );
    }

    function test_updateOperators() public {
        address[] memory operators = new address[](2);
        operators[0] = testOperator1.key.addr;
        operators[1] = testOperator2.key.addr;

        _setOperatorWeight(operators[0], defaultStake);
        _setOperatorWeight(operators[1], defaultStake);

        vm.prank(serviceManager);
        slashingRegistryCoordinator.updateOperators(operators);

        _verifyOperatorStatus(
            testOperator1.key.addr, ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
        );
        _verifyOperatorStatus(
            testOperator2.key.addr, ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
        );

        _verifyOperatorBitmap(testOperator1Id, BITMAP_QUORUM_0);
        _verifyOperatorBitmap(testOperator2Id, BITMAP_QUORUM_0);

        // Verify stake in StakeRegistry
        uint96 stake1 = stakeRegistry.getCurrentStake(testOperator1Id, QUORUM_0);
        uint96 stake2 = stakeRegistry.getCurrentStake(testOperator2Id, QUORUM_0);
        assertEq(stake1, 10 ether, "StakeRegistry stake for operator 1 not updated correctly");
        assertEq(stake2, 10 ether, "StakeRegistry stake for operator 2 not updated correctly");
    }

    function test_When_multipleQuorums() public {
        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.createTotalDelegatedStakeQuorum(
            getDefaultOperatorSetParams(), minimumStake, getStrategyParams()
        );

        uint32[] memory quorum1 = new uint32[](1);
        quorum1[0] = QUORUM_1;
        registerOperatorInSlashingRegistryCoordinator(testOperator1, "socket1:8545", quorum1);
        registerOperatorInSlashingRegistryCoordinator(testOperator2, "socket2:8545", quorum1);

        _setOperatorWeight(testOperator1.key.addr, defaultStake);
        _setOperatorWeight(testOperator2.key.addr, defaultStake);

        address[] memory operators = new address[](2);
        operators[0] = testOperator1.key.addr;
        operators[1] = testOperator2.key.addr;

        vm.prank(serviceManager);
        slashingRegistryCoordinator.updateOperators(operators);

        _verifyOperatorStatus(
            testOperator1.key.addr, ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
        );
        _verifyOperatorStatus(
            testOperator2.key.addr, ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
        );

        _verifyOperatorBitmap(testOperator1Id, BITMAP_BOTH_QUORUMS);
        _verifyOperatorBitmap(testOperator2Id, BITMAP_BOTH_QUORUMS);

        // Verify stake in StakeRegistry for both quorums
        uint96 stake1Quorum0 = stakeRegistry.getCurrentStake(testOperator1Id, QUORUM_0);
        uint96 stake2Quorum0 = stakeRegistry.getCurrentStake(testOperator2Id, QUORUM_0);
        uint96 stake1Quorum1 = stakeRegistry.getCurrentStake(testOperator1Id, QUORUM_1);
        uint96 stake2Quorum1 = stakeRegistry.getCurrentStake(testOperator2Id, QUORUM_1);

        assertEq(
            stake1Quorum0,
            10 ether,
            "StakeRegistry stake for operator 1 in quorum 0 not updated correctly"
        );
        assertEq(
            stake2Quorum0,
            10 ether,
            "StakeRegistry stake for operator 2 in quorum 0 not updated correctly"
        );
        assertEq(
            stake1Quorum1,
            10 ether,
            "StakeRegistry stake for operator 1 in quorum 1 not updated correctly"
        );
        assertEq(
            stake2Quorum1,
            10 ether,
            "StakeRegistry stake for operator 2 in quorum 1 not updated correctly"
        );
    }

    function test_RevertsWhen_Paused() public {
        address[] memory operators = new address[](2);
        operators[0] = testOperator1.key.addr;
        operators[1] = testOperator2.key.addr;

        vm.prank(pauser);
        slashingRegistryCoordinator.pause(4); // PAUSED_UPDATE_OPERATOR = 2

        vm.prank(serviceManager);
        vm.expectRevert(bytes4(keccak256("CurrentlyPaused()")));
        slashingRegistryCoordinator.updateOperators(operators);
    }

    function test_When_DeregistersInsufficientStake() public {
        address[] memory operators = new address[](2);
        operators[0] = testOperator1.key.addr;
        operators[1] = testOperator2.key.addr;

        _setOperatorWeight(testOperator1.key.addr, 0);
        _setOperatorWeight(testOperator2.key.addr, defaultStake);

        vm.prank(serviceManager);
        slashingRegistryCoordinator.updateOperators(operators);

        _verifyOperatorStatus(
            testOperator1.key.addr, ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED
        );
        _verifyOperatorStatus(
            testOperator2.key.addr, ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
        );

        _verifyOperatorBitmap(testOperator1Id, 0);
        _verifyOperatorBitmap(testOperator2Id, BITMAP_QUORUM_0);

        uint96 stake1 = stakeRegistry.getCurrentStake(testOperator1Id, QUORUM_0);
        uint96 stake2 = stakeRegistry.getCurrentStake(testOperator2Id, QUORUM_0);
        assertEq(stake1, 0, "StakeRegistry stake for deregistered operator should be 0");
        assertEq(stake2, 10 ether, "StakeRegistry stake for operator 2 not updated correctly");
    }

    function test_updateOperators_nonRegisteredOperator() public {
        address[] memory operators = new address[](3);
        operators[0] = testOperator1.key.addr;
        operators[1] = testOperator2.key.addr;
        operators[2] = testOperator3.key.addr; // Not registered

        _setOperatorWeight(testOperator1.key.addr, defaultStake);
        _setOperatorWeight(testOperator2.key.addr, defaultStake);

        vm.prank(serviceManager);
        slashingRegistryCoordinator.updateOperators(operators);

        _verifyOperatorStatus(
            testOperator1.key.addr, ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
        );
        _verifyOperatorStatus(
            testOperator2.key.addr, ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
        );

        ISlashingRegistryCoordinator.OperatorInfo memory operatorInfo =
            slashingRegistryCoordinator.getOperator(testOperator3.key.addr);
        assertEq(
            uint256(operatorInfo.status),
            uint256(ISlashingRegistryCoordinatorTypes.OperatorStatus.NEVER_REGISTERED),
            "Non-registered operator should remain unregistered"
        );
    }
}

contract SlashingRegistryCoordinator_UpdateOperatorsForQuorum is
    SlashingRegistryCoordinatorUnitTestSetup
{
    using EnumerableSet for EnumerableSet.Bytes32Set;

    Operator internal testOperator1;
    Operator internal testOperator2;
    Operator internal testOperator3;
    bytes32 internal testOperator1Id;
    bytes32 internal testOperator2Id;
    bytes32 internal testOperator3Id;
    uint96 internal defaultStake;
    uint96 internal minimumStake;

    uint8 internal constant QUORUM_0 = 0;
    uint8 internal constant QUORUM_1 = 1;
    uint192 internal constant BITMAP_QUORUM_0 = 1; // 2^0 = 1
    uint192 internal constant BITMAP_QUORUM_1 = 2; // 2^1 = 2
    uint192 internal constant BITMAP_BOTH_QUORUMS = 3; // 2^0 + 2^1 = 3
    uint192 internal constant PAUSED_UPDATE_OPERATORS = 4; // 2^2 - Bit flag position 2

    function setUp() public override {
        super.setUp();

        // Use DelegationManagerHarness for this test so we can manipulate their shares
        _useDelegationManagerHarness();

        testOperator1 = operatorsByID[operatorIds.at(0)];
        testOperator2 = operatorsByID[operatorIds.at(1)];

        testOperator1Id = operatorIds.at(0);
        testOperator2Id = operatorIds.at(1);

        defaultStake = 10 ether;
        minimumStake = 1 ether; // Minimum stake set in the setup

        registerOperatorInSlashingRegistryCoordinator(
            testOperator1, "socket1:8545", uint32(QUORUM_0)
        );
        registerOperatorInSlashingRegistryCoordinator(
            testOperator2, "socket2:8545", uint32(QUORUM_0)
        );

        _setOperatorWeight(testOperator1.key.addr, defaultStake);
        _setOperatorWeight(testOperator2.key.addr, defaultStake);

        vm.prank(serviceManager);
        IPermissionController(coreDeployment.permissionController).setAppointee(
            address(serviceManager),
            address(slashingRegistryCoordinator),
            address(coreDeployment.allocationManager),
            IAllocationManager.deregisterFromOperatorSets.selector
        );
    }

    function test_updateOperators() public {
        address[][] memory operatorsPerQuorum = new address[][](1);
        operatorsPerQuorum[0] = new address[](2);
        operatorsPerQuorum[0][0] = testOperator1.key.addr;
        operatorsPerQuorum[0][1] = testOperator2.key.addr;

        bytes memory quorumNumbers = abi.encodePacked(uint8(QUORUM_0));

        _setOperatorWeight(operatorsPerQuorum[0][0], defaultStake);
        _setOperatorWeight(operatorsPerQuorum[0][1], defaultStake);

        vm.prank(serviceManager);
        slashingRegistryCoordinator.updateOperatorsForQuorum(operatorsPerQuorum, quorumNumbers);

        _verifyOperatorStatus(
            testOperator1.key.addr, ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
        );
        _verifyOperatorStatus(
            testOperator2.key.addr, ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
        );

        _verifyOperatorBitmap(testOperator1Id, BITMAP_QUORUM_0);
        _verifyOperatorBitmap(testOperator2Id, BITMAP_QUORUM_0);

        // Verify stake in StakeRegistry
        uint96 stake1 = stakeRegistry.getCurrentStake(testOperator1Id, QUORUM_0);
        uint96 stake2 = stakeRegistry.getCurrentStake(testOperator2Id, QUORUM_0);
        assertEq(stake1, 10 ether, "StakeRegistry stake for operator 1 not updated correctly");
        assertEq(stake2, 10 ether, "StakeRegistry stake for operator 2 not updated correctly");
    }

    function test_When_multipleQuorums() public {
        vm.prank(proxyAdminOwner);
        slashingRegistryCoordinator.createTotalDelegatedStakeQuorum(
            getDefaultOperatorSetParams(), minimumStake, getStrategyParams()
        );

        uint32[] memory quorum1 = new uint32[](1);
        quorum1[0] = QUORUM_1;
        registerOperatorInSlashingRegistryCoordinator(testOperator1, "socket1:8545", quorum1);
        registerOperatorInSlashingRegistryCoordinator(testOperator2, "socket2:8545", quorum1);

        _setOperatorWeight(testOperator1.key.addr, defaultStake);
        _setOperatorWeight(testOperator2.key.addr, defaultStake);

        address[][] memory operatorsPerQuorum = new address[][](2);
        operatorsPerQuorum[0] = new address[](2);
        operatorsPerQuorum[0][0] = testOperator1.key.addr;
        operatorsPerQuorum[0][1] = testOperator2.key.addr;

        operatorsPerQuorum[1] = new address[](2);
        operatorsPerQuorum[1][0] = testOperator1.key.addr;
        operatorsPerQuorum[1][1] = testOperator2.key.addr;

        bytes memory quorumNumbers = abi.encodePacked(uint8(QUORUM_0), uint8(QUORUM_1));

        vm.prank(serviceManager);
        slashingRegistryCoordinator.updateOperatorsForQuorum(operatorsPerQuorum, quorumNumbers);

        _verifyOperatorStatus(
            testOperator1.key.addr, ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
        );
        _verifyOperatorStatus(
            testOperator2.key.addr, ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
        );

        _verifyOperatorBitmap(testOperator1Id, BITMAP_BOTH_QUORUMS);
        _verifyOperatorBitmap(testOperator2Id, BITMAP_BOTH_QUORUMS);

        // Verify stake in StakeRegistry for both quorums
        uint96 stake1Quorum0 = stakeRegistry.getCurrentStake(testOperator1Id, QUORUM_0);
        uint96 stake2Quorum0 = stakeRegistry.getCurrentStake(testOperator2Id, QUORUM_0);
        uint96 stake1Quorum1 = stakeRegistry.getCurrentStake(testOperator1Id, QUORUM_1);
        uint96 stake2Quorum1 = stakeRegistry.getCurrentStake(testOperator2Id, QUORUM_1);

        assertEq(
            stake1Quorum0,
            10 ether,
            "StakeRegistry stake for operator 1 in quorum 0 not updated correctly"
        );
        assertEq(
            stake2Quorum0,
            10 ether,
            "StakeRegistry stake for operator 2 in quorum 0 not updated correctly"
        );
        assertEq(
            stake1Quorum1,
            10 ether,
            "StakeRegistry stake for operator 1 in quorum 1 not updated correctly"
        );
        assertEq(
            stake2Quorum1,
            10 ether,
            "StakeRegistry stake for operator 2 in quorum 1 not updated correctly"
        );
    }

    function test_RevertsWhen_Paused() public {
        address[][] memory operatorsPerQuorum = new address[][](1);
        operatorsPerQuorum[0] = new address[](2);
        operatorsPerQuorum[0][0] = testOperator1.key.addr;
        operatorsPerQuorum[0][1] = testOperator2.key.addr;

        bytes memory quorumNumbers = abi.encodePacked(uint8(QUORUM_0));

        vm.prank(pauser);
        slashingRegistryCoordinator.pause(4); // PAUSED_UPDATE_OPERATOR = 2

        vm.prank(serviceManager);
        vm.expectRevert(bytes4(keccak256("CurrentlyPaused()")));
        slashingRegistryCoordinator.updateOperatorsForQuorum(operatorsPerQuorum, quorumNumbers);
    }

    function test_When_DeregistersInsufficientStake() public {
        address[] memory operators = new address[](2);
        operators[0] = testOperator1.key.addr;
        operators[1] = testOperator2.key.addr;

        _setOperatorWeight(testOperator1.key.addr, 0);
        _setOperatorWeight(testOperator2.key.addr, defaultStake);

        vm.prank(serviceManager);
        slashingRegistryCoordinator.updateOperators(operators);

        _verifyOperatorStatus(
            testOperator1.key.addr, ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED
        );
        _verifyOperatorStatus(
            testOperator2.key.addr, ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
        );

        _verifyOperatorBitmap(testOperator1Id, 0);
        _verifyOperatorBitmap(testOperator2Id, BITMAP_QUORUM_0);

        uint96 stake1 = stakeRegistry.getCurrentStake(testOperator1Id, QUORUM_0);
        uint96 stake2 = stakeRegistry.getCurrentStake(testOperator2Id, QUORUM_0);
        assertEq(stake1, 0, "StakeRegistry stake for deregistered operator should be 0");
        assertEq(stake2, 10 ether, "StakeRegistry stake for operator 2 not updated correctly");
    }

    function test_updateOperators_nonRegisteredOperator() public {
        address[][] memory operatorsPerQuorum = new address[][](1);
        operatorsPerQuorum[0] = new address[](2);
        operatorsPerQuorum[0][0] = testOperator1.key.addr;
        operatorsPerQuorum[0][1] = testOperator2.key.addr;

        bytes memory quorumNumbers = abi.encodePacked(uint8(QUORUM_0));

        _setOperatorWeight(testOperator1.key.addr, defaultStake);
        _setOperatorWeight(testOperator2.key.addr, defaultStake);

        vm.prank(serviceManager);
        slashingRegistryCoordinator.updateOperatorsForQuorum(operatorsPerQuorum, quorumNumbers);

        _verifyOperatorStatus(
            testOperator1.key.addr, ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
        );
        _verifyOperatorStatus(
            testOperator2.key.addr, ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
        );

        ISlashingRegistryCoordinator.OperatorInfo memory operatorInfo =
            slashingRegistryCoordinator.getOperator(testOperator3.key.addr);
        assertEq(
            uint256(operatorInfo.status),
            uint256(ISlashingRegistryCoordinatorTypes.OperatorStatus.NEVER_REGISTERED),
            "Non-registered operator should remain unregistered"
        );
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {VetoableSlasher} from "../../src/slashers/VetoableSlasher.sol";
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
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
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
import {IVetoableSlasherTypes} from "../../src/interfaces/IVetoableSlasher.sol";
import {SocketRegistry} from "../../src/SocketRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVetoableSlasherErrors} from "../../src/interfaces/IVetoableSlasher.sol";
import {MiddlewareDeployLib} from "../utils/MiddlewareDeployLib.sol";

contract VetoableSlasherTest is Test {
    VetoableSlasher public vetoableSlasher;
    VetoableSlasher public vetoableSlasherImplementation;
    ProxyAdmin public proxyAdmin;
    EmptyContract public emptyContract;
    CoreDeployLib.DeploymentData public coreDeployment;
    PauserRegistry public pauserRegistry;
    ERC20Mock public mockToken;
    StrategyFactory public strategyFactory;
    StakeRegistry public stakeRegistry;
    BLSApkRegistry public blsApkRegistry;
    IndexRegistry public indexRegistry;
    SocketRegistry public socketRegistry;
    SlashingRegistryCoordinator public slashingRegistryCoordinator;
    SlashingRegistryCoordinator public slashingRegistryCoordinatorImplementation;

    address public vetoCommittee;
    address public slasher;
    address public serviceManager;
    Operator public operatorWallet;
    IStrategy public mockStrategy;
    address public proxyAdminOwner = address(uint160(uint256(keccak256("proxyAdminOwner"))));
    address public pauser = address(uint160(uint256(keccak256("pauser"))));
    address public unpauser = address(uint160(uint256(keccak256("unpauser"))));
    address public churnApprover = address(uint160(uint256(keccak256("churnApprover"))));
    address public ejector = address(uint160(uint256(keccak256("ejector"))));

    uint32 constant vetoWindowBlocks = 3 days / 12 seconds;
    uint32 constant DEALLOCATION_DELAY = 7 days;
    uint32 constant ALLOCATION_CONFIGURATION_DELAY = 1 days;

    function setUp() public {
        serviceManager = address(0x2);
        vetoCommittee = address(0x3);
        slasher = address(0x4);
        operatorWallet = OperatorWalletLib.createOperator("operator");

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

        MiddlewareDeployLib.MiddlewareDeployData memory middlewareDeployments = MiddlewareDeployLib
            .deployMiddleware(
            address(proxyAdmin),
            coreDeployment.allocationManager,
            address(pauserRegistry),
            middlewareConfig
        );
        vm.stopPrank();

        vetoableSlasher = VetoableSlasher(middlewareDeployments.instantSlasher);
        slashingRegistryCoordinator =
            SlashingRegistryCoordinator(middlewareDeployments.slashingRegistryCoordinator);
        stakeRegistry = StakeRegistry(middlewareDeployments.stakeRegistry);
        blsApkRegistry = BLSApkRegistry(middlewareDeployments.blsApkRegistry);
        indexRegistry = IndexRegistry(middlewareDeployments.indexRegistry);
        socketRegistry = SocketRegistry(middlewareDeployments.socketRegistry);

        vetoableSlasherImplementation = new VetoableSlasher(
            IAllocationManager(coreDeployment.allocationManager),
            ISlashingRegistryCoordinator(slashingRegistryCoordinator),
            slasher,
            vetoCommittee,
            vetoWindowBlocks
        );

        vm.startPrank(proxyAdminOwner);
        vetoableSlasher = VetoableSlasher(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(payable(address(vetoableSlasher))),
            address(vetoableSlasherImplementation)
        );
        vm.stopPrank();

        vm.startPrank(serviceManager);
        PermissionController(coreDeployment.permissionController).setAppointee(
            address(serviceManager),
            address(vetoableSlasher),
            coreDeployment.allocationManager,
            AllocationManager.slashOperator.selector
        );

        PermissionController(coreDeployment.permissionController).setAppointee(
            address(serviceManager),
            address(slashingRegistryCoordinator),
            coreDeployment.allocationManager,
            AllocationManager.createOperatorSets.selector
        );

        PermissionController(coreDeployment.permissionController).setAppointee(
            address(serviceManager),
            address(slashingRegistryCoordinator),
            coreDeployment.allocationManager,
            AllocationManager.deregisterFromOperatorSets.selector
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

        vm.label(address(vetoableSlasher), "VetoableSlasher Proxy");
        vm.label(address(vetoableSlasherImplementation), "VetoableSlasher Implementation");
        vm.label(address(slashingRegistryCoordinator), "SlashingRegistryCoordinator Proxy");
        vm.label(
            address(slashingRegistryCoordinatorImplementation),
            "SlashingRegistryCoordinator Implementation"
        );
        vm.label(address(proxyAdmin), "ProxyAdmin");
        vm.label(coreDeployment.allocationManager, "AllocationManager Proxy");
    }

    function test_initialization() public {
        assertEq(vetoableSlasher.vetoCommittee(), vetoCommittee);
        assertEq(vetoableSlasher.vetoWindowBlocks(), vetoWindowBlocks);
    }

    function _createMockSlashingParams()
        internal
        view
        returns (IAllocationManagerTypes.SlashingParams memory)
    {
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = mockStrategy;

        uint256[] memory wadsToSlash = new uint256[](1);
        wadsToSlash[0] = 0.5e18; // 50% slash

        return IAllocationManagerTypes.SlashingParams({
            operator: operatorWallet.key.addr,
            operatorSetId: 1,
            strategies: strategies,
            wadsToSlash: wadsToSlash,
            description: "Test slashing"
        });
    }

    function test_queueSlashingRequest_revert_notSlasher() public {
        IAllocationManagerTypes.SlashingParams memory params = _createMockSlashingParams();
        vm.expectRevert(ISlasherErrors.OnlySlasher.selector);
        vetoableSlasher.queueSlashingRequest(params);
    }

    function test_queueSlashingRequest() public {
        IAllocationManagerTypes.SlashingParams memory params = _createMockSlashingParams();

        vm.prank(slasher);
        vetoableSlasher.queueSlashingRequest(params);

        (
            IAllocationManagerTypes.SlashingParams memory resultParams,
            uint256 requestTimestamp,
            IVetoableSlasherTypes.SlashingStatus status
        ) = vetoableSlasher.slashingRequests(0);
        IVetoableSlasherTypes.VetoableSlashingRequest memory request =
            IVetoableSlasherTypes.VetoableSlashingRequest(params, requestTimestamp, status);
        assertEq(resultParams.operator, operatorWallet.key.addr);
        assertEq(resultParams.operatorSetId, 1);
        assertEq(resultParams.wadsToSlash[0], 0.5e18);
        assertEq(resultParams.description, "Test slashing");
        assertEq(uint8(status), uint8(IVetoableSlasherTypes.SlashingStatus.Requested));
        assertEq(requestTimestamp, block.timestamp);
    }

    function test_cancelSlashingRequest_revert_notVetoCommittee() public {
        IAllocationManagerTypes.SlashingParams memory params = _createMockSlashingParams();

        vm.prank(slasher);
        vetoableSlasher.queueSlashingRequest(params);

        vm.expectRevert(IVetoableSlasherErrors.OnlyVetoCommittee.selector);
        vetoableSlasher.cancelSlashingRequest(0);
    }

    function test_cancelSlashingRequest_revert_afterVetoPeriod() public {
        IAllocationManagerTypes.SlashingParams memory params = _createMockSlashingParams();

        vm.prank(slasher);
        vetoableSlasher.queueSlashingRequest(params);

        vm.roll(block.number + vetoWindowBlocks + 1);

        vm.prank(vetoCommittee);
        vm.expectRevert(IVetoableSlasherErrors.VetoPeriodPassed.selector);
        vetoableSlasher.cancelSlashingRequest(0);
    }

    function test_cancelSlashingRequest() public {
        IAllocationManagerTypes.SlashingParams memory params = _createMockSlashingParams();

        vm.prank(slasher);
        vetoableSlasher.queueSlashingRequest(params);

        vm.prank(vetoCommittee);
        vetoableSlasher.cancelSlashingRequest(0);

        (
            IAllocationManagerTypes.SlashingParams memory resultParams,
            uint256 requestTimestamp,
            IVetoableSlasherTypes.SlashingStatus status
        ) = vetoableSlasher.slashingRequests(0);
        assertEq(uint8(status), uint8(IVetoableSlasherTypes.SlashingStatus.Cancelled));
    }

    function test_fulfillSlashingRequest_revert_beforeVetoPeriod() public {
        IAllocationManagerTypes.SlashingParams memory params = _createMockSlashingParams();

        vm.prank(slasher);
        vetoableSlasher.queueSlashingRequest(params);

        vm.prank(slasher);
        vm.expectRevert(IVetoableSlasherErrors.VetoPeriodNotPassed.selector);
        vetoableSlasher.fulfillSlashingRequest(0);
    }

    function test_fulfillSlashingRequest() public {
        vm.startPrank(operatorWallet.key.addr);
        IDelegationManager(coreDeployment.delegationManager).registerAsOperator(
            address(0), 1, "metadata"
        );

        uint256 depositAmount = 1 ether;
        mockToken.mint(operatorWallet.key.addr, depositAmount);
        mockToken.approve(address(coreDeployment.strategyManager), depositAmount);
        IStrategyManager(coreDeployment.strategyManager).depositIntoStrategy(
            mockStrategy, mockToken, depositAmount
        );

        uint32 minDelay = 1;
        IAllocationManager(coreDeployment.allocationManager).setAllocationDelay(
            operatorWallet.key.addr, minDelay
        );
        vm.stopPrank();

        vm.roll(block.number + ALLOCATION_CONFIGURATION_DELAY + 1);

        IStrategy[] memory allocStrategies = new IStrategy[](1);
        allocStrategies[0] = mockStrategy;

        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = uint64(1 ether); // Allocate full magnitude

        OperatorSet memory operatorSet = OperatorSet({avs: address(serviceManager), id: 0});

        vm.startPrank(serviceManager);
        IAllocationManagerTypes.CreateSetParams[] memory createParams =
            new IAllocationManagerTypes.CreateSetParams[](1);
        createParams[0] =
            IAllocationManagerTypes.CreateSetParams({operatorSetId: 0, strategies: allocStrategies});
        IAllocationManager(coreDeployment.allocationManager).setAVSRegistrar(
            address(serviceManager), IAVSRegistrar(address(slashingRegistryCoordinator))
        );
        vm.stopPrank();

        vm.startPrank(operatorWallet.key.addr);

        IAllocationManagerTypes.AllocateParams[] memory allocParams =
            new IAllocationManagerTypes.AllocateParams[](1);
        allocParams[0] = IAllocationManagerTypes.AllocateParams({
            operatorSet: operatorSet,
            strategies: allocStrategies,
            newMagnitudes: magnitudes
        });

        IAllocationManager(coreDeployment.allocationManager).modifyAllocations(
            operatorWallet.key.addr, allocParams
        );
        vm.roll(block.number + 100);

        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 0;
        bytes32 messageHash = slashingRegistryCoordinator.calculatePubkeyRegistrationMessageHash(
            operatorWallet.key.addr
        );
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams = IBLSApkRegistryTypes
            .PubkeyRegistrationParams({
            pubkeyRegistrationSignature: SigningKeyOperationsLib.sign(
                operatorWallet.signingKey, messageHash
            ),
            pubkeyG1: operatorWallet.signingKey.publicKeyG1,
            pubkeyG2: operatorWallet.signingKey.publicKeyG2
        });

        bytes memory registrationData = abi.encode(
            ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL, "socket", pubkeyParams
        );

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: operatorSetIds,
            data: registrationData
        });
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            operatorWallet.key.addr, registerParams
        );
        vm.stopPrank();

        vm.roll(block.number + 100);

        IAllocationManagerTypes.SlashingParams memory params = IAllocationManagerTypes
            .SlashingParams({
            operator: operatorWallet.key.addr,
            operatorSetId: 0,
            strategies: allocStrategies,
            wadsToSlash: new uint256[](allocStrategies.length),
            description: "Test slashing"
        });

        for (uint256 i = 0; i < params.wadsToSlash.length; i++) {
            params.wadsToSlash[i] = 1e18;
        }

        vm.prank(slasher);
        vetoableSlasher.queueSlashingRequest(params);

        vm.roll(block.number + vetoWindowBlocks + 1);

        vm.prank(slasher);
        vetoableSlasher.fulfillSlashingRequest(0);

        (
            IAllocationManagerTypes.SlashingParams memory resultParams,
            uint256 requestTimestamp,
            IVetoableSlasherTypes.SlashingStatus status
        ) = vetoableSlasher.slashingRequests(0);
        assertEq(uint8(status), uint8(IVetoableSlasherTypes.SlashingStatus.Completed));
    }

    function _getFullSlashingParams()
        internal
        view
        returns (IAllocationManagerTypes.SlashingParams memory)
    {
        IStrategy[] memory allocStrategies = new IStrategy[](1);
        allocStrategies[0] = mockStrategy;

        IAllocationManagerTypes.SlashingParams memory params = IAllocationManagerTypes
            .SlashingParams({
            operator: operatorWallet.key.addr,
            operatorSetId: 0,
            strategies: allocStrategies,
            wadsToSlash: new uint256[](allocStrategies.length),
            description: "Full slash test"
        });

        for (uint256 i = 0; i < params.wadsToSlash.length; i++) {
            params.wadsToSlash[i] = 1e18; // 100% slash
        }

        return params;
    }

    function _getPartialSlashingParams()
        internal
        view
        returns (IAllocationManagerTypes.SlashingParams memory)
    {
        IStrategy[] memory allocStrategies = new IStrategy[](1);
        allocStrategies[0] = mockStrategy;

        IAllocationManagerTypes.SlashingParams memory params = IAllocationManagerTypes
            .SlashingParams({
            operator: operatorWallet.key.addr,
            operatorSetId: 0,
            strategies: allocStrategies,
            wadsToSlash: new uint256[](allocStrategies.length),
            description: "Partial slash test"
        });

        for (uint256 i = 0; i < params.wadsToSlash.length; i++) {
            params.wadsToSlash[i] = 0.5e18; // 50% slash
        }

        return params;
    }

    function test_fulfillSlashingRequest_updatesWeightButMaintainsMembership() public {
        bytes32 operatorId = _setupOperatorForSlashing();

        uint96 initialOperatorStake =
            stakeRegistry.weightOfOperatorForQuorum(0, operatorWallet.key.addr);
        uint96 initialTotalStake = stakeRegistry.getCurrentTotalStake(0);

        assertEq(initialOperatorStake, 2 ether, "Initial operator stake is incorrect");

        IAllocationManagerTypes.SlashingParams memory params = _getPartialSlashingParams();

        vm.prank(slasher);
        vetoableSlasher.queueSlashingRequest(params);

        vm.roll(block.number + vetoWindowBlocks + 1);

        vm.prank(slasher);
        vetoableSlasher.fulfillSlashingRequest(0);

        uint96 postSlashingStake =
            stakeRegistry.weightOfOperatorForQuorum(0, operatorWallet.key.addr);
        uint96 totalStakeAfter = stakeRegistry.getCurrentTotalStake(0);

        assertEq(postSlashingStake, 1 ether, "Incorrect post-slash stake");

        assertEq(totalStakeAfter, initialTotalStake - 1 ether, "Total stake incorrect");

        uint192 bitmap = slashingRegistryCoordinator.getCurrentQuorumBitmap(operatorId);
        assertTrue(bitmap & 1 != 0, "Operator removed from quorum 0");

        ISlashingRegistryCoordinatorTypes.OperatorStatus status =
            slashingRegistryCoordinator.getOperatorStatus(operatorWallet.key.addr);
        assertEq(
            uint256(status),
            uint256(ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED),
            "Operator not in REGISTERED status"
        );

        // Verify slashing request status is completed
        (,, IVetoableSlasherTypes.SlashingStatus slashStatus) = vetoableSlasher.slashingRequests(0);
        assertEq(
            uint8(slashStatus),
            uint8(IVetoableSlasherTypes.SlashingStatus.Completed),
            "Slashing request not marked as completed"
        );
    }

    // Helper function to set up operator for slashing test
    function _setupOperatorForSlashing() internal returns (bytes32) {
        vm.startPrank(operatorWallet.key.addr);
        IDelegationManager(coreDeployment.delegationManager).registerAsOperator(
            address(0), 1, "metadata"
        );

        uint256 depositAmount = 2 ether;
        mockToken.mint(operatorWallet.key.addr, depositAmount);
        mockToken.approve(address(coreDeployment.strategyManager), depositAmount);
        IStrategyManager(coreDeployment.strategyManager).depositIntoStrategy(
            mockStrategy, mockToken, depositAmount
        );

        uint32 minDelay = 1;
        IAllocationManager(coreDeployment.allocationManager).setAllocationDelay(
            operatorWallet.key.addr, minDelay
        );
        vm.stopPrank();

        vm.roll(block.number + ALLOCATION_CONFIGURATION_DELAY + 1);

        IStrategy[] memory allocStrategies = new IStrategy[](1);
        allocStrategies[0] = mockStrategy;

        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = uint64(1 ether); // Allocate full magnitude (2 ETH)

        OperatorSet memory operatorSet = OperatorSet({avs: address(serviceManager), id: 0});

        vm.startPrank(serviceManager);
        IAllocationManagerTypes.CreateSetParams[] memory createParams =
            new IAllocationManagerTypes.CreateSetParams[](1);
        createParams[0] =
            IAllocationManagerTypes.CreateSetParams({operatorSetId: 0, strategies: allocStrategies});
        IAllocationManager(coreDeployment.allocationManager).setAVSRegistrar(
            address(serviceManager), IAVSRegistrar(address(slashingRegistryCoordinator))
        );
        vm.stopPrank();

        vm.startPrank(operatorWallet.key.addr);

        IAllocationManagerTypes.AllocateParams[] memory allocParams =
            new IAllocationManagerTypes.AllocateParams[](1);
        allocParams[0] = IAllocationManagerTypes.AllocateParams({
            operatorSet: operatorSet,
            strategies: allocStrategies,
            newMagnitudes: magnitudes
        });

        IAllocationManager(coreDeployment.allocationManager).modifyAllocations(
            operatorWallet.key.addr, allocParams
        );
        vm.roll(block.number + 100);

        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 0;
        bytes32 messageHash = slashingRegistryCoordinator.calculatePubkeyRegistrationMessageHash(
            operatorWallet.key.addr
        );
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory pubkeyParams = IBLSApkRegistryTypes
            .PubkeyRegistrationParams({
            pubkeyRegistrationSignature: SigningKeyOperationsLib.sign(
                operatorWallet.signingKey, messageHash
            ),
            pubkeyG1: operatorWallet.signingKey.publicKeyG1,
            pubkeyG2: operatorWallet.signingKey.publicKeyG2
        });

        bytes memory registrationData = abi.encode(
            ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL, "socket", pubkeyParams
        );

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
            avs: address(serviceManager),
            operatorSetIds: operatorSetIds,
            data: registrationData
        });
        IAllocationManager(coreDeployment.allocationManager).registerForOperatorSets(
            operatorWallet.key.addr, registerParams
        );
        vm.stopPrank();

        vm.roll(block.number + 100);

        bytes32 operatorId = slashingRegistryCoordinator.getOperatorId(operatorWallet.key.addr);
        return operatorId;
    }

    function test_fulfillSlashingRequest_fullySlashesAndRemovesOperator() public {
        bytes32 operatorId = _setupOperatorForSlashing();

        // Verify operator is registered before slashing
        uint96 initialOperatorStake =
            stakeRegistry.weightOfOperatorForQuorum(0, operatorWallet.key.addr);
        uint96 initialTotalStake = stakeRegistry.getCurrentTotalStake(0);

        assertEq(initialOperatorStake, 2 ether, "Initial operator stake is incorrect");

        uint192 initialBitmap = slashingRegistryCoordinator.getCurrentQuorumBitmap(operatorId);
        assertTrue(initialBitmap & 1 != 0, "Operator should be in quorum 0 before slashing");

        ISlashingRegistryCoordinatorTypes.OperatorStatus initialStatus =
            slashingRegistryCoordinator.getOperatorStatus(operatorWallet.key.addr);
        assertEq(
            uint256(initialStatus),
            uint256(ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED),
            "Operator should be in REGISTERED status before slashing"
        );

        // Create a full slashing request (100%)
        IAllocationManagerTypes.SlashingParams memory params = _getFullSlashingParams();

        // Queue slashing request
        vm.prank(slasher);
        vetoableSlasher.queueSlashingRequest(params);

        // Verify slashing request is queued
        (
            IAllocationManagerTypes.SlashingParams memory resultParams,
            uint256 requestTimestamp,
            IVetoableSlasherTypes.SlashingStatus status
        ) = vetoableSlasher.slashingRequests(0);
        assertEq(uint8(status), uint8(IVetoableSlasherTypes.SlashingStatus.Requested));

        // Wait for veto period to pass
        vm.roll(block.number + vetoWindowBlocks + 1);

        // Execute slashing
        vm.prank(slasher);
        vetoableSlasher.fulfillSlashingRequest(0);

        // Verify slashing request is completed
        (,, status) = vetoableSlasher.slashingRequests(0);
        assertEq(uint8(status), uint8(IVetoableSlasherTypes.SlashingStatus.Completed));

        // Verify operator is fully slashed and removed
        uint96 postSlashingStake =
            stakeRegistry.weightOfOperatorForQuorum(0, operatorWallet.key.addr);
        uint96 totalStakeAfter = stakeRegistry.getCurrentTotalStake(0);

        assertEq(postSlashingStake, 0, "Post-slash stake should be zero");
        assertEq(
            totalStakeAfter,
            initialTotalStake - 2 ether,
            "Total stake should be reduced by full amount"
        );

        uint192 finalBitmap = slashingRegistryCoordinator.getCurrentQuorumBitmap(operatorId);
        assertEq(finalBitmap & 1, 0, "Operator should be removed from quorum 0");

        ISlashingRegistryCoordinatorTypes.OperatorStatus finalStatus =
            slashingRegistryCoordinator.getOperatorStatus(operatorWallet.key.addr);
        assertEq(
            uint256(finalStatus),
            uint256(ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED),
            "Operator should be in DEREGISTERED status after full slashing"
        );
    }
}

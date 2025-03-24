// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, Vm, console2 as console} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SelfSlasher} from "../../src/examples/SelfSlasher/SelfSlasher.sol";
import {
    IAllocationManager,
    IAllocationManagerTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IRegistryCoordinator} from "../../src/interfaces/IRegistryCoordinator.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
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

contract SelfSlasherTest is Test {
    SelfSlasher public selfSlasher;
    ProxyAdmin public proxyAdmin;
    EmptyContract public emptyContract;
    SlashingRegistryCoordinator public slashingRegistryCoordinator;
    CoreDeployLib.DeploymentData public coreDeployment;
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

    event OperatorSlashed(
        uint256 indexed slashingRequestId,
        address indexed operator,
        uint32 operatorSetId,
        uint256[] slashingAmounts,
        string description
    );

    function setUp() public {
        serviceManager = address(0x2);
        slasher = address(0x3);
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
        configData.rewardsCoordinator.rewardsUpdater = address(0x123);
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

        // Give serviceManager permissions
        vm.startPrank(proxyAdminOwner);
        PermissionController(coreDeployment.permissionController).setAppointee(
            proxyAdminOwner,
            address(serviceManager),
            address(coreDeployment.permissionController),
            PermissionController.setAppointee.selector
        );
        vm.stopPrank();

        vm.startPrank(serviceManager);

        slashingRegistryCoordinator =
            SlashingRegistryCoordinator(payable(middlewareDeployments.slashingRegistryCoordinator));
        stakeRegistry = StakeRegistry(middlewareDeployments.stakeRegistry);
        blsApkRegistry = BLSApkRegistry(middlewareDeployments.blsApkRegistry);
        indexRegistry = IndexRegistry(middlewareDeployments.indexRegistry);
        socketRegistry = SocketRegistry(middlewareDeployments.socketRegistry);

        // Setup permissions
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

        // Setup quorum
        vm.startPrank(proxyAdminOwner);
        IAllocationManager(coreDeployment.allocationManager).updateAVSMetadataURI(
            serviceManager, "fake-avs-metadata"
        );

        slashingRegistryCoordinator.createSlashableStakeQuorum(
            ISlashingRegistryCoordinatorTypes.OperatorSetParam({
                maxOperatorCount: 10,
                kickBIPsOfOperatorStake: 0,
                kickBIPsOfTotalStake: 0
            }),
            1 ether,
            _getStrategyParams(),
            0
        );

        // Deploy SelfSlasher
        selfSlasher = new SelfSlasher(
            IAllocationManager(coreDeployment.allocationManager),
            ISlashingRegistryCoordinator(slashingRegistryCoordinator),
            slasher
        );
        vm.stopPrank();

        // Now grant selfSlasher permissions from serviceManager
        vm.startPrank(serviceManager);
        PermissionController(coreDeployment.permissionController).setAppointee(
            address(serviceManager),
            address(selfSlasher),
            coreDeployment.allocationManager,
            AllocationManager.slashOperator.selector
        );
        vm.stopPrank();
    }

    function test_Initialization() public {
        assertEq(selfSlasher.slasher(), slasher, "Slasher address not set correctly");
        assertEq(
            address(selfSlasher.allocationManager()),
            address(coreDeployment.allocationManager),
            "AllocationManager address not set correctly"
        );
        assertEq(
            address(selfSlasher.slashingRegistryCoordinator()),
            address(slashingRegistryCoordinator),
            "Registry coordinator address not set correctly"
        );
        assertEq(selfSlasher.nextRequestId(), 0, "Initial request ID should be 0");
    }

    function test_SelfSlash_RevertIfInvalidWadToSlash() public {
        _setupOperatorForSlashing();

        vm.prank(operatorWallet.key.addr);
        vm.expectRevert(SelfSlasher.InvalidWadToSlash.selector);
        selfSlasher.selfSlash(0, 0, "zero slash");

        vm.prank(operatorWallet.key.addr);
        vm.expectRevert(SelfSlasher.InvalidWadToSlash.selector);
        selfSlasher.selfSlash(0, 1.1e18, "over 100% slash");
    }

    function test_SelfSlash_RevertIfNotRegistered() public {
        address nonOperator = makeAddr("nonOperator");

        vm.prank(nonOperator);
        vm.expectRevert(SelfSlasher.OperatorNotSlashable.selector);
        selfSlasher.selfSlash(0, 0.5e18, "not registered");
    }

    function test_SelfSlash_RevertIfNoStrategies() public {
        // Setup an operator set with no strategies (this is done in the mockCall)
        vm.mockCall(
            address(coreDeployment.allocationManager),
            abi.encodeWithSelector(IAllocationManager.getStrategiesInOperatorSet.selector),
            abi.encode(new IStrategy[](0))
        );

        _setupOperatorForSlashing();

        vm.prank(operatorWallet.key.addr);
        vm.expectRevert(SelfSlasher.NoStrategiesInOperatorSet.selector);
        selfSlasher.selfSlash(0, 0.5e18, "no strategies");

        // Clear the mock to not affect other tests
        vm.clearMockedCalls();
    }

    function test_SelfSlash_PartialSlashUpdatesStake() public {
        bytes32 operatorId = _setupOperatorForSlashing();
        uint96 initialStake = stakeRegistry.weightOfOperatorForQuorum(0, operatorWallet.key.addr);
        uint96 initialTotalStake = stakeRegistry.getCurrentTotalStake(0);

        vm.prank(operatorWallet.key.addr);
        selfSlasher.selfSlash(0, 0.5e18, "partial slash");

        uint96 newStake = stakeRegistry.weightOfOperatorForQuorum(0, operatorWallet.key.addr);
        uint96 newTotalStake = stakeRegistry.getCurrentTotalStake(0);

        assertEq(newStake, initialStake / 2, "Stake not reduced by 50%");
        assertEq(
            newTotalStake,
            initialTotalStake - (initialStake / 2),
            "Total stake not reduced by operator's 50%"
        );

        // Verify the operator is still registered
        ISlashingRegistryCoordinatorTypes.OperatorStatus status =
            slashingRegistryCoordinator.getOperatorStatus(operatorWallet.key.addr);
        assertEq(
            uint256(status),
            uint256(ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED),
            "Operator should remain registered after partial slash"
        );

        // Verify the quorum bitmap still includes this operator for quorum 0
        uint192 bitmap = slashingRegistryCoordinator.getCurrentQuorumBitmap(operatorId);
        assertTrue(bitmap & 1 != 0, "Operator should still be in quorum 0 after partial slash");
    }

    function test_SelfSlash_FullSlashRemovesOperator() public {
        bytes32 operatorId = _setupOperatorForSlashing();
        uint96 initialStake = stakeRegistry.weightOfOperatorForQuorum(0, operatorWallet.key.addr);
        uint96 initialTotalStake = stakeRegistry.getCurrentTotalStake(0);

        vm.prank(operatorWallet.key.addr);
        selfSlasher.selfSlash(0, 1e18, "full slash");

        uint96 newStake = stakeRegistry.weightOfOperatorForQuorum(0, operatorWallet.key.addr);
        uint96 newTotalStake = stakeRegistry.getCurrentTotalStake(0);

        assertEq(newStake, 0, "Stake should be reduced to 0");
        assertEq(
            newTotalStake,
            initialTotalStake - initialStake,
            "Total stake should be reduced by operator's full stake"
        );

        // Verify the operator is deregistered
        ISlashingRegistryCoordinatorTypes.OperatorStatus status =
            slashingRegistryCoordinator.getOperatorStatus(operatorWallet.key.addr);
        assertEq(
            uint256(status),
            uint256(ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED),
            "Operator should be deregistered after full slash"
        );

        // Verify the quorum bitmap no longer includes this operator for quorum 0
        uint192 bitmap = slashingRegistryCoordinator.getCurrentQuorumBitmap(operatorId);
        assertTrue(bitmap & 1 == 0, "Operator should be removed from quorum 0 after full slash");
    }

    function test_SelfSlash_EmitsEvent() public {
        _setupOperatorForSlashing();

        vm.recordLogs();

        vm.prank(operatorWallet.key.addr);
        selfSlasher.selfSlash(0, 0.1e18, "test slash");

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool eventFound = false;

        for (uint256 i = 0; i < entries.length; i++) {
            // Check for the slashing event from our contract
            if (
                entries[i].topics[0]
                    == keccak256("OperatorSlashed(uint256,address,uint32,uint256[],string)")
            ) {
                eventFound = true;
                break;
            }
        }

        assertTrue(eventFound, "OperatorSlashed event not emitted");
    }

    function test_SelfSlash_IncreasesRequestId() public {
        _setupOperatorForSlashing();
        uint256 requestIdBefore = selfSlasher.nextRequestId();

        vm.prank(operatorWallet.key.addr);
        selfSlasher.selfSlash(0, 0.5e18, "test slash");

        assertEq(
            selfSlasher.nextRequestId(), requestIdBefore + 1, "Request ID should be incremented"
        );
    }

    function test_SelfSlash_MinimumAmount() public {
        _setupOperatorForSlashing();
        uint96 initialStake = stakeRegistry.weightOfOperatorForQuorum(0, operatorWallet.key.addr);

        // Test with minimum possible value (1 wei of 1e18)
        vm.prank(operatorWallet.key.addr);
        selfSlasher.selfSlash(0, 1, "minimum slash");

        uint96 newStake = stakeRegistry.weightOfOperatorForQuorum(0, operatorWallet.key.addr);
        // Should subtract a very small amount (initial * 1/1e18)
        assertTrue(newStake < initialStake, "Stake should be reduced by minimum amount");
        assertTrue(initialStake - newStake <= 3, "Reduction should be minimal");
    }

    // -----------------
    // Helper functions
    // -----------------

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

    function _getStrategyParams()
        internal
        view
        returns (IStakeRegistryTypes.StrategyParams[] memory)
    {
        IStakeRegistryTypes.StrategyParams[] memory stratParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        stratParams[0] =
            IStakeRegistryTypes.StrategyParams({strategy: mockStrategy, multiplier: 1 ether});
        return stratParams;
    }
}

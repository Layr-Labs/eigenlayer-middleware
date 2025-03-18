// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Test.sol";

// OpenZeppelin
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// Core contracts
import "eigenlayer-contracts/src/contracts/core/DelegationManager.sol";
import "eigenlayer-contracts/src/contracts/core/StrategyManager.sol";
import "eigenlayer-contracts/src/contracts/core/AVSDirectory.sol";
import "eigenlayer-contracts/src/contracts/core/RewardsCoordinator.sol";
import "eigenlayer-contracts/src/contracts/core/AllocationManager.sol";
import "eigenlayer-contracts/src/contracts/strategies/StrategyBase.sol";
import "eigenlayer-contracts/src/contracts/pods/EigenPodManager.sol";
import "eigenlayer-contracts/src/contracts/pods/EigenPod.sol";
import "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import "eigenlayer-contracts/src/contracts/permissions/PermissionController.sol";
import "eigenlayer-contracts/src/test/mocks/ETHDepositMock.sol";

// Middleware contracts
import "../../src/RegistryCoordinator.sol";
import "../../src/StakeRegistry.sol";
import "../../src/IndexRegistry.sol";
import "../../src/BLSApkRegistry.sol";
import "../mocks/ServiceManagerMock.sol";
import "../../src/OperatorStateRetriever.sol";
import "../../src/SocketRegistry.sol";
import "../../src/interfaces/IRegistryCoordinator.sol";

// Mocks and More
import "../../src/libraries/BN254.sol";
import "../../src/libraries/BitmapUtils.sol";

import "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";
// import "../integration/mocks/ServiceManagerMock.t.sol";
import "./User.t.sol";
import "./OperatorSetUser.t.sol";

abstract contract IntegrationDeployer is Test, IUserDeployer {
    using Strings for *;

    Vm cheats = Vm(VM_ADDRESS);

    // Core contracts to deploy
    DelegationManager delegationManager;
    AVSDirectory public avsDirectory;
    StrategyManager strategyManager;
    EigenPodManager eigenPodManager;
    RewardsCoordinator rewardsCoordinator;
    PauserRegistry pauserRegistry;
    IBeacon eigenPodBeacon;
    EigenPod pod;
    ETHPOSDepositMock ethPOSDeposit;
    AllocationManager public allocationManager;
    PermissionController permissionController;

    // Base strategy implementation in case we want to create more strategies later
    StrategyBase baseStrategyImplementation;

    // Middleware contracts to deploy
    SlashingRegistryCoordinator public slashingRegistryCoordinator;
    RegistryCoordinator public registryCoordinator;
    ServiceManagerMock public serviceManager;
    BLSApkRegistry blsApkRegistry;
    StakeRegistry stakeRegistry;
    IndexRegistry indexRegistry;
    SocketRegistry socketRegistry;
    OperatorStateRetriever operatorStateRetriever;

    TimeMachine public timeMachine;

    // Lists of strategies used in the system
    IStrategy[] allStrats;
    IERC20[] allTokens;

    // ProxyAdmin
    ProxyAdmin proxyAdmin;
    // Admin Addresses
    address eigenLayerReputedMultisig = address(this); // admin address
    address constant pauser = address(555);
    address constant unpauser = address(556);
    address public registryCoordinatorOwner =
        address(uint160(uint256(keccak256("registryCoordinatorOwner"))));
    uint256 public churnApproverPrivateKey = uint256(keccak256("churnApproverPrivateKey"));
    address public churnApprover = cheats.addr(churnApproverPrivateKey);
    address ejector = address(uint160(uint256(keccak256("ejector"))));
    address rewardsUpdater = address(uint160(uint256(keccak256("rewardsUpdater"))));

    /// @dev Account identifier for the AVS. This is the unique identifier address for the AVS in the AllocationManager.
    /// This address is by default a UAM PermissionController admin and can transfer admin permissions to other addresses.
    /// For existing AVSs using ServiceManagers, this should be the same address as the ServiceManager and there exist
    /// interfaces on the ServiceManager to interact with UAM.
    address avsAccountIdentifier = address(uint160(uint256(keccak256("avsAccountIdentifier"))));

    // Constants/Defaults
    uint64 constant GENESIS_TIME_LOCAL = 1 hours * 12;
    uint256 constant MIN_BALANCE = 1e6;
    uint256 constant MAX_BALANCE = 5e6;
    uint256 constant MAX_STRATEGY_COUNT = 32; // From StakeRegistry.MAX_WEIGHING_FUNCTION_LENGTH
    uint96 constant DEFAULT_STRATEGY_MULTIPLIER = 1e18;
    // RewardsCoordinator
    // Config Variables
    /// @notice intervals(epochs) are 1 weeks
    uint32 CALCULATION_INTERVAL_SECONDS = 7 days;

    /// @notice Max duration is 5 epochs (2 weeks * 5 = 10 weeks in seconds)
    uint32 MAX_REWARDS_DURATION = 70 days;

    /// @notice Lower bound start range is ~3 months into the past, multiple of CALCULATION_INTERVAL_SECONDS
    uint32 MAX_RETROACTIVE_LENGTH = 84 days;
    /// @notice Upper bound start range is ~1 month into the future, multiple of CALCULATION_INTERVAL_SECONDS
    uint32 MAX_FUTURE_LENGTH = 28 days;
    /// @notice absolute min timestamp that a rewards can start at
    uint32 GENESIS_REWARDS_TIMESTAMP = 1712188800;
    /// @notice Equivalent to 100%, but in basis points.
    uint16 internal constant ONE_HUNDRED_IN_BIPS = 10000;

    uint32 defaultOperatorSplitBips = 1000;
    /// @notice Delay in timestamp before a posted root can be claimed against
    uint32 activationDelay = 7 days;
    /// @notice intervals(epochs) are 2 weeks
    uint32 calculationIntervalSeconds = 14 days;
    /// @notice the commission for all operators across all avss
    uint16 globalCommissionBips = 1000;

    function setUp() public virtual {
        // Deploy ProxyAdmin
        proxyAdmin = new ProxyAdmin();

        // Deploy PauserRegistry
        address[] memory pausers = new address[](1);
        pausers[0] = pauser;
        pauserRegistry = new PauserRegistry(pausers, unpauser);

        // Deploy mocks
        EmptyContract emptyContract = new EmptyContract();
        ethPOSDeposit = new ETHPOSDepositMock();

        /**
         * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
         * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
         */
        delegationManager = DelegationManager(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );
        strategyManager = StrategyManager(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );
        eigenPodManager = EigenPodManager(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );
        avsDirectory = AVSDirectory(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        allocationManager = AllocationManager(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        permissionController = PermissionController(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        rewardsCoordinator = RewardsCoordinator(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        // Deploy EigenPod Contracts
        pod = new EigenPod(ethPOSDeposit, eigenPodManager, GENESIS_TIME_LOCAL, "v0.0.1");

        eigenPodBeacon = new UpgradeableBeacon(address(pod));

        PermissionController permissionControllerImplementation = new PermissionController("v0.0.1");

        // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
        DelegationManager delegationImplementation = new DelegationManager(
            strategyManager,
            eigenPodManager,
            allocationManager,
            pauserRegistry,
            permissionController,
            0,
            "v0.0.1"
        );
        StrategyManager strategyManagerImplementation =
            new StrategyManager(delegationManager, pauserRegistry, "v0.0.1");
        EigenPodManager eigenPodManagerImplementation = new EigenPodManager(
            ethPOSDeposit, eigenPodBeacon, delegationManager, pauserRegistry, "v0.0.1"
        );
        AVSDirectory avsDirectoryImplementation =
            new AVSDirectory(delegationManager, pauserRegistry, "v0.0.1");

        RewardsCoordinator rewardsCoordinatorImplementation = new RewardsCoordinator(
            IRewardsCoordinatorTypes.RewardsCoordinatorConstructorParams({
                delegationManager: delegationManager,
                strategyManager: strategyManager,
                allocationManager: allocationManager,
                pauserRegistry: pauserRegistry,
                permissionController: permissionController,
                CALCULATION_INTERVAL_SECONDS: CALCULATION_INTERVAL_SECONDS,
                MAX_REWARDS_DURATION: MAX_REWARDS_DURATION,
                MAX_RETROACTIVE_LENGTH: MAX_RETROACTIVE_LENGTH,
                MAX_FUTURE_LENGTH: MAX_FUTURE_LENGTH,
                GENESIS_REWARDS_TIMESTAMP: GENESIS_REWARDS_TIMESTAMP,
                version: "v0.0.1"
            })
        );

        AllocationManager allocationManagerImplementation = new AllocationManager(
            delegationManager,
            pauserRegistry,
            permissionController,
            uint32(7 days), // DEALLOCATION_DELAY
            uint32(1 days), // ALLOCATION_CONFIGURATION_DELAY
            "v0.0.1" // Added config parameter
        );

        // Third, upgrade the proxy contracts to point to the implementations
        uint256 minWithdrawalDelayBlocks = 7 days / 12 seconds;
        IStrategy[] memory initializeStrategiesToSetDelayBlocks = new IStrategy[](0);
        uint256[] memory initializeWithdrawalDelayBlocks = new uint256[](0);
        // DelegationManager
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(delegationManager))),
            address(delegationImplementation),
            abi.encodeWithSelector(
                DelegationManager.initialize.selector,
                eigenLayerReputedMultisig, // initialOwner
                0 /* initialPausedStatus */
            )
        );
        // StrategyManager
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(strategyManager))),
            address(strategyManagerImplementation),
            abi.encodeWithSelector(
                StrategyManager.initialize.selector,
                eigenLayerReputedMultisig, //initialOwner
                eigenLayerReputedMultisig, //initial whitelister
                0 // initialPausedStatus
            )
        );
        // EigenPodManager
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(eigenPodManager))),
            address(eigenPodManagerImplementation),
            abi.encodeWithSelector(
                EigenPodManager.initialize.selector,
                eigenLayerReputedMultisig, // initialOwner
                0 // initialPausedStatus
            )
        );
        // AVSDirectory
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(avsDirectory))),
            address(avsDirectoryImplementation),
            abi.encodeWithSelector(
                AVSDirectory.initialize.selector,
                eigenLayerReputedMultisig, // initialOwner
                // pauserRegistry,
                0 // initialPausedStatus
            )
        );

        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(payable(address(permissionController))),
            address(permissionControllerImplementation)
        );

        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(rewardsCoordinator))),
            address(rewardsCoordinatorImplementation),
            abi.encodeWithSelector(
                RewardsCoordinator.initialize.selector,
                eigenLayerReputedMultisig, // initialOwner
                0, // initialPausedStatus
                rewardsUpdater,
                activationDelay,
                defaultOperatorSplitBips // defaultSplitBips
            )
        );

        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(allocationManager))),
            address(allocationManagerImplementation),
            abi.encodeWithSelector(
                AllocationManager.initialize.selector,
                eigenLayerReputedMultisig, // initialOwner
                0 // initialPausedStatus
            )
        );

        // Deploy and whitelist strategies
        baseStrategyImplementation = new StrategyBase(strategyManager, pauserRegistry, "v0.0.1");
        for (uint256 i = 0; i < MAX_STRATEGY_COUNT; i++) {
            string memory number = uint256(i).toString();
            string memory stratName = string.concat("StrategyToken", number);
            string memory stratSymbol = string.concat("STT", number);
            _newStrategyAndToken(stratName, stratSymbol, 10e50, address(this));
        }

        // wibbly-wobbly timey-wimey shenanigans
        timeMachine = new TimeMachine();

        cheats.startPrank(registryCoordinatorOwner);
        registryCoordinator = RegistryCoordinator(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );
        slashingRegistryCoordinator = SlashingRegistryCoordinator(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        stakeRegistry = StakeRegistry(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        socketRegistry = SocketRegistry(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        indexRegistry = IndexRegistry(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        blsApkRegistry = BLSApkRegistry(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        serviceManager = ServiceManagerMock(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );
        cheats.stopPrank();

        StakeRegistry stakeRegistryImplementation = new StakeRegistry(
            ISlashingRegistryCoordinator(slashingRegistryCoordinator),
            IDelegationManager(delegationManager),
            IAVSDirectory(avsDirectory),
            allocationManager
        );
        BLSApkRegistry blsApkRegistryImplementation =
            new BLSApkRegistry(ISlashingRegistryCoordinator(slashingRegistryCoordinator));
        IndexRegistry indexRegistryImplementation =
            new IndexRegistry(ISlashingRegistryCoordinator(slashingRegistryCoordinator));
        ServiceManagerMock serviceManagerImplementation = new ServiceManagerMock(
            IAVSDirectory(avsDirectory),
            rewardsCoordinator,
            ISlashingRegistryCoordinator(slashingRegistryCoordinator),
            stakeRegistry,
            permissionController,
            allocationManager
        );
        SocketRegistry socketRegistryImplementation =
            new SocketRegistry(ISlashingRegistryCoordinator(slashingRegistryCoordinator));

        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(payable(address(stakeRegistry))),
            address(stakeRegistryImplementation)
        );

        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(payable(address(blsApkRegistry))),
            address(blsApkRegistryImplementation)
        );

        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(payable(address(indexRegistry))),
            address(indexRegistryImplementation)
        );

        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(payable(address(serviceManager))),
            address(serviceManagerImplementation)
        );

        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(payable(address(socketRegistry))),
            address(socketRegistryImplementation)
        );

        serviceManager.initialize({
            initialOwner: registryCoordinatorOwner,
            rewardsInitiator: address(msg.sender)
        });

        IStakeRegistryTypes.StakeType[] memory quorumStakeTypes =
            new IStakeRegistryTypes.StakeType[](0);
        uint32[] memory slashableStakeQuorumLookAheadPeriods = new uint32[](0);

        RegistryCoordinator registryCoordinatorImplementation = new RegistryCoordinator(
            IRegistryCoordinatorTypes.RegistryCoordinatorParams(
                serviceManager,
                IRegistryCoordinatorTypes.SlashingRegistryParams(
                    stakeRegistry,
                    blsApkRegistry,
                    indexRegistry,
                    socketRegistry,
                    allocationManager,
                    pauserRegistry
                )
            )
        );
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(registryCoordinator))),
            address(registryCoordinatorImplementation),
            abi.encodeWithSelector(
                SlashingRegistryCoordinator.initialize.selector,
                registryCoordinatorOwner,
                churnApprover,
                ejector,
                0, /*initialPausedStatus*/
                address(serviceManager) /* accountIdentifier */
            )
        );

        SlashingRegistryCoordinator slashingRegistryCoordinatorImplementation = new SlashingRegistryCoordinator(
            stakeRegistry,
            blsApkRegistry,
            indexRegistry,
            socketRegistry,
            allocationManager,
            pauserRegistry,
            "v0.0.1"
        );
        cheats.prank(avsAccountIdentifier);
        allocationManager.updateAVSMetadataURI(
            address(avsAccountIdentifier), "ipfs://mock-metadata-uri"
        );

        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(slashingRegistryCoordinator))),
            address(slashingRegistryCoordinatorImplementation),
            abi.encodeWithSelector(
                SlashingRegistryCoordinator.initialize.selector,
                registryCoordinatorOwner,
                churnApprover,
                ejector,
                0, /*initialPausedStatus*/
                avsAccountIdentifier /* accountIdentifier */
            )
        );

        operatorStateRetriever = new OperatorStateRetriever();

        // Setup UAM Permissions
        cheats.startPrank(serviceManager.owner());
        // 1. set AVS registrar
        serviceManager.setAppointee({
            appointee: serviceManager.owner(),
            target: address(allocationManager),
            selector: IAllocationManager.setAVSRegistrar.selector
        });

        // 2. set AVS metadata
        serviceManager.setAppointee({
            appointee: serviceManager.owner(),
            target: address(allocationManager),
            selector: IAllocationManager.updateAVSMetadataURI.selector
        });
        // 3. create operator sets
        serviceManager.setAppointee({
            appointee: address(registryCoordinator),
            target: address(allocationManager),
            selector: IAllocationManager.createOperatorSets.selector
        });
        // 4. deregister operator from operator sets
        serviceManager.setAppointee({
            appointee: address(registryCoordinator),
            target: address(allocationManager),
            selector: IAllocationManager.deregisterFromOperatorSets.selector
        });
        // 5. add strategies to operator sets
        serviceManager.setAppointee({
            appointee: address(registryCoordinator),
            target: address(stakeRegistry),
            selector: IAllocationManager.addStrategiesToOperatorSet.selector
        });
        // 6. remove strategies from operator sets
        serviceManager.setAppointee({
            appointee: address(registryCoordinator),
            target: address(stakeRegistry),
            selector: IAllocationManager.removeStrategiesFromOperatorSet.selector
        });
        cheats.stopPrank();
        _setOperatorSetsEnabled(false);
        _setM2QuorumsDisabled(false);
        _setM2QuorumBitmap(0);

        /// Setup UAM Permissions for SlashingRegistryCoordinator
        cheats.startPrank(avsAccountIdentifier);
        permissionController.setAppointee({
            account: avsAccountIdentifier,
            appointee: address(avsAccountIdentifier),
            target: address(allocationManager),
            selector: IAllocationManager.setAVSRegistrar.selector
        });
        permissionController.setAppointee({
            account: avsAccountIdentifier,
            appointee: address(slashingRegistryCoordinator),
            target: address(allocationManager),
            selector: IAllocationManager.createOperatorSets.selector
        });
        permissionController.setAppointee({
            account: avsAccountIdentifier,
            appointee: address(slashingRegistryCoordinator),
            target: address(allocationManager),
            selector: IAllocationManager.deregisterFromOperatorSets.selector
        });
        permissionController.setAppointee({
            account: avsAccountIdentifier,
            appointee: address(stakeRegistry),
            target: address(allocationManager),
            selector: IAllocationManager.addStrategiesToOperatorSet.selector
        });
        permissionController.setAppointee({
            account: avsAccountIdentifier,
            appointee: address(stakeRegistry),
            target: address(allocationManager),
            selector: IAllocationManager.removeStrategiesFromOperatorSet.selector
        });
        // set AVS Registrar to slashingRegistryCoordinator
        allocationManager.setAVSRegistrar(
            avsAccountIdentifier, IAVSRegistrar(address(slashingRegistryCoordinator))
        );

        cheats.stopPrank();
    }

    /// @notice Overwrite RegistryCoordinator.operatorSetsEnabled to the specified value.
    /// This is to enable testing of RegistryCoordinator in non-operator set mode.
    function _setOperatorSetsEnabled(
        bool operatorSetsEnabled
    ) internal {
        // 1. First read the current value of the entire slot
        // which holds operatorSetsEnabled, m2QuorumsDisabled, and accountIdentifier
        bytes32 currentSlot = cheats.load(address(registryCoordinator), bytes32(uint256(200)));

        // 2. Clear only the first byte (operatorSetsEnabled) while keeping the rest
        bytes32 newSlot = (currentSlot & ~bytes32(uint256(0xff)))
            | bytes32(uint256(operatorSetsEnabled ? 0x01 : 0x00));

        // 3. Store the modified slot
        cheats.store(address(registryCoordinator), bytes32(uint256(200)), newSlot);
    }

    /// @notice Overwrite RegistryCoordinator.m2QuorumsDisabled to the specified value.
    function _setM2QuorumsDisabled(
        bool m2QuorumsDisabled
    ) internal {
        // 1. First read the current value of the entire slot
        // which holds operatorSetsEnabled, m2QuorumsDisabled, and accountIdentifier
        bytes32 currentSlot = cheats.load(address(registryCoordinator), bytes32(uint256(200)));

        // 2. Clear only the second byte (m2QuorumsDisabled) while keeping the rest
        bytes32 newSlot = (currentSlot & ~bytes32(uint256(0xff) << 8))
            | bytes32(uint256(m2QuorumsDisabled ? 0x01 : 0x00) << 8);

        // 3. Store the modified slot
        cheats.store(address(registryCoordinator), bytes32(uint256(200)), newSlot);
    }

    /// @notice Overwrite RegistryCoordinator._m2QuorumBitmap to the specified value
    function _setM2QuorumBitmap(
        uint256 m2QuorumBitmap
    ) internal {
        bytes32 currentSlot = cheats.load(address(registryCoordinator), bytes32(uint256(200)));

        cheats.store(address(registryCoordinator), bytes32(uint256(200)), bytes32(m2QuorumBitmap));
    }

    /// @dev Deploy a strategy and its underlying token, push to global lists of tokens/strategies, and whitelist
    /// strategy in strategyManager
    function _newStrategyAndToken(
        string memory tokenName,
        string memory tokenSymbol,
        uint256 initialSupply,
        address owner
    ) internal {
        IERC20 underlyingToken =
            new ERC20PresetFixedSupply(tokenName, tokenSymbol, initialSupply, owner);
        StrategyBase strategy = StrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(baseStrategyImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        StrategyBase.initialize.selector, underlyingToken, pauserRegistry
                    )
                )
            )
        );

        // Whitelist strategy
        IStrategy[] memory strategies = new IStrategy[](1);
        bool[] memory thirdPartyTransfersForbiddenValues = new bool[](1);
        strategies[0] = strategy;
        cheats.prank(strategyManager.strategyWhitelister());
        strategyManager.addStrategiesToDepositWhitelist(strategies);

        // Add to allStrats
        allStrats.push(strategy);
        allTokens.push(underlyingToken);
    }
}

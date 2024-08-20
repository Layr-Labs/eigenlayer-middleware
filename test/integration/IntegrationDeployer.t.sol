// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "forge-std/Test.sol";

// OpenZeppelin
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// Core contracts
import "eigenlayer-contracts/src/contracts/core/DelegationManager.sol";
import "eigenlayer-contracts/src/contracts/core/StrategyManager.sol";
import "eigenlayer-contracts/src/contracts/core/Slasher.sol";
import "eigenlayer-contracts/src/contracts/core/AVSDirectory.sol";
import "eigenlayer-contracts/src/contracts/core/RewardsCoordinator.sol";
import "eigenlayer-contracts/src/contracts/strategies/StrategyBase.sol";
import "eigenlayer-contracts/src/contracts/pods/EigenPodManager.sol";
import "eigenlayer-contracts/src/contracts/pods/EigenPod.sol";
import "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import "eigenlayer-contracts/src/test/mocks/ETHDepositMock.sol";

// Middleware contracts
import "src/RegistryCoordinator.sol";
import "src/StakeRegistry.sol";
import "src/IndexRegistry.sol";
import "src/BLSApkRegistry.sol";
import "test/mocks/ServiceManagerMock.sol";
import "src/OperatorStateRetriever.sol";

// Mocks and More
import "src/libraries/BN254.sol";
import "src/libraries/BitmapUtils.sol";

import "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";
// import "src/test/integration/mocks/ServiceManagerMock.t.sol";
import "test/integration/User.t.sol";

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
    Slasher slasher;
    IBeacon eigenPodBeacon;
    EigenPod pod;
    ETHPOSDepositMock ethPOSDeposit;

    // Base strategy implementation in case we want to create more strategies later
    StrategyBase baseStrategyImplementation;

    // Middleware contracts to deploy
    RegistryCoordinator public registryCoordinator;
    ServiceManagerMock serviceManager;
    BLSApkRegistry blsApkRegistry;
    StakeRegistry stakeRegistry;
    IndexRegistry indexRegistry;
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

    // Constants/Defaults
    uint64 constant GENESIS_TIME_LOCAL = 1 hours * 12;
    uint256 constant MIN_BALANCE = 1e6;
    uint256 constant MAX_BALANCE = 5e6;
    uint256 constant MAX_STRATEGY_COUNT = 32; // From StakeRegistry.MAX_WEIGHING_FUNCTION_LENGTH
    uint96 constant DEFAULT_STRATEGY_MULTIPLIER = 1e18;
    // RewardsCoordinator
    uint32 MAX_REWARDS_DURATION = 70 days;
    uint32 MAX_RETROACTIVE_LENGTH = 84 days;
    uint32 MAX_FUTURE_LENGTH = 28 days;
    uint32 GENESIS_REWARDS_TIMESTAMP = 1_712_092_632;
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
        slasher = Slasher(
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
        // RewardsCoordinator = RewardsCoordinator(
        //     address(new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), ""))
        // );

        // Deploy EigenPod Contracts
        pod = new EigenPod(
            ethPOSDeposit,
            eigenPodManager,
            GENESIS_TIME_LOCAL
        );

        eigenPodBeacon = new UpgradeableBeacon(address(pod));

        // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
        DelegationManager delegationImplementation =
            new DelegationManager(strategyManager, slasher, eigenPodManager);
        StrategyManager strategyManagerImplementation =
            new StrategyManager(delegationManager, eigenPodManager, slasher);
        Slasher slasherImplementation = new Slasher(strategyManager, delegationManager);
        EigenPodManager eigenPodManagerImplementation = new EigenPodManager(
            ethPOSDeposit, eigenPodBeacon, strategyManager, slasher, delegationManager
        );
        AVSDirectory avsDirectoryImplemntation = new AVSDirectory(delegationManager);
        // RewardsCoordinator rewardsCoordinatorImplementation = new RewardsCoordinator(
        //     delegationManager,
        //     IStrategyManager(address(strategyManager)),
        //     MAX_REWARDS_DURATION,
        //     MAX_RETROACTIVE_LENGTH,
        //     MAX_FUTURE_LENGTH,
        //     GENESIS_REWARDS_TIMESTAMP
        // );

        // Third, upgrade the proxy contracts to point to the implementations
        uint256 minWithdrawalDelayBlocks = 7 days / 12 seconds;
        IStrategy[] memory initializeStrategiesToSetDelayBlocks = new IStrategy[](0);
        uint256[] memory initializeWithdrawalDelayBlocks = new uint256[](0);
        // DelegationManager
        proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(delegationManager))),
            address(delegationImplementation),
            abi.encodeWithSelector(
                DelegationManager.initialize.selector,
                eigenLayerReputedMultisig, // initialOwner
                pauserRegistry,
                0, /* initialPausedStatus */
                minWithdrawalDelayBlocks,
                initializeStrategiesToSetDelayBlocks,
                initializeWithdrawalDelayBlocks
            )
        );
        // StrategyManager
        proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(strategyManager))),
            address(strategyManagerImplementation),
            abi.encodeWithSelector(
                StrategyManager.initialize.selector,
                eigenLayerReputedMultisig, //initialOwner
                eigenLayerReputedMultisig, //initial whitelister
                pauserRegistry,
                0 // initialPausedStatus
            )
        );
        // Slasher
        proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(slasher))),
            address(slasherImplementation),
            abi.encodeWithSelector(
                Slasher.initialize.selector,
                eigenLayerReputedMultisig,
                pauserRegistry,
                0 // initialPausedStatus
            )
        );
        // EigenPodManager
        proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(eigenPodManager))),
            address(eigenPodManagerImplementation),
            abi.encodeWithSelector(
                EigenPodManager.initialize.selector,
                eigenLayerReputedMultisig, // initialOwner
                pauserRegistry,
                0 // initialPausedStatus
            )
        );
        // AVSDirectory
        proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(avsDirectory))),
            address(avsDirectoryImplemntation),
            abi.encodeWithSelector(
                AVSDirectory.initialize.selector,
                eigenLayerReputedMultisig, // initialOwner
                pauserRegistry,
                0 // initialPausedStatus
            )
        );
        // // RewardsCoordinator
        // proxyAdmin.upgradeAndCall(
        //     TransparentUpgradeableProxy(payable(address(rewardsCoordinator))),
        //     address(rewardsCoordinatorImplementation),
        //     abi.encodeWithSelector(
        //         RewardsCoordinator.initialize.selector,
        //         eigenLayerReputedMultisig, // initialOwner
        //         pauserRegistry,
        //         0, // initialPausedStatus
        //         rewardsUpdater,
        //         activationDelay,
        //         calculationIntervalSeconds,
        //         globalCommissionBips
        //     )
        // );

        // Deploy and whitelist strategies
        baseStrategyImplementation = new StrategyBase(strategyManager);
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

        stakeRegistry = StakeRegistry(
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
            IRegistryCoordinator(registryCoordinator), IDelegationManager(delegationManager)
        );
        BLSApkRegistry blsApkRegistryImplementation =
            new BLSApkRegistry(IRegistryCoordinator(registryCoordinator));
        IndexRegistry indexRegistryImplementation =
            new IndexRegistry(IRegistryCoordinator(registryCoordinator));
        ServiceManagerMock serviceManagerImplementation = new ServiceManagerMock(
            IAVSDirectory(avsDirectory),
            rewardsCoordinator,
            IRegistryCoordinator(registryCoordinator),
            stakeRegistry
        );

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(stakeRegistry))),
            address(stakeRegistryImplementation)
        );

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(blsApkRegistry))),
            address(blsApkRegistryImplementation)
        );

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(indexRegistry))),
            address(indexRegistryImplementation)
        );

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(serviceManager))),
            address(serviceManagerImplementation)
        );

        serviceManager.initialize({
            initialOwner: registryCoordinatorOwner,
            rewardsInitiator: address(msg.sender)
        });

        RegistryCoordinator registryCoordinatorImplementation =
            new RegistryCoordinator(serviceManager, stakeRegistry, blsApkRegistry, indexRegistry);
        proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(registryCoordinator))),
            address(registryCoordinatorImplementation),
            abi.encodeWithSelector(
                RegistryCoordinator.initialize.selector,
                registryCoordinatorOwner,
                churnApprover,
                ejector,
                pauserRegistry,
                0, /*initialPausedStatus*/
                new IRegistryCoordinator.OperatorSetParam[](0),
                new uint96[](0),
                new IStakeRegistry.StrategyParams[][](0)
            )
        );

        operatorStateRetriever = new OperatorStateRetriever();
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
        strategyManager.addStrategiesToDepositWhitelist(
            strategies, thirdPartyTransfersForbiddenValues
        );

        // Add to allStrats
        allStrats.push(strategy);
        allTokens.push(underlyingToken);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

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
import "eigenlayer-contracts/src/contracts/strategies/StrategyBase.sol";
import "eigenlayer-contracts/src/contracts/pods/EigenPodManager.sol";
import "eigenlayer-contracts/src/contracts/pods/EigenPod.sol";
import "eigenlayer-contracts/src/contracts/pods/DelayedWithdrawalRouter.sol";
import "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import "eigenlayer-contracts/src/test/mocks/ETHDepositMock.sol";
// import "eigenlayer-contracts/src/test/integration/mocks/BeaconChainOracleMock.t.sol";
import "test/integration/mocks/BeaconChainOracleMock.t.sol";

// Middleware contracts
import "src/RegistryCoordinator.sol";
import "src/StakeRegistry.sol";
import "src/IndexRegistry.sol";
import "src/BLSApkRegistry.sol";
import "src/ServiceManagerBase.sol";
import "src/OperatorStateRetriever.sol";

// Mocks and More
import "src/libraries/BN254.sol";
import "test/ffi/util/G2Operations.sol";
import "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";
// import "src/test/integration/mocks/ServiceManagerMock.t.sol";
import "test/integration/User.t.sol";

abstract contract IntegrationDeployer is Test, IUserDeployer, G2Operations {

    using Strings for *;
    using BN254 for *;

    Vm cheats = Vm(HEVM_ADDRESS);

    // Core contracts to deploy
    DelegationManager delegationManager;
    StrategyManager strategyManager;
    EigenPodManager eigenPodManager;
    PauserRegistry pauserRegistry;
    Slasher slasher;
    IBeacon eigenPodBeacon;
    EigenPod pod;
    DelayedWithdrawalRouter delayedWithdrawalRouter;
    ETHPOSDepositMock ethPOSDeposit;
    BeaconChainOracleMock beaconChainOracle;

    // Base strategy implementation in case we want to create more strategies later
    StrategyBase baseStrategyImplementation;

    // Middleware contracts to deploy
    RegistryCoordinator public registryCoordinator;
    ServiceManagerBase serviceManager;
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
    address public registryCoordinatorOwner = address(uint160(uint256(keccak256("registryCoordinatorOwner"))));
    uint256 churnApproverPrivateKey = uint256(keccak256("churnApproverPrivateKey"));
    address churnApprover = cheats.addr(churnApproverPrivateKey);
    address ejector = address(uint160(uint256(keccak256("ejector"))));
    
    // Initialized quorums:
    uint quorumCount;
    uint192 quorumBitmap;
    bytes quorumArray;

    // Randomness state vars
    bytes32 random;
    // _configRang sets this values, which determine what kind of config the AVS starts with
    bytes quorumTypes;
    bytes strategyTypes;
    bytes minimumStakeTypes;

    // Constants/Defaults
    uint64 constant MAX_RESTAKED_BALANCE_GWEI_PER_VALIDATOR = 32e9;
    uint constant MIN_BALANCE = 1e6;
    uint constant MAX_BALANCE = 5e6;
    uint constant MAX_QUORUM_COUNT = 192;  // From RegistryCoordinator.MAX_QUORUM_COUNT
    uint constant MAX_STRATEGY_COUNT = 32; // From StakeRegistry.MAX_WEIGHING_FUNCTION_LENGTH
    uint96 constant DEFAULT_STRATEGY_MULTIPLIER = 1e18;
    uint32 constant MAX_OPERATOR_COUNT = 1000;
    uint16 constant KICK_BIPS_OPERATOR_STAKE = 15000;
    uint16 constant KICK_BIPS_TOTAL_STAKE = 150;

    // Flags
    uint constant FLAG = 1;

    /// @dev Flags for quorumTypes and strategyTypes
    // These are used with _configRand to determine how many quorums to create,
    // as well as how many StrategyParams to configure quorums with.
    uint constant ONE = (FLAG << 0);
    uint constant TWO = (FLAG << 1);
    uint constant MANY = (FLAG << 2);

    /// @dev Flags for minimumStakeTypes
    // These are used with _configRand to determine what types of "minimum stake"
    // a quorum is configured with when created
    uint constant NO_MINIMUM = (FLAG << 0);
    uint constant HAS_MINIMUM = (FLAG << 1);

    // Generated BLS keypairs
    uint constant KEYS_TO_GENERATE = 20;
    uint fetchIdx = 0;
    uint[] privKeys;
    IBLSApkRegistry.PubkeyRegistrationParams[] pubkeys;

    /**
     * Since BLS key generation uses FFI, it's pretty slow. Pregenerating keys
     * in the constructor apparently ensures that this only happens once,
     * so this is the best way to speed things up when running multiple tests.
     */
    constructor() {
        for (uint i = 0; i < KEYS_TO_GENERATE; i++) {            
            IBLSApkRegistry.PubkeyRegistrationParams memory pubkey;
            uint privKey = uint(keccak256(abi.encodePacked(i + 1)));
            
            pubkey.pubkeyG1 = BN254.generatorG1().scalar_mul(privKey);
            pubkey.pubkeyG2 = G2Operations.mul(privKey);

            privKeys.push(privKey);
            pubkeys.push(pubkey);
        }
    }

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
        beaconChainOracle = new BeaconChainOracleMock();

        /**
         * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
         * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
         */
        delegationManager = DelegationManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), ""))
        );
        strategyManager = StrategyManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), ""))
        );
        slasher = Slasher(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), ""))
        );
        eigenPodManager = EigenPodManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), ""))
        );
        delayedWithdrawalRouter = DelayedWithdrawalRouter(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), ""))
        );

        // Deploy EigenPod Contracts
        pod = new EigenPod(
            ethPOSDeposit,
            delayedWithdrawalRouter,
            eigenPodManager,
            MAX_RESTAKED_BALANCE_GWEI_PER_VALIDATOR,
            0
        );

        eigenPodBeacon = new UpgradeableBeacon(address(pod));

        // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
        DelegationManager delegationImplementation = new DelegationManager(strategyManager, slasher, eigenPodManager);
        StrategyManager strategyManagerImplementation = new StrategyManager(delegationManager, eigenPodManager, slasher);
        Slasher slasherImplementation = new Slasher(strategyManager, delegationManager);
        EigenPodManager eigenPodManagerImplementation = new EigenPodManager(
            ethPOSDeposit,
            eigenPodBeacon,
            strategyManager,
            slasher,
            delegationManager
        );
        DelayedWithdrawalRouter delayedWithdrawalRouterImplementation = new DelayedWithdrawalRouter(eigenPodManager);

        // Third, upgrade the proxy contracts to point to the implementations
        uint256 withdrawalDelayBlocks = 7 days / 12 seconds;
        // DelegationManager
        proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(delegationManager))),
            address(delegationImplementation),
            abi.encodeWithSelector(
                DelegationManager.initialize.selector,
                eigenLayerReputedMultisig, // initialOwner
                pauserRegistry,
                0 /* initialPausedStatus */,
                withdrawalDelayBlocks
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
                type(uint).max, // maxPods
                address(beaconChainOracle),
                eigenLayerReputedMultisig, // initialOwner
                pauserRegistry,
                0 // initialPausedStatus
            )
        );
        // Delayed Withdrawal Router
        proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(delayedWithdrawalRouter))),
            address(delayedWithdrawalRouterImplementation),
            abi.encodeWithSelector(
                DelayedWithdrawalRouter.initialize.selector,
                eigenLayerReputedMultisig, // initialOwner
                pauserRegistry,
                0, // initialPausedStatus
                withdrawalDelayBlocks
            )
        );

        // Deploy and whitelist strategies
        baseStrategyImplementation = new StrategyBase(strategyManager);
        for (uint i = 0; i < MAX_STRATEGY_COUNT; i++) {
            string memory number = uint(i).toString();
            string memory stratName = string.concat("StrategyToken", number);
            string memory stratSymbol = string.concat("STT", number);
            _newStrategyAndToken(stratName, stratSymbol, 10e50, address(this));
        }

        // wibbly-wobbly timey-wimey shenanigans
        timeMachine = new TimeMachine();

        cheats.startPrank(registryCoordinatorOwner);
        registryCoordinator = RegistryCoordinator(address(
            new TransparentUpgradeableProxy(
                address(emptyContract),
                address(proxyAdmin),
                ""
            )
        ));

        stakeRegistry = StakeRegistry(
            address(
                new TransparentUpgradeableProxy(
                    address(emptyContract),
                    address(proxyAdmin),
                    ""
                )
            )
        );

        indexRegistry = IndexRegistry(
            address(
                new TransparentUpgradeableProxy(
                    address(emptyContract),
                    address(proxyAdmin),
                    ""
                )
            )
        );

        blsApkRegistry = BLSApkRegistry(
            address(
                new TransparentUpgradeableProxy(
                    address(emptyContract),
                    address(proxyAdmin),
                    ""
                )
            )
        );

        serviceManager = ServiceManagerBase(
            address(
                new TransparentUpgradeableProxy(
                    address(emptyContract),
                    address(proxyAdmin),
                    ""
                )
            )
        );
        cheats.stopPrank();

        StakeRegistry stakeRegistryImplementation = new StakeRegistry(IRegistryCoordinator(registryCoordinator), IDelegationManager(delegationManager));
        BLSApkRegistry blsApkRegistryImplementation = new BLSApkRegistry(IRegistryCoordinator(registryCoordinator));
        IndexRegistry indexRegistryImplementation = new IndexRegistry(IRegistryCoordinator(registryCoordinator));
        ServiceManagerBase serviceManagerImplementation = new ServiceManagerBase(IDelegationManager(delegationManager), IRegistryCoordinator(registryCoordinator), stakeRegistry);

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

        serviceManager.initialize({initialOwner: registryCoordinatorOwner});

        RegistryCoordinator registryCoordinatorImplementation = new RegistryCoordinator(serviceManager, stakeRegistry, blsApkRegistry, indexRegistry);
        proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(registryCoordinator))),
            address(registryCoordinatorImplementation),
            abi.encodeWithSelector(
                RegistryCoordinator.initialize.selector,
                registryCoordinatorOwner,
                churnApprover,
                ejector,
                pauserRegistry,
                0/*initialPausedStatus*/,
                new IRegistryCoordinator.OperatorSetParam[](0),
                new uint96[](0),
                new IStakeRegistry.StrategyParams[][](0)
            )
        );

        operatorStateRetriever = new OperatorStateRetriever();
    }

    /// @dev Deploy a strategy and its underlying token, push to global lists of tokens/strategies, and whitelist
    /// strategy in strategyManager
    function _newStrategyAndToken(string memory tokenName, string memory tokenSymbol, uint initialSupply, address owner) internal {
        IERC20 underlyingToken = new ERC20PresetFixedSupply(tokenName, tokenSymbol, initialSupply, owner); 
        StrategyBase strategy = StrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(baseStrategyImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(StrategyBase.initialize.selector, underlyingToken, pauserRegistry)
                )
            )
        );

        // Whitelist strategy
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy;
        cheats.prank(strategyManager.strategyWhitelister());
        strategyManager.addStrategiesToDepositWhitelist(strategies);

        // Add to allStrats
        allStrats.push(strategy);
        allTokens.push(underlyingToken);
    }

    function _configRand(
        uint24 _randomSeed, 
        uint _quorumTypes,
        uint _strategyTypes,
        uint _minStakeTypes
    ) internal {
        // Using uint24 for the seed type so that if a test fails, it's easier
        // to manually use the seed to replay the same test.
        emit log_named_uint("_configRand: set random seed to: ", _randomSeed);
        random = keccak256(abi.encodePacked(_randomSeed));

        // Convert flag bitmaps to bytes of set bits for easy use with _randUint
        quorumTypes = _bitmapToBytes(_quorumTypes);
        strategyTypes = _bitmapToBytes(_strategyTypes);
        minimumStakeTypes = _bitmapToBytes(_minStakeTypes);

        assertTrue(quorumTypes.length != 0, "_configRand: invalid quorumTypes, no flags passed");
        assertTrue(strategyTypes.length != 0, "_configRand: invalid strategyTypes, no flags passed");
        assertTrue(minimumStakeTypes.length != 0, "_configRand: invalid minimumStakeTypes, no flags passed");

        // Decide how many quorums to initialize:
        quorumCount = _randQuorumCount();
        quorumBitmap = uint192((1 << quorumCount) - 1);
        quorumArray = BitmapUtils.bitmapToBytesArray(quorumBitmap);
        emit log_named_uint("_configRand: number of quorums being initialized: ", quorumCount);

        // Initialize each quorum with random config:
        for (uint i = 0; i < quorumCount; i++) {

            IRegistryCoordinator.OperatorSetParam memory operatorSet = IRegistryCoordinator.OperatorSetParam({
                maxOperatorCount: MAX_OPERATOR_COUNT,
                kickBIPsOfOperatorStake: KICK_BIPS_OPERATOR_STAKE,
                kickBIPsOfTotalStake: KICK_BIPS_TOTAL_STAKE
            });

            IStakeRegistry.StrategyParams[] memory strategyParams = _randStrategyParams();
            uint96 minimumStake = _randMinStake();

            emit log_named_uint("_configRand: creating quorum ", i);
            emit log_named_uint("- Max operator count: ", operatorSet.maxOperatorCount);
            emit log_named_uint("- Num strategies considered: ", strategyParams.length);
            emit log_named_uint("- Minimum stake: ", minimumStake);

            cheats.prank(registryCoordinatorOwner);
            registryCoordinator.createQuorum({
                operatorSetParams: operatorSet,
                minimumStake: minimumStake,
                strategyParams: strategyParams
            });
        }
    }

    /// @dev Create a new user with token balances in ALL core-whitelisted strategies
    function _randUser(string memory name) internal returns (User, IStrategy[] memory, uint[] memory) {
        // Create User contract and give it a unique BLS keypair
        (uint privKey, IBLSApkRegistry.PubkeyRegistrationParams memory pubkey) = _fetchKeypair();
        User user = new User(name, privKey, pubkey);
        emit log_named_string("_randUser: Creating user ", user.NAME());

        IStrategy[] memory strategies = new IStrategy[](allStrats.length);
        uint[] memory balances = new uint[](allStrats.length);

        // Deal the user a random balance between [MIN_BALANCE, MAX_BALANCE] for each existing strategy
        emit log_named_uint("- Num assets: ", allStrats.length);
        for (uint i = 0; i < allStrats.length; i++) {
            IStrategy strat = allStrats[i];
            IERC20 underlyingToken = strat.underlyingToken();

            uint balance = _randUint({ min: MIN_BALANCE, max: MAX_BALANCE });
            StdCheats.deal(address(underlyingToken), address(user), balance);

            strategies[i] = strat;
            balances[i] = balance;
        }

        return (user, strategies, balances);
    }

    function _fetchKeypair() internal returns (uint, IBLSApkRegistry.PubkeyRegistrationParams memory) {
        // should probably just generate another keypair at this point
        if (fetchIdx == privKeys.length) {
            revert("_fetchKeypair: not enough generated keys");
        }

        uint privKey = privKeys[fetchIdx];
        IBLSApkRegistry.PubkeyRegistrationParams memory pubkey = pubkeys[fetchIdx];
        fetchIdx++;

        return (privKey, pubkey);
    }

    /// @dev Uses `random` to return a random uint, with a range given by `min` and `max` (inclusive)
    /// @return `min` <= result <= `max`
    function _randUint(uint min, uint max) internal returns (uint) {        
        uint range = max - min + 1;

        // calculate the number of bits needed for the range
        uint bitsNeeded = 0;
        uint tempRange = range;
        while (tempRange > 0) {
            bitsNeeded++;
            tempRange >>= 1;
        }

        // create a mask for the required number of bits
        // and extract the value from the hash
        uint mask = (1 << bitsNeeded) - 1;
        uint value = uint(random) & mask;

        // in case value is out of range, wrap around or retry
        while (value >= range) {
            value = (value - range) & mask;
        }

        // Hash `random` with itself so the next value we generate is different
        random = keccak256(abi.encodePacked(random));
        return min + value;
    }

    function _randBool() internal returns (bool) {
        return _randUint({ min: 0, max: 1 }) == 0;
    }

    /// @dev Select a random value from `arr` and return it. Reverts if arr is empty
    function _randValue(bytes memory arr) internal returns (uint) {
        assertTrue(arr.length > 0, "_randValue: tried to select value from empty array");
        
        uint idx = _randUint({ min: 0, max: arr.length - 1 });
        return uint(uint8(arr[idx]));
    }

    /// Private _randX methods used by _configRand:

    /// @dev Select a random number of quorums to initialize
    /// NOTE: This should only be used when initializing quorums for the first time (in _configRand)
    function _randQuorumCount() private returns (uint) {
        uint quorumFlag = _randValue(quorumTypes);
        
        if (quorumFlag == ONE) {
            return 1;
        } else if (quorumFlag == TWO) {
            return 2;
        } else if (quorumFlag == MANY) {
            return _randUint({ min: 3, max: MAX_QUORUM_COUNT });
        } else {
            revert("_randQuorumCount: flag not recognized");
        }
    }

    /// @dev Select a random number of strategies and multipliers to create a quorum with
    /// NOTE: This should only be used when creating a quorum for the first time. If you're
    /// selecting strategies to add after the quorum has been initialized, this is likely to
    /// return duplicates.
    function _randStrategyParams() private returns (IStakeRegistry.StrategyParams[] memory) {
        uint strategyFlag = _randValue(strategyTypes);
        uint strategyCount;

        if (strategyFlag == ONE) {
            strategyCount = 1;
        } else if (strategyFlag == TWO) {
            strategyCount = 2;
        } else if (strategyFlag == MANY) {
            strategyCount = _randUint({ min: 3, max: allStrats.length - 1 });
        } else {
            revert("_randStrategyCount: flag not recognized");
        }

        IStakeRegistry.StrategyParams[] memory params = new IStakeRegistry.StrategyParams[](strategyCount);

        for (uint i = 0; i < params.length; i++) {
            params[i] = IStakeRegistry.StrategyParams({
                strategy: allStrats[i],
                multiplier: DEFAULT_STRATEGY_MULTIPLIER
            });
        }

        return params;
    }

    /// @dev Select a random number of quorums to initialize
    function _randMinStake() private returns (uint96) {
        uint minStakeFlag = _randValue(minimumStakeTypes);
        
        if (minStakeFlag == NO_MINIMUM) {
            return 0;
        } else if (minStakeFlag == HAS_MINIMUM) {
            return uint96(MIN_BALANCE);
        } else {
            revert("_randQuorumCount: flag not recognized");
        }
    }

    /**
     * @dev Converts a bitmap into an array of bytes
     * @dev Each byte in the input is processed as indicating a single bit to flip in the bitmap
     */
    function _bitmapToBytes(uint bitmap) internal pure returns (bytes memory bytesArray) {
        for (uint i = 0; i < 256; ++i) {
            // Mask for i-th bit
            uint mask = uint(1 << i);

            // emit log_named_uint("mask: ", mask);

            // If the i-th bit is flipped, add a byte to the return array
            if (bitmap & mask != 0) {
                bytesArray = bytes.concat(bytesArray, bytes1(uint8(1 << i)));
            }
        }
        return bytesArray;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {UpgradeableProxyLib} from "../unit/UpgradeableProxyLib.sol";
import {BN254} from "../../src/libraries/BN254.sol";
import {Pausable} from "eigenlayer-contracts/src/contracts/permissions/Pausable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {OperatorLib} from "../utils/OperatorLib.sol";
import {BitmapUtils} from "../../src/libraries/BitmapUtils.sol";

import {IRegistryCoordinator} from "../../src/interfaces/IRegistryCoordinator.sol";
import {IServiceManager} from "../../src/interfaces/IServiceManager.sol";
import {IStakeRegistry} from "../../src/interfaces/IStakeRegistry.sol";
import {IBLSApkRegistry, IBLSApkRegistryTypes} from "../../src/interfaces/IBLSApkRegistry.sol";
import {IIndexRegistry} from "../../src/interfaces/IIndexRegistry.sol";
import {ISlashingRegistryCoordinator} from "../../src/interfaces/ISlashingRegistryCoordinator.sol";
import {ISocketRegistry} from "../../src/interfaces/ISocketRegistry.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from
    "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {
    IAllocationManager,
    OperatorSet,
    IAllocationManagerTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";

// Import concrete implementation for deployment
import {RegistryCoordinator, IRegistryCoordinatorTypes} from "../../src/RegistryCoordinator.sol";
import {ISlashingRegistryCoordinatorTypes} from
    "../../src/interfaces/ISlashingRegistryCoordinator.sol";
import {ServiceManagerBase} from "../../src/ServiceManagerBase.sol";
import {BLSApkRegistry} from "../../src/BLSApkRegistry.sol";
import {IndexRegistry} from "../../src/IndexRegistry.sol";
import {StakeRegistry, IStakeRegistryTypes} from "../../src/StakeRegistry.sol";
import {SocketRegistry} from "../../src/SocketRegistry.sol";

// Import ERC20Mock contract
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {IStrategyFactory} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyFactory.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";

// Extended interface to get addresses of other contracts
interface IServiceManagerExtended {
    function avsDirectory() external view returns (IAVSDirectory);
}

interface StakeRegistryExtended {
    function delegation() external view returns (IDelegationManager);
}

interface IDelegationManagerExtended {
    function allocationManager() external view returns (IAllocationManager);
    function strategyManager() external view returns (IStrategyManager);
}

interface IAllocationManagerExtended {
    function permissionController() external view returns (IPermissionController);
}

contract EigenDA_SM_Gap {
    uint256[50] private __EigenDASM_GAP;
}

contract BLSSignatureChecker_Pausable_GAP {
    uint256[100] private __GAP;
}

// EigenDAServiceManagerStorage, ServiceManagerBase, BLSSignatureChecker, Pausable
contract TestServiceManager is
    EigenDA_SM_Gap,
    ServiceManagerBase,
    BLSSignatureChecker_Pausable_GAP
{
    constructor(
        IAVSDirectory __avsDirectory,
        IRewardsCoordinator __rewardsCoordinator,
        ISlashingRegistryCoordinator __registryCoordinator,
        IStakeRegistry __stakeRegistry,
        IPermissionController __permissionController,
        IAllocationManager __allocationManager
    )
        ServiceManagerBase(
            __avsDirectory,
            __rewardsCoordinator,
            __registryCoordinator,
            __stakeRegistry,
            __permissionController,
            __allocationManager
        )
    {}
}

contract EigenDATest is Test {
    using stdJson for string;
    using OperatorLib for *;

    struct EigenDADeploymentData {
        address blsApkRegistry;
        address eigenDAProxyAdmin;
        address eigenDAServiceManager;
        address indexRegistry;
        address mockDispatcher;
        address operatorStateRetriever;
        address registryCoordinator;
        address serviceManagerRouter;
        address stakeRegistry;
    }

    struct EigenDAChainInfo {
        uint256 chainId;
        uint256 deploymentBlock;
    }

    struct EigenDAPermissionsData {
        address eigenDABatchConfirmer;
        address eigenDAChurner;
        address eigenDAEjector;
        address eigenDAOwner;
        address eigenDAUpgrader;
        address pauserRegistry;
    }

    struct EigenDAData {
        EigenDADeploymentData addresses;
        EigenDAChainInfo chainInfo;
        EigenDAPermissionsData permissions;
    }

    struct RegistryCoordinatorState {
        uint32 operatorSetUpdateNonce;
        uint8 numQuorums;
    }

    struct ServiceManagerState {
        uint256 paused;
        address owner;
    }

    struct BlsApkRegistryState {
        bytes32[] currentApkHashes;
    }

    struct IndexRegistryState {
        uint32[] operatorCounts;
    }

    struct StakeRegistryState {
        uint32[] numStrategies;
    }

    struct M2QuorumOperators {
        uint8[] quorumNumbers;
        address[][] operatorIds;
        string placeholder; // Add a dummy field to avoid getter compiler error
    }

    struct ContractStates {
        RegistryCoordinatorState registryCoordinator;
        ServiceManagerState serviceManager;
        BlsApkRegistryState blsApkRegistry;
        IndexRegistryState indexRegistry;
        StakeRegistryState stakeRegistry;
    }

    // Variables to hold our data
    EigenDAData public eigenDAData;
    ContractStates public preUpgradeStates;
    M2QuorumOperators public m2QuorumOperators;

    // Core contract addresses from StakeRegistry
    address public delegationManagerAddr;
    address public avsDirectoryAddr;
    address public allocationManagerAddr;
    address public permissionControllerAddr;
    address public rewardsCoordinatorAddr;

    address public registryCoordinatorOwner;
    address public serviceManagerOwner;

    uint256 constant OPERATOR_COUNT = 5;
    OperatorLib.Operator[OPERATOR_COUNT] public operators;

    address public newRegistryCoordinatorImpl;
    address public newServiceManagerImpl;
    address public newBlsApkRegistryImpl;
    address public newIndexRegistryImpl;
    address public newStakeRegistryImpl;
    address public socketRegistry;

    ISlashingRegistryCoordinator public registryCoordinator;
    IBLSApkRegistry public apkRegistry;
    IIndexRegistry public indexRegistry;
    IStakeRegistry public stakeRegistry;
    IServiceManager public serviceManager;
    IAllocationManager public allocationManager;
    IAVSDirectory public avsDirectory;
    IDelegationManagerExtended public delegationManager;
    IPermissionController public permissionController;

    address public token;
    IStrategy public strategy;
    IStrategyFactory public strategyFactory;
    IStrategyManager public strategyManager;

    function setUp() public virtual {
        // Setup the Holesky fork and load EigenDA deployment data
        eigenDAData = _setupEigenDAFork("test/utils");

        delegationManagerAddr =
            address(StakeRegistryExtended(eigenDAData.addresses.stakeRegistry).delegation());
        avsDirectoryAddr = address(
            IServiceManagerExtended(eigenDAData.addresses.eigenDAServiceManager).avsDirectory()
        );
        allocationManagerAddr =
            address(IDelegationManagerExtended(delegationManagerAddr).allocationManager());
        permissionControllerAddr =
            address(IAllocationManagerExtended(allocationManagerAddr).permissionController());
        /// TODO:
        rewardsCoordinatorAddr = address(0);

        registryCoordinator =
            ISlashingRegistryCoordinator(eigenDAData.addresses.registryCoordinator);
        apkRegistry = IBLSApkRegistry(eigenDAData.addresses.blsApkRegistry);
        indexRegistry = IIndexRegistry(eigenDAData.addresses.indexRegistry);
        stakeRegistry = IStakeRegistry(eigenDAData.addresses.stakeRegistry);
        serviceManager = IServiceManager(eigenDAData.addresses.eigenDAServiceManager);
        allocationManager = IAllocationManager(allocationManagerAddr);
        avsDirectory = IAVSDirectory(avsDirectoryAddr);
        delegationManager = IDelegationManagerExtended(delegationManagerAddr);
        permissionController = IPermissionController(permissionControllerAddr);
        // Initialize strategy manager and factory
        strategyManager = delegationManager.strategyManager();
        strategyFactory = IStrategyFactory(strategyManager.strategyWhitelister());
        serviceManagerOwner =
            OwnableUpgradeable(eigenDAData.addresses.eigenDAServiceManager).owner();
        registryCoordinatorOwner =
            OwnableUpgradeable(eigenDAData.addresses.registryCoordinator).owner();

        _verifyInitialSetup();

        _captureAndStorePreUpgradeState();

        _deployNewImplementations();

        _createOperators();

        uint256 operatorTokenAmount = 10 ether;
        (token, strategy) = _setupTokensForOperators(operatorTokenAmount);
        _setUpTokensForExistingQuorums(1000 ether);

        console.log("Registering operators in EigenLayer...");
        _registerOperatorsAsEigenLayerOperators();
    }

    function test_Upgrade() public {
        _upgradeContracts();
    }

    function test_ValidatePostUpgradeState() public {
        _upgradeContracts();
        console.log("Validating post-upgrade contract states");
        require(
            serviceManagerOwner == OwnableUpgradeable(address(serviceManager)).owner(),
            "Service Manager owner mismatch post-upgrade"
        );

        // Verify quorum count is maintained
        uint8 quorumCount = registryCoordinator.quorumCount();
        console.log("quorum count:", quorumCount);
        require(
            quorumCount == preUpgradeStates.registryCoordinator.numQuorums,
            "Quorum count changed after upgrade"
        );

        // Verify each quorum's data is maintained across all registries
        for (uint8 i = 0; i < quorumCount; i++) {
            // 1. Verify BLSApkRegistry state
            bytes32 currentApkHash = BN254.hashG1Point(apkRegistry.getApk(i));
            require(
                currentApkHash == preUpgradeStates.blsApkRegistry.currentApkHashes[i],
                "BLSApkRegistry: APK hash changed after upgrade"
            );

            // 2. Verify IndexRegistry state
            uint32 operatorCount = indexRegistry.totalOperatorsForQuorum(i);
            require(
                operatorCount == preUpgradeStates.indexRegistry.operatorCounts[i],
                "IndexRegistry: Operator count changed after upgrade"
            );

            // 3. Verify StakeRegistry state - only if quorum exists in StakeRegistry
            if (stakeRegistry.getTotalStakeHistoryLength(i) > 0) {
                uint256 strategyCount = stakeRegistry.strategyParamsLength(i);
                require(
                    uint32(strategyCount) == preUpgradeStates.stakeRegistry.numStrategies[i],
                    "StakeRegistry: Strategy count changed after upgrade"
                );
            }
        }

        console.log("Post-upgrade validation successful");
    }

    function test_PostUpgrade_CreateOperatorSet() public {
        _upgradeContracts();

        _configureUAMAppointees();

        _createTotalDelegatedStakeOpSet();

        // Register operators for the new quorum
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 3; // Quorum 3 (totalDelegatedStake)

        console.log("Registering operators for quorum 1...");
        for (uint256 i = 0; i < OPERATOR_COUNT; i++) {
            vm.startPrank(operators[i].key.addr);
            OperatorLib.registerOperatorFromAVS_OpSet(
                operators[i],
                allocationManagerAddr,
                address(registryCoordinator),
                address(serviceManager),
                operatorSetIds
            );
            vm.stopPrank();
        }

        // Verify that operator sets are enabled in the Registry Coordinator
        console.log("Verifying operator sets are enabled...");
        bool operatorSetsEnabled =
            IRegistryCoordinator(address(registryCoordinator)).operatorSetsEnabled();
        assertTrue(
            operatorSetsEnabled,
            "Operator sets should be enabled after creating a slashable stake quorum"
        );

        // Verify operators are registered
        uint32 operatorCount = indexRegistry.totalOperatorsForQuorum(3);
        assertEq(operatorCount, OPERATOR_COUNT, "All operators should be registered");

        console.log("Successfully created new operator set quorum with %d operators", operatorCount);
    }

    function test_PostUpgrade_DeregisterM2Operators() public {
        // Upgrade the contracts first
        _upgradeContracts();
        _configureUAMAppointees();

        _createTotalDelegatedStakeOpSet();

        uint256 totalDeregisteredOperators = 0;

        console.log("Deregistering M2 quorum operators...");

        // Iterate through quorums and deregister each operator
        for (uint8 i = 0; i < m2QuorumOperators.quorumNumbers.length; i++) {
            uint8 quorumNumber = m2QuorumOperators.quorumNumbers[i];
            address[] memory operatorAddresses = m2QuorumOperators.operatorIds[i];

            console.log(
                "Deregistering %d operators from quorum %d", operatorAddresses.length, quorumNumber
            );

            // Prepare quorum number array for deregistration
            uint8[] memory quorumNumbersArray = new uint8[](1);
            quorumNumbersArray[0] = quorumNumber;

            // Deregister each operator from the quorum
            for (uint256 j = 0; j < operatorAddresses.length; j++) {
                address operatorAddr = operatorAddresses[j];

                OperatorLib.Wallet memory wallet;
                wallet.addr = operatorAddr;

                OperatorLib.Operator memory operator;
                operator.key = wallet;

                vm.startPrank(operatorAddr);

                OperatorLib.deregisterOperatorFromAVS_M2(
                    operator, address(registryCoordinator), quorumNumbersArray
                );

                vm.stopPrank();
                totalDeregisteredOperators++;
            }
        }

        console.log(
            "Successfully deregistered %d operators from M2 quorums", totalDeregisteredOperators
        );

        // Verify operators are deregistered by checking the updated operator counts
        for (uint8 i = 0; i < m2QuorumOperators.quorumNumbers.length; i++) {
            uint8 quorumNumber = m2QuorumOperators.quorumNumbers[i];
            if (m2QuorumOperators.operatorIds[i].length > 0) {
                uint32 operatorCountAfter = indexRegistry.totalOperatorsForQuorum(quorumNumber);
                assertEq(operatorCountAfter, 0, "Operators should be deregistered from quorum");
                console.log("Verified quorum %d now has 0 operators", quorumNumber);
            }
        }
    }

    function test_PostUpgrade_RegisterToM2Quorums() public {
        _upgradeContracts();
        _configureUAMAppointees();
        _createTotalDelegatedStakeOpSet();

        // Use existing operators that were created in setUp
        console.log("Using %d existing operators", OPERATOR_COUNT);

        console.log("Registering operators to M2 quorums...");

        uint256 quorumCount = 1;
        uint8[] memory quorumsToRegister = new uint8[](quorumCount);
        for (uint8 i = 0; i < quorumCount; i++) {
            quorumsToRegister[i] = 0;
        }

        // Register each operator to the existing M2 quorums
        for (uint256 i = 0; i < OPERATOR_COUNT; i++) {
            vm.startPrank(operators[i].key.addr);

            OperatorLib.registerOperatorToAVS_M2(
                operators[i],
                address(avsDirectory),
                address(serviceManager),
                address(registryCoordinator),
                quorumsToRegister
            );

            vm.stopPrank();
            console.log("Registered operator %d to M2 quorums", i + 1);
        }

        console.log("Successfully registered %d operators to M2 quorums", OPERATOR_COUNT);
    }

    function test_PostUpgrade_DisableM2() public {
        _upgradeContracts();

        _configureUAMAppointees();

        // Create a slashable stake quorum with lookAheadPeriod
        _createSlashableStakeOpSet(10);

        // Verify that operator sets are enabled in the Registry Coordinator
        console.log("Verifying operator sets are enabled...");
        bool operatorSetsEnabled =
            IRegistryCoordinator(address(registryCoordinator)).operatorSetsEnabled();
        assertTrue(
            operatorSetsEnabled,
            "Operator sets should be enabled after creating a slashable stake quorum"
        );

        // Disable M2 quorum registration in the Registry Coordinator
        console.log("Disabling M2 quorum registration...");
        vm.startPrank(registryCoordinatorOwner);
        IRegistryCoordinator(address(registryCoordinator)).disableM2QuorumRegistration();
        vm.stopPrank();

        // Verify M2 quorum registration is disabled
        bool isM2QuorumRegistrationDisabled =
            IRegistryCoordinator(address(registryCoordinator)).isM2QuorumRegistrationDisabled();
        assertTrue(isM2QuorumRegistrationDisabled, "M2 quorum registration should be disabled");

        console.log("Successfully disabled M2 quorum registration.");
    }

    function test_PostUpgrade_DisableM2_Registration() public {
        _upgradeContracts();
        _configureUAMAppointees();
        _createTotalDelegatedStakeOpSet();

        console.log("Disabling M2 quorum registration...");
        vm.startPrank(registryCoordinatorOwner);
        IRegistryCoordinator(address(registryCoordinator)).disableM2QuorumRegistration();
        vm.stopPrank();

        bool isM2QuorumRegistrationDisabled =
            IRegistryCoordinator(address(registryCoordinator)).isM2QuorumRegistrationDisabled();
        assertTrue(isM2QuorumRegistrationDisabled, "M2 quorum registration should be disabled");

        uint8[] memory quorumsToRegister = new uint8[](1);
        quorumsToRegister[0] = 0; // Quorum 0 is an M2 quorum

        console.log("Attempting to register to M2 quorums after disabling M2 registration...");
        vm.startPrank(operators[0].key.addr);

        bytes32 salt = keccak256(abi.encodePacked(block.timestamp, operators[0].key.addr));
        uint256 expiry = block.timestamp + 1 hours;

        bytes32 operatorRegistrationDigestHash = avsDirectory
            .calculateOperatorAVSRegistrationDigestHash(
            operators[0].key.addr, address(serviceManager), salt, expiry
        );

        bytes memory signature =
            OperatorLib.signWithOperatorKey(operators[0], operatorRegistrationDigestHash);

        bytes32 pubkeyRegistrationMessageHash =
            registryCoordinator.calculatePubkeyRegistrationMessageHash(operators[0].key.addr);

        BN254.G1Point memory blsSig =
            OperatorLib.signMessage(operators[0].signingKey, pubkeyRegistrationMessageHash);

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory params = IBLSApkRegistryTypes
            .PubkeyRegistrationParams({
            pubkeyG1: operators[0].signingKey.publicKeyG1,
            pubkeyG2: operators[0].signingKey.publicKeyG2,
            pubkeyRegistrationSignature: blsSig
        });

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature =
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry({
            signature: signature,
            salt: salt,
            expiry: expiry
        });

        uint256 quorumBitmap = 0;
        for (uint256 i = 0; i < quorumsToRegister.length; i++) {
            quorumBitmap = BitmapUtils.setBit(quorumBitmap, quorumsToRegister[i]);
        }
        bytes memory quorumNumbersBytes = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        vm.expectRevert(bytes4(keccak256("M2QuorumRegistrationIsDisabled()")));
        IRegistryCoordinator(address(registryCoordinator)).registerOperator(
            quorumNumbersBytes, "socket", params, operatorSignature
        );

        vm.stopPrank();
        console.log("Successfully verified M2 registration is disabled");
    }

    function test_PostUpgrade_DisableM2_Deregistration() public {
        _upgradeContracts();
        _configureUAMAppointees();

        // Register operators to M2 quorums before disabling M2 registration
        console.log("Registering operators to M2 quorums before disabling registration...");
        uint8[] memory quorumsToRegister = new uint8[](1);
        quorumsToRegister[0] = 0; // Quorum 0 is an M2 quorum

        // Now disable M2 quorum registration
        console.log("Disabling M2 quorum registration...");
        vm.startPrank(registryCoordinatorOwner);
        IRegistryCoordinator(address(registryCoordinator)).disableM2QuorumRegistration();
        vm.stopPrank();

        // Verify M2 quorum registration is disabled
        bool isM2QuorumRegistrationDisabled =
            IRegistryCoordinator(address(registryCoordinator)).isM2QuorumRegistrationDisabled();
        assertTrue(isM2QuorumRegistrationDisabled, "M2 quorum registration should be disabled");

        // Attempt to deregister operator from M2 quorums - this should succeed
        console.log("Attempting to deregister from M2 quorums after disabling M2 registration...");
        address operatorAddr = m2QuorumOperators.operatorIds[0][0];

        OperatorLib.Wallet memory wallet;
        wallet.addr = operatorAddr;

        OperatorLib.Operator memory operator;
        operator.key = wallet;

        vm.startPrank(operatorAddr);
        OperatorLib.deregisterOperatorFromAVS_M2(
            operators[0], address(registryCoordinator), quorumsToRegister
        );
        vm.stopPrank();

        console.log(
            "Successfully verified deregistration from M2 quorums is still possible after disabling registration"
        );
    }

    function test_TotalDelegatedStakeQuorumRegistration() public {
        _upgradeContracts();
        _configureUAMAppointees();
        _createTotalDelegatedStakeOpSet();
        vm.startPrank(registryCoordinatorOwner);
        IRegistryCoordinator(address(registryCoordinator)).disableM2QuorumRegistration();
        vm.stopPrank();

        uint8 quorumCount = registryCoordinator.quorumCount();
        uint8 totalDelegatedStakeQuorumId = quorumCount - 1;

        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = totalDelegatedStakeQuorumId;

        for (uint256 i = 0; i < OPERATOR_COUNT; i++) {
            vm.startPrank(operators[i].key.addr);

            console.log("Registering operator %d: %s", i, operators[i].key.addr);

            OperatorLib.registerOperatorFromAVS_OpSet(
                operators[i],
                allocationManagerAddr,
                address(registryCoordinator),
                address(serviceManager),
                operatorSetIds
            );

            vm.stopPrank();
        }

        uint32 registeredOperatorCount =
            indexRegistry.totalOperatorsForQuorum(totalDelegatedStakeQuorumId);
        assertEq(
            registeredOperatorCount,
            OPERATOR_COUNT,
            "All operators should be registered to operatorset"
        );

        for (uint256 i = 0; i < OPERATOR_COUNT; i++) {
            // Check operator registration status in RegistryCoordinator
            ISlashingRegistryCoordinatorTypes.OperatorStatus status =
                registryCoordinator.getOperatorStatus(operators[i].key.addr);

            assertTrue(
                status == ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED,
                "Operator should be registered"
            );
        }
    }

    function _createTotalDelegatedStakeOpSet() internal {
        console.log("Creating a new slashable stake quorum (quorum 1)...");

        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParam =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 100,
            kickBIPsOfOperatorStake: 10500, // 105%
            kickBIPsOfTotalStake: 100 // 1%
        });

        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] =
            IStakeRegistryTypes.StrategyParams({strategy: strategy, multiplier: 1 * 1e18});

        uint96 minimumStake = uint96(1 ether);

        vm.startPrank(serviceManagerOwner);
        registryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParam, minimumStake, strategyParams
        );
        vm.stopPrank();
    }

    function _createSlashableStakeOpSet(
        uint32 lookAheadPeriod
    ) internal {
        console.log("Creating a new slashable stake quorum with look ahead period...");

        // Define parameters for the new quorum
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParam =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 100,
            kickBIPsOfOperatorStake: 10500, // 105%
            kickBIPsOfTotalStake: 100 // 1%
        });

        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] =
            IStakeRegistryTypes.StrategyParams({strategy: strategy, multiplier: 1 * 1e18});

        uint96 minimumStake = uint96(1 ether);

        vm.startPrank(serviceManagerOwner);
        registryCoordinator.createSlashableStakeQuorum(
            operatorSetParam, minimumStake, strategyParams, lookAheadPeriod
        );
        vm.stopPrank();
    }

    function _captureAndStorePreUpgradeState() internal {
        preUpgradeStates.registryCoordinator.numQuorums = registryCoordinator.quorumCount();

        Pausable serviceManagerPausable = Pausable(address(serviceManager));
        preUpgradeStates.serviceManager.paused = serviceManagerPausable.paused();

        uint8 quorumCount = registryCoordinator.quorumCount();
        preUpgradeStates.blsApkRegistry.currentApkHashes = new bytes32[](quorumCount);
        preUpgradeStates.indexRegistry.operatorCounts = new uint32[](quorumCount);
        preUpgradeStates.stakeRegistry.numStrategies = new uint32[](quorumCount);

        // For each quorum, gather data from all registries
        for (uint8 quorumIndex = 0; quorumIndex < quorumCount; quorumIndex++) {
            // Get operator count for each quorum from IndexRegistry
            uint32 operatorCount = indexRegistry.totalOperatorsForQuorum(quorumIndex);
            preUpgradeStates.indexRegistry.operatorCounts[quorumIndex] = operatorCount;

            // Get APK hash for each quorum from BLSApkRegistry
            // Store the hash of the APK as bytes32
            preUpgradeStates.blsApkRegistry.currentApkHashes[quorumIndex] =
                BN254.hashG1Point(apkRegistry.getApk(quorumIndex));

            // Get strategy count for each quorum from StakeRegistry
            uint256 strategyCount = 0;
            // Check if quorum exists in StakeRegistry before querying
            if (stakeRegistry.getTotalStakeHistoryLength(quorumIndex) > 0) {
                strategyCount = stakeRegistry.strategyParamsLength(quorumIndex);
            }
            preUpgradeStates.stakeRegistry.numStrategies[quorumIndex] = uint32(strategyCount);
        }

        // Record operators for M2 quorums
        _recordM2QuorumOperators();
    }

    function _recordM2QuorumOperators() internal {
        // Use the getM2QuorumOperators function to get M2 quorum operators
        (uint8[] memory quorumNumbers, address[][] memory operatorLists) = _getM2QuorumOperators();

        // Set the values in the m2QuorumOperators struct
        m2QuorumOperators.quorumNumbers = quorumNumbers;
        m2QuorumOperators.operatorIds = operatorLists;

        for (uint8 i = 0; i < quorumNumbers.length; i++) {
            console.log(
                "Recorded %d operators for quorum %d", operatorLists[i].length, quorumNumbers[i]
            );
        }
    }

    function _getM2QuorumOperators()
        public
        view
        returns (uint8[] memory m2QuorumNumbers, address[][] memory m2QuorumOperatorLists)
    {
        uint256 quorumCount = registryCoordinator.quorumCount();
        m2QuorumNumbers = new uint8[](quorumCount);
        m2QuorumOperatorLists = new address[][](quorumCount);

        for (uint8 i = 0; i < quorumCount; i++) {
            uint32 operatorCount = indexRegistry.totalOperatorsForQuorum(i);

            if (operatorCount > 0) {
                // Get the current list of operators for this quorum using external call
                bytes32[] memory operatorIds =
                    indexRegistry.getOperatorListAtBlockNumber(i, uint32(block.number));

                // Convert bytes32 operatorIds to addresses
                address[] memory operatorAddresses = new address[](operatorIds.length);
                for (uint256 j = 0; j < operatorIds.length; j++) {
                    // Use the BLSApkRegistry to get the operator address from the ID
                    operatorAddresses[j] = apkRegistry.getOperatorFromPubkeyHash(operatorIds[j]);
                }

                m2QuorumOperatorLists[i] = operatorAddresses;
                m2QuorumNumbers[i] = i;
            }
        }

        return (m2QuorumNumbers, m2QuorumOperatorLists);
    }

    function _configureUAMAppointees() internal {
        console.log("Configuring permissions for operator set creation...");

        console.log("Setting AVS address in Registry Coordinator...");
        vm.startPrank(registryCoordinatorOwner);
        registryCoordinator.setAVS(address(serviceManager));
        vm.stopPrank();

        console.log("Appointee set for createOperatorSets");
        vm.startPrank(serviceManagerOwner);
        serviceManager.setAppointee(
            address(registryCoordinator),
            allocationManagerAddr,
            IAllocationManager.createOperatorSets.selector
        );
        serviceManager.setAppointee(
            serviceManagerOwner,
            allocationManagerAddr,
            IAllocationManager.updateAVSMetadataURI.selector
        );

        serviceManager.setAppointee(
            serviceManagerOwner, allocationManagerAddr, IAllocationManager.setAVSRegistrar.selector
        );

        console.log("Appointees set for required permissions");

        string memory metadataURI = "https://eigenda.xyz/metadata";
        console.log("Updating AVS metadata URI to:", metadataURI);
        allocationManager.updateAVSMetadataURI(address(serviceManager), metadataURI);

        allocationManager.setAVSRegistrar(
            address(serviceManager), IAVSRegistrar(address(registryCoordinator))
        );
        vm.stopPrank();
        console.log("AVS Registrar set");
    }

    function _deployNewImplementations() internal {
        socketRegistry = address(
            new SocketRegistry(
                ISlashingRegistryCoordinator(eigenDAData.addresses.registryCoordinator)
            )
        );

        IRegistryCoordinatorTypes.SlashingRegistryParams memory slashingParams =
        IRegistryCoordinatorTypes.SlashingRegistryParams({
            stakeRegistry: stakeRegistry,
            blsApkRegistry: apkRegistry,
            indexRegistry: indexRegistry,
            socketRegistry: ISocketRegistry(socketRegistry),
            allocationManager: allocationManager,
            pauserRegistry: IPauserRegistry(eigenDAData.permissions.pauserRegistry)
        });

        IRegistryCoordinatorTypes.RegistryCoordinatorParams memory params =
        IRegistryCoordinatorTypes.RegistryCoordinatorParams({
            serviceManager: serviceManager,
            slashingParams: slashingParams
        });

        newRegistryCoordinatorImpl = address(new RegistryCoordinator(params));

        IRewardsCoordinator rewardsCoordinator = IRewardsCoordinator(rewardsCoordinatorAddr);

        // Assert all addresses are not zero before deployment
        assertTrue(permissionControllerAddr != address(0), "PermissionController address not found");
        assertTrue(address(avsDirectory) != address(0), "AVSDirectory address is zero");
        // assertTrue(address(rewardsCoordinator) != address(0), "RewardsCoordinator address is zero"); //TODO:
        assertTrue(
            address(registryCoordinator) != address(0), "RegistryCoordinator address is zero"
        );
        assertTrue(address(stakeRegistry) != address(0), "StakeRegistry address is zero");
        assertTrue(
            address(permissionController) != address(0), "PermissionController address is zero"
        );
        assertTrue(address(allocationManager) != address(0), "AllocationManager address is zero");
        assertTrue(delegationManagerAddr != address(0), "DelegationManager address is zero");
        assertTrue(address(avsDirectory) != address(0), "AVSDirectory address is zero");
        assertTrue(address(allocationManager) != address(0), "AllocationManager address is zero");

        newServiceManagerImpl = address(
            new TestServiceManager(
                avsDirectory,
                rewardsCoordinator,
                registryCoordinator,
                stakeRegistry,
                permissionController,
                allocationManager
            )
        );
        newBlsApkRegistryImpl = address(new BLSApkRegistry(registryCoordinator));
        newIndexRegistryImpl = address(new IndexRegistry(registryCoordinator));

        newStakeRegistryImpl = address(
            new StakeRegistry(
                registryCoordinator,
                IDelegationManager(address(delegationManager)),
                avsDirectory,
                allocationManager
            )
        );
    }

    function _setupEigenDAFork(
        string memory jsonPath
    ) internal returns (EigenDAData memory) {
        string memory rpcUrl = vm.envString("HOLESKY_RPC_URL");

        vm.createSelectFork(rpcUrl);

        EigenDAData memory data = _readEigenDADeploymentJson(jsonPath, 17000);

        /// Recent block post ALM upgrade
        vm.rollFork(3592349);

        return data;
    }

    function _upgradeContracts() internal {
        vm.startPrank(eigenDAData.permissions.eigenDAUpgrader);

        UpgradeableProxyLib.upgrade(
            eigenDAData.addresses.registryCoordinator, newRegistryCoordinatorImpl
        );
        UpgradeableProxyLib.upgrade(
            eigenDAData.addresses.eigenDAServiceManager, newServiceManagerImpl
        );
        UpgradeableProxyLib.upgrade(eigenDAData.addresses.blsApkRegistry, newBlsApkRegistryImpl);
        UpgradeableProxyLib.upgrade(eigenDAData.addresses.indexRegistry, newIndexRegistryImpl);
        UpgradeableProxyLib.upgrade(eigenDAData.addresses.stakeRegistry, newStakeRegistryImpl);

        vm.stopPrank();
    }

    function _readEigenDADeploymentJson(
        string memory path,
        uint256 chainId
    ) internal returns (EigenDAData memory) {
        string memory filePath = string(abi.encodePacked(path, "/EigenDA_Holesky.json"));
        return _loadEigenDAJson(filePath);
    }

    function _loadEigenDAJson(
        string memory filePath
    ) internal returns (EigenDAData memory) {
        string memory json = vm.readFile(filePath);
        require(vm.exists(filePath), "EigenDA deployment file does not exist");

        EigenDAData memory data;

        // Parse addresses section
        data.addresses.blsApkRegistry = json.readAddress(".addresses.blsApkRegistry");
        data.addresses.eigenDAProxyAdmin = json.readAddress(".addresses.eigenDAProxyAdmin");
        data.addresses.eigenDAServiceManager = json.readAddress(".addresses.eigenDAServiceManager");
        data.addresses.indexRegistry = json.readAddress(".addresses.indexRegistry");
        data.addresses.mockDispatcher = json.readAddress(".addresses.mockRollup");
        data.addresses.operatorStateRetriever =
            json.readAddress(".addresses.operatorStateRetriever");
        data.addresses.registryCoordinator = json.readAddress(".addresses.registryCoordinator");
        data.addresses.serviceManagerRouter = json.readAddress(".addresses.serviceManagerRouter");
        data.addresses.stakeRegistry = json.readAddress(".addresses.stakeRegistry");

        // Parse chainInfo section
        data.chainInfo.chainId = json.readUint(".chainInfo.chainId");
        data.chainInfo.deploymentBlock = json.readUint(".chainInfo.deploymentBlock");

        // Parse permissions section
        data.permissions.eigenDABatchConfirmer =
            json.readAddress(".permissions.eigenDABatchConfirmer");
        data.permissions.eigenDAChurner = json.readAddress(".permissions.eigenDAChurner");
        data.permissions.eigenDAEjector = json.readAddress(".permissions.eigenDAEjector");
        data.permissions.eigenDAOwner = json.readAddress(".permissions.eigenDAOwner");
        data.permissions.eigenDAUpgrader = json.readAddress(".permissions.eigenDAUpgrader");
        data.permissions.pauserRegistry = json.readAddress(".permissions.pauserRegistry");

        // Label all addresses for better debugging and tracing
        vm.label(data.addresses.blsApkRegistry, "BLSApkRegistry");
        vm.label(data.addresses.eigenDAProxyAdmin, "EigenDAProxyAdmin");
        vm.label(data.addresses.eigenDAServiceManager, "EigenDAServiceManager");
        vm.label(data.addresses.indexRegistry, "IndexRegistry");
        vm.label(data.addresses.mockDispatcher, "MockDispatcher");
        vm.label(data.addresses.operatorStateRetriever, "OperatorStateRetriever");
        vm.label(data.addresses.registryCoordinator, "RegistryCoordinator");
        vm.label(data.addresses.serviceManagerRouter, "ServiceManagerRouter");
        vm.label(data.addresses.stakeRegistry, "StakeRegistry");

        // Label permissioned addresses
        vm.label(data.permissions.eigenDABatchConfirmer, "EigenDABatchConfirmer");
        vm.label(data.permissions.eigenDAChurner, "EigenDAChurner");
        vm.label(data.permissions.eigenDAEjector, "EigenDAEjector");
        vm.label(data.permissions.eigenDAOwner, "EigenDAOwner");
        vm.label(data.permissions.eigenDAUpgrader, "EigenDAUpgrader");
        vm.label(data.permissions.pauserRegistry, "PauserRegistry");

        return data;
    }

    function _verifyInitialSetup() internal view {
        // Verify that contracts are deployed and at least not null
        require(
            eigenDAData.addresses.registryCoordinator != address(0),
            "Registry Coordinator should be deployed"
        );
        require(
            eigenDAData.addresses.eigenDAServiceManager != address(0),
            "Service Manager should be deployed"
        );
        require(
            eigenDAData.addresses.blsApkRegistry != address(0),
            "BLS APK Registry should be deployed"
        );
        require(
            eigenDAData.addresses.indexRegistry != address(0), "Index Registry should be deployed"
        );
        require(
            eigenDAData.addresses.stakeRegistry != address(0), "Stake Registry should be deployed"
        );

        require(
            eigenDAData.permissions.eigenDAUpgrader != address(0),
            "EigenDA Upgrader should be defined"
        );
        require(
            eigenDAData.permissions.pauserRegistry != address(0),
            "Pauser Registry should be defined"
        );
    }

    function _createTokenAndStrategy() internal returns (address token, IStrategy strategy) {
        ERC20Mock tokenContract = new ERC20Mock();
        token = address(tokenContract);
        strategy = IStrategyFactory(strategyFactory).deployNewStrategy(IERC20(token));
    }

    function _setUpTokensForExistingQuorums(
        uint256 amount
    ) internal {
        uint8 quorumNumber = 0;
        uint8 strategyIndex = 2;
        /// Strategy with a token we can deal with foundry
        IStakeRegistry.StrategyParams memory stratParams =
            stakeRegistry.strategyParamsByIndex(quorumNumber, strategyIndex);

        address strategyAddress = address(stratParams.strategy);

        console.log("Using strategy %s for quorum %d", strategyAddress, quorumNumber);

        // For each operator, deposit tokens into each strategy
        for (uint256 opIndex = 0; opIndex < OPERATOR_COUNT; opIndex++) {
            // Get the underlying token for this strategy
            IERC20 underlyingTokenIERC20 = IStrategy(strategyAddress).underlyingToken();
            address tokenAddress = address(underlyingTokenIERC20);

            deal(tokenAddress, operators[opIndex].key.addr, amount, true);

            vm.startPrank(operators[opIndex].key.addr);
            // Deposit tokens into the strategy
            OperatorLib.depositTokenIntoStrategy(
                operators[opIndex], address(strategyManager), strategyAddress, tokenAddress, amount
            );

            console.log(
                "Deposited %d tokens into strategy %s for operator %s",
                amount,
                strategyAddress,
                operators[opIndex].key.addr
            );

            vm.stopPrank();
        }
    }

    function _setupTokensForOperators(
        uint256 amount
    ) internal returns (address token, IStrategy strategy) {
        (token, strategy) = _createTokenAndStrategy();

        for (uint256 i = 0; i < OPERATOR_COUNT; i++) {
            OperatorLib.mintMockTokens(operators[i], token, amount);
            vm.startPrank(operators[i].key.addr);
            OperatorLib.depositTokenIntoStrategy(
                operators[i], address(strategyManager), address(strategy), token, amount
            );
            vm.stopPrank();
        }
    }

    function _createOperators() internal {
        for (uint256 i = 0; i < OPERATOR_COUNT; i++) {
            operators[i] = OperatorLib.createOperator(string(abi.encodePacked("operator-", i + 1)));
        }
    }

    function _createOperators(
        uint256 numOperators
    ) internal returns (OperatorLib.Operator[] memory) {
        OperatorLib.Operator[] memory ops = new OperatorLib.Operator[](numOperators);
        for (uint256 i = 0; i < numOperators; i++) {
            ops[i] = OperatorLib.createOperator(string(abi.encodePacked("operator-", i + 1)));
        }
        return ops;
    }

    /**
     * @dev Registers operators as EigenLayer operators
     */
    function _registerOperatorsAsEigenLayerOperators() internal {
        for (uint256 i = 0; i < OPERATOR_COUNT; i++) {
            vm.startPrank(operators[i].key.addr);
            OperatorLib.registerAsOperator(operators[i], delegationManagerAddr);
            vm.stopPrank();
        }
    }

    /**
     * @dev Registers operators as EigenLayer operators
     * @param operatorsToRegister Array of operators to register
     */
    function _registerOperatorsAsEigenLayerOperators(
        OperatorLib.Operator[] memory operatorsToRegister
    ) internal {
        for (uint256 i = 0; i < operatorsToRegister.length; i++) {
            vm.startPrank(operatorsToRegister[i].key.addr);
            OperatorLib.registerAsOperator(operatorsToRegister[i], delegationManagerAddr);
            vm.stopPrank();
        }
    }

    /**
     * @dev Gets and sorts operator addresses for use in quorum updates
     * @return Sorted two-dimensional array of operator addresses
     */
    function _getAndSortOperators() internal view returns (address[][] memory) {
        address[][] memory registeredOperators = new address[][](1);
        registeredOperators[0] = new address[](OPERATOR_COUNT);
        for (uint256 i = 0; i < OPERATOR_COUNT; i++) {
            registeredOperators[0][i] = operators[i].key.addr;
        }

        // Sort operator addresses
        for (uint256 i = 0; i < registeredOperators[0].length - 1; i++) {
            for (uint256 j = 0; j < registeredOperators[0].length - i - 1; j++) {
                if (registeredOperators[0][j] > registeredOperators[0][j + 1]) {
                    address temp = registeredOperators[0][j];
                    registeredOperators[0][j] = registeredOperators[0][j + 1];
                    registeredOperators[0][j + 1] = temp;
                }
            }
        }

        return registeredOperators;
    }
}

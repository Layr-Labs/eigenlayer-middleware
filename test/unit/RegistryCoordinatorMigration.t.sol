// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import {
    RewardsCoordinator,
    IRewardsCoordinator,
    IRewardsCoordinatorTypes,
    IERC20
} from "eigenlayer-contracts/src/contracts/core/RewardsCoordinator.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {StrategyBase} from "eigenlayer-contracts/src/contracts/strategies/StrategyBase.sol";
import {IServiceManagerBaseEvents} from "../events/IServiceManagerBaseEvents.sol";
import {IAVSDirectoryTypes} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {AVSDirectoryHarness} from "../harnesses/AVSDirectoryHarness.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";

import "../utils/MockAVSDeployer.sol";

contract RegistryCoordinatorMigrationUnit is MockAVSDeployer, IServiceManagerBaseEvents {
    // RewardsCoordinator config
    address rewardsUpdater = address(uint160(uint256(keccak256("rewardsUpdater"))));
    uint32 CALCULATION_INTERVAL_SECONDS = 7 days;
    uint32 MAX_REWARDS_DURATION = 70 days;
    uint32 MAX_RETROACTIVE_LENGTH = 84 days;
    uint32 MAX_FUTURE_LENGTH = 28 days;
    uint32 GENESIS_REWARDS_TIMESTAMP = 1_712_188_800;
    uint256 MAX_REWARDS_AMOUNT = 1e38 - 1;
    /// @notice Delay in timestamp before a posted root can be claimed against
    uint32 activationDelay = 7 days;
    /// @notice the commission for all operators across all avss
    uint16 globalCommissionBips = 1000;

    // Testing Config and Mocks
    address serviceManagerOwner;
    IERC20[] rewardTokens;
    uint256 mockTokenInitialSupply = 10e50;
    IStrategy strategyMock1;
    IStrategy strategyMock2;
    IStrategy strategyMock3;
    StrategyBase strategyImplementation;
    IRewardsCoordinator.StrategyAndMultiplier[] defaultStrategyAndMultipliers;
    AVSDirectoryHarness avsDirectoryHarness;

    // mapping to setting fuzzed inputs
    mapping(address => bool) public addressIsExcludedFromFuzzedInputs;

    modifier filterFuzzedAddressInputs(address fuzzedAddress) {
        cheats.assume(!addressIsExcludedFromFuzzedInputs[fuzzedAddress]);
        _;
    }

    function setUp() public virtual {
        numQuorums = maxQuorumsToRegisterFor;
        _deployMockEigenLayerAndAVS();

        serviceManagerImplementation = new ServiceManagerMock(
            avsDirectory,
            IRewardsCoordinator(address(rewardsCoordinatorMock)),
            registryCoordinator,
            stakeRegistry,
            allocationManager
        );
        avsDirectoryHarness = new AVSDirectoryHarness(delegationMock);

        serviceManagerImplementation = new ServiceManagerMock(
            avsDirectory,
            rewardsCoordinatorMock,
            registryCoordinator,
            stakeRegistry,
            allocationManager
        );
        /// Needed to upgrade to a service manager that points to an AVS Directory that can track state
        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(serviceManager))),
            address(serviceManagerImplementation)
        );

        serviceManagerOwner = serviceManager.owner();

        _setUpDefaultStrategiesAndMultipliers();

        addressIsExcludedFromFuzzedInputs[address(pauserRegistry)] = true;
        addressIsExcludedFromFuzzedInputs[address(proxyAdmin)] = true;
    }

    function _setUpDefaultStrategiesAndMultipliers() internal virtual {
        // Deploy Mock Strategies
        IERC20 token1 = new ERC20PresetFixedSupply(
            "dog wif hat", "MOCK1", mockTokenInitialSupply, address(this)
        );
        IERC20 token2 =
            new ERC20PresetFixedSupply("jeo boden", "MOCK2", mockTokenInitialSupply, address(this));
        IERC20 token3 = new ERC20PresetFixedSupply(
            "pepe wif avs", "MOCK3", mockTokenInitialSupply, address(this)
        );
        strategyImplementation = new StrategyBase(IStrategyManager(address(strategyManagerMock)));
        strategyMock1 = StrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(strategyImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(StrategyBase.initialize.selector, token1, pauserRegistry)
                )
            )
        );
        strategyMock2 = StrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(strategyImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(StrategyBase.initialize.selector, token2, pauserRegistry)
                )
            )
        );
        strategyMock3 = StrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(strategyImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(StrategyBase.initialize.selector, token3, pauserRegistry)
                )
            )
        );
        IStrategy[] memory strategies = new IStrategy[](3);
        strategies[0] = strategyMock1;
        strategies[1] = strategyMock2;
        strategies[2] = strategyMock3;
        strategies = _sortArrayAsc(strategies);

        strategyManagerMock.setStrategyWhitelist(strategies[0], true);
        strategyManagerMock.setStrategyWhitelist(strategies[1], true);
        strategyManagerMock.setStrategyWhitelist(strategies[2], true);

        defaultStrategyAndMultipliers.push(
            IRewardsCoordinatorTypes.StrategyAndMultiplier(IStrategy(address(strategies[0])), 1e18)
        );
        defaultStrategyAndMultipliers.push(
            IRewardsCoordinatorTypes.StrategyAndMultiplier(IStrategy(address(strategies[1])), 2e18)
        );
        defaultStrategyAndMultipliers.push(
            IRewardsCoordinatorTypes.StrategyAndMultiplier(IStrategy(address(strategies[2])), 3e18)
        );
    }

    /// @dev Sort to ensure that the array is in ascending order for strategies
    function _sortArrayAsc(IStrategy[] memory arr) internal pure returns (IStrategy[] memory) {
        uint256 l = arr.length;
        for (uint256 i = 0; i < l; i++) {
            for (uint256 j = i + 1; j < l; j++) {
                if (address(arr[i]) > address(arr[j])) {
                    IStrategy temp = arr[i];
                    arr[i] = arr[j];
                    arr[j] = temp;
                }
            }
        }
        return arr;
    }

    function test_migrateToOperatorSets() public {
        (uint32[] memory operatorSetsToCreate, uint32[][] memory operatorSetIdsToMigrate, address[] memory operators) = serviceManager.getOperatorsToMigrate();
        cheats.startPrank(serviceManagerOwner);
        serviceManager.migrateAndCreateOperatorSetIds(operatorSetsToCreate);
        serviceManager.migrateToOperatorSets(operatorSetIdsToMigrate, operators);
        cheats.stopPrank();

        assertTrue(avsDirectory.isOperatorSetAVS(address(serviceManager)), "AVS is not an operator set AVS");
    }



    function test_createQuorum() public {
        (uint32[] memory operatorSetsToCreate, uint32[][] memory operatorSetIdsToMigrate, address[] memory operators) = serviceManager.getOperatorsToMigrate();
        cheats.startPrank(serviceManagerOwner);
        serviceManager.migrateAndCreateOperatorSetIds(operatorSetsToCreate);
        serviceManager.migrateToOperatorSets(operatorSetIdsToMigrate, operators);
        cheats.stopPrank();

        assertTrue(avsDirectory.isOperatorSetAVS(address(serviceManager)), "AVS is not an operator set AVS");

        uint8 quorumNumber = registryCoordinator.quorumCount();
        uint96 minimumStake = 1000;
        IRegistryCoordinator.OperatorSetParam memory operatorSetParams = IRegistryCoordinator.OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 50,
            kickBIPsOfTotalStake: 2
        });
        IStakeRegistry.StrategyParams[] memory strategyParams = new IStakeRegistry.StrategyParams[](1);
        strategyParams[0] =
            IStakeRegistry.StrategyParams({
                strategy: IStrategy(address(1000)),
                multiplier: 1e16
            });

        assertFalse(avsDirectory.isOperatorSet(address(serviceManager), quorumNumber), "Operator set already existed");
        assertTrue(avsDirectory.isOperatorSet(address(serviceManager), quorumNumber-1), "Operator set doesn't already existed");

        vm.prank(registryCoordinator.owner());
        registryCoordinator.createQuorum(operatorSetParams, minimumStake, strategyParams);

        assertTrue(avsDirectory.isOperatorSet(address(serviceManager), quorumNumber), "Operator set was not created for the quorum");

    }

    function test_updateOperatorsForQuorumsAfterDirectUnregister() public {
        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(avsDirectory))),
            address(avsDirectoryMock)
        );
        uint256 pseudoRandomNumber = uint256(keccak256("pseudoRandomNumber"));
        _registerRandomOperators(pseudoRandomNumber);

        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(avsDirectory))),
            address(avsDirectoryHarness)
        );

        uint256 quorumCount = registryCoordinator.quorumCount();
        for (uint256 i = 0; i < quorumCount; i++) {
            uint256 operatorCount = indexRegistry.totalOperatorsForQuorum(uint8(i));
            bytes32[] memory operatorIds =
                indexRegistry.getOperatorListAtBlockNumber(uint8(i), uint32(block.number));
            assertEq(operatorCount, operatorIds.length, "Operator Id length mismatch"); // sanity check
            for (uint256 j = 0; j < operatorCount; j++) {
                address operatorAddress =
                 registryCoordinator.blsApkRegistry().getOperatorFromPubkeyHash(operatorIds[j]);
                AVSDirectoryHarness(address(avsDirectory)).setAvsOperatorStatus(
                    address(serviceManager),
                    operatorAddress,
                    IAVSDirectoryTypes.OperatorAVSRegistrationStatus.REGISTERED
                );
            }
        }

        (
            uint32[] memory operatorSetsToCreate,
            uint32[][] memory operatorSetIdsToMigrate,
            address[] memory operators
        ) = serviceManager.getOperatorsToMigrate();
        cheats.startPrank(serviceManagerOwner);
        serviceManager.migrateAndCreateOperatorSetIds(operatorSetsToCreate);
        serviceManager.migrateToOperatorSets(operatorSetIdsToMigrate, operators);
        cheats.stopPrank();

        bytes32[] memory registeredOperators = indexRegistry.getOperatorListAtBlockNumber(defaultQuorumNumber, uint32(block.number));
        uint256 preNumOperators = registeredOperators.length;
        address[] memory registeredOperatorAddresses = new address[](registeredOperators.length);
        for (uint256 i = 0; i < registeredOperators.length; i++) {
            registeredOperatorAddresses[i] = registryCoordinator.blsApkRegistry().pubkeyHashToOperator(registeredOperators[i]);
        }

        uint32[] memory operatorSetsToUnregister = new uint32[](1);
        operatorSetsToUnregister[0] = defaultQuorumNumber;

        vm.prank(operators[0]);
        avsDirectory.forceDeregisterFromOperatorSets(
            operators[0], 
            address(serviceManager), 
            operatorSetsToUnregister,
            ISignatureUtils.SignatureWithSaltAndExpiry({
                signature: new bytes(0),
                salt: bytes32(0),
                expiry: 0
            })
        );
        // sanity check if the operator was unregistered from the intended operator set
        bool operatorIsUnRegistered = !avsDirectory.isMember(operators[0], OperatorSet({
            avs: address(serviceManager),
            operatorSetId: defaultQuorumNumber
        }));
        bool isOperatorSetAVS = avsDirectory.isOperatorSetAVS(address(serviceManager));
        assertTrue(isOperatorSetAVS, "ServiceManager is not an operator set AVS");
        assertTrue(operatorIsUnRegistered, "Operator wasnt unregistered from op set");

        address[][] memory registeredOperatorAddresses2D = new address[][](1);
        registeredOperatorAddresses2D[0] = registeredOperatorAddresses;
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        registryCoordinator.updateOperatorsForQuorum(registeredOperatorAddresses2D, quorumNumbers);

        registeredOperators = indexRegistry.getOperatorListAtBlockNumber(defaultQuorumNumber, uint32(block.number));
        uint256 postRegisteredOperators = registeredOperators.length;

        assertEq(preNumOperators-1, postRegisteredOperators, "");

    }

    function test_deregister_afterMigration() public {
        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(avsDirectory))),
            address(avsDirectoryMock)
        );
        uint256 pseudoRandomNumber = uint256(keccak256("pseudoRandomNumber"));
        _registerRandomOperators(pseudoRandomNumber);

        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(avsDirectory))),
            address(avsDirectoryHarness)
        );

        uint256 quorumCount = registryCoordinator.quorumCount();
        for (uint256 i = 0; i < quorumCount; i++) {
            uint256 operatorCount = indexRegistry.totalOperatorsForQuorum(uint8(i));
            bytes32[] memory operatorIds =
                indexRegistry.getOperatorListAtBlockNumber(uint8(i), uint32(block.number));
            assertEq(operatorCount, operatorIds.length, "Operator Id length mismatch"); // sanity check
            for (uint256 j = 0; j < operatorCount; j++) {
                address operatorAddress =
                 registryCoordinator.blsApkRegistry().getOperatorFromPubkeyHash(operatorIds[j]);
                AVSDirectoryHarness(address(avsDirectory)).setAvsOperatorStatus(
                    address(serviceManager),
                    operatorAddress,
                    IAVSDirectoryTypes.OperatorAVSRegistrationStatus.REGISTERED
                );
            }
        }

        (
            uint32[] memory operatorSetsToCreate,
            uint32[][] memory operatorSetIdsToMigrate,
            address[] memory operators
        ) = serviceManager.getOperatorsToMigrate();
        cheats.startPrank(serviceManagerOwner);
        serviceManager.migrateAndCreateOperatorSetIds(operatorSetsToCreate);
        serviceManager.migrateToOperatorSets(operatorSetIdsToMigrate, operators);
        cheats.stopPrank();

        bytes32[] memory registeredOperators = indexRegistry.getOperatorListAtBlockNumber(defaultQuorumNumber, uint32(block.number));
        address[] memory registeredOperatorAddresses = new address[](registeredOperators.length);
        for (uint256 i = 0; i < registeredOperators.length; i++) {
            registeredOperatorAddresses[i] = registryCoordinator.blsApkRegistry().pubkeyHashToOperator(registeredOperators[i]);
        }

        uint32[] memory operatorSetsToUnregister = new uint32[](1);
        operatorSetsToUnregister[0] = defaultQuorumNumber;

        address operatorToDeregister = operators[0];

        bool isOperatorRegistered = avsDirectory.isMember(operatorToDeregister, OperatorSet({
            avs: address(serviceManager),
            operatorSetId: defaultQuorumNumber
        }));
        bool isOperatorSetAVS = avsDirectory.isOperatorSetAVS(address(serviceManager));
        // sanity check if the operator was registered from the intended operator set
        assertTrue(isOperatorSetAVS, "ServiceManager is not an operator set AVS");
        assertTrue(isOperatorRegistered, "Operator wasnt unregistered from op set");

        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        cheats.startPrank(operatorToDeregister);
        registryCoordinator.deregisterOperator(quorumNumbers);
        cheats.stopPrank();

        isOperatorRegistered = avsDirectory.isMember(operatorToDeregister, OperatorSet({
            avs: address(serviceManager),
            operatorSetId: defaultQuorumNumber
        }));
        assertFalse(isOperatorRegistered, "Operator wasn't deregistered from operator set");
    }

    function test_register_afterMigration() public {
        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(avsDirectory))),
            address(avsDirectoryMock)
        );
        uint256 pseudoRandomNumber = uint256(keccak256("pseudoRandomNumber"));
        _registerRandomOperators(pseudoRandomNumber);

        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(avsDirectory))),
            address(avsDirectoryHarness)
        );

        uint256 quorumCount = registryCoordinator.quorumCount();
        for (uint256 i = 0; i < quorumCount; i++) {
            uint256 operatorCount = indexRegistry.totalOperatorsForQuorum(uint8(i));
            bytes32[] memory operatorIds =
                indexRegistry.getOperatorListAtBlockNumber(uint8(i), uint32(block.number));
            assertEq(operatorCount, operatorIds.length, "Operator Id length mismatch"); // sanity check
            for (uint256 j = 0; j < operatorCount; j++) {
                address operatorAddress =
                 registryCoordinator.blsApkRegistry().getOperatorFromPubkeyHash(operatorIds[j]);
                AVSDirectoryHarness(address(avsDirectory)).setAvsOperatorStatus(
                    address(serviceManager),
                    operatorAddress,
                    IAVSDirectoryTypes.OperatorAVSRegistrationStatus.REGISTERED
                );
            }
        }

        (
            uint32[] memory operatorSetsToCreate,
            uint32[][] memory operatorSetIdsToMigrate,
            address[] memory operators
        ) = serviceManager.getOperatorsToMigrate();
        cheats.startPrank(serviceManagerOwner);
        serviceManager.migrateAndCreateOperatorSetIds(operatorSetsToCreate);
        serviceManager.migrateToOperatorSets(operatorSetIdsToMigrate, operators);
        cheats.stopPrank();

        bytes32[] memory registeredOperators = indexRegistry.getOperatorListAtBlockNumber(defaultQuorumNumber, uint32(block.number));
        address[] memory registeredOperatorAddresses = new address[](registeredOperators.length);
        for (uint256 i = 0; i < registeredOperators.length; i++) {
            registeredOperatorAddresses[i] = registryCoordinator.blsApkRegistry().pubkeyHashToOperator(registeredOperators[i]);
        }

        uint32[] memory operatorSetsToRegisterFor = new uint32[](1);
        operatorSetsToRegisterFor[0] = defaultQuorumNumber;

        uint256 operatorPk = uint256(keccak256("operator to register"));
        address operatorToRegister = vm.addr(operatorPk) ;

        bool isOperatorRegistered = avsDirectory.isMember(operatorToRegister, OperatorSet({
            avs: address(serviceManager),
            operatorSetId: defaultQuorumNumber
        }));
        bool isOperatorSetAVS = avsDirectory.isOperatorSetAVS(address(serviceManager));
        // sanity check if the operator was registered from the intended operator set
        assertTrue(isOperatorSetAVS, "ServiceManager is not an operator set AVS");
        assertTrue(!isOperatorRegistered, "Operator wasnt unregistered from op set");

        IDelegationManager.OperatorDetails memory details;

        cheats.startPrank(operatorToRegister);
        delegationMock.registerAsOperator(details, "your_metadata_URI_here");
        cheats.stopPrank();

        delegationMock.setIsOperator(operatorToRegister, true);

        bytes memory quorumNumbers = new bytes(1);
        IBLSApkRegistry.PubkeyRegistrationParams memory params;
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature;
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        bytes32 typeHash = avsDirectory.calculateOperatorSetRegistrationDigestHash(
            address(serviceManager),
            operatorSetsToRegisterFor,
            keccak256(abi.encodePacked("operator registration salt")),
            block.timestamp + 1 days
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorPk, typeHash);
        operatorSignature = ISignatureUtils.SignatureWithSaltAndExpiry({
            signature: abi.encodePacked(r, s, v),
            salt: keccak256(abi.encodePacked("operator registration salt")),
            expiry: block.timestamp + 1 days
        });

        blsApkRegistry.setBLSPublicKey(operatorToRegister, defaultPubKey);
        delegationMock.setOperatorShares(operatorToRegister, IStrategy(address(0)), 100 ether);
        cheats.startPrank(operatorToRegister);
        registryCoordinator.registerOperator(quorumNumbers, "", params, operatorSignature);
        cheats.stopPrank();

        isOperatorRegistered = avsDirectory.isMember(operatorToRegister, OperatorSet({
            avs: address(serviceManager),
            operatorSetId: defaultQuorumNumber
        }));
        assertTrue(isOperatorRegistered, "Operator wasn't deregistered from operator set");
    }

    
}

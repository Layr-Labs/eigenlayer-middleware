// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import {
    RewardsCoordinator,
    IRewardsCoordinator,
    IERC20
} from "eigenlayer-contracts/src/contracts/core/RewardsCoordinator.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {StrategyBase} from "eigenlayer-contracts/src/contracts/strategies/StrategyBase.sol";
import {IServiceManagerBaseEvents} from "../events/IServiceManagerBaseEvents.sol";
import {AVSDirectoryHarness} from "../harnesses/AVSDirectoryHarness.sol";
import {StakeRootCompendium} from "eigenlayer-contracts/src/contracts/core/StakeRootCompendium.sol";

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

    modifier filterFuzzedAddressInputs(
        address fuzzedAddress
    ) {
        cheats.assume(!addressIsExcludedFromFuzzedInputs[fuzzedAddress]);
        _;
    }

    function setUp() public virtual {
        numQuorums = maxQuorumsToRegisterFor;
        _deployMockEigenLayerAndAVS();
        vm.deal(address(serviceManager), 1 ether);

        serviceManagerImplementation = new ServiceManagerMock(
            avsDirectory,
            IRewardsCoordinator(address(rewardsCoordinatorMock)),
            stakeRootCompendium,
            registryCoordinator,
            stakeRegistry
        );
        avsDirectoryHarness = new AVSDirectoryHarness(delegationMock);

        serviceManagerImplementation = new ServiceManagerMock(
            avsDirectory, rewardsCoordinatorMock, stakeRootCompendium, registryCoordinator, stakeRegistry
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
        strategyImplementation = new StrategyBase(strategyManagerMock);
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
            IRewardsCoordinator.StrategyAndMultiplier(IStrategy(address(strategies[0])), 1e18)
        );
        defaultStrategyAndMultipliers.push(
            IRewardsCoordinator.StrategyAndMultiplier(IStrategy(address(strategies[1])), 2e18)
        );
        defaultStrategyAndMultipliers.push(
            IRewardsCoordinator.StrategyAndMultiplier(IStrategy(address(strategies[2])), 3e18)
        );
    }

    /// @dev Sort to ensure that the array is in ascending order for strategies
    function _sortArrayAsc(
        IStrategy[] memory arr
    ) internal pure returns (IStrategy[] memory) {
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
        uint32[] memory operatorSetsToCreate;
        uint32[][] memory operatorSetIdsToMigrate;
        address[] memory operators;
        cheats.startPrank(serviceManagerOwner);
        serviceManager.migrateAndCreateOperatorSetIds(operatorSetsToCreate, new uint256[](0));
        serviceManager.migrateToOperatorSets(operatorSetIdsToMigrate, operators);
        cheats.stopPrank();

        assertTrue(
            avsDirectory.isOperatorSetAVS(address(serviceManager)), "AVS is not an operator set AVS"
        );
    }

    function test_createQuorum() public {
        uint32[] memory operatorSetsToCreate;
        uint32[][] memory operatorSetIdsToMigrate;
        address[] memory operators;
        cheats.startPrank(serviceManagerOwner);
        serviceManager.migrateAndCreateOperatorSetIds(operatorSetsToCreate, new uint256[](0));
        serviceManager.migrateToOperatorSets(operatorSetIdsToMigrate, operators);
        serviceManager.finalizeMigration();
        cheats.stopPrank();

        assertTrue(
            avsDirectory.isOperatorSetAVS(address(serviceManager)), "AVS is not an operator set AVS"
        );

        uint8 quorumNumber = registryCoordinator.quorumCount();
        uint96 minimumStake = 1000;
        IRegistryCoordinator.OperatorSetParam memory operatorSetParams = IRegistryCoordinator
            .OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 50,
            kickBIPsOfTotalStake: 2
        });
        IStakeRootCompendium.StrategyAndMultiplier[] memory strategyParams =
            new IStakeRootCompendium.StrategyAndMultiplier[](1);
        strategyParams[0] =
            IStakeRootCompendium.StrategyAndMultiplier({strategy: IStrategy(address(1000)), multiplier: 1e16});
        vm.prank(registryCoordinator.owner());
        registryCoordinator.createQuorum(operatorSetParams, 0.3 ether, strategyParams);

        assertTrue(
            avsDirectory.isOperatorSet(address(serviceManager), quorumNumber),
            "Operator set was not created for the quorum"
        );
    }
}

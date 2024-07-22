// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import {
    RewardsCoordinator,
    IRewardsCoordinator,
    IERC20
} from "eigenlayer-contracts/src/contracts/core/RewardsCoordinator.sol";
import {StrategyBase} from "eigenlayer-contracts/src/contracts/strategies/StrategyBase.sol";
import {IServiceManagerBaseEvents} from "../events/IServiceManagerBaseEvents.sol";
import {AVSDirectoryHarness} from "../harnesses/AVSDirectoryHarness.sol";

import "../utils/MockAVSDeployer.sol";

contract ServiceManagerMigration_UnitTests is MockAVSDeployer, IServiceManagerBaseEvents {
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
    address rewardsInitiator = address(uint160(uint256(keccak256("rewardsInitiator"))));
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

        avsDirectoryHarness = new AVSDirectoryHarness(delegationMock);
        // Deploy rewards coordinator
        rewardsCoordinatorImplementation = new RewardsCoordinator(
            delegationMock,
            strategyManagerMock,
            CALCULATION_INTERVAL_SECONDS,
            MAX_REWARDS_DURATION,
            MAX_RETROACTIVE_LENGTH,
            MAX_FUTURE_LENGTH,
            GENESIS_REWARDS_TIMESTAMP
        );

        rewardsCoordinator = RewardsCoordinator(
            address(
                new TransparentUpgradeableProxy(
                    address(rewardsCoordinatorImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        RewardsCoordinator.initialize.selector,
                        msg.sender,
                        pauserRegistry,
                        0, /*initialPausedStatus*/
                        rewardsUpdater,
                        activationDelay,
                        globalCommissionBips
                    )
                )
            )
        );
        // Deploy ServiceManager
        serviceManagerImplementation = new ServiceManagerMock(
            avsDirectory,
            rewardsCoordinator,
            registryCoordinator,
            stakeRegistry
        );

        serviceManager = ServiceManagerMock(
            address(
                new TransparentUpgradeableProxy(
                    address(serviceManagerImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        ServiceManagerMock.initialize.selector, msg.sender, msg.sender
                    )
                )
            )
        );


        serviceManagerOwner = serviceManager.owner();
        cheats.prank(serviceManagerOwner);
        serviceManager.setRewardsInitiator(rewardsInitiator);

        _setUpDefaultStrategiesAndMultipliers();

        cheats.warp(GENESIS_REWARDS_TIMESTAMP + 2 weeks);

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
        cheats.prank(serviceManagerOwner);
        serviceManager.migrateToOperatorSets();

        assertTrue(avsDirectory.isOperatorSetAVS(address(serviceManager)), "AVS is not an operator set AVS");
    }

    function test_migrateToOperatorSets_revert_alreadyMigrated() public {
        cheats.startPrank(serviceManagerOwner);
        serviceManager.migrateToOperatorSets();

        vm.expectRevert();
        serviceManager.migrateToOperatorSets();
    }

    function test_migrateToOperatorSets_revert_notOwner() public {
        address caller = address(uint160(uint256(keccak256("caller"))));
        cheats.expectRevert("Ownable: caller is not the owner");
        cheats.prank(caller);
        serviceManager.migrateToOperatorSets();
    }

    function test_migrateToOperatorSets_verify() public {
        console.log(serviceManager.avsDirectory(), "service manager avs directory");
        console.log(address(avsDirectory), "actual avs directory");
        console.log(address(avsDirectoryMock), "mock avs directory");


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
        console.log(address(registryCoordinator), "Test:RegistryCoord");
        console.log(quorumCount, "quorum count");
        for (uint256 i = 0; i < quorumCount; i++) {
            uint256 operatorCount = indexRegistry.totalOperatorsForQuorum(uint8(i));
            bytes32[] memory operatorIds = indexRegistry.getOperatorListAtBlockNumber(uint8(i), uint32(block.number));
            assertEq(operatorCount, operatorIds.length, "Operator Id length mismatch");// sanity check
            if (operatorCount > 0) {
                console.log(i, "quorum number");
                console.log(operatorCount, "operator count");
            }
            for (uint256 j = 0; j < operatorCount; j++) {
                address operatorAddress = registryCoordinator.blsApkRegistry().getOperatorFromPubkeyHash(operatorIds[j]);
                console.log(operatorAddress, "operator");
                console.log(uint8(avsDirectory.avsOperatorStatus(address(serviceManager), operatorAddress)), "status before ");

                AVSDirectoryHarness(address(avsDirectory)).setAvsOperatorStatus(address(serviceManager), operatorAddress, IAVSDirectory.OperatorAVSRegistrationStatus.REGISTERED);
                console.log(uint8(avsDirectory.avsOperatorStatus(address(serviceManager), operatorAddress)), "status after ");
                // console.log(avsDirectory.isMember(address(serviceManager), operatorAddress, uint32(i)), "operator status");
                // assertTrue(
                //     avsDirectory.isMember(address(serviceManager), operatorAddress, uint32(i)),
                //     "Operator not migrated to operator set"
                // );
            }
        }
        cheats.prank(serviceManagerOwner);
        serviceManager.migrateToOperatorSets();

        /// quick check, this operator is in operator set 3
        assertTrue(
            avsDirectory.isMember(address(serviceManager), 0x73e2Ce949f15Be901f76b54F5a4554A6C8DCf539, uint32(3)),
            "Operator not migrated to operator set"
        ); 
    }
}

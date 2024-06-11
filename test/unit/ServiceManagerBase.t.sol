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

import "../utils/MockAVSDeployer.sol";

contract ServiceManagerBase_UnitTests is MockAVSDeployer, IServiceManagerBaseEvents {
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

    // mapping to setting fuzzed inputs
    mapping(address => bool) public addressIsExcludedFromFuzzedInputs;

    modifier filterFuzzedAddressInputs(address fuzzedAddress) {
        cheats.assume(!addressIsExcludedFromFuzzedInputs[fuzzedAddress]);
        _;
    }

    function setUp() public virtual {
        _deployMockEigenLayerAndAVS();
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
            registryCoordinatorImplementation,
            stakeRegistryImplementation
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

    /// @notice deploy token to owner and approve ServiceManager. Used for deploying reward tokens
    function _deployMockRewardTokens(address owner, uint256 numTokens) internal virtual {
        cheats.startPrank(owner);
        for (uint256 i = 0; i < numTokens; ++i) {
            IERC20 token =
                new ERC20PresetFixedSupply("dog wif hat", "MOCK1", mockTokenInitialSupply, owner);
            rewardTokens.push(token);
            token.approve(address(serviceManager), mockTokenInitialSupply);
        }
        cheats.stopPrank();
    }

    function _getBalanceForTokens(
        IERC20[] memory tokens,
        address holder
    ) internal view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            balances[i] = tokens[i].balanceOf(holder);
        }
        return balances;
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

    function _maxTimestamp(uint32 timestamp1, uint32 timestamp2) internal pure returns (uint32) {
        return timestamp1 > timestamp2 ? timestamp1 : timestamp2;
    }

    function testFuzz_createAVSRewardsSubmission_Revert_WhenNotOwner(address caller)
        public
        filterFuzzedAddressInputs(caller)
    {
        cheats.assume(caller != rewardsInitiator);
        IRewardsCoordinator.RewardsSubmission[] memory rewardsSubmissions;

        cheats.prank(caller);
        cheats.expectRevert(
            "ServiceManagerBase.onlyRewardsInitiator: caller is not the rewards initiator"
        );
        serviceManager.createAVSRewardsSubmission(rewardsSubmissions);
    }

    function test_createAVSRewardsSubmission_Revert_WhenERC20NotApproved() public {
        IERC20 token = new ERC20PresetFixedSupply(
            "dog wif hat", "MOCK1", mockTokenInitialSupply, rewardsInitiator
        );

        IRewardsCoordinator.RewardsSubmission[] memory rewardsSubmissions =
            new IRewardsCoordinator.RewardsSubmission[](1);
        rewardsSubmissions[0] = IRewardsCoordinator.RewardsSubmission({
            strategiesAndMultipliers: defaultStrategyAndMultipliers,
            token: token,
            amount: 100,
            startTimestamp: uint32(block.timestamp),
            duration: uint32(1 weeks)
        });

        cheats.prank(rewardsInitiator);
        cheats.expectRevert("ERC20: insufficient allowance");
        serviceManager.createAVSRewardsSubmission(rewardsSubmissions);
    }

    function test_createAVSRewardsSubmission_SingleSubmission(
        uint256 startTimestamp,
        uint256 duration,
        uint256 amount
    ) public {
        // 1. Bound fuzz inputs to valid ranges and amounts
        IERC20 rewardToken = new ERC20PresetFixedSupply(
            "dog wif hat", "MOCK1", mockTokenInitialSupply, rewardsInitiator
        );
        amount = bound(amount, 1, MAX_REWARDS_AMOUNT);
        duration = bound(duration, 0, MAX_REWARDS_DURATION);
        duration = duration - (duration % CALCULATION_INTERVAL_SECONDS);
        startTimestamp = bound(
            startTimestamp,
            uint256(
                _maxTimestamp(
                    GENESIS_REWARDS_TIMESTAMP, uint32(block.timestamp) - MAX_RETROACTIVE_LENGTH
                )
            ) + CALCULATION_INTERVAL_SECONDS - 1,
            block.timestamp + uint256(MAX_FUTURE_LENGTH)
        );
        startTimestamp = startTimestamp - (startTimestamp % CALCULATION_INTERVAL_SECONDS);

        // 2. Create reward submission input param
        IRewardsCoordinator.RewardsSubmission[] memory rewardsSubmissions =
            new IRewardsCoordinator.RewardsSubmission[](1);
        rewardsSubmissions[0] = IRewardsCoordinator.RewardsSubmission({
            strategiesAndMultipliers: defaultStrategyAndMultipliers,
            token: rewardToken,
            amount: amount,
            startTimestamp: uint32(startTimestamp),
            duration: uint32(duration)
        });

        // 3. Approve serviceManager for ERC20
        cheats.startPrank(rewardsInitiator);
        rewardToken.approve(address(serviceManager), amount);

        // 4. call createAVSRewardsSubmission() with expected event emitted
        uint256 rewardsInitiatorBalanceBefore =
            rewardToken.balanceOf(address(rewardsInitiator));
        uint256 rewardsCoordinatorBalanceBefore =
            rewardToken.balanceOf(address(rewardsCoordinator));

        rewardToken.approve(address(rewardsCoordinator), amount);
        uint256 currSubmissionNonce = rewardsCoordinator.submissionNonce(address(serviceManager));
        bytes32 avsSubmissionHash =
            keccak256(abi.encode(address(serviceManager), currSubmissionNonce, rewardsSubmissions[0]));

        cheats.expectEmit(true, true, true, true, address(rewardsCoordinator));
        emit AVSRewardsSubmissionCreated(
            address(serviceManager), currSubmissionNonce, avsSubmissionHash, rewardsSubmissions[0]
        );
        serviceManager.createAVSRewardsSubmission(rewardsSubmissions);
        cheats.stopPrank();

        assertTrue(
            rewardsCoordinator.isAVSRewardsSubmissionHash(address(serviceManager), avsSubmissionHash),
            "reward submission hash not submitted"
        );
        assertEq(
            currSubmissionNonce + 1,
            rewardsCoordinator.submissionNonce(address(serviceManager)),
            "submission nonce not incremented"
        );
        assertEq(
            rewardsInitiatorBalanceBefore - amount,
            rewardToken.balanceOf(rewardsInitiator),
            "rewardsInitiator balance not decremented by amount of reward submission"
        );
        assertEq(
            rewardsCoordinatorBalanceBefore + amount,
            rewardToken.balanceOf(address(rewardsCoordinator)),
            "RewardsCoordinator balance not incremented by amount of reward submission"
        );
    }

    function test_createAVSRewardsSubmission_MultipleSubmissions(
        uint256 startTimestamp,
        uint256 duration,
        uint256 amount,
        uint256 numSubmissions
    ) public {
        cheats.assume(2 <= numSubmissions && numSubmissions <= 10);
        cheats.prank(rewardsCoordinator.owner());

        IRewardsCoordinator.RewardsSubmission[] memory rewardsSubmissions =
            new IRewardsCoordinator.RewardsSubmission[](numSubmissions);
        bytes32[] memory avsSubmissionHashes = new bytes32[](numSubmissions);
        uint256 startSubmissionNonce = rewardsCoordinator.submissionNonce(address(serviceManager));
        _deployMockRewardTokens(rewardsInitiator, numSubmissions);

        uint256[] memory avsBalancesBefore =
            _getBalanceForTokens(rewardTokens, rewardsInitiator);
        uint256[] memory rewardsCoordinatorBalancesBefore =
            _getBalanceForTokens(rewardTokens, address(rewardsCoordinator));
        uint256[] memory amounts = new uint256[](numSubmissions);

        // Create multiple rewards submissions and their expected event
        for (uint256 i = 0; i < numSubmissions; ++i) {
            // 1. Bound fuzz inputs to valid ranges and amounts using randSeed for each
            amount = bound(amount + i, 1, MAX_REWARDS_AMOUNT);
            amounts[i] = amount;
            duration = bound(duration + i, 0, MAX_REWARDS_DURATION);
            duration = duration - (duration % CALCULATION_INTERVAL_SECONDS);
            startTimestamp = bound(
                startTimestamp + i,
                uint256(
                    _maxTimestamp(
                        GENESIS_REWARDS_TIMESTAMP, uint32(block.timestamp) - MAX_RETROACTIVE_LENGTH
                    )
                ) + CALCULATION_INTERVAL_SECONDS - 1,
                block.timestamp + uint256(MAX_FUTURE_LENGTH)
            );
            startTimestamp = startTimestamp - (startTimestamp % CALCULATION_INTERVAL_SECONDS);

            // 2. Create reward submission input param
            IRewardsCoordinator.RewardsSubmission memory rewardsSubmission = IRewardsCoordinator.RewardsSubmission({
                strategiesAndMultipliers: defaultStrategyAndMultipliers,
                token: rewardTokens[i],
                amount: amounts[i],
                startTimestamp: uint32(startTimestamp),
                duration: uint32(duration)
            });
            rewardsSubmissions[i] = rewardsSubmission;

            // 3. expected event emitted for this rewardsSubmission
            avsSubmissionHashes[i] = keccak256(
                abi.encode(address(serviceManager), startSubmissionNonce + i, rewardsSubmissions[i])
            );
            cheats.expectEmit(true, true, true, true, address(rewardsCoordinator));
            emit AVSRewardsSubmissionCreated(
                address(serviceManager),
                startSubmissionNonce + i,
                avsSubmissionHashes[i],
                rewardsSubmissions[i]
            );
        }

        // 4. call createAVSRewardsSubmission()
        cheats.prank(rewardsInitiator);
        serviceManager.createAVSRewardsSubmission(rewardsSubmissions);

        // 5. Check for submissionNonce() and avsSubmissionHashes being set
        assertEq(
            startSubmissionNonce + numSubmissions,
            rewardsCoordinator.submissionNonce(address(serviceManager)),
            "avs submission nonce not incremented properly"
        );

        for (uint256 i = 0; i < numSubmissions; ++i) {
            assertTrue(
                rewardsCoordinator.isAVSRewardsSubmissionHash(
                    address(serviceManager), avsSubmissionHashes[i]
                ),
                "rewards submission hash not submitted"
            );
            assertEq(
                avsBalancesBefore[i] - amounts[i],
                rewardTokens[i].balanceOf(rewardsInitiator),
                "AVS balance not decremented by amount of rewards submission"
            );
            assertEq(
                rewardsCoordinatorBalancesBefore[i] + amounts[i],
                rewardTokens[i].balanceOf(address(rewardsCoordinator)),
                "RewardsCoordinator balance not incremented by amount of rewards submission"
            );
        }
    }

    function test_createAVSRewardsSubmission_MultipleSubmissionsSingleToken(
        uint256 startTimestamp,
        uint256 duration,
        uint256 amount,
        uint256 numSubmissions
    ) public {
        cheats.assume(2 <= numSubmissions && numSubmissions <= 10);
        cheats.prank(rewardsCoordinator.owner());

        IRewardsCoordinator.RewardsSubmission[] memory rewardsSubmissions =
            new IRewardsCoordinator.RewardsSubmission[](numSubmissions);
        bytes32[] memory avsSubmissionHashes = new bytes32[](numSubmissions);
        uint256 startSubmissionNonce = rewardsCoordinator.submissionNonce(address(serviceManager));
        IERC20 rewardToken = new ERC20PresetFixedSupply(
            "dog wif hat", "MOCK1", mockTokenInitialSupply, rewardsInitiator
        );
        cheats.prank(rewardsInitiator);
        rewardToken.approve(address(serviceManager), mockTokenInitialSupply);
        uint256 avsBalanceBefore = rewardToken.balanceOf(rewardsInitiator);
        uint256 rewardsCoordinatorBalanceBefore =
            rewardToken.balanceOf(address(rewardsCoordinator));
        uint256 totalAmount = 0;

        uint256[] memory amounts = new uint256[](numSubmissions);

        // Create multiple rewards submissions and their expected event
        for (uint256 i = 0; i < numSubmissions; ++i) {
            // 1. Bound fuzz inputs to valid ranges and amounts using randSeed for each
            amount = bound(amount + i, 1, MAX_REWARDS_AMOUNT);
            amounts[i] = amount;
            totalAmount += amount;
            duration = bound(duration + i, 0, MAX_REWARDS_DURATION);
            duration = duration - (duration % CALCULATION_INTERVAL_SECONDS);
            startTimestamp = bound(
                startTimestamp + i,
                uint256(
                    _maxTimestamp(
                        GENESIS_REWARDS_TIMESTAMP, uint32(block.timestamp) - MAX_RETROACTIVE_LENGTH
                    )
                ) + CALCULATION_INTERVAL_SECONDS - 1,
                block.timestamp + uint256(MAX_FUTURE_LENGTH)
            );
            startTimestamp = startTimestamp - (startTimestamp % CALCULATION_INTERVAL_SECONDS);

            // 2. Create reward submission input param
            IRewardsCoordinator.RewardsSubmission memory rewardsSubmission = IRewardsCoordinator.RewardsSubmission({
                strategiesAndMultipliers: defaultStrategyAndMultipliers,
                token: rewardToken,
                amount: amounts[i],
                startTimestamp: uint32(startTimestamp),
                duration: uint32(duration)
            });
            rewardsSubmissions[i] = rewardsSubmission;

            // 3. expected event emitted for this avs rewards submission
            avsSubmissionHashes[i] = keccak256(
                abi.encode(address(serviceManager), startSubmissionNonce + i, rewardsSubmissions[i])
            );
            cheats.expectEmit(true, true, true, true, address(rewardsCoordinator));
            emit AVSRewardsSubmissionCreated(
                address(serviceManager),
                startSubmissionNonce + i,
                avsSubmissionHashes[i],
                rewardsSubmissions[i]
            );
        }

        // 4. call createAVSRewardsSubmission()
        cheats.prank(rewardsInitiator);
        serviceManager.createAVSRewardsSubmission(rewardsSubmissions);

        // 5. Check for submissionNonce() and avsSubmissionHashes being set
        assertEq(
            startSubmissionNonce + numSubmissions,
            rewardsCoordinator.submissionNonce(address(serviceManager)),
            "avs submission nonce not incremented properly"
        );
        assertEq(
            avsBalanceBefore - totalAmount,
            rewardToken.balanceOf(rewardsInitiator),
            "AVS balance not decremented by amount of rewards submissions"
        );
        assertEq(
            rewardsCoordinatorBalanceBefore + totalAmount,
            rewardToken.balanceOf(address(rewardsCoordinator)),
            "RewardsCoordinator balance not incremented by amount of rewards submissions"
        );

        for (uint256 i = 0; i < numSubmissions; ++i) {
            assertTrue(
                rewardsCoordinator.isAVSRewardsSubmissionHash(
                    address(serviceManager), avsSubmissionHashes[i]
                ),
                "rewards submission hash not submitted"
            );
        }
    }

    function test_setRewardsInitiator() public {
        address newRewardsInitiator = address(uint160(uint256(keccak256("newRewardsInitiator"))));
        cheats.prank(serviceManagerOwner);
        serviceManager.setRewardsInitiator(newRewardsInitiator);
        assertEq(newRewardsInitiator, serviceManager.rewardsInitiator());
    }

    function test_setRewardsInitiator_revert_notOwner() public {
        address caller = address(uint160(uint256(keccak256("caller"))));
        address newRewardsInitiator = address(uint160(uint256(keccak256("newRewardsInitiator"))));
        cheats.expectRevert("Ownable: caller is not the owner");
        cheats.prank(caller);
        serviceManager.setRewardsInitiator(newRewardsInitiator);
    }
}

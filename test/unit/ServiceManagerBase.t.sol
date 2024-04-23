// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import {PaymentCoordinator, IPaymentCoordinator, IERC20} from "eigenlayer-contracts/src/contracts/core/PaymentCoordinator.sol";
import {StrategyBase} from "eigenlayer-contracts/src/contracts/strategies/StrategyBase.sol";
import {IServiceManagerBaseEvents} from "../events/IServiceManagerBaseEvents.sol";

import "../utils/MockAVSDeployer.sol";

contract ServiceManagerBase_UnitTests is
    MockAVSDeployer,
    IServiceManagerBaseEvents
{
    // PaymentCoordinator config
    address paymentUpdater =
        address(uint160(uint256(keccak256("paymentUpdater"))));
    uint32 MAX_PAYMENT_DURATION = 70 days;
    uint32 MAX_RETROACTIVE_LENGTH = 84 days;
    uint32 MAX_FUTURE_LENGTH = 28 days;
    uint32 GENESIS_PAYMENT_TIMESTAMP = 1712092632;
    /// @notice Delay in timestamp before a posted root can be claimed against
    uint32 activationDelay = 7 days;
    /// @notice intervals(epochs) are 2 weeks
    uint32 calculationIntervalSeconds = 14 days;
    /// @notice the commission for all operators across all avss
    uint16 globalCommissionBips = 1000;

    // Testing Config and Mocks
    address serviceManagerOwner;
    IERC20[] paymentTokens;
    uint256 mockTokenInitialSupply = 10e50;
    IStrategy strategyMock1;
    IStrategy strategyMock2;
    IStrategy strategyMock3;
    StrategyBase strategyImplementation;
    IPaymentCoordinator.StrategyAndMultiplier[] defaultStrategyAndMultipliers;

    // mapping to setting fuzzed inputs
    mapping(address => bool) public addressIsExcludedFromFuzzedInputs;

    modifier filterFuzzedAddressInputs(address fuzzedAddress) {
        cheats.assume(!addressIsExcludedFromFuzzedInputs[fuzzedAddress]);
        _;
    }

    function setUp() public virtual {
        _deployMockEigenLayerAndAVS();
        // Deploy paymentcoordinator
        paymentCoordinatorImplementation = new PaymentCoordinator(
            delegationMock,
            strategyManagerMock,
            MAX_PAYMENT_DURATION,
            MAX_RETROACTIVE_LENGTH,
            MAX_FUTURE_LENGTH,
            GENESIS_PAYMENT_TIMESTAMP
        );

        paymentCoordinator = PaymentCoordinator(
            address(
                new TransparentUpgradeableProxy(
                    address(paymentCoordinatorImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        PaymentCoordinator.initialize.selector,
                        msg.sender,
                        pauserRegistry,
                        0 /*initialPausedStatus*/,
                        paymentUpdater,
                        activationDelay,
                        calculationIntervalSeconds,
                        globalCommissionBips
                    )
                )
            )
        );
        // Deploy ServiceManager
        serviceManagerImplementation = new ServiceManagerMock(
            avsDirectory,
            paymentCoordinator,
            registryCoordinatorImplementation,
            stakeRegistryImplementation
        );
        serviceManager = ServiceManagerMock(
            address(
                new TransparentUpgradeableProxy(
                    address(serviceManagerImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        ServiceManagerMock.initialize.selector,
                        msg.sender
                    )
                )
            )
        );
        serviceManagerOwner = serviceManager.owner();

        _setUpDefaultStrategiesAndMultipliers();

        cheats.warp(GENESIS_PAYMENT_TIMESTAMP + 2 weeks);

        addressIsExcludedFromFuzzedInputs[address(pauserRegistry)] = true;
        addressIsExcludedFromFuzzedInputs[address(proxyAdmin)] = true;
    }

    /// @notice deploy token to owner and approve ServiceManager. Used for deploying payment tokens
    function _deployMockPaymentTokens(
        address owner,
        uint256 numTokens
    ) internal virtual {
        cheats.startPrank(owner);
        for (uint256 i = 0; i < numTokens; ++i) {
            IERC20 token = new ERC20PresetFixedSupply(
                "dog wif hat",
                "MOCK1",
                mockTokenInitialSupply,
                owner
            );
            paymentTokens.push(token);
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
            "dog wif hat",
            "MOCK1",
            mockTokenInitialSupply,
            address(this)
        );
        IERC20 token2 = new ERC20PresetFixedSupply(
            "jeo boden",
            "MOCK2",
            mockTokenInitialSupply,
            address(this)
        );
        IERC20 token3 = new ERC20PresetFixedSupply(
            "pepe wif avs",
            "MOCK3",
            mockTokenInitialSupply,
            address(this)
        );
        strategyImplementation = new StrategyBase(strategyManagerMock);
        strategyMock1 = StrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(strategyImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        StrategyBase.initialize.selector,
                        token1,
                        pauserRegistry
                    )
                )
            )
        );
        strategyMock2 = StrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(strategyImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        StrategyBase.initialize.selector,
                        token2,
                        pauserRegistry
                    )
                )
            )
        );
        strategyMock3 = StrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(strategyImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        StrategyBase.initialize.selector,
                        token3,
                        pauserRegistry
                    )
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
            IPaymentCoordinator.StrategyAndMultiplier(
                IStrategy(address(strategies[0])),
                1e18
            )
        );
        defaultStrategyAndMultipliers.push(
            IPaymentCoordinator.StrategyAndMultiplier(
                IStrategy(address(strategies[1])),
                2e18
            )
        );
        defaultStrategyAndMultipliers.push(
            IPaymentCoordinator.StrategyAndMultiplier(
                IStrategy(address(strategies[2])),
                3e18
            )
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

    function _maxTimestamp(
        uint32 timestamp1,
        uint32 timestamp2
    ) internal pure returns (uint32) {
        return timestamp1 > timestamp2 ? timestamp1 : timestamp2;
    }

    function testFuzz_submitPayments_Revert_WhenNotOwner(
        address caller
    ) public filterFuzzedAddressInputs(caller) {
        IPaymentCoordinator.RangePayment[] memory rangePayments;

        cheats.prank(caller);
        cheats.expectRevert("Ownable: caller is not the owner");
        serviceManager.payForRange(rangePayments);
    }

    function test_submitPayments_Revert_WhenERC20NotApproved() public {
        IERC20 token = new ERC20PresetFixedSupply(
            "dog wif hat",
            "MOCK1",
            mockTokenInitialSupply,
            serviceManagerOwner
        );

        IPaymentCoordinator.RangePayment[]
            memory rangePayments = new IPaymentCoordinator.RangePayment[](1);
        rangePayments[0] = IPaymentCoordinator.RangePayment({
            strategiesAndMultipliers: defaultStrategyAndMultipliers,
            token: token,
            amount: 100,
            startTimestamp: uint32(block.timestamp),
            duration: uint32(1 weeks)
        });

        cheats.prank(serviceManagerOwner);
        cheats.expectRevert("ERC20: insufficient allowance");
        serviceManager.payForRange(rangePayments);
    }

    function test_submitPayments_SingleRangePayment(
        uint256 startTimestamp,
        uint256 duration,
        uint256 amount
    ) public {
        // 1. Bound fuzz inputs to valid ranges and amounts
        IERC20 paymentToken = new ERC20PresetFixedSupply(
            "dog wif hat",
            "MOCK1",
            mockTokenInitialSupply,
            serviceManagerOwner
        );
        amount = bound(amount, 1, mockTokenInitialSupply);
        duration = bound(duration, 0, MAX_PAYMENT_DURATION);
        duration = duration - (duration % calculationIntervalSeconds);
        startTimestamp = bound(
            startTimestamp,
            uint256(
                _maxTimestamp(
                    GENESIS_PAYMENT_TIMESTAMP,
                    uint32(block.timestamp) - MAX_RETROACTIVE_LENGTH
                )
            ) +
                calculationIntervalSeconds -
                1,
            block.timestamp + uint256(MAX_FUTURE_LENGTH)
        );
        startTimestamp =
            startTimestamp -
            (startTimestamp % calculationIntervalSeconds);

        // 2. Create range payment input param
        IPaymentCoordinator.RangePayment[]
            memory rangePayments = new IPaymentCoordinator.RangePayment[](1);
        rangePayments[0] = IPaymentCoordinator.RangePayment({
            strategiesAndMultipliers: defaultStrategyAndMultipliers,
            token: paymentToken,
            amount: amount,
            startTimestamp: uint32(startTimestamp),
            duration: uint32(duration)
        });

        // 3. Approve serviceManager for ERC20
        cheats.startPrank(serviceManagerOwner);
        paymentToken.approve(address(serviceManager), amount);

        // 4. call payForRange() with expected event emitted
        uint256 serviceManagerOwnerBalanceBefore = paymentToken.balanceOf(
            address(serviceManagerOwner)
        );
        uint256 paymentCoordinatorBalanceBefore = paymentToken.balanceOf(
            address(paymentCoordinator)
        );

        paymentToken.approve(address(paymentCoordinator), amount);
        uint256 currPaymentNonce = paymentCoordinator.paymentNonce(
            address(serviceManager)
        );
        bytes32 rangePaymentHash = keccak256(
            abi.encode(
                address(serviceManager),
                currPaymentNonce,
                rangePayments[0]
            )
        );

        cheats.expectEmit(true, true, true, true, address(paymentCoordinator));
        emit RangePaymentCreated(
            address(serviceManager),
            currPaymentNonce,
            rangePaymentHash,
            rangePayments[0]
        );
        serviceManager.payForRange(rangePayments);
        cheats.stopPrank();

        assertTrue(
            paymentCoordinator.isRangePaymentHash(
                address(serviceManager),
                rangePaymentHash
            ),
            "Range payment hash not submitted"
        );
        assertEq(
            currPaymentNonce + 1,
            paymentCoordinator.paymentNonce(address(serviceManager)),
            "Payment nonce not incremented"
        );
        assertEq(
            serviceManagerOwnerBalanceBefore - amount,
            paymentToken.balanceOf(serviceManagerOwner),
            "serviceManagerOwner balance not decremented by amount of range payment"
        );
        assertEq(
            paymentCoordinatorBalanceBefore + amount,
            paymentToken.balanceOf(address(paymentCoordinator)),
            "PaymentCoordinator balance not incremented by amount of range payment"
        );
    }

    function test_submitPayments_MultipleRangePayments(
        uint256 startTimestamp,
        uint256 duration,
        uint256 amount,
        uint256 numPayments
    ) public {
        cheats.assume(2 <= numPayments && numPayments <= 10);
        cheats.prank(paymentCoordinator.owner());

        IPaymentCoordinator.RangePayment[]
            memory rangePayments = new IPaymentCoordinator.RangePayment[](
                numPayments
            );
        bytes32[] memory rangePaymentHashes = new bytes32[](numPayments);
        uint256 startPaymentNonce = paymentCoordinator.paymentNonce(
            address(serviceManager)
        );
        _deployMockPaymentTokens(serviceManagerOwner, numPayments);

        uint256[] memory avsBalancesBefore = _getBalanceForTokens(
            paymentTokens,
            serviceManagerOwner
        );
        uint256[]
            memory paymentCoordinatorBalancesBefore = _getBalanceForTokens(
                paymentTokens,
                address(paymentCoordinator)
            );
        uint256[] memory amounts = new uint256[](numPayments);

        // Create multiple range payments and their expected event
        for (uint256 i = 0; i < numPayments; ++i) {
            // 1. Bound fuzz inputs to valid ranges and amounts using randSeed for each
            amount = bound(amount + i, 1, mockTokenInitialSupply);
            amounts[i] = amount;
            duration = bound(duration + i, 0, MAX_PAYMENT_DURATION);
            duration = duration - (duration % calculationIntervalSeconds);
            startTimestamp = bound(
                startTimestamp + i,
                uint256(
                    _maxTimestamp(
                        GENESIS_PAYMENT_TIMESTAMP,
                        uint32(block.timestamp) - MAX_RETROACTIVE_LENGTH
                    )
                ) +
                    calculationIntervalSeconds -
                    1,
                block.timestamp + uint256(MAX_FUTURE_LENGTH)
            );
            startTimestamp =
                startTimestamp -
                (startTimestamp % calculationIntervalSeconds);

            // 2. Create range payment input param
            IPaymentCoordinator.RangePayment
                memory rangePayment = IPaymentCoordinator.RangePayment({
                    strategiesAndMultipliers: defaultStrategyAndMultipliers,
                    token: paymentTokens[i],
                    amount: amounts[i],
                    startTimestamp: uint32(startTimestamp),
                    duration: uint32(duration)
                });
            rangePayments[i] = rangePayment;

            // 3. expected event emitted for this rangePayment
            rangePaymentHashes[i] = keccak256(
                abi.encode(
                    address(serviceManager),
                    startPaymentNonce + i,
                    rangePayments[i]
                )
            );
            cheats.expectEmit(
                true,
                true,
                true,
                true,
                address(paymentCoordinator)
            );
            emit RangePaymentCreated(
                address(serviceManager),
                startPaymentNonce + i,
                rangePaymentHashes[i],
                rangePayments[i]
            );
        }

        // 4. call payForRange()
        cheats.prank(serviceManagerOwner);
        serviceManager.payForRange(rangePayments);

        // 5. Check for paymentNonce() and rangePaymentHashes being set
        assertEq(
            startPaymentNonce + numPayments,
            paymentCoordinator.paymentNonce(address(serviceManager)),
            "Payment nonce not incremented properly"
        );

        for (uint256 i = 0; i < numPayments; ++i) {
            assertTrue(
                paymentCoordinator.isRangePaymentHash(
                    address(serviceManager),
                    rangePaymentHashes[i]
                ),
                "Range payment hash not submitted"
            );
            assertEq(
                avsBalancesBefore[i] - amounts[i],
                paymentTokens[i].balanceOf(serviceManagerOwner),
                "AVS balance not decremented by amount of range payment"
            );
            assertEq(
                paymentCoordinatorBalancesBefore[i] + amounts[i],
                paymentTokens[i].balanceOf(address(paymentCoordinator)),
                "PaymentCoordinator balance not incremented by amount of range payment"
            );
        }
    }
}

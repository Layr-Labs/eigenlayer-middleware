// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {PermissionControllerMixin} from
    "eigenlayer-contracts/src/contracts/mixins/PermissionControllerMixin.sol";

import "../BN254TableCalculatorBase.sol";

/// @notice Minimal Chainlink AggregatorV3 interface (inline to avoid an external dependency)
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/**
 * @title BN254PriceWeightedTableCalculator (UNAUDITED)
 * @notice Calculates BN254 operator tables with weights derived from Chainlink oracle prices per strategy
 * @dev For each operator, weight = sum_over_strategies( minSlashableStake(strategy) * price(strategy) )
 *      Stake amounts and oracle prices are both normalized to 1e18 before multiplication to keep units consistent.
 *      Admins must configure price feeds and stake decimals per strategy (scoped by operator set) before use.
 */
contract BN254PriceWeightedTableCalculator is BN254TableCalculatorBase, PermissionControllerMixin {
    /// @notice AllocationManager for stake queries
    IAllocationManager public immutable allocationManager;
    /// @notice Lookahead blocks used in slashable stake lookup
    uint256 public immutable LOOKAHEAD_BLOCKS;

    /// @notice Strategy configuration scoped by operator set key
    struct StrategyConfig {
        AggregatorV3Interface priceFeed; // Chainlink price feed for the strategy's underlying
        uint8 stakeDecimals; // Decimals of the strategy's stake unit (usually underlying token decimals)
        bool feedSet;
        bool stakeDecimalsSet;
    }

    /// @dev operatorSetKey => strategy => config
    mapping(bytes32 => mapping(IStrategy => StrategyConfig)) public strategyConfigs;

    /// @notice Emitted when price feeds are set for strategies
    event StrategyPriceFeedsSet(OperatorSet indexed operatorSet, IStrategy[] strategies, address[] feeds);
    /// @notice Emitted when stake decimals are set for strategies
    event StrategyStakeDecimalsSet(OperatorSet indexed operatorSet, IStrategy[] strategies, uint8[] stakeDecimals);

    error ArrayLengthMismatch();

    constructor(
        IKeyRegistrar _keyRegistrar,
        IAllocationManager _allocationManager,
        IPermissionController _permissionController,
        uint256 _LOOKAHEAD_BLOCKS
    ) BN254TableCalculatorBase(_keyRegistrar) PermissionControllerMixin(_permissionController) {
        allocationManager = _allocationManager;
        LOOKAHEAD_BLOCKS = _LOOKAHEAD_BLOCKS;
    }

    /**
     * @notice Set Chainlink price feeds per strategy for a specific operator set
     * @dev Restricted to the AVS of the operator set via PermissionController
     */
    function setStrategyPriceFeeds(
        OperatorSet calldata operatorSet,
        IStrategy[] calldata strategies,
        address[] calldata feeds
    ) external checkCanCall(operatorSet.avs) {
        if (strategies.length != feeds.length) revert ArrayLengthMismatch();
        bytes32 key = operatorSet.key();
        for (uint256 i = 0; i < strategies.length; i++) {
            strategyConfigs[key][strategies[i]].priceFeed = AggregatorV3Interface(feeds[i]);
            strategyConfigs[key][strategies[i]].feedSet = feeds[i] != address(0);
        }
        emit StrategyPriceFeedsSet(operatorSet, strategies, feeds);
    }

    /**
     * @notice Set stake decimals per strategy for a specific operator set
     * @dev Restricted to the AVS of the operator set via PermissionController
     */
    function setStrategyStakeDecimals(
        OperatorSet calldata operatorSet,
        IStrategy[] calldata strategies,
        uint8[] calldata stakeDecimals
    ) external checkCanCall(operatorSet.avs) {
        if (strategies.length != stakeDecimals.length) revert ArrayLengthMismatch();
        bytes32 key = operatorSet.key();
        for (uint256 i = 0; i < strategies.length; i++) {
            strategyConfigs[key][strategies[i]].stakeDecimals = stakeDecimals[i];
            strategyConfigs[key][strategies[i]].stakeDecimalsSet = true;
        }
        emit StrategyStakeDecimalsSet(operatorSet, strategies, stakeDecimals);
    }

    /**
     * @notice Weight calculation using Chainlink prices
     * @dev Only strategies with both a configured feed and stake decimals contribute to weights
     */
    function _getOperatorWeights(
        OperatorSet calldata operatorSet
    ) internal view override returns (address[] memory operators, uint256[][] memory weights) {
        address[] memory registeredOperators = allocationManager.getMembers(operatorSet);
        IStrategy[] memory strategies = allocationManager.getStrategiesInOperatorSet(operatorSet);

        uint256[][] memory minSlashableStake = allocationManager.getMinimumSlashableStake({
            operatorSet: operatorSet,
            operators: registeredOperators,
            strategies: strategies,
            futureBlock: uint32(block.number + LOOKAHEAD_BLOCKS)
        });

        bytes32 key = operatorSet.key();

        operators = new address[](registeredOperators.length);
        weights = new uint256[][](registeredOperators.length);
        uint256 operatorCount = 0;

        for (uint256 i = 0; i < registeredOperators.length; ++i) {
            uint256 totalWeight;
            for (uint256 stratIndex = 0; stratIndex < strategies.length; ++stratIndex) {
                uint256 stakeAmount = minSlashableStake[i][stratIndex];
                if (stakeAmount == 0) continue;

                StrategyConfig memory cfg = strategyConfigs[key][strategies[stratIndex]];
                if (!cfg.feedSet || !cfg.stakeDecimalsSet) continue;

                AggregatorV3Interface feed = cfg.priceFeed;
                if (address(feed) == address(0)) continue;

                (, int256 price, , , ) = feed.latestRoundData();
                if (price <= 0) continue;

                uint8 priceDecimals = feed.decimals();

                // Normalize stake to 1e18: stakeAmount * 10^(18 - stakeDecimals)
                uint256 stakeScaled = _scaleTo1e18(stakeAmount, cfg.stakeDecimals);
                // Normalize price to 1e18
                uint256 priceScaled = _scaleTo1e18(uint256(price), priceDecimals);

                // weight += (stakeScaled * priceScaled) / 1e18
                totalWeight += (stakeScaled * priceScaled) / 1e18;
            }

            if (totalWeight > 0) {
                weights[operatorCount] = new uint256[](1);
                weights[operatorCount][0] = totalWeight;
                operators[operatorCount] = registeredOperators[i];
                operatorCount++;
            }
        }

        assembly {
            mstore(operators, operatorCount)
            mstore(weights, operatorCount)
        }

        return (operators, weights);
    }

    function _scaleTo1e18(uint256 amount, uint8 decimals_) private pure returns (uint256) {
        if (decimals_ == 18) return amount;
        if (decimals_ < 18) {
            unchecked {
                return amount * (10 ** (18 - decimals_));
            }
        }
        // decimals_ > 18
        return amount / (10 ** (decimals_ - 18));
    }
}



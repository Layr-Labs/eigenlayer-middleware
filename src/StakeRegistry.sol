// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

import {StakeRegistryStorage, IStrategy} from "./StakeRegistryStorage.sol";

import {ISlashingRegistryCoordinator} from "./interfaces/ISlashingRegistryCoordinator.sol";
import {IStakeRegistry, IStakeRegistryTypes} from "./interfaces/IStakeRegistry.sol";

import {BitmapUtils} from "./libraries/BitmapUtils.sol";

/**
 * @title A `Registry` that keeps track of stakes of operators for up to 256 quorums.
 * Specifically, it keeps track of
 *      1) The stake of each operator in all the quorums they are a part of for block ranges
 *      2) The total stake of all operators in each quorum for block ranges
 *      3) The minimum stake required to register for each quorum
 * It allows an additional functionality (in addition to registering and deregistering) to update the stake of an operator.
 * @author Layr Labs, Inc.
 */
contract StakeRegistry is StakeRegistryStorage {
    using BitmapUtils for *;

    modifier onlySlashingRegistryCoordinator() {
        _checkSlashingRegistryCoordinator();
        _;
    }

    modifier onlyCoordinatorOwner() {
        _checkSlashingRegistryCoordinatorOwner();
        _;
    }

    modifier quorumExists(
        uint8 quorumNumber
    ) {
        _checkQuorumExists(quorumNumber);
        _;
    }

    constructor(
        ISlashingRegistryCoordinator _slashingRegistryCoordinator,
        IDelegationManager _delegationManager,
        IAVSDirectory _avsDirectory,
        IAllocationManager _allocationManager
    )
        StakeRegistryStorage(
            _slashingRegistryCoordinator,
            _delegationManager,
            _avsDirectory,
            _allocationManager
        )
    {}

    /**
     *
     *                   EXTERNAL FUNCTIONS - REGISTRY COORDINATOR
     *
     */

    /// @inheritdoc IStakeRegistry
    function registerOperator(
        address operator,
        bytes32 operatorId,
        bytes calldata quorumNumbers
    ) public virtual onlySlashingRegistryCoordinator returns (uint96[] memory, uint96[] memory) {
        uint96[] memory currentStakes = new uint96[](quorumNumbers.length);
        uint96[] memory totalStakes = new uint96[](quorumNumbers.length);
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            _checkQuorumExists(quorumNumber);

            // Retrieve the operator's current weighted stake for the quorum, reverting if they have not met
            // the minimum.
            (uint96 currentStake, bool hasMinimumStake) =
                _weightOfOperatorForQuorum(quorumNumber, operator);
            require(hasMinimumStake, BelowMinimumStakeRequirement());

            // Update the operator's stake
            int256 stakeDelta = _recordOperatorStakeUpdate({
                operatorId: operatorId,
                quorumNumber: quorumNumber,
                newStake: currentStake
            });

            // Update this quorum's total stake by applying the operator's delta
            currentStakes[i] = currentStake;
            totalStakes[i] = _recordTotalStakeUpdate(quorumNumber, stakeDelta);
        }

        return (currentStakes, totalStakes);
    }

    /// @inheritdoc IStakeRegistry
    function deregisterOperator(
        bytes32 operatorId,
        bytes calldata quorumNumbers
    ) public virtual onlySlashingRegistryCoordinator {
        /**
         * For each quorum, remove the operator's stake for the quorum and update
         * the quorum's total stake to account for the removal
         */
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            _checkQuorumExists(quorumNumber);

            // Update the operator's stake for the quorum and retrieve the shares removed
            int256 stakeDelta = _recordOperatorStakeUpdate({
                operatorId: operatorId,
                quorumNumber: quorumNumber,
                newStake: 0
            });

            // Apply the operator's stake delta to the total stake for this quorum
            _recordTotalStakeUpdate(quorumNumber, stakeDelta);
        }
    }

    /// @inheritdoc IStakeRegistry
    function updateOperatorsStake(
        address[] memory operators,
        bytes32[] memory operatorIds,
        uint8 quorumNumber
    ) external onlySlashingRegistryCoordinator returns (bool[] memory) {
        bool[] memory shouldBeDeregistered = new bool[](operators.length);

        /**
         * For each quorum, update the operator's stake and record the delta
         * in the quorum's total stake.
         *
         * If the operator no longer has the minimum stake required to be registered
         * in the quorum, the quorum number is added to `quorumsToRemove`, which
         * is returned to the registry coordinator.
         */
        _checkQuorumExists(quorumNumber);

        // Fetch the operators' current stake, applying weighting parameters and checking
        // against the minimum stake requirements for the quorum.
        (uint96[] memory stakeWeights, bool[] memory hasMinimumStakes) =
            _weightOfOperatorsForQuorum(quorumNumber, operators);

        int256 totalStakeDelta = 0;
        // If the operator no longer meets the minimum stake, set their stake to zero and mark them for removal
        /// also handle setting the operator's stake to 0 and remove them from the quorum
        for (uint256 i = 0; i < operators.length; i++) {
            if (!hasMinimumStakes[i]) {
                stakeWeights[i] = 0;
                shouldBeDeregistered[i] = true;
            }

            // Update the operator's stake and retrieve the delta
            // If we're deregistering them, their weight is set to 0
            int256 stakeDelta = _recordOperatorStakeUpdate({
                operatorId: operatorIds[i],
                quorumNumber: quorumNumber,
                newStake: stakeWeights[i]
            });

            totalStakeDelta += stakeDelta;
        }

        // Apply the delta to the quorum's total stake
        _recordTotalStakeUpdate(quorumNumber, totalStakeDelta);

        return shouldBeDeregistered;
    }

    /// @inheritdoc IStakeRegistry
    function initializeDelegatedStakeQuorum(
        uint8 quorumNumber,
        uint96 minimumStake,
        StrategyParams[] memory _strategyParams
    ) public virtual onlySlashingRegistryCoordinator {
        require(!_quorumExists(quorumNumber), QuorumAlreadyExists());
        _addStrategyParams(quorumNumber, _strategyParams);
        _setMinimumStakeForQuorum(quorumNumber, minimumStake);
        _setStakeType(quorumNumber, IStakeRegistryTypes.StakeType.TOTAL_DELEGATED);

        _totalStakeHistory[quorumNumber].push(
            StakeUpdate({
                updateBlockNumber: uint32(block.number),
                nextUpdateBlockNumber: 0,
                stake: 0
            })
        );
    }

    /// @inheritdoc IStakeRegistry
    function initializeSlashableStakeQuorum(
        uint8 quorumNumber,
        uint96 minimumStake,
        uint32 lookAheadPeriod,
        StrategyParams[] memory _strategyParams
    ) public virtual onlySlashingRegistryCoordinator {
        require(!_quorumExists(quorumNumber), QuorumAlreadyExists());
        _addStrategyParams(quorumNumber, _strategyParams);
        _setMinimumStakeForQuorum(quorumNumber, minimumStake);
        _setStakeType(quorumNumber, IStakeRegistryTypes.StakeType.TOTAL_SLASHABLE);
        _setLookAheadPeriod(quorumNumber, lookAheadPeriod);

        _totalStakeHistory[quorumNumber].push(
            StakeUpdate({
                updateBlockNumber: uint32(block.number),
                nextUpdateBlockNumber: 0,
                stake: 0
            })
        );
    }

    /// @inheritdoc IStakeRegistry
    function setMinimumStakeForQuorum(
        uint8 quorumNumber,
        uint96 minimumStake
    ) public virtual onlyCoordinatorOwner quorumExists(quorumNumber) {
        _setMinimumStakeForQuorum(quorumNumber, minimumStake);
    }

    /// @inheritdoc IStakeRegistry
    function setSlashableStakeLookahead(
        uint8 quorumNumber,
        uint32 _lookAheadBlocks
    ) external onlyCoordinatorOwner quorumExists(quorumNumber) {
        _setLookAheadPeriod(quorumNumber, _lookAheadBlocks);
    }

    /// @inheritdoc IStakeRegistry
    function addStrategies(
        uint8 quorumNumber,
        StrategyParams[] memory _strategyParams
    ) public virtual onlyCoordinatorOwner quorumExists(quorumNumber) {
        _addStrategyParams(quorumNumber, _strategyParams);

        uint256 numStratsToAdd = _strategyParams.length;

        address avs = registryCoordinator.avs();
        if (allocationManager.isOperatorSet(OperatorSet(avs, quorumNumber))) {
            IStrategy[] memory strategiesToAdd = new IStrategy[](numStratsToAdd);
            for (uint256 i = 0; i < numStratsToAdd; i++) {
                strategiesToAdd[i] = _strategyParams[i].strategy;
            }
            allocationManager.addStrategiesToOperatorSet({
                avs: avs,
                operatorSetId: quorumNumber,
                strategies: strategiesToAdd
            });
        }
    }

    /// @inheritdoc IStakeRegistry
    function removeStrategies(
        uint8 quorumNumber,
        uint256[] memory indicesToRemove
    ) public virtual onlyCoordinatorOwner quorumExists(quorumNumber) {
        uint256 toRemoveLength = indicesToRemove.length;
        require(toRemoveLength > 0, InputArrayLengthZero());

        StrategyParams[] storage _strategyParams = strategyParams[quorumNumber];
        IStrategy[] storage _strategiesPerQuorum = strategiesPerQuorum[quorumNumber];
        IStrategy[] memory _strategiesToRemove = new IStrategy[](toRemoveLength);

        for (uint256 i = 0; i < toRemoveLength; i++) {
            _strategiesToRemove[i] = _strategyParams[indicesToRemove[i]].strategy;
            emit StrategyRemovedFromQuorum(
                quorumNumber, _strategyParams[indicesToRemove[i]].strategy
            );
            emit StrategyMultiplierUpdated(
                quorumNumber, _strategyParams[indicesToRemove[i]].strategy, 0
            );

            // Replace index to remove with the last item in the list, then pop the last item
            _strategyParams[indicesToRemove[i]] = _strategyParams[_strategyParams.length - 1];
            _strategyParams.pop();
            _strategiesPerQuorum[indicesToRemove[i]] =
                _strategiesPerQuorum[_strategiesPerQuorum.length - 1];
            _strategiesPerQuorum.pop();
        }

        address avs = registryCoordinator.avs();
        if (allocationManager.isOperatorSet(OperatorSet(avs, quorumNumber))) {
            allocationManager.removeStrategiesFromOperatorSet({
                avs: avs,
                operatorSetId: quorumNumber,
                strategies: _strategiesToRemove
            });
        }
    }

    /// @inheritdoc IStakeRegistry
    function modifyStrategyParams(
        uint8 quorumNumber,
        uint256[] calldata strategyIndices,
        uint96[] calldata newMultipliers
    ) public virtual onlyCoordinatorOwner quorumExists(quorumNumber) {
        uint256 numStrats = strategyIndices.length;
        require(numStrats > 0, InputArrayLengthZero());
        require(newMultipliers.length == numStrats, InputArrayLengthMismatch());

        StrategyParams[] storage _strategyParams = strategyParams[quorumNumber];

        for (uint256 i = 0; i < numStrats; i++) {
            // Change the strategy's associated multiplier
            _strategyParams[strategyIndices[i]].multiplier = newMultipliers[i];
            emit StrategyMultiplierUpdated(
                quorumNumber, _strategyParams[strategyIndices[i]].strategy, newMultipliers[i]
            );
        }
    }

    /**
     *
     *                         INTERNAL FUNCTIONS
     *
     */
    function _getStakeUpdateIndexForOperatorAtBlockNumber(
        bytes32 operatorId,
        uint8 quorumNumber,
        uint32 blockNumber
    ) internal view returns (uint32) {
        uint256 length = operatorStakeHistory[operatorId][quorumNumber].length;

        // Iterate backwards through operatorStakeHistory until we find an update that preceeds blockNumber
        for (uint256 i = length; i > 0; i--) {
            if (
                operatorStakeHistory[operatorId][quorumNumber][i - 1].updateBlockNumber
                    <= blockNumber
            ) {
                return uint32(i - 1);
            }
        }

        // If we hit this point, no stake update exists at blockNumber
        revert(
            "StakeRegistry._getStakeUpdateIndexForOperatorAtBlockNumber: no stake update found for operatorId and quorumNumber at block number"
        );
    }

    function _setMinimumStakeForQuorum(uint8 quorumNumber, uint96 minimumStake) internal {
        minimumStakeForQuorum[quorumNumber] = minimumStake;
        emit MinimumStakeForQuorumUpdated(quorumNumber, minimumStake);
    }

    /**
     * @notice Records that `operatorId`'s current stake for `quorumNumber` is now `newStake`
     * @return The change in the operator's stake as a signed int256
     */
    function _recordOperatorStakeUpdate(
        bytes32 operatorId,
        uint8 quorumNumber,
        uint96 newStake
    ) internal returns (int256) {
        uint96 prevStake;
        uint256 historyLength = operatorStakeHistory[operatorId][quorumNumber].length;

        if (historyLength == 0) {
            // No prior stake history - push our first entry
            operatorStakeHistory[operatorId][quorumNumber].push(
                StakeUpdate({
                    updateBlockNumber: uint32(block.number),
                    nextUpdateBlockNumber: 0,
                    stake: newStake
                })
            );
        } else {
            // We have prior stake history - fetch our last-recorded stake
            StakeUpdate storage lastUpdate =
                operatorStakeHistory[operatorId][quorumNumber][historyLength - 1];
            prevStake = lastUpdate.stake;

            // Short-circuit in case there's no change in stake
            if (prevStake == newStake) {
                return 0;
            }

            /**
             * If our last stake entry was made in the current block, update the entry
             * Otherwise, push a new entry and update the previous entry's "next" field
             */
            if (lastUpdate.updateBlockNumber == uint32(block.number)) {
                lastUpdate.stake = newStake;
            } else {
                lastUpdate.nextUpdateBlockNumber = uint32(block.number);
                operatorStakeHistory[operatorId][quorumNumber].push(
                    StakeUpdate({
                        updateBlockNumber: uint32(block.number),
                        nextUpdateBlockNumber: 0,
                        stake: newStake
                    })
                );
            }
        }

        // Log update and return stake delta
        emit OperatorStakeUpdate(operatorId, quorumNumber, newStake);
        return _calculateDelta({prev: prevStake, cur: newStake});
    }

    /// @notice Applies a delta to the total stake recorded for `quorumNumber`
    /// @return Returns the new total stake for the quorum
    function _recordTotalStakeUpdate(
        uint8 quorumNumber,
        int256 stakeDelta
    ) internal returns (uint96) {
        // Get our last-recorded stake update
        uint256 historyLength = _totalStakeHistory[quorumNumber].length;
        StakeUpdate storage lastStakeUpdate = _totalStakeHistory[quorumNumber][historyLength - 1];

        // Return early if no update is needed
        if (stakeDelta == 0) {
            return lastStakeUpdate.stake;
        }

        // Calculate the new total stake by applying the delta to our previous stake
        uint96 newStake = _applyDelta(lastStakeUpdate.stake, stakeDelta);

        /**
         * If our last stake entry was made in the current block, update the entry
         * Otherwise, push a new entry and update the previous entry's "next" field
         */
        if (lastStakeUpdate.updateBlockNumber == uint32(block.number)) {
            lastStakeUpdate.stake = newStake;
        } else {
            lastStakeUpdate.nextUpdateBlockNumber = uint32(block.number);
            _totalStakeHistory[quorumNumber].push(
                StakeUpdate({
                    updateBlockNumber: uint32(block.number),
                    nextUpdateBlockNumber: 0,
                    stake: newStake
                })
            );
        }

        return newStake;
    }

    /**
     * @notice Adds `strategyParams` to the `quorumNumber`-th quorum.
     * @dev Checks to make sure that the *same* strategy cannot be added multiple times (checks against both against existing and new strategies).
     * @dev This function has no check to make sure that the strategies for a single quorum have the same underlying asset. This is a conscious choice,
     * since a middleware may want, e.g., a stablecoin quorum that accepts USDC, USDT, DAI, etc. as underlying assets and trades them as "equivalent".
     */
    function _addStrategyParams(
        uint8 quorumNumber,
        StrategyParams[] memory _strategyParams
    ) internal {
        require(_strategyParams.length > 0, InputArrayLengthZero());
        uint256 numStratsToAdd = _strategyParams.length;
        uint256 numStratsExisting = strategyParams[quorumNumber].length;
        require(
            numStratsExisting + numStratsToAdd <= MAX_WEIGHING_FUNCTION_LENGTH,
            InputArrayLengthMismatch()
        );
        for (uint256 i = 0; i < numStratsToAdd; i++) {
            // fairly gas-expensive internal loop to make sure that the *same* strategy cannot be added multiple times
            for (uint256 j = 0; j < (numStratsExisting + i); j++) {
                require(
                    strategyParams[quorumNumber][j].strategy != _strategyParams[i].strategy,
                    InputDuplicateStrategy()
                );
            }
            require(_strategyParams[i].multiplier > 0, InputMultiplierZero());
            strategyParams[quorumNumber].push(_strategyParams[i]);
            strategiesPerQuorum[quorumNumber].push(_strategyParams[i].strategy);
            emit StrategyAddedToQuorum(quorumNumber, _strategyParams[i].strategy);
            emit StrategyMultiplierUpdated(
                quorumNumber, _strategyParams[i].strategy, _strategyParams[i].multiplier
            );
        }
    }

    /// @notice Returns the change between a previous and current value as a signed int
    function _calculateDelta(uint96 prev, uint96 cur) internal pure returns (int256) {
        return int256(uint256(cur)) - int256(uint256(prev));
    }

    /// @notice Adds or subtracts delta from value, according to its sign
    function _applyDelta(uint96 value, int256 delta) internal pure returns (uint96) {
        if (delta < 0) {
            return value - uint96(uint256(-delta));
        } else {
            return value + uint96(uint256(delta));
        }
    }

    /// @notice Checks that the `stakeUpdate` was valid at the given `blockNumber`
    function _validateStakeUpdateAtBlockNumber(
        StakeUpdate memory stakeUpdate,
        uint32 blockNumber
    ) internal pure {
        /**
         * Check that the update is valid for the given blockNumber:
         * - blockNumber should be >= the update block number
         * - the next update block number should be either 0 or strictly greater than blockNumber
         */
        require(blockNumber >= stakeUpdate.updateBlockNumber, InvalidBlockNumber());
        require(
            stakeUpdate.nextUpdateBlockNumber == 0
                || blockNumber < stakeUpdate.nextUpdateBlockNumber,
            InvalidBlockNumber()
        );
    }

    /// Returns total Slashable stake for a list of operators per strategy that can have the weights applied based on strategy multipliers
    function _getSlashableStakePerStrategy(
        uint8 quorumNumber,
        address[] memory operators
    ) internal view returns (uint256[][] memory) {
        uint32 beforeBlock = uint32(block.number + slashableStakeLookAheadPerQuorum[quorumNumber]);

        uint256[][] memory slashableShares = allocationManager.getMinimumSlashableStake(
            OperatorSet(registryCoordinator.avs(), quorumNumber),
            operators,
            strategiesPerQuorum[quorumNumber],
            beforeBlock
        );

        return slashableShares;
    }

    /**
     * @notice This function computes the total weight of the @param operators in the quorum @param quorumNumber.
     * @dev this method DOES NOT check that the quorum exists
     * @return `uint96[] memory` The weighted sum of the operators' shares across each strategy considered by the quorum
     * @return `bool[] memory` True if the respective operator meets the quorum's minimum stake
     */
    function _weightOfOperatorsForQuorum(
        uint8 quorumNumber,
        address[] memory operators
    ) internal view virtual returns (uint96[] memory, bool[] memory) {
        uint96[] memory weights = new uint96[](operators.length);
        bool[] memory hasMinimumStakes = new bool[](operators.length);

        uint256 stratsLength = strategyParamsLength(quorumNumber);
        StrategyParams[] memory stratsAndMultipliers = strategyParams[quorumNumber];
        uint256[][] memory strategyShares;

        if (stakeTypePerQuorum[quorumNumber] == IStakeRegistryTypes.StakeType.TOTAL_SLASHABLE) {
            // get slashable stake for the operators from AllocationManager
            strategyShares = _getSlashableStakePerStrategy(quorumNumber, operators);
        } else {
            // get delegated stake for the operators from DelegationManager
            strategyShares =
                delegation.getOperatorsShares(operators, strategiesPerQuorum[quorumNumber]);
        }

        // Calculate weight of each operator and whether they contain minimum stake for the quorum
        for (uint256 opIndex = 0; opIndex < operators.length; opIndex++) {
            // 1. For the given operator, loop through the strategies and calculate the operator's
            // weight for the quorum
            for (uint256 stratIndex = 0; stratIndex < stratsLength; stratIndex++) {
                // get multiplier for strategy
                StrategyParams memory strategyAndMultiplier = stratsAndMultipliers[stratIndex];

                // calculate added weight for strategy and multiplier
                if (strategyShares[opIndex][stratIndex] > 0) {
                    weights[opIndex] += uint96(
                        strategyShares[opIndex][stratIndex] * strategyAndMultiplier.multiplier
                            / WEIGHTING_DIVISOR
                    );
                }
            }

            // 2. Check whether operator is above minimum stake threshold
            hasMinimumStakes[opIndex] = weights[opIndex] >= minimumStakeForQuorum[quorumNumber];
        }

        return (weights, hasMinimumStakes);
    }

    function _weightOfOperatorForQuorum(
        uint8 quorumNumber,
        address operator
    ) internal view virtual returns (uint96, bool) {
        address[] memory operators = new address[](1);
        operators[0] = operator;
        (uint96[] memory weights, bool[] memory hasMinimumStakes) =
            _weightOfOperatorsForQuorum(quorumNumber, operators);
        return (weights[0], hasMinimumStakes[0]);
    }

    /// @notice Returns `true` if the quorum has been initialized
    function _quorumExists(
        uint8 quorumNumber
    ) internal view returns (bool) {
        return _totalStakeHistory[quorumNumber].length != 0;
    }

    /**
     *
     *                         VIEW FUNCTIONS
     *
     */

    /// @inheritdoc IStakeRegistry
    function weightOfOperatorForQuorum(
        uint8 quorumNumber,
        address operator
    ) public view virtual quorumExists(quorumNumber) returns (uint96) {
        (uint96 stake,) = _weightOfOperatorForQuorum(quorumNumber, operator);
        return stake;
    }

    /// @inheritdoc IStakeRegistry
    function strategyParamsLength(
        uint8 quorumNumber
    ) public view returns (uint256) {
        return strategyParams[quorumNumber].length;
    }

    /// @inheritdoc IStakeRegistry
    function strategyParamsByIndex(
        uint8 quorumNumber,
        uint256 index
    ) public view returns (StrategyParams memory) {
        return strategyParams[quorumNumber][index];
    }

    /**
     *
     *                   VIEW FUNCTIONS - Operator Stake History
     *
     */

    /// @inheritdoc IStakeRegistry
    function getStakeHistoryLength(
        bytes32 operatorId,
        uint8 quorumNumber
    ) external view returns (uint256) {
        return operatorStakeHistory[operatorId][quorumNumber].length;
    }

    /// @inheritdoc IStakeRegistry
    function getStakeHistory(
        bytes32 operatorId,
        uint8 quorumNumber
    ) external view returns (StakeUpdate[] memory) {
        return operatorStakeHistory[operatorId][quorumNumber];
    }

    /// @inheritdoc IStakeRegistry
    function getCurrentStake(
        bytes32 operatorId,
        uint8 quorumNumber
    ) external view returns (uint96) {
        StakeUpdate memory operatorStakeUpdate = getLatestStakeUpdate(operatorId, quorumNumber);
        return operatorStakeUpdate.stake;
    }

    /// @inheritdoc IStakeRegistry
    function getLatestStakeUpdate(
        bytes32 operatorId,
        uint8 quorumNumber
    ) public view returns (StakeUpdate memory) {
        uint256 historyLength = operatorStakeHistory[operatorId][quorumNumber].length;
        StakeUpdate memory operatorStakeUpdate;
        if (historyLength == 0) {
            return operatorStakeUpdate;
        } else {
            operatorStakeUpdate = operatorStakeHistory[operatorId][quorumNumber][historyLength - 1];
            return operatorStakeUpdate;
        }
    }

    /// @inheritdoc IStakeRegistry
    function getStakeUpdateAtIndex(
        uint8 quorumNumber,
        bytes32 operatorId,
        uint256 index
    ) external view returns (StakeUpdate memory) {
        return operatorStakeHistory[operatorId][quorumNumber][index];
    }

    /// @inheritdoc IStakeRegistry
    function getStakeAtBlockNumber(
        bytes32 operatorId,
        uint8 quorumNumber,
        uint32 blockNumber
    ) external view returns (uint96) {
        return operatorStakeHistory[operatorId][quorumNumber][_getStakeUpdateIndexForOperatorAtBlockNumber(
            operatorId, quorumNumber, blockNumber
        )].stake;
    }

    /// @inheritdoc IStakeRegistry
    function getStakeUpdateIndexAtBlockNumber(
        bytes32 operatorId,
        uint8 quorumNumber,
        uint32 blockNumber
    ) external view returns (uint32) {
        return _getStakeUpdateIndexForOperatorAtBlockNumber(operatorId, quorumNumber, blockNumber);
    }

    /// @inheritdoc IStakeRegistry
    function getStakeAtBlockNumberAndIndex(
        uint8 quorumNumber,
        uint32 blockNumber,
        bytes32 operatorId,
        uint256 index
    ) external view returns (uint96) {
        StakeUpdate memory operatorStakeUpdate =
            operatorStakeHistory[operatorId][quorumNumber][index];
        _validateStakeUpdateAtBlockNumber(operatorStakeUpdate, blockNumber);
        return operatorStakeUpdate.stake;
    }

    /**
     *
     *                     VIEW FUNCTIONS - Total Stake History
     *
     */

    /// @inheritdoc IStakeRegistry
    function getTotalStakeHistoryLength(
        uint8 quorumNumber
    ) external view returns (uint256) {
        return _totalStakeHistory[quorumNumber].length;
    }

    /// @inheritdoc IStakeRegistry
    function getCurrentTotalStake(
        uint8 quorumNumber
    ) external view returns (uint96) {
        return _totalStakeHistory[quorumNumber][_totalStakeHistory[quorumNumber].length - 1].stake;
    }

    /// @inheritdoc IStakeRegistry
    function getTotalStakeUpdateAtIndex(
        uint8 quorumNumber,
        uint256 index
    ) external view returns (StakeUpdate memory) {
        return _totalStakeHistory[quorumNumber][index];
    }

    /// @inheritdoc IStakeRegistry
    function getTotalStakeAtBlockNumberFromIndex(
        uint8 quorumNumber,
        uint32 blockNumber,
        uint256 index
    ) external view returns (uint96) {
        StakeUpdate memory totalStakeUpdate = _totalStakeHistory[quorumNumber][index];
        _validateStakeUpdateAtBlockNumber(totalStakeUpdate, blockNumber);
        return totalStakeUpdate.stake;
    }

    /// @inheritdoc IStakeRegistry
    function getTotalStakeIndicesAtBlockNumber(
        uint32 blockNumber,
        bytes calldata quorumNumbers
    ) external view returns (uint32[] memory) {
        uint32[] memory indices = new uint32[](quorumNumbers.length);
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            _checkQuorumExists(quorumNumber);
            require(
                _totalStakeHistory[quorumNumber][0].updateBlockNumber <= blockNumber,
                EmptyStakeHistory()
            );
            uint256 length = _totalStakeHistory[quorumNumber].length;
            for (uint256 j = 0; j < length; j++) {
                if (
                    _totalStakeHistory[quorumNumber][length - j - 1].updateBlockNumber
                        <= blockNumber
                ) {
                    indices[i] = uint32(length - j - 1);
                    break;
                }
            }
        }
        return indices;
    }

    /**
     * @notice Sets the stake type for the registry for a specific quorum
     * @param quorumNumber The quorum number to set the stake type for
     * @param _stakeType The type of stake to track (TOTAL_DELEGATED, TOTAL_SLASHABLE, or BOTH)
     */
    function _setStakeType(uint8 quorumNumber, IStakeRegistryTypes.StakeType _stakeType) internal {
        stakeTypePerQuorum[quorumNumber] = _stakeType;
        emit StakeTypeSet(_stakeType);
    }

    /**
     * @notice Sets the look ahead time for checking operator shares for a specific quorum
     * @param quorumNumber The quorum number to set the look ahead period for
     * @param _lookAheadBlocks The number of blocks to look ahead when checking shares
     */
    function _setLookAheadPeriod(uint8 quorumNumber, uint32 _lookAheadBlocks) internal {
        require(
            stakeTypePerQuorum[quorumNumber] == IStakeRegistryTypes.StakeType.TOTAL_SLASHABLE,
            QuorumNotSlashable()
        );
        uint32 oldLookAheadDays = slashableStakeLookAheadPerQuorum[quorumNumber];
        slashableStakeLookAheadPerQuorum[quorumNumber] = _lookAheadBlocks;
        emit LookAheadPeriodChanged(oldLookAheadDays, _lookAheadBlocks);
    }

    function _checkSlashingRegistryCoordinator() internal view {
        require(msg.sender == address(registryCoordinator), OnlySlashingRegistryCoordinator());
    }

    function _checkSlashingRegistryCoordinatorOwner() internal view {
        require(
            msg.sender == Ownable(address(registryCoordinator)).owner(),
            OnlySlashingRegistryCoordinatorOwner()
        );
    }

    function _checkQuorumExists(
        uint8 quorumNumber
    ) internal view {
        require(_quorumExists(quorumNumber), QuorumDoesNotExist());
    }
}

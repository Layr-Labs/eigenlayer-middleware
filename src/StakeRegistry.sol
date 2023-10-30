// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "eigenlayer-contracts/src/contracts/libraries/BitmapUtils.sol";
import "src/interfaces/IServiceManager.sol";
import "src/interfaces/IStakeRegistry.sol";
import "src/interfaces/IRegistryCoordinator.sol";
import "src/StakeRegistryStorage.sol";

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
    
    modifier onlyRegistryCoordinator() {
        require(
            msg.sender == address(registryCoordinator),
            "StakeRegistry.onlyRegistryCoordinator: caller is not the RegistryCoordinator"
        );
        _;
    }

    modifier onlyServiceManagerOwner() {
        require(msg.sender == serviceManager.owner(), "StakeRegistry.onlyServiceManagerOwner: caller is not the owner of the serviceManager");
        _;
    }

    modifier quorumExists(uint8 quorumNumber) {
        require(_totalStakeHistory[quorumNumber].length != 0, "StakeRegistry.quorumExists: quorum does not exist");
        _;
    }

    constructor(
        IRegistryCoordinator _registryCoordinator,
        IDelegationManager _delegationManager,
        IServiceManager _serviceManager
    ) StakeRegistryStorage(_registryCoordinator, _delegationManager, _serviceManager) {}

    /*******************************************************************************
                            EXTERNAL FUNCTIONS 
    *******************************************************************************/

    /**
     * @notice Used for updating information on deposits of nodes.
     * @param operators are the addresses of the operators whose stake information is getting updated
     * @dev reverts if there are no operators registered with index out of bounds
     */
    function updateStakes(address[] calldata operators) external {
        // for each quorum, loop through operators and see if they are a part of the quorum
        // if they are, get their new weight and update their individual stake history and the
        // quorum's total stake history accordingly
        uint8 quorumCount = registryCoordinator.quorumCount();
        for (uint8 quorumNumber = 0; quorumNumber < quorumCount; ) {
            int256 totalStakeDelta;

            // TODO - not a huge fan of this dependency on the reg coord, but i do prefer this
            //        over the stakereg also keeping its own count.
            require(_totalStakeHistory[quorumNumber].length != 0, "StakeRegistry.updateStakes: quorum does not exist");

            for (uint256 i = 0; i < operators.length; ) {
                bytes32 operatorId = registryCoordinator.getOperatorId(operators[i]);
                uint192 quorumBitmap = registryCoordinator.getCurrentQuorumBitmapByOperatorId(operatorId);

                /**
                 * If the operator is a part of the quorum, update their current stake
                 * and apply the delta to the total
                 */ 
                if (BitmapUtils.numberIsInBitmap(quorumBitmap, quorumNumber)) {
                    (int256 stakeDelta, ) = _updateOperatorStake({
                        operator: operators[i],
                        operatorId: operatorId,
                        quorumNumber: quorumNumber
                    });

                    totalStakeDelta += stakeDelta;
                }
                unchecked {
                    ++i;
                }
            }

            // Record the update for the quorum's total stake
            _recordTotalStakeUpdate(quorumNumber, totalStakeDelta);

            unchecked {
                ++quorumNumber;
            }
        }
    }

    /*******************************************************************************
                      EXTERNAL FUNCTIONS - REGISTRY COORDINATOR
    *******************************************************************************/

    /**
     * @notice Registers the `operator` with `operatorId` for the specified `quorumNumbers`.
     * @param operator The address of the operator to register.
     * @param operatorId The id of the operator to register.
     * @param quorumNumbers The quorum numbers the operator is registering for, where each byte is an 8 bit integer quorumNumber.
     * @dev access restricted to the RegistryCoordinator
     * @dev Preconditions (these are assumed, not validated in this contract):
     *         1) `quorumNumbers` has no duplicates
     *         2) `quorumNumbers.length` != 0
     *         3) `quorumNumbers` is ordered in ascending order
     *         4) the operator is not already registered
     */
    function registerOperator(
        address operator,
        bytes32 operatorId,
        bytes calldata quorumNumbers
    ) public virtual onlyRegistryCoordinator {

        for (uint256 i = 0; i < quorumNumbers.length; ) {            
            
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            require(_totalStakeHistory[quorumNumber].length != 0, "StakeRegistry.registerOperator: quorum does not exist");
            
            /**
             * Update the operator's stake for the quorum and retrieve their current stake
             * as well as the change in stake.
             * - If this method returns `hasMinimumStake == false`, the operator has not met 
             *   the minimum stake requirement for this quorum
             */
            (int256 stakeDelta, bool hasMinimumStake) = _updateOperatorStake({
                operator: operator, 
                operatorId: operatorId, 
                quorumNumber: quorumNumber
            });
            require(
                hasMinimumStake,
                "StakeRegistry.registerOperator: Operator does not meet minimum stake requirement for quorum"
            );

            // Update this quorum's total stake
            _recordTotalStakeUpdate(quorumNumber, stakeDelta);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Deregisters the operator with `operatorId` for the specified `quorumNumbers`.
     * @param operatorId The id of the operator to deregister.
     * @param quorumNumbers The quorum numbers the operator is deregistering from, where each byte is an 8 bit integer quorumNumber.
     * @dev access restricted to the RegistryCoordinator
     * @dev Preconditions (these are assumed, not validated in this contract):
     *         1) `quorumNumbers` has no duplicates
     *         2) `quorumNumbers.length` != 0
     *         3) `quorumNumbers` is ordered in ascending order
     *         4) the operator is not already deregistered
     *         5) `quorumNumbers` is a subset of the quorumNumbers that the operator is registered for
     */
    function deregisterOperator(
        bytes32 operatorId,
        bytes calldata quorumNumbers
    ) public virtual onlyRegistryCoordinator {
        /**
         * For each quorum, remove the operator's stake for the quorum and update
         * the quorum's total stake to account for the removal
         */
        for (uint256 i = 0; i < quorumNumbers.length; ) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            require(_totalStakeHistory[quorumNumber].length != 0, "StakeRegistry.deregisterOperator: quorum does not exist");

            // Update the operator's stake for the quorum and retrieve the shares removed
            int256 stakeDelta = _recordOperatorStakeUpdate({
                operatorId: operatorId, 
                quorumNumber: quorumNumber, 
                newStake: 0
            });

            // Apply the operator's stake delta to the total stake for this quorum
            _recordTotalStakeUpdate(quorumNumber, stakeDelta);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Initialize a new quorum and push its first history update
    function initializeQuorum(
        uint8 quorumNumber,
        uint96 minimumStake,
        StrategyAndWeightingMultiplier[] memory strategyParams
    ) public virtual onlyRegistryCoordinator {
        require(_totalStakeHistory[quorumNumber].length == 0, "StakeRegistry.initializeQuorum: quorum already exists");
        _addStrategyParams(quorumNumber, strategyParams);
        _setMinimumStakeForQuorum(quorumNumber, minimumStake);

        _totalStakeHistory[quorumNumber].push(OperatorStakeUpdate({
            updateBlockNumber: uint32(block.number),
            nextUpdateBlockNumber: 0,
            stake: 0
        }));
    }

    function setMinimumStakeForQuorum(
        uint8 quorumNumber, 
        uint96 minimumStake
    ) public virtual onlyServiceManagerOwner quorumExists(quorumNumber) {
        _setMinimumStakeForQuorum(quorumNumber, minimumStake);
    }

    /** 
     * @notice Adds strategies and weights to the quorum
     * @dev Checks to make sure that the *same* strategy cannot be added multiple times (checks against both against existing and new strategies).
     * @dev This function has no check to make sure that the strategies for a single quorum have the same underlying asset. This is a concious choice,
     * since a middleware may want, e.g., a stablecoin quorum that accepts USDC, USDT, DAI, etc. as underlying assets and trades them as "equivalent".
     */
    function addStrategies(
        uint8 quorumNumber, 
        StrategyAndWeightingMultiplier[] memory strategyParams
    ) public virtual onlyServiceManagerOwner quorumExists(quorumNumber) {
        _addStrategyParams(quorumNumber, strategyParams);
    }

    /**
     * @notice Remove strategies and their associated weights from the quorum's considered strategies
     * @dev higher indices should be *first* in the list of @param indicesToRemove, since otherwise
     * the removal of lower index entries will cause a shift in the indices of the other strategies to remove
     */
    function removeStrategies(
        uint8 quorumNumber,
        uint256[] memory indicesToRemove
    ) public virtual onlyServiceManagerOwner quorumExists(quorumNumber) {
        uint256 toRemoveLength = indicesToRemove.length;
        require(toRemoveLength > 0, "StakeRegistry.removeStrategyParams: no indices to remove provided");

        StrategyAndWeightingMultiplier[] storage strategyParams = strategiesConsideredAndMultipliers[quorumNumber];

        for (uint256 i = 0; i < toRemoveLength; i++) {
            emit StrategyRemovedFromQuorum(quorumNumber, strategyParams[indicesToRemove[i]].strategy);
            emit StrategyMultiplierUpdated(quorumNumber, strategyParams[indicesToRemove[i]].strategy, 0);

            // Replace index to remove with the last item in the list, then pop the last item
            strategyParams[indicesToRemove[i]] = strategyParams[strategyParams.length - 1];
            strategyParams.pop();
        }
    }

    /**
     * @notice Modifys the weights of existing strategies for a specific quorum
     * @param quorumNumber is the quorum number to which the strategies belong
     * @param strategyIndices are the indices of the strategies to change
     * @param newMultipliers are the new multipliers for the strategies
     */
    function modifyStrategyParams(
        uint8 quorumNumber,
        uint256[] calldata strategyIndices,
        uint96[] calldata newMultipliers
    ) public virtual onlyServiceManagerOwner quorumExists(quorumNumber) {
        uint256 numStrats = strategyIndices.length;
        require(numStrats > 0, "StakeRegistry.modifyStrategyParams: no strategy indices provided");
        require(newMultipliers.length == numStrats, "StakeRegistry.modifyStrategyParams: input length mismatch");

        StrategyAndWeightingMultiplier[] storage strategyParams = strategiesConsideredAndMultipliers[quorumNumber];

        for (uint256 i = 0; i < numStrats; i++) {
            // Change the strategy's associated multiplier
            strategyParams[strategyIndices[i]].multiplier = newMultipliers[i];
            emit StrategyMultiplierUpdated(quorumNumber, strategyParams[strategyIndices[i]].strategy, newMultipliers[i]);
        }
    }

    /*******************************************************************************
                            INTERNAL FUNCTIONS
    *******************************************************************************/

    function _getStakeUpdateIndexForOperatorIdForQuorumAtBlockNumber(
        bytes32 operatorId,
        uint8 quorumNumber,
        uint32 blockNumber
    ) internal view returns (uint32) {
        uint256 length = operatorIdToStakeHistory[operatorId][quorumNumber].length;
        for (uint256 i = 0; i < length; i++) {
            if (operatorIdToStakeHistory[operatorId][quorumNumber][length - i - 1].updateBlockNumber <= blockNumber) {
                uint32 nextUpdateBlockNumber = 
                    operatorIdToStakeHistory[operatorId][quorumNumber][length - i - 1].nextUpdateBlockNumber;
                require(
                    nextUpdateBlockNumber == 0 || nextUpdateBlockNumber > blockNumber,
                    "StakeRegistry._getStakeUpdateIndexForOperatorIdForQuorumAtBlockNumber: operatorId has no stake update at blockNumber"
                );
                return uint32(length - i - 1);
            }
        }
        revert(
            "StakeRegistry._getStakeUpdateIndexForOperatorIdForQuorumAtBlockNumber: no stake update found for operatorId and quorumNumber at block number"
        );
    }

    function _setMinimumStakeForQuorum(uint8 quorumNumber, uint96 minimumStake) internal {
        minimumStakeForQuorum[quorumNumber] = minimumStake;
        emit MinimumStakeForQuorumUpdated(quorumNumber, minimumStake);
    }

    /**
     * @notice Finds the updated stake for `operator` for `quorumNumber`, stores it and records the update
     * @dev **DOES NOT UPDATE `totalStake` IN ANY WAY** -- `totalStake` updates must be done elsewhere.
     * @return delta The change in the operator's stake as a signed int256
     * @return hasMinimumStake Whether the operator meets the minimum stake requirement for the quorum
     */
    function _updateOperatorStake(
        address operator,
        bytes32 operatorId,
        uint8 quorumNumber
    ) internal returns (int256 delta, bool hasMinimumStake) {
        /**
         * Get the operator's current stake for the quorum. If their stake
         * is below the quorum's threshold, set their stake to 0
         */
        uint96 currentStake = _weightOfOperatorForQuorum(quorumNumber, operator);
        if (currentStake < minimumStakeForQuorum[quorumNumber]) {
            currentStake = uint96(0);
        } else {
            hasMinimumStake = true;
        }
        
        // Update the operator's stake and retrieve the delta
        delta = _recordOperatorStakeUpdate({
            operatorId: operatorId, 
            quorumNumber: quorumNumber, 
            newStake: currentStake
        });

        return (delta, hasMinimumStake);
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
        uint256 historyLength = operatorIdToStakeHistory[operatorId][quorumNumber].length;

        if (historyLength == 0) {
            // No prior stake history - push our first entry
            operatorIdToStakeHistory[operatorId][quorumNumber].push(OperatorStakeUpdate({
                updateBlockNumber: uint32(block.number),
                nextUpdateBlockNumber: 0,
                stake: newStake
            }));
        } else {
            // We have prior stake history - fetch our last-recorded stake
            prevStake = operatorIdToStakeHistory[operatorId][quorumNumber][historyLength-1].stake;

            /**
             * If our last stake entry was made in the current block, update the entry
             * Otherwise, push a new entry and update the previous entry's "next" field
             */ 
            if (operatorIdToStakeHistory[operatorId][quorumNumber][historyLength-1].updateBlockNumber == uint32(block.number)) {
                operatorIdToStakeHistory[operatorId][quorumNumber][historyLength-1].stake = newStake;
            } else {
                operatorIdToStakeHistory[operatorId][quorumNumber][historyLength-1].nextUpdateBlockNumber = uint32(block.number);
                operatorIdToStakeHistory[operatorId][quorumNumber].push(OperatorStakeUpdate({
                    updateBlockNumber: uint32(block.number),
                    nextUpdateBlockNumber: 0,
                    stake: newStake
                }));
            }
        }

        // Log update and return stake delta
        emit StakeUpdate(operatorId, quorumNumber, newStake);
        return _calculateDelta({ prev: prevStake, cur: newStake });
    }

    /// @notice Applies a delta to the total stake recorded for `quorumNumber`
    function _recordTotalStakeUpdate(uint8 quorumNumber, int256 stakeDelta) internal {
        // Return early if no update is needed
        if (stakeDelta == 0) {
            return;
        }

        uint96 prevStake;
        uint256 historyLength = _totalStakeHistory[quorumNumber].length;

        if (historyLength == 0) {
            // No prior stake history - push our first entry
            _totalStakeHistory[quorumNumber].push(OperatorStakeUpdate({
                updateBlockNumber: uint32(block.number),
                nextUpdateBlockNumber: 0,
                stake: _applyDelta(prevStake, stakeDelta)
            }));
        } else {
            // We have prior stake history - calculate our new stake as a function of our last-recorded stake
            prevStake = _totalStakeHistory[quorumNumber][historyLength - 1].stake;
            uint96 newStake = _applyDelta(prevStake, stakeDelta);

            /**
             * If our last stake entry was made in the current block, update the entry
             * Otherwise, push a new entry and update the previous entry's "next" field
             */
            if (_totalStakeHistory[quorumNumber][historyLength-1].updateBlockNumber == uint32(block.number)) {
                _totalStakeHistory[quorumNumber][historyLength-1].stake = newStake;
            } else {
                _totalStakeHistory[quorumNumber][historyLength-1].nextUpdateBlockNumber = uint32(block.number);
                _totalStakeHistory[quorumNumber].push(OperatorStakeUpdate({
                    updateBlockNumber: uint32(block.number),
                    nextUpdateBlockNumber: 0,
                    stake: newStake
                }));
            }
        }
    }

    /** 
     * @notice Adds `strategyParams` to the `quorumNumber`-th quorum.
     * @dev Checks to make sure that the *same* strategy cannot be added multiple times (checks against both against existing and new strategies).
     * @dev This function has no check to make sure that the strategies for a single quorum have the same underlying asset. This is a concious choice,
     * since a middleware may want, e.g., a stablecoin quorum that accepts USDC, USDT, DAI, etc. as underlying assets and trades them as "equivalent".
     */
     function _addStrategyParams(
        uint8 quorumNumber,
        StrategyAndWeightingMultiplier[] memory strategyParams
    ) internal {
        require(strategyParams.length > 0, "StakeRegistry._addStrategyParams: no strategies provided");
        uint256 numStratsToAdd = strategyParams.length;
        uint256 numStratsExisting = strategiesConsideredAndMultipliers[quorumNumber].length;
        require(
            numStratsExisting + numStratsToAdd <= MAX_WEIGHING_FUNCTION_LENGTH,
            "StakeRegistry._addStrategyParams: exceed MAX_WEIGHING_FUNCTION_LENGTH"
        );
        for (uint256 i = 0; i < numStratsToAdd; ) {
            // fairly gas-expensive internal loop to make sure that the *same* strategy cannot be added multiple times
            for (uint256 j = 0; j < (numStratsExisting + i); ) {
                require(
                    strategiesConsideredAndMultipliers[quorumNumber][j].strategy !=
                        strategyParams[i].strategy,
                    "StakeRegistry._addStrategyParams: cannot add same strategy 2x"
                );
                unchecked {
                    ++j;
                }
            }
            require(
                strategyParams[i].multiplier > 0,
                "StakeRegistry._addStrategyParams: cannot add strategy with zero weight"
            );
            strategiesConsideredAndMultipliers[quorumNumber].push(strategyParams[i]);
            emit StrategyAddedToQuorum(quorumNumber, strategyParams[i].strategy);
            emit StrategyMultiplierUpdated(
                quorumNumber,
                strategyParams[i].strategy,
                strategyParams[i].multiplier
            );
            unchecked {
                ++i;
            }
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

    /// @notice Validates that the `operatorStake` was accurate at the given `blockNumber`
    function _validateOperatorStakeUpdateAtBlockNumber(
        OperatorStakeUpdate memory operatorStakeUpdate,
        uint32 blockNumber
    ) internal pure {
        require(
            operatorStakeUpdate.updateBlockNumber <= blockNumber,
            "StakeRegistry._validateOperatorStakeAtBlockNumber: operatorStakeUpdate is from after blockNumber"
        );
        require(
            operatorStakeUpdate.nextUpdateBlockNumber == 0 || operatorStakeUpdate.nextUpdateBlockNumber > blockNumber,
            "StakeRegistry._validateOperatorStakeAtBlockNumber: there is a newer operatorStakeUpdate available before blockNumber"
        );
    }

    /**
     * @notice This function computes the total weight of the @param operator in the quorum @param quorumNumber.
     * @dev this method DOES NOT check that the quorum exists
     */
    function _weightOfOperatorForQuorum(uint8 quorumNumber, address operator) internal virtual view returns (uint96) {
        uint96 weight;
        uint256 stratsLength = strategiesConsideredAndMultipliersLength(quorumNumber);
        StrategyAndWeightingMultiplier memory strategyAndMultiplier;

        for (uint256 i = 0; i < stratsLength;) {
            // accessing i^th StrategyAndWeightingMultiplier struct for the quorumNumber
            strategyAndMultiplier = strategiesConsideredAndMultipliers[quorumNumber][i];

            // shares of the operator in the strategy
            uint256 sharesAmount = delegation.operatorShares(operator, strategyAndMultiplier.strategy);

            // add the weight from the shares for this strategy to the total weight
            if (sharesAmount > 0) {
                weight += uint96(sharesAmount * strategyAndMultiplier.multiplier / WEIGHTING_DIVISOR);
            }

            unchecked {
                ++i;
            }
        }

        return weight;
    }

    /*******************************************************************************
                            VIEW FUNCTIONS
    *******************************************************************************/

    /**
     * @notice This function computes the total weight of the @param operator in the quorum @param quorumNumber.
     * @dev reverts if the quorum does not exist
     */
    function weightOfOperatorForQuorum(
        uint8 quorumNumber, 
        address operator
    ) public virtual view quorumExists(quorumNumber) returns (uint96) {
        return _weightOfOperatorForQuorum(quorumNumber, operator);
    }

    /// @notice Returns the length of the dynamic array stored in `strategiesConsideredAndMultipliers[quorumNumber]`.
    function strategiesConsideredAndMultipliersLength(uint8 quorumNumber) public view returns (uint256) {
        return strategiesConsideredAndMultipliers[quorumNumber].length;
    }

    /// @notice Returns the strategy and weight multiplier for the `index`'th strategy in the quorum `quorumNumber`
    function strategyAndWeightingMultiplierForQuorumByIndex(
        uint8 quorumNumber, 
        uint256 index
    ) public view returns (StrategyAndWeightingMultiplier memory)
    {
        return strategiesConsideredAndMultipliers[quorumNumber][index];
    }

    /**
     * @notice Returns the entire `operatorIdToStakeHistory[operatorId][quorumNumber]` array.
     * @param operatorId The id of the operator of interest.
     * @param quorumNumber The quorum number to get the stake for.
     */
     function getOperatorIdToStakeHistory(
        bytes32 operatorId, 
        uint8 quorumNumber
    ) external view returns (OperatorStakeUpdate[] memory) {
        return operatorIdToStakeHistory[operatorId][quorumNumber];
    }

    /**
     * @notice Returns the `index`-th entry in the `operatorIdToStakeHistory[operatorId][quorumNumber]` array.
     * @param quorumNumber The quorum number to get the stake for.
     * @param operatorId The id of the operator of interest.
     * @param index Array index for lookup, within the dynamic array `operatorIdToStakeHistory[operatorId][quorumNumber]`.
     * @dev Function will revert if `index` is out-of-bounds.
     */
    function getStakeUpdateForQuorumFromOperatorIdAndIndex(
        uint8 quorumNumber,
        bytes32 operatorId,
        uint256 index
    ) external view returns (OperatorStakeUpdate memory) {
        return operatorIdToStakeHistory[operatorId][quorumNumber][index];
    }

    /**
     * @notice Returns the `index`-th entry in the dynamic array of total stake, `_totalStakeHistory` for quorum `quorumNumber`.
     * @param quorumNumber The quorum number to get the stake for.
     * @param index Array index for lookup, within the dynamic array `_totalStakeHistory[quorumNumber]`.
     */
    function getTotalStakeUpdateForQuorumFromIndex(
        uint8 quorumNumber,
        uint256 index
    ) external view returns (OperatorStakeUpdate memory) {
        return _totalStakeHistory[quorumNumber][index];
    }

    /// @notice Returns the indices of the operator stakes for the provided `quorumNumber` at the given `blockNumber`
    function getStakeUpdateIndexForOperatorIdForQuorumAtBlockNumber(
        bytes32 operatorId,
        uint8 quorumNumber,
        uint32 blockNumber
    ) external view returns (uint32) {
        return _getStakeUpdateIndexForOperatorIdForQuorumAtBlockNumber(operatorId, quorumNumber, blockNumber);
    }

    /**
     * @notice Returns the indices of the total stakes for the provided `quorumNumbers` at the given `blockNumber`
     * @param blockNumber Block number to retrieve the stake indices from.
     * @param quorumNumbers The quorum numbers to get the stake indices for.
     * @dev Function will revert if there are no indices for the given `blockNumber`
     */
    function getTotalStakeIndicesByQuorumNumbersAtBlockNumber(
        uint32 blockNumber,
        bytes calldata quorumNumbers
    ) external view returns (uint32[] memory) {
        uint32[] memory indices = new uint32[](quorumNumbers.length);
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            require(
                _totalStakeHistory[quorumNumber][0].updateBlockNumber <= blockNumber,
                "StakeRegistry.getTotalStakeIndicesByQuorumNumbersAtBlockNumber: quorum has no stake history at blockNumber"
            );
            uint256 length = _totalStakeHistory[quorumNumber].length;
            for (uint256 j = 0; j < length; j++) {
                if (_totalStakeHistory[quorumNumber][length - j - 1].updateBlockNumber <= blockNumber) {
                    indices[i] = uint32(length - j - 1);
                    break;
                }
            }
        }
        return indices;
    }

    /**
     * @notice Returns the stake weight corresponding to `operatorId` for quorum `quorumNumber`, at the
     * `index`-th entry in the `operatorIdToStakeHistory[operatorId][quorumNumber]` array if it was the operator's
     * stake at `blockNumber`. Reverts otherwise.
     * @param quorumNumber The quorum number to get the stake for.
     * @param operatorId The id of the operator of interest.
     * @param index Array index for lookup, within the dynamic array `operatorIdToStakeHistory[operatorId][quorumNumber]`.
     * @param blockNumber Block number to make sure the stake is from.
     * @dev Function will revert if `index` is out-of-bounds.
     */
    function getStakeForQuorumAtBlockNumberFromOperatorIdAndIndex(
        uint8 quorumNumber,
        uint32 blockNumber,
        bytes32 operatorId,
        uint256 index
    ) external view returns (uint96) {
        OperatorStakeUpdate memory operatorStakeUpdate = operatorIdToStakeHistory[operatorId][quorumNumber][index];
        _validateOperatorStakeUpdateAtBlockNumber(operatorStakeUpdate, blockNumber);
        return operatorStakeUpdate.stake;
    }

    /**
     * @notice Returns the total stake weight for quorum `quorumNumber`, at the `index`-th entry in the
     * `_totalStakeHistory[quorumNumber]` array if it was the stake at `blockNumber`. Reverts otherwise.
     * @param quorumNumber The quorum number to get the stake for.
     * @param index Array index for lookup, within the dynamic array `_totalStakeHistory[quorumNumber]`.
     * @param blockNumber Block number to make sure the stake is from.
     * @dev Function will revert if `index` is out-of-bounds.
     */
    function getTotalStakeAtBlockNumberFromIndex(
        uint8 quorumNumber,
        uint32 blockNumber,
        uint256 index
    ) external view returns (uint96) {
        OperatorStakeUpdate memory totalStakeUpdate = _totalStakeHistory[quorumNumber][index];
        _validateOperatorStakeUpdateAtBlockNumber(totalStakeUpdate, blockNumber);
        return totalStakeUpdate.stake;
    }

    /**
     * @notice Returns the most recent stake weight for the `operatorId` for a certain quorum
     * @dev Function returns an OperatorStakeUpdate struct with **every entry equal to 0** in the event that the operator has no stake history
     */
    function getMostRecentStakeUpdateByOperatorId(
        bytes32 operatorId,
        uint8 quorumNumber
    ) public view returns (OperatorStakeUpdate memory) {
        uint256 historyLength = operatorIdToStakeHistory[operatorId][quorumNumber].length;
        OperatorStakeUpdate memory operatorStakeUpdate;
        if (historyLength == 0) {
            return operatorStakeUpdate;
        } else {
            operatorStakeUpdate = operatorIdToStakeHistory[operatorId][quorumNumber][historyLength - 1];
            return operatorStakeUpdate;
        }
    }

    /**
     * @notice Returns the most recent stake weight for the `operatorId` for quorum `quorumNumber`
     * @dev Function returns weight of **0** in the event that the operator has no stake history
     */
    function getCurrentOperatorStakeForQuorum(bytes32 operatorId, uint8 quorumNumber) external view returns (uint96) {
        OperatorStakeUpdate memory operatorStakeUpdate = getMostRecentStakeUpdateByOperatorId(operatorId, quorumNumber);
        return operatorStakeUpdate.stake;
    }

    /// @notice Returns the stake of the operator for the provided `quorumNumber` at the given `blockNumber`
    function getStakeForOperatorIdForQuorumAtBlockNumber(
        bytes32 operatorId,
        uint8 quorumNumber,
        uint32 blockNumber
    ) external view returns (uint96) {
        return
            operatorIdToStakeHistory[operatorId][quorumNumber][
                _getStakeUpdateIndexForOperatorIdForQuorumAtBlockNumber(operatorId, quorumNumber, blockNumber)
            ].stake;
    }

    /**
     * @notice Returns the stake weight from the latest entry in `_totalStakeHistory` for quorum `quorumNumber`.
     * @dev Will revert if `_totalStakeHistory[quorumNumber]` is empty.
     */
    function getCurrentTotalStakeForQuorum(uint8 quorumNumber) external view returns (uint96) {
        return _totalStakeHistory[quorumNumber][_totalStakeHistory[quorumNumber].length - 1].stake;
    }

    function getLengthOfOperatorIdStakeHistoryForQuorum(
        bytes32 operatorId,
        uint8 quorumNumber
    ) external view returns (uint256) {
        return operatorIdToStakeHistory[operatorId][quorumNumber].length;
    }

    function getLengthOfTotalStakeHistoryForQuorum(uint8 quorumNumber) external view returns (uint256) {
        return _totalStakeHistory[quorumNumber].length;
    }
}

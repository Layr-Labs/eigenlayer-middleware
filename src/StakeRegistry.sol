// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "eigenlayer-contracts/src/contracts/libraries/BitmapUtils.sol";
import "src/interfaces/IServiceManager.sol";
import "src/interfaces/IStakeRegistry.sol";
import "src/interfaces/IRegistryCoordinator.sol";
import "src/StakeRegistryStorage.sol";
import {VoteWeigherBase} from "src/VoteWeigherBase.sol";

/**
 * @title A `Registry` that keeps track of stakes of operators for up to 256 quorums.
 * Specifically, it keeps track of
 *      1) The stake of each operator in all the quorums they are a part of for block ranges
 *      2) The total stake of all operators in each quorum for block ranges
 *      3) The minimum stake required to register for each quorum
 * It allows an additional functionality (in addition to registering and deregistering) to update the stake of an operator.
 * @author Layr Labs, Inc.
 */
contract StakeRegistry is VoteWeigherBase, StakeRegistryStorage {
    /// @notice requires that the caller is the RegistryCoordinator
    modifier onlyRegistryCoordinator() {
        require(
            msg.sender == address(registryCoordinator),
            "StakeRegistry.onlyRegistryCoordinator: caller is not the RegistryCoordinator"
        );
        _;
    }

    constructor(
        IRegistryCoordinator _registryCoordinator,
        IStrategyManager _strategyManager,
        IServiceManager _serviceManager
    ) VoteWeigherBase(_strategyManager, _serviceManager) StakeRegistryStorage(_registryCoordinator) {}

    /**
     * @notice Sets the minimum stake for each quorum and adds `_quorumStrategiesConsideredAndMultipliers` for each
     * quorum the Registry is being initialized with
     */
    function initialize(
        uint96[] memory _minimumStakeForQuorum,
        StrategyAndWeightingMultiplier[][] memory _quorumStrategiesConsideredAndMultipliers
    ) external virtual initializer {
        _initialize(_minimumStakeForQuorum, _quorumStrategiesConsideredAndMultipliers);
    }

    function _initialize(
        uint96[] memory _minimumStakeForQuorum,
        StrategyAndWeightingMultiplier[][] memory _quorumStrategiesConsideredAndMultipliers
    ) internal virtual onlyInitializing {
        // sanity check lengths
        require(
            _minimumStakeForQuorum.length == _quorumStrategiesConsideredAndMultipliers.length,
            "Registry._initialize: minimumStakeForQuorum length mismatch"
        );

        // add the strategies considered and multipliers for each quorum
        for (uint8 quorumNumber = 0; quorumNumber < _quorumStrategiesConsideredAndMultipliers.length; ) {
            _setMinimumStakeForQuorum(quorumNumber, _minimumStakeForQuorum[quorumNumber]);
            _createQuorum(_quorumStrategiesConsideredAndMultipliers[quorumNumber]);
            unchecked {
                ++quorumNumber;
            }
        }
    }

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
        for (uint8 quorumNumber = 0; quorumNumber < quorumCount; ) {
            int256 totalStakeDelta;

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

            // If we have a change in total stake for this quorum, update state
            // TODO - do we want to record the update, even if the delta is zero?
            //        maybe this makes sense in the case that the quorum doesn't have
            //        an update for this block?
            if (totalStakeDelta != 0) {
                _recordTotalStakeUpdate(quorumNumber, totalStakeDelta);
            }

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
        // check the operator is registering for only valid quorums
        require(
            uint8(quorumNumbers[quorumNumbers.length - 1]) < quorumCount,
            "StakeRegistry._registerOperator: greatest quorumNumber must be less than quorumCount"
        );

        for (uint256 i = 0; i < quorumNumbers.length; ) {            
            /**
             * Update the operator's stake for the quorum and retrieve their current stake
             * as well as the change in stake.
             * If this method returns `stake == 0`, the operator has not met the minimum requirement
             * 
             * TODO - we only use the `stake` return here. It's probably better to use a bool instead
             *        of relying on the method returning "0" in only this one case.
             */
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            (int256 stakeDelta, uint96 stake) = _updateOperatorStake({
                operator: operator, 
                operatorId: operatorId, 
                quorumNumber: quorumNumber
            });
            require(
                stake != 0,
                "StakeRegistry._registerOperator: Operator does not meet minimum stake requirement for quorum"
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
            // Update the operator's stake for the quorum and retrieve the shares removed
            uint8 quorumNumber = uint8(quorumNumbers[i]);
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

    /*******************************************************************************
                    EXTERNAL FUNCTIONS - SERVICE MANAGER OWNER
    *******************************************************************************/

    /// @notice Adjusts the `minimumStakeFirstQuorum` -- i.e. the node stake (weight) requirement for inclusion in the 1st quorum.
    function setMinimumStakeForQuorum(uint8 quorumNumber, uint96 minimumStake) external onlyServiceManagerOwner {
        _setMinimumStakeForQuorum(quorumNumber, minimumStake);
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
     * @return `int256` The change in the operator's stake as a signed int256
     * @return `uint96` The operator's new stake after the update
     */
    function _updateOperatorStake(
        address operator,
        bytes32 operatorId,
        uint8 quorumNumber
    ) internal returns (int256, uint96) {
        /**
         * Get the operator's current stake for the quorum. If their stake
         * is below the quorum's threshold, set their stake to 0
         */
        uint96 currentStake = weightOfOperatorForQuorum(quorumNumber, operator);
        if (currentStake < minimumStakeForQuorum[quorumNumber]) {
            currentStake = uint96(0);
        }
        
        // Update the operator's stake and retrieve the delta
        int256 delta = _recordOperatorStakeUpdate({
            operatorId: operatorId, 
            quorumNumber: quorumNumber, 
            newStake: currentStake
        });

        return (delta, currentStake);
    }

    /**
     * @notice Records that `operatorId`'s current stake for `quorumNumber` is now param @operatorStakeUpdate
     * @return The change in the operator's stake as a signed int256
     */
    function _recordOperatorStakeUpdate(
        bytes32 operatorId,
        uint8 quorumNumber,
        uint96 newStake
    ) internal returns (int256) {
        /**
         * If the operator has previous stake history, update the previous entry
         * and fetch their previous stake
         */
        uint96 prevStake;
        uint256 historyLength = operatorIdToStakeHistory[operatorId][quorumNumber].length;
        if (historyLength != 0) {
            operatorIdToStakeHistory[operatorId][quorumNumber][historyLength - 1]
                .nextUpdateBlockNumber = uint32(block.number);

            prevStake = 
                operatorIdToStakeHistory[operatorId][quorumNumber][historyLength - 1].stake;
        }
        
        // Create a new stake update and push it to storage
        // TODO - update the entry instead of pushing, if the last update block is this block
        operatorIdToStakeHistory[operatorId][quorumNumber].push(OperatorStakeUpdate({
            updateBlockNumber: uint32(block.number),
            nextUpdateBlockNumber: 0,
            stake: newStake
        }));

        emit StakeUpdate(operatorId, quorumNumber, newStake);

        // Return the change in stake
        return _calculateDelta({ prev: prevStake, cur: newStake });
    }

    /// @notice Records that the `totalStake` for `quorumNumber` is now equal to the input param @_totalStake
    function _recordTotalStakeUpdate(uint8 quorumNumber, int256 stakeDelta) internal {
        /**
         * If this quorum has previous stake history, update the previous entry
         * and fetch the previous total stake
         */
        uint96 prevStake;
        uint256 historyLength = _totalStakeHistory[quorumNumber].length;
        if (historyLength != 0) {
            _totalStakeHistory[quorumNumber][historyLength - 1].nextUpdateBlockNumber = uint32(block.number);

            prevStake = _totalStakeHistory[quorumNumber][historyLength - 1].stake;
        }
        
        // Apply the stake delta to the previous stake, and push an update to the
        // quorum's stake history
        _totalStakeHistory[quorumNumber].push(OperatorStakeUpdate({
            updateBlockNumber: uint32(block.number),
            nextUpdateBlockNumber: 0,
            stake: _applyDelta(prevStake, stakeDelta)
        }));
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

    /*******************************************************************************
                            VIEW FUNCTIONS
    *******************************************************************************/

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

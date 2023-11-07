// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "src/IndexRegistryStorage.sol";

/**
 * @title A `Registry` that keeps track of an ordered list of operators for each quorum
 * @author Layr Labs, Inc.
 */
contract IndexRegistry is IndexRegistryStorage {

    /// @notice when applied to a function, only allows the RegistryCoordinator to call it
    modifier onlyRegistryCoordinator() {
        require(msg.sender == address(registryCoordinator), "IndexRegistry.onlyRegistryCoordinator: caller is not the registry coordinator");
        _;
    }

    /// @notice sets the (immutable) `registryCoordinator` address
    constructor(
        IRegistryCoordinator _registryCoordinator
    ) IndexRegistryStorage(_registryCoordinator) {}

    /*******************************************************************************
                      EXTERNAL FUNCTIONS - REGISTRY COORDINATOR
    *******************************************************************************/

    /**
     * @notice Registers the operator with the specified `operatorId` for the quorums specified by `quorumNumbers`.
     * @param operatorId is the id of the operator that is being registered
     * @param quorumNumbers is the quorum numbers the operator is registered for
     * @return numOperatorsPerQuorum is a list of the number of operators (including the registering operator) in each of the quorums the operator is registered for
     * @dev access restricted to the RegistryCoordinator
     * @dev Preconditions (these are assumed, not validated in this contract):
     *         1) `quorumNumbers` has no duplicates
     *         2) `quorumNumbers.length` != 0
     *         3) `quorumNumbers` is ordered in ascending order
     *         4) the operator is not already registered
     */
    function registerOperator(
        bytes32 operatorId, 
        bytes calldata quorumNumbers
    ) public virtual onlyRegistryCoordinator returns(uint32[] memory) {
        uint32[] memory numOperatorsPerQuorum = new uint32[](quorumNumbers.length);

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);

            //this is the would-be index of the operator being registered, the total number of operators for that quorum (which is last index + 1)
            uint256 quorumHistoryLength = _totalOperatorsHistory[quorumNumber].length;
            uint32 numOperators = quorumHistoryLength > 0 ? _totalOperatorsHistory[quorumNumber][quorumHistoryLength - 1].numOperators : 0;
            _updateOperatorIdToIndexHistory({
                operatorId: operatorId, 
                quorumNumber: quorumNumber, 
                index: numOperators
            });
            _updateTotalOperatorHistory({
                quorumNumber: quorumNumber, 
                numOperators: numOperators + 1
            });
            numOperatorsPerQuorum[i] = numOperators + 1;
        }

        return numOperatorsPerQuorum;
    }

    /**
     * @notice Deregisters the operator with the specified `operatorId` for the quorums specified by `quorumNumbers`.
     * @param operatorId is the id of the operator that is being deregistered
     * @param quorumNumbers is the quorum numbers the operator is deregistered for
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
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            uint32 indexOfOperatorToRemove = operatorIdToIndex[quorumNumber][operatorId];
            _processOperatorRemoval({
                operatorId: operatorId, 
                quorumNumber: quorumNumber, 
                indexOfOperatorToRemove: indexOfOperatorToRemove 
            });
            _updateTotalOperatorHistory({
                quorumNumber: quorumNumber, 
                numOperators: _totalOperatorsHistory[quorumNumber][_totalOperatorsHistory[quorumNumber].length - 1].numOperators - 1
            });
        }
    }

    /*******************************************************************************
                                INTERNAL FUNCTIONS
    *******************************************************************************/

    /**
     * @notice updates the total numbers of operator in `quorumNumber` to `numOperators`
     * @param quorumNumber is the number of the quorum to update
     * @param numOperators is the number of operators in the quorum
     */
    function _updateTotalOperatorHistory(uint8 quorumNumber, uint32 numOperators) internal {
        QuorumUpdate memory quorumUpdate;
        // In the case of totalOperatorsHistory, the index parameter is the number of operators in the quorum
        quorumUpdate.numOperators = numOperators;
        quorumUpdate.fromBlockNumber = uint32(block.number);

        _totalOperatorsHistory[quorumNumber].push(quorumUpdate);
    }

    /**
     * @param operatorId operatorId of the operator to update
     * @param quorumNumber quorumNumber of the operator to update
     * @param index the latest index of that operator in the list of operators registered for this quorum
     */ 
    function _updateOperatorIdToIndexHistory(bytes32 operatorId, uint8 quorumNumber, uint32 index) internal {
        OperatorUpdate memory latestOperatorUpdate;
        latestOperatorUpdate.operatorId = operatorId;
        latestOperatorUpdate.fromBlockNumber = uint32(block.number);
        _indexToOperatorIdHistory[quorumNumber][index].push(latestOperatorUpdate);

        operatorIdToIndex[quorumNumber][operatorId] = index;

        emit QuorumIndexUpdate(operatorId, quorumNumber, index);
    }

    /**v
     * @notice when we remove an operator from a quorum, we simply update the operator's index history
     * as well as any operatorIds we have to swap
     * @param quorumNumber quorum number of the operator to remove
     * @param indexOfOperatorToRemove index of the operator to remove
     */ 
    function _processOperatorRemoval(
        bytes32 operatorId, 
        uint8 quorumNumber, 
        uint32 indexOfOperatorToRemove 
    ) internal {   
        uint32 currentNumOperators = _totalOperatorsForQuorum(quorumNumber);
        bytes32 operatorIdToSwap = _indexToOperatorIdHistory[quorumNumber][currentNumOperators - 1][_indexToOperatorIdHistory[quorumNumber][currentNumOperators - 1].length - 1].operatorId;
        // if the operator is not the last in the list, we must swap the last operator into their positon
        if (operatorId != operatorIdToSwap) {
            //update the swapped operator's operatorIdToIndexHistory list with a new entry, as their index has now changed
            _updateOperatorIdToIndexHistory({
                operatorId: operatorIdToSwap, 
                quorumNumber: quorumNumber, 
                index: indexOfOperatorToRemove
            }); 
        } 
        // marking the last index with OPERATOR_DOES_NOT_EXIST_ID, to signal that the index it not at use at the block number 
        _updateOperatorIdToIndexHistory({
            operatorId: OPERATOR_DOES_NOT_EXIST_ID, 
            quorumNumber: quorumNumber, 
            index: currentNumOperators - 1
        });
    }

    /**
     * @notice Returns the total number of operators of the service for the given `quorumNumber` at the given `blockNumber`
     * @dev Returns zero if the @param blockNumber is from before the @param quorumNumber existed, and returns the current number 
     * of total operators if the @param blockNumber is in the future.
     */
    function _getTotalOperatorsForQuorumAtBlockNumber(
        uint8 quorumNumber, 
        uint32 blockNumber
    ) internal view returns (uint32){
        // store list length in memory
        uint256 totalOperatorsHistoryLength = _totalOperatorsHistory[quorumNumber].length;
        // if there are no entries in the total operator history, return 0
        if (totalOperatorsHistoryLength == 0) {
            return 0;
        }

        // if `blockNumber` is from before the `quorumNumber` existed, return `0`
        if (blockNumber < _totalOperatorsHistory[quorumNumber][0].fromBlockNumber) {
            return 0;
        }

        // loop backwards through the total operator history to find the total number of operators at the given block number
        for (uint256 i = 0; i <= totalOperatorsHistoryLength - 1; i++) {
            uint256 listIndex = (totalOperatorsHistoryLength - 1) - i;
            QuorumUpdate memory quorumUpdate = _totalOperatorsHistory[quorumNumber][listIndex];
            // look for the first update that began before or at `blockNumber`
            if (quorumUpdate.fromBlockNumber <= blockNumber) {
                return _totalOperatorsHistory[quorumNumber][listIndex].numOperators;
            }
        }        
        return _totalOperatorsHistory[quorumNumber][0].numOperators;
    }

    /// @notice Returns the total number of operators for a given `quorumNumber`
    function _totalOperatorsForQuorum(uint8 quorumNumber) internal view returns (uint32){
        uint256 totalOperatorsHistoryLength = _totalOperatorsHistory[quorumNumber].length;
        if (totalOperatorsHistoryLength == 0) {
            return 0;
        }
        return _totalOperatorsHistory[quorumNumber][totalOperatorsHistoryLength - 1].numOperators;
    }
    
    /**
     * @return operatorId at the given `index` at the given `blockNumber` for the given `quorumNumber`
     * Precondition: requires that the index was used active at the given block number for quorum
     */
    function _getOperatorIdAtIndexForQuorumAtBlockNumber(
        uint32 index, 
        uint8 quorumNumber, 
        uint32 blockNumber
    ) internal view returns(bytes32) {
        uint256 indexOperatorHistoryLength = _indexToOperatorIdHistory[quorumNumber][index].length;
        // loop backward through index history to find the index of the operator at the given block number
        for (uint256 i = 0; i < indexOperatorHistoryLength; i++) {
            uint256 listIndex = (indexOperatorHistoryLength - 1) - i;
            OperatorUpdate memory operatorIndexUpdate = _indexToOperatorIdHistory[quorumNumber][index][listIndex];
            if (operatorIndexUpdate.fromBlockNumber <= blockNumber) {
                // one special case is that this will be OPERATOR_DOES_NOT_EXIST_ID if this index was not used at the block number
                return operatorIndexUpdate.operatorId;
            }
        }

        // we should only it this if the index was never used before blockNumber
        return OPERATOR_DOES_NOT_EXIST_ID;
    }

    /*******************************************************************************
                                 VIEW FUNCTIONS
    *******************************************************************************/

    /// @notice Returns the _indexToOperatorIdHistory entry for the specified `operatorIndex` and `quorumNumber` at the specified `index`
    function getOperatorIndexUpdateOfIndexForQuorumAtIndex(uint32 operatorIndex, uint8 quorumNumber, uint32 index) external view returns (OperatorUpdate memory) {
        return _indexToOperatorIdHistory[quorumNumber][operatorIndex][index];
    }

    /// @notice Returns the _totalOperatorsHistory entry for the specified `quorumNumber` at the specified `index`
    function getQuorumUpdateAtIndex(uint8 quorumNumber, uint32 index) external view returns (QuorumUpdate memory) {
        return _totalOperatorsHistory[quorumNumber][index];
    }

    /**
     * @notice Looks up the number of total operators for `quorumNumber` at the specified `blockNumber`.
     * @param quorumNumber is the quorum number for which the total number of operators is desired
     * @param blockNumber is the block number at which the total number of operators is desired
     * @param index is the index of the entry in the dynamic array `_totalOperatorsHistory[quorumNumber]` to read data from
     * @dev Function will revert in the event that the specified `index` input is outisde the bounds of the provided `blockNumber`
     */
    function getTotalOperatorsForQuorumAtBlockNumberByIndex(
        uint8 quorumNumber, 
        uint32 blockNumber, 
        uint32 index
    ) external view returns (uint32){
        QuorumUpdate memory quorumUpdate = _totalOperatorsHistory[quorumNumber][index];

        // blocknumber must be at or after the "index'th" entry's fromBlockNumber
        require(
            blockNumber >= quorumUpdate.fromBlockNumber, 
            "IndexRegistry.getTotalOperatorsForQuorumAtBlockNumberByIndex: provided index is too far in the past for provided block number"
        );
        
        // if there is an index update after the "index'th" update, the blocknumber must be before the next entry's fromBlockNumber
        if (index != _totalOperatorsHistory[quorumNumber].length - 1){
            QuorumUpdate memory nextQuorumUpdate = _totalOperatorsHistory[quorumNumber][index + 1];
            require(
                blockNumber < nextQuorumUpdate.fromBlockNumber, 
                "IndexRegistry.getTotalOperatorsForQuorumAtBlockNumberByIndex: provided index is too far in the future for provided block number"
            );
        }
        return quorumUpdate.numOperators;
    }

    /// @notice Returns an ordered list of operators of the services for the given `quorumNumber` at the given `blockNumber`
    function getOperatorListForQuorumAtBlockNumber(
        uint8 quorumNumber, 
        uint32 blockNumber
    ) external view returns (bytes32[] memory){
        bytes32[] memory quorumOperatorList = new bytes32[](_getTotalOperatorsForQuorumAtBlockNumber(quorumNumber, blockNumber));
        for (uint256 i = 0; i < quorumOperatorList.length; i++) {
            quorumOperatorList[i] = _getOperatorIdAtIndexForQuorumAtBlockNumber(uint32(i), quorumNumber, blockNumber);
            require(
                quorumOperatorList[i] != OPERATOR_DOES_NOT_EXIST_ID, 
                "IndexRegistry.getOperatorListForQuorumAtBlockNumber: operator does not exist at the given block number"
            );
        }
        return quorumOperatorList;
    }

    /// @notice Returns the total number of operators for a given `quorumNumber`
    function totalOperatorsForQuorum(uint8 quorumNumber) external view returns (uint32){
        return _totalOperatorsForQuorum(quorumNumber);
    }
}

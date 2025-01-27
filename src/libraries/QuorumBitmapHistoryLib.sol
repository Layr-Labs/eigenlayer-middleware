// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    ISlashingRegistryCoordinator,
    ISlashingRegistryCoordinatorTypes
} from "../interfaces/ISlashingRegistryCoordinator.sol";

/// @title QuorumBitmapHistoryLib
/// @notice This library operates on the _operatorBitmapHistory in the RegistryCoordinator
library QuorumBitmapHistoryLib {
    /// @dev Thrown when the quorum bitmap update is not found
    error BitmapUpdateNotFound();
    /// @dev Thrown when quorum bitmap update is after the block number
    error BitmapUpdateIsAfterBlockNumber();
    /// @dev Thrown when the next update block number is not 0 and strictly greater than blockNumber
    error NextBitmapUpdateIsBeforeBlockNumber();

    /// @notice Retrieves the index of the quorum bitmap update at or before the specified block number
    /// @param self The mapping of operator IDs to their quorum bitmap update history
    /// @param blockNumber The block number to search for
    /// @param operatorId The ID of the operator
    /// @return index The index of the quorum bitmap update
    function getQuorumBitmapIndexAtBlockNumber(
        mapping(bytes32 => ISlashingRegistryCoordinator.QuorumBitmapUpdate[]) storage self,
        uint32 blockNumber,
        bytes32 operatorId
    ) internal view returns (uint32 index) {
        uint256 length = self[operatorId].length;

        // Traverse the operator's bitmap history in reverse, returning the first index
        // corresponding to an update made before or at `blockNumber`
        for (uint256 i = 0; i < length; i++) {
            index = uint32(length - i - 1);

            if (self[operatorId][index].updateBlockNumber <= blockNumber) {
                return index;
            }
        }

        revert(
            "RegistryCoordinator.getQuorumBitmapIndexAtBlockNumber: no bitmap update found for operatorId"
        );
    }

    /// @notice Retrieves the current quorum bitmap for the given operator ID
    /// @param self The mapping of operator IDs to their quorum bitmap update history
    /// @param operatorId The ID of the operator
    /// @return The current quorum bitmap
    function currentOperatorBitmap(
        mapping(bytes32 => ISlashingRegistryCoordinator.QuorumBitmapUpdate[]) storage self,
        bytes32 operatorId
    ) internal view returns (uint192) {
        uint256 historyLength = self[operatorId].length;
        if (historyLength == 0) {
            return 0;
        } else {
            return self[operatorId][historyLength - 1].quorumBitmap;
        }
    }

    /// @notice Retrieves the indices of the quorum bitmap updates for the given operator IDs at the specified block number
    /// @param self The mapping of operator IDs to their quorum bitmap update history
    /// @param blockNumber The block number to search for
    /// @param operatorIds The array of operator IDs
    /// @return An array of indices corresponding to the quorum bitmap updates
    function getQuorumBitmapIndicesAtBlockNumber(
        mapping(bytes32 => ISlashingRegistryCoordinator.QuorumBitmapUpdate[]) storage self,
        uint32 blockNumber,
        bytes32[] memory operatorIds
    ) internal view returns (uint32[] memory) {
        uint32[] memory indices = new uint32[](operatorIds.length);
        for (uint256 i = 0; i < operatorIds.length; i++) {
            indices[i] = getQuorumBitmapIndexAtBlockNumber(self, blockNumber, operatorIds[i]);
        }
        return indices;
    }

    /// @notice Retrieves the quorum bitmap for the given operator ID at the specified block number and index
    /// @param self The mapping of operator IDs to their quorum bitmap update history
    /// @param operatorId The ID of the operator
    /// @param blockNumber The block number to validate against
    /// @param index The index of the quorum bitmap update
    /// @return The quorum bitmap at the specified index
    function getQuorumBitmapAtBlockNumberByIndex(
        mapping(bytes32 => ISlashingRegistryCoordinator.QuorumBitmapUpdate[]) storage self,
        bytes32 operatorId,
        uint32 blockNumber,
        uint256 index
    ) internal view returns (uint192) {
        ISlashingRegistryCoordinator.QuorumBitmapUpdate memory quorumBitmapUpdate =
            self[operatorId][index];

        /**
         * Validate that the update is valid for the given blockNumber:
         * - blockNumber should be >= the update block number
         * - the next update block number should be either 0 or strictly greater than blockNumber
         */
        require(
            blockNumber >= quorumBitmapUpdate.updateBlockNumber, BitmapUpdateIsAfterBlockNumber()
        );
        require(
            quorumBitmapUpdate.nextUpdateBlockNumber == 0
                || blockNumber < quorumBitmapUpdate.nextUpdateBlockNumber,
            NextBitmapUpdateIsBeforeBlockNumber()
        );

        return quorumBitmapUpdate.quorumBitmap;
    }

    /// @notice Updates the quorum bitmap for the given operator ID
    /// @param self The mapping of operator IDs to their quorum bitmap update history
    /// @param operatorId The ID of the operator
    /// @param newBitmap The new quorum bitmap to set
    function updateOperatorBitmap(
        mapping(bytes32 => ISlashingRegistryCoordinator.QuorumBitmapUpdate[]) storage self,
        bytes32 operatorId,
        uint192 newBitmap
    ) internal {
        uint256 historyLength = self[operatorId].length;

        if (historyLength == 0) {
            // No prior bitmap history - push our first entry
            self[operatorId].push(
                ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                    updateBlockNumber: uint32(block.number),
                    nextUpdateBlockNumber: 0,
                    quorumBitmap: newBitmap
                })
            );
        } else {
            // We have prior history - fetch our last-recorded update
            ISlashingRegistryCoordinator.QuorumBitmapUpdate storage lastUpdate =
                self[operatorId][historyLength - 1];

            /**
             * If the last update was made in the current block, update the entry.
             * Otherwise, push a new entry and update the previous entry's "next" field
             */
            if (lastUpdate.updateBlockNumber == uint32(block.number)) {
                lastUpdate.quorumBitmap = newBitmap;
            } else {
                lastUpdate.nextUpdateBlockNumber = uint32(block.number);
                self[operatorId].push(
                    ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                        updateBlockNumber: uint32(block.number),
                        nextUpdateBlockNumber: 0,
                        quorumBitmap: newBitmap
                    })
                );
            }
        }
    }
}

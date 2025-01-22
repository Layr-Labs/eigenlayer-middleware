// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

interface IIndexRegistryEvents {
    // emitted when an operator's index in the ordered operator list for the quorum with number `quorumNumber` is updated
    event QuorumIndexUpdate(
        bytes32 indexed operatorId, uint8 quorumNumber, uint32 newOperatorIndex
    );
}

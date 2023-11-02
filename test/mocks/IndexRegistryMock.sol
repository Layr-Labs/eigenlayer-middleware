// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {IIndexRegistry} from "src/interfaces/IIndexRegistry.sol";
import {IRegistryCoordinator} from "src/interfaces/IRegistryCoordinator.sol";

// Mock contract for IndexRegistry that allows setting totalOperatorsForQuorum and implements IIndexRegistry interface
contract IndexRegistryMock is IIndexRegistry {
    uint32[256] _totalOperatorsForQuorum;

    function registryCoordinator() external view returns (IRegistryCoordinator) {}

    function registerOperator(bytes32 operatorId, bytes calldata quorumNumbers) external returns(uint32[] memory) {}

    function deregisterOperator(bytes32 operatorId, bytes calldata quorumNumbers) external {}

    function getOperatorIndexUpdateOfIndexForQuorumAtIndex(uint32 operatorIndex, uint8 quorumNumber, uint32 index) external view returns (OperatorUpdate memory) {}

    function getQuorumUpdateAtIndex(uint8 quorumNumber, uint32 index) external view returns (QuorumUpdate memory) {}

    function getTotalOperatorsForQuorumAtBlockNumberByIndex(uint8 quorumNumber, uint32 blockNumber, uint32 index) external view returns (uint32) {}

    function totalOperatorsForQuorum(uint8 quorumNumber) external view returns (uint32) {
        return _totalOperatorsForQuorum[quorumNumber];
    }

    function getOperatorListForQuorumAtBlockNumber(uint8 quorumNumber, uint32 blockNumber) external view returns (bytes32[] memory) {}

    function setTotalOperatorsForQuorum(uint256 quorumNumber, uint32 numOperators) external {
        _totalOperatorsForQuorum[quorumNumber] = numOperators;
    }
}

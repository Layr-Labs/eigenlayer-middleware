// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "src/IndexRegistry.sol";

contract IndexRegistryHarness is IndexRegistry {
    constructor(
        IRegistryCoordinator _registryCoordinator
    ) IndexRegistry(_registryCoordinator) {}

    function operatorIndexHistory(uint8 quorumNumber, uint32 operatorIndex) public view returns (OperatorUpdate[] memory) {
        return _operatorIndexHistory[quorumNumber][operatorIndex];
    }

    function operatorCountHistory(uint8 quorumNumber) public view returns (QuorumUpdate[] memory) {
        return _operatorCountHistory[quorumNumber];
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../../src/StakeRegistry.sol";

// wrapper around the StakeRegistry contract that exposes the internal functions for unit testing.
contract StakeRegistryHarness is StakeRegistry {
    constructor(
        ISlashingRegistryCoordinator _registryCoordinator,
        IDelegationManager _delegationManager,
        IAVSDirectory _avsDirectory,
        IAllocationManager _allocationManager
    ) StakeRegistry(_registryCoordinator, _delegationManager, _avsDirectory, _allocationManager) {}

    function recordOperatorStakeUpdate(
        bytes32 operatorId,
        uint8 quorumNumber,
        uint96 newStake
    ) external returns (int256) {
        return _recordOperatorStakeUpdate(operatorId, quorumNumber, newStake);
    }

    function recordTotalStakeUpdate(uint8 quorumNumber, int256 stakeDelta) external {
        _recordTotalStakeUpdate(quorumNumber, stakeDelta);
    }

    function calculateDelta(uint96 prev, uint96 cur) external pure returns (int256) {
        return _calculateDelta(prev, cur);
    }

    function applyDelta(uint96 value, int256 delta) external pure returns (uint96) {
        return _applyDelta(value, delta);
    }
}

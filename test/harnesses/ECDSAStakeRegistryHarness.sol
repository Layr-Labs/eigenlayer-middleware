// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "../../src/unaudited/ECDSAStakeRegistry.sol";

// Wrapper around the ECDSAStakeRegistry contract that exposes the internal functions for unit testing.
contract ECDSAStakeRegistryHarness is ECDSAStakeRegistry {
    constructor(
        IDelegationManager _delegationManager
    ) ECDSAStakeRegistry(_delegationManager) {
    }

    function recordOperatorStakeUpdate(address operator, uint96 newStake) external returns (int256) {
        return _updateOperatorWeight(operator);
    }

    function recordTotalStakeUpdate(int256 stakeDelta) external {
        _updateTotalWeight(stakeDelta);
    }
}

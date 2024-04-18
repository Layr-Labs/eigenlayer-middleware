// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "src/StakeRegistry.sol";

contract StakeRegistryHarness is StakeRegistry {
    constructor(
        IRegistryCoordinator _registryCoordinator,
        IDelegationManager _delegationManager
    ) StakeRegistry(_registryCoordinator, _delegationManager) {}

    function totalStakeHistory(uint8 quorumNumber) public view returns (StakeUpdate[] memory) {
        return _totalStakeHistory[quorumNumber];
    }
}

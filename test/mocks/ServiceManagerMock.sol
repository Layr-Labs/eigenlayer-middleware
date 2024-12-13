// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../../src/ServiceManagerBase.sol";

contract ServiceManagerMock is ServiceManagerBase {
    constructor(
        IAVSDirectory _avsDirectory,
        IRewardsCoordinator _rewardsCoordinator,
        IRegistryCoordinator _registryCoordinator,
        IStakeRegistry _stakeRegistry,
        IAllocationManager _allocationManager
    )
        ServiceManagerBase(
            _avsDirectory,
            _rewardsCoordinator,
            _registryCoordinator,
            _stakeRegistry,
            _allocationManager
        )
    {}

    function initialize(
        address initialOwner,
        address rewardsInitiator,
        address slasher
    ) public virtual initializer {
        __ServiceManagerBase_init(initialOwner, rewardsInitiator, slasher);
    }
}

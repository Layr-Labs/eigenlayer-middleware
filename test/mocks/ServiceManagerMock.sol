// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../../src/ServiceManagerBase.sol";

contract ServiceManagerMock is ServiceManagerBase {
    constructor(
        IAVSDirectory _avsDirectory,
        IRewardsCoordinator _rewardsCoordinator,
        ISlashingRegistryCoordinator _slashingRegistryCoordinator,
        IStakeRegistry _stakeRegistry,
        IPermissionController _permissionController,
        IAllocationManager _allocationManager
    )
        ServiceManagerBase(
            _avsDirectory,
            _rewardsCoordinator,
            _slashingRegistryCoordinator,
            _stakeRegistry,
            _permissionController,
            _allocationManager
        )
    {}

    function initialize(
        address initialOwner,
        address rewardsInitiator
    ) public virtual initializer {
        __ServiceManagerBase_init(initialOwner, rewardsInitiator);
    }

    function slashOperator(
        IAllocationManager.SlashingParams memory _params
    ) public {
        _allocationManager.slashOperator({avs: address(this), params: _params});
    }
}

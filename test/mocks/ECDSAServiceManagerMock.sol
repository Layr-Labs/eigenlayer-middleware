// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../../src/unaudited/ECDSAServiceManagerBase.sol";
import {IAllocationManagerTypes} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

contract ECDSAServiceManagerMock is ECDSAServiceManagerBase {
    constructor(
        address _avsDirectory,
        address _stakeRegistry,
        address _rewardsCoordinator,
        address _delegationManager,
        address _allocationManager,
        address _permissionController,
        address _initialOwner,
        address _rewardsInitiator
    )
        ECDSAServiceManagerBase(
            _avsDirectory,
            _stakeRegistry,
            _rewardsCoordinator,
            _delegationManager,
            _allocationManager,
            _permissionController
        )
    {
        // disable initializer and directly set owner and rewardsInitiator for testing
        _transferOwnership(_initialOwner);
        _setRewardsInitiator(_rewardsInitiator);
    }

    // function initialize(
    //     address initialOwner,
    //     address rewardsInitiator
    // ) public virtual initializer {
    //     __ServiceManagerBase_init(initialOwner, rewardsInitiator);
    // }
}

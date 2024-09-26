// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "../../src/unaudited/ECDSAServiceManagerBase.sol";

contract ECDSAServiceManagerMock is ECDSAServiceManagerBase {
    constructor(
        address _avsDirectory,
        address _stakeRegistry,
        address _rewardsCoordinator,
        address _delegationManager
    )
        ECDSAServiceManagerBase(_avsDirectory, _stakeRegistry, _rewardsCoordinator, _delegationManager)
    {}

    function initialize(
        address initialOwner,
        address rewardsInitiator
    ) public virtual initializer {
        __ServiceManagerBase_init(initialOwner, rewardsInitiator);
    }
}

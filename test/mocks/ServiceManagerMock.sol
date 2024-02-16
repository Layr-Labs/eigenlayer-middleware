// SPDX-License-Identifier: BUSL-1.1
<<<<<<< HEAD
pragma solidity ^0.8.12;
=======
pragma solidity =0.8.12;
>>>>>>> fixes(m2-mainnet): combined pr for all m2-mainnet fixs (#162)

import "../../src/ServiceManagerBase.sol";

contract ServiceManagerMock is ServiceManagerBase {
    constructor(
        IAVSDirectory _avsDirectory,
<<<<<<< HEAD
        IRewardsCoordinator _rewardsCoordinator,
        IRegistryCoordinator _registryCoordinator,
        IStakeRegistry _stakeRegistry
    )
        ServiceManagerBase(_avsDirectory, _rewardsCoordinator, _registryCoordinator, _stakeRegistry)
    {}

    function initialize(
        address initialOwner,
        address rewardsInitiator
    ) public virtual initializer {
        __ServiceManagerBase_init(initialOwner, rewardsInitiator);
=======
        IRegistryCoordinator _registryCoordinator,
        IStakeRegistry _stakeRegistry
    ) ServiceManagerBase(_avsDirectory, _registryCoordinator, _stakeRegistry) {}

    function initialize(address initialOwner) public virtual initializer {
        __ServiceManagerBase_init(initialOwner);
>>>>>>> fixes(m2-mainnet): combined pr for all m2-mainnet fixs (#162)
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "../../src/ServiceManagerBase.sol";

contract ServiceManagerMock is ServiceManagerBase {
    constructor(IDelegationManager _delegationManager, IRegistryCoordinator _registryCoordinator, IStakeRegistry _stakeRegistry) ServiceManagerBase(_delegationManager, _registryCoordinator, _stakeRegistry){}

}

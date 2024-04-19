// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "../../src/ServiceManagerBase.sol";

contract ServiceManagerMock is ServiceManagerBase {
    constructor(
        IAVSDirectory _avsDirectory,
        IRegistryCoordinator _registryCoordinator,
        IStakeRegistry _stakeRegistry,
        IPaymentCoordinator _paymentCoordinator
    ) ServiceManagerBase(_avsDirectory, _registryCoordinator, _stakeRegistry, _paymentCoordinator) {}

    function initialize(address initialOwner) public virtual initializer {
        __ServiceManagerBase_init(initialOwner);
    }
}

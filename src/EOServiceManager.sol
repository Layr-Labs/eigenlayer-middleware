// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {ServiceManagerBase, IAVSDirectory, IEORegistryCoordinator, IEOStakeRegistry} from "./ServiceManagerBase.sol";

contract EOServiceManager is ServiceManagerBase {
    constructor(
        IAVSDirectory _avsDirectory,
        IEORegistryCoordinator _registryCoordinator,
        IEOStakeRegistry _stakeRegistry
    ) ServiceManagerBase(_avsDirectory, _registryCoordinator, _stakeRegistry) {}

    function initialize(address initialOwner) public virtual initializer {
        __ServiceManagerBase_init(initialOwner);
    }
}

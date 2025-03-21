// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ServiceManagerBase, ServiceManagerBaseStorage} from "../../src/ServiceManagerBase.sol";
import {IRegistryCoordinator} from "../../src/interfaces/IRegistryCoordinator.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IRewardsCoordinator} from
    "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {ISlashingRegistryCoordinator} from "../../src/interfaces/ISlashingRegistryCoordinator.sol";
import {IStakeRegistry} from "../../src/interfaces/IStakeRegistry.sol";
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

/**
 * @title MockServiceManager
 * @dev Implementation of a mock ServiceManager for testing
 */
contract MockServiceManager is ServiceManagerBase {
    address private _rewardsInitiator;

    /// @notice Sets the (immutable) `_registryCoordinator` address
    constructor(
        IAVSDirectory __avsDirectory,
        IRewardsCoordinator __rewardsCoordinator,
        ISlashingRegistryCoordinator __registryCoordinator,
        IStakeRegistry __stakeRegistry,
        IPermissionController __permissionController,
        IAllocationManager __allocationManager
    )
        ServiceManagerBase(
            __avsDirectory,
            __rewardsCoordinator,
            __registryCoordinator,
            __stakeRegistry,
            __permissionController,
            __allocationManager
        )
    {
        _disableInitializers();
    }

    function initialize(address owner, address rewardsInitiator) external {
        _rewardsInitiator = rewardsInitiator;
    }
}

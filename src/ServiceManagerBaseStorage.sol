// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

import {IServiceManager} from "./interfaces/IServiceManager.sol";
import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";

import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

/**
 * @title Storage variables for the `ServiceManagerBase` contract.
 * @author Layr Labs, Inc.
 * @notice This storage contract is separate from the logic to simplify the upgrade process.
 */
abstract contract ServiceManagerBaseStorage is IServiceManager, OwnableUpgradeable {
    /**
     *
     *                            CONSTANTS AND IMMUTABLES
     *
     */
    IAVSDirectory internal immutable _avsDirectory;
    IRewardsCoordinator internal immutable _rewardsCoordinator;
    IRegistryCoordinator internal immutable _registryCoordinator;
    IStakeRegistry internal immutable _stakeRegistry;
    IAllocationManager internal immutable _allocationManager;

    /**
     *
     *                            STATE VARIABLES
     *
     */

    /// @notice The address of the entity that can initiate rewards
    address public rewardsInitiator;

    /// @notice The address of the slasher account
    address public slasher;

    /// @notice The address of the proposed slasher account
    address public proposedSlasher;

    /// @notice The timestamp when the slasher was proposed
    uint256 public slasherProposalTimestamp;

    /// @notice Boolean indicating if the migration has been finalized
    bool public migrationFinalized;

    /// @notice Sets the (immutable) `_avsDirectory`, `_rewardsCoordinator`, `_registryCoordinator`, `_stakeRegistry`, and `_allocationManager` addresses
    constructor(
        IAVSDirectory __avsDirectory,
        IRewardsCoordinator __rewardsCoordinator,
        IRegistryCoordinator __registryCoordinator,
        IStakeRegistry __stakeRegistry,
        IAllocationManager __allocationManager
    ) {
        _avsDirectory = __avsDirectory;
        _rewardsCoordinator = __rewardsCoordinator;
        _registryCoordinator = __registryCoordinator;
        _stakeRegistry = __stakeRegistry;
        _allocationManager = __allocationManager;
    }

    // storage gap for upgradeability
    uint256[45] private __GAP;
}

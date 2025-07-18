// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {ISlashingRegistryCoordinator} from "../../interfaces/ISlashingRegistryCoordinator.sol";
import {ISlasher} from "../../interfaces/ISlasher.sol";

/// @title SlasherStorage
/// @notice Base storage contract for slashing functionality
/// @dev Provides storage variables and events for slashing operations
abstract contract SlasherStorage is ISlasher {
    /**
     *
     *                            CONSTANTS AND IMMUTABLES
     *
     */

    /// @notice The `AllocationManager` tracks operator sets, operator set allocations, and slashing in EigenLayer.
    IAllocationManager public immutable allocationManager;
    /// @notice The `StrategyManager` handles strategy inflows/outflows.
    IStrategyManager public immutable strategyManager;
    /// @notice The `SlashingRegistryCoordinator` for this AVS.
    ISlashingRegistryCoordinator public immutable slashingRegistryCoordinator;

    /// @notice the address of the slasher
    address public immutable slasher;

    /// @dev DEPRECATED -- `AllocationManager` now tracks monotonically increasing `slashId`.
    uint256 private __deprecated_nextRequestId;

    constructor(
        IAllocationManager _allocationManager,
        IStrategyManager _strategyManager,
        ISlashingRegistryCoordinator _slashingRegistryCoordinator,
        address _slasher
    ) {
        allocationManager = _allocationManager;
        strategyManager = _strategyManager;
        slashingRegistryCoordinator = _slashingRegistryCoordinator;
        slasher = _slasher;
    }

    uint256[49] private __gap;
}

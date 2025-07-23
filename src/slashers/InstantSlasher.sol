// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {SlasherBase} from "./base/SlasherBase.sol";
import {ISlashingRegistryCoordinator} from "../interfaces/ISlashingRegistryCoordinator.sol";
import {IInstantSlasher} from "../interfaces/IInstantSlasher.sol";

/// @title InstantSlasher
/// @notice A slashing contract that immediately executes slashing requests without any delay or veto period
/// @dev Extends SlasherBase to provide access controlled slashing functionality
contract InstantSlasher is IInstantSlasher, SlasherBase {
    constructor(
        IAllocationManager _allocationManager,
        IStrategyManager _strategyManager,
        ISlashingRegistryCoordinator _slashingRegistryCoordinator,
        address _slasher
    ) SlasherBase(_allocationManager, _strategyManager, _slashingRegistryCoordinator, _slasher) {}

    /// @inheritdoc IInstantSlasher
    function fulfillSlashingRequest(
        IAllocationManager.SlashingParams calldata params
    ) external virtual override(IInstantSlasher) onlySlasher returns (uint256 slashId) {
        slashId = _fulfillSlashingRequest(params);
    }

    /// @inheritdoc IInstantSlasher
    function fulfillSlashingRequestAndBurnOrRedistribute(
        IAllocationManager.SlashingParams calldata params
    ) external virtual override onlySlasher returns (uint256 slashId) {
        slashId = _fulfillSlashingRequestAndBurnOrRedistribute(params);
    }
}

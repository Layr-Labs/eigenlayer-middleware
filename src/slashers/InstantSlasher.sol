// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {SlasherBase} from "./base/SlasherBase.sol";
import {ISlashingRegistryCoordinator} from "../interfaces/ISlashingRegistryCoordinator.sol";
import {IInstantSlasher} from "../interfaces/IInstantSlasher.sol";

/// @title InstantSlasher
/// @notice A slashing contract that immediately executes slashing requests without any delay or veto period
/// @dev Extends SlasherBase to provide access controlled slashing functionality
contract InstantSlasher is IInstantSlasher, SlasherBase {
    constructor(
        IAllocationManager _allocationManager,
        ISlashingRegistryCoordinator _slashingRegistryCoordinator,
        address _slasher
    ) SlasherBase(_allocationManager, _slashingRegistryCoordinator, _slasher) {}

    /// @inheritdoc IInstantSlasher
    function fulfillSlashingRequest(
        IAllocationManager.SlashingParams calldata _slashingParams
    ) external virtual override(IInstantSlasher) onlySlasher {
        uint256 requestId = nextRequestId++;
        _fulfillSlashingRequest(requestId, _slashingParams);

        address[] memory operators = new address[](1);
        operators[0] = _slashingParams.operator;
        slashingRegistryCoordinator.updateOperators(operators);
    }
}

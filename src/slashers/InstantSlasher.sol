// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {SlasherBase} from "./base/SlasherBase.sol";
import {ISlashingRegistryCoordinator} from "../interfaces/ISlashingRegistryCoordinator.sol";

/// @title InstantSlasher
/// @notice A slashing contract that immediately executes slashing requests without any delay or veto period
/// @dev Extends SlasherBase to provide access controlled slashing functionality
contract InstantSlasher is SlasherBase {
    constructor(
        IAllocationManager _allocationManager,
        ISlashingRegistryCoordinator _slashingRegistryCoordinator,
        address _slasher
    ) SlasherBase(_allocationManager, _slashingRegistryCoordinator) {}

    /// @notice Initializes the contract with a slasher address
    /// @param _slasher Address authorized to create and fulfill slashing requests
    function initialize(
        address _slasher
    ) external initializer {
        __SlasherBase_init(_slasher);
    }

    /// @notice Immediately executes a slashing request
    /// @param _slashingParams Parameters defining the slashing request including operator and amount
    /// @dev Can only be called by the authorized slasher
    function fulfillSlashingRequest(
        IAllocationManager.SlashingParams memory _slashingParams
    ) external virtual onlySlasher {
        uint256 requestId = nextRequestId++;
        _fulfillSlashingRequest(requestId, _slashingParams);
    }
}

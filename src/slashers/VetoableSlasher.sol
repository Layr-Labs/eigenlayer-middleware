// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {SlasherBase} from "./base/SlasherBase.sol";
import {ISlashingRegistryCoordinator} from "../interfaces/ISlashingRegistryCoordinator.sol";

/// @title VetoableSlasher
/// @notice A slashing contract that implements a veto mechanism allowing a designated committee to cancel slashing requests
/// @dev Extends SlasherBase and adds a veto period during which slashing requests can be cancelled
contract VetoableSlasher is SlasherBase {
    /// @notice Duration of the veto period during which the veto committee can cancel slashing requests
    /// @dev Set to 3 days (259,200 seconds)
    uint256 public constant VETO_PERIOD = 3 days;

    /// @notice Address of the committee that has veto power over slashing requests
    address public vetoCommittee;

    /// @notice Mapping of request IDs to their corresponding slashing request details
    mapping(uint256 => SlashingRequest) public slashingRequests;

    /// @notice Modifier to restrict function access to only the veto committee
    modifier onlyVetoCommittee() {
        _checkVetoCommittee(msg.sender);
        _;
    }

    constructor(
        IAllocationManager _allocationManager,
        ISlashingRegistryCoordinator _slashingRegistryCoordinator
    ) SlasherBase(_allocationManager, _slashingRegistryCoordinator) {}

    /// @notice Initializes the contract with a veto committee and slasher address
    /// @param _vetoCommittee Address of the committee that can veto slashing requests
    /// @param _slasher Address authorized to create and fulfill slashing requests
    function initialize(address _vetoCommittee, address _slasher) external virtual initializer {
        __SlasherBase_init(_slasher);
        vetoCommittee = _vetoCommittee;
    }

    /// @notice Queues a new slashing request
    /// @param params Parameters defining the slashing request including operator and amount
    /// @dev Can only be called by the authorized slasher
    function queueSlashingRequest(
        IAllocationManager.SlashingParams calldata params
    ) external virtual onlySlasher {
        _queueSlashingRequest(params);
    }

    /// @notice Cancels a pending slashing request
    /// @param requestId The ID of the slashing request to cancel
    /// @dev Can only be called by the veto committee during the veto period
    function cancelSlashingRequest(
        uint256 requestId
    ) external virtual onlyVetoCommittee {
        require(
            block.timestamp < slashingRequests[requestId].requestTimestamp + VETO_PERIOD,
            VetoPeriodPassed()
        );
        require(
            slashingRequests[requestId].status == SlashingStatus.Requested,
            SlashingRequestNotRequested()
        );

        _cancelSlashingRequest(requestId);
    }

    /// @notice Executes a slashing request after the veto period has passed
    /// @param requestId The ID of the slashing request to fulfill
    /// @dev Can only be called by the authorized slasher after the veto period
    function fulfillSlashingRequest(
        uint256 requestId
    ) external virtual onlySlasher {
        SlashingRequest storage request = slashingRequests[requestId];
        require(block.timestamp >= request.requestTimestamp + VETO_PERIOD, VetoPeriodNotPassed());
        require(request.status == SlashingStatus.Requested, SlashingRequestIsCancelled());

        request.status = SlashingStatus.Completed;

        _fulfillSlashingRequest(requestId, request.params);
    }

    /// @notice Internal function to create and store a new slashing request
    /// @param params Parameters defining the slashing request
    /// @dev Emits a SlashingRequested event
    function _queueSlashingRequest(
        IAllocationManager.SlashingParams calldata params
    ) internal virtual {
        uint256 requestId = nextRequestId++;
        slashingRequests[requestId] = SlashingRequest({
            params: params,
            requestTimestamp: block.timestamp,
            status: SlashingStatus.Requested
        });

        emit SlashingRequested(
            requestId, params.operator, params.operatorSetId, params.wadsToSlash, params.description
        );
    }

    /// @notice Internal function to mark a slashing request as cancelled
    /// @param requestId The ID of the slashing request to cancel
    /// @dev Emits a SlashingRequestCancelled event
    function _cancelSlashingRequest(
        uint256 requestId
    ) internal virtual {
        slashingRequests[requestId].status = SlashingStatus.Cancelled;
        emit SlashingRequestCancelled(requestId);
    }

    /// @notice Internal function to verify if an account is the veto committee
    /// @param account The address to check
    /// @dev Reverts if the account is not the veto committee
    function _checkVetoCommittee(
        address account
    ) internal view virtual {
        require(account == vetoCommittee, OnlyVetoCommittee());
    }
}

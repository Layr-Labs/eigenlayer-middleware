// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {ISlasher} from "./ISlasher.sol";

interface IVetoableSlasherErrors {
    /// @notice Thrown when a caller without veto committee privileges attempts a restricted operation
    error OnlyVetoCommittee();
    /// @notice Thrown when attempting to veto a slashing request after the veto period has expired
    error VetoPeriodPassed();
    /// @notice Thrown when attempting to execute a slashing request before the veto period has ended
    error VetoPeriodNotPassed();
    /// @notice Thrown when attempting to interact with a slashing request that has been cancelled
    error SlashingRequestIsCancelled();
    /// @notice Thrown when attempting to modify a slashing request that does not exist
    error SlashingRequestNotRequested();
}

interface IVetoableSlasherTypes {
    /// @notice Represents the status of a slashing request
    enum SlashingStatus {
        Requested,
        Cancelled,
        Completed
    }

    /// @notice Structure containing details about a vetoable slashing request
    struct VetoableSlashingRequest {
        IAllocationManager.SlashingParams params;
        uint256 requestTimestamp;
        SlashingStatus status;
    }
}

interface IVetoableSlasherEvents {
    /// @notice Emitted when a new slashing request is created
    event SlashingRequested(
        uint256 indexed requestId,
        address indexed operator,
        uint32 operatorSetId,
        uint256[] wadsToSlash,
        string description
    );

    /// @notice Emitted when a slashing request is cancelled by the veto committee
    event SlashingRequestCancelled(uint256 indexed requestId);
}

/// @title IVetoableSlasher
/// @notice A slashing contract that implements a veto mechanism allowing a designated committee to cancel slashing requests
/// @dev Extends base interfaces and adds a veto period during which slashing requests can be cancelled
interface IVetoableSlasher is
    ISlasher,
    IVetoableSlasherErrors,
    IVetoableSlasherTypes,
    IVetoableSlasherEvents
{
    /// @notice Duration of the veto period during which the veto committee can cancel slashing requests
    /// @dev Set to 3 days (259,200 seconds)
    function VETO_PERIOD() external view returns (uint256);

    /// @notice Address of the committee that has veto power over slashing requests
    function vetoCommittee() external view returns (address);

    /// @notice Initializes the contract with a veto committee and slasher address
    /// @param _vetoCommittee Address of the committee that can veto slashing requests
    /// @param _slasher Address authorized to create and fulfill slashing requests
    function initialize(address _vetoCommittee, address _slasher) external;

    /// @notice Queues a new slashing request
    /// @param params Parameters defining the slashing request including operator and amount
    /// @dev Can only be called by the authorized slasher
    function queueSlashingRequest(
        IAllocationManager.SlashingParams calldata params
    ) external;

    /// @notice Cancels a pending slashing request
    /// @param requestId The ID of the slashing request to cancel
    /// @dev Can only be called by the veto committee during the veto period
    function cancelSlashingRequest(
        uint256 requestId
    ) external;

    /// @notice Executes a slashing request after the veto period has passed
    /// @param requestId The ID of the slashing request to fulfill
    /// @dev Can only be called by the authorized slasher after the veto period
    function fulfillSlashingRequest(
        uint256 requestId
    ) external;
}

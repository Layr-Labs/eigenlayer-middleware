// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

interface ISlasherErrors {
    /// @notice Thrown when a caller without veto committee privileges attempts a restricted operation.
    error OnlyVetoCommittee();
    /// @notice Thrown when a caller without slasher privileges attempts a restricted operation.
    error OnlySlasher();
    /// @notice Thrown when attempting to veto a slashing request after the veto period has expired.
    error VetoPeriodPassed();
    /// @notice Thrown when attempting to execute a slashing request before the veto period has ended.
    error VetoPeriodNotPassed();
    /// @notice Thrown when attempting to interact with a slashing request that has been cancelled.
    error SlashingRequestIsCancelled();
    /// @notice Thrown when attempting to modify a slashing request that does not exist.
    error SlashingRequestNotRequested();
}

interface ISlasherTypes {
    /**
     * @notice Represents the current status of a slashing request.
     * @dev The status of a slashing request can be one of the following:
     *      - Null: Default state, no request exists.
     *      - Requested: Slashing has been requested but not yet executed.
     *      - Completed: Slashing has been successfully executed.
     *      - Cancelled: Slashing request was cancelled by veto committee.
     */
    enum SlashingStatus {
        Null,
        Requested,
        Completed,
        Cancelled
    }

    /**
     * @notice Contains all information related to a slashing request.
     * @param params The slashing parameters from the allocation manager.
     * @param requestTimestamp The timestamp when the slashing request was created.
     * @param status The current status of the slashing request.
     */
    struct SlashingRequest {
        IAllocationManager.SlashingParams params;
        uint256 requestTimestamp;
        SlashingStatus status;
    }
}

interface ISlasherEvents is ISlasherTypes {
    /**
     * @notice Emitted when a new slashing request is created.
     * @param requestId The unique identifier for the slashing request (indexed).
     * @param operator The address of the operator to be slashed (indexed).
     * @param operatorSetId The ID of the operator set involved (indexed).
     * @param wadsToSlash The amounts to slash from each strategy.
     * @param description A human-readable description of the slashing reason.
     */
    event SlashingRequested(
        uint256 indexed requestId,
        address indexed operator,
        uint32 indexed operatorSetId,
        uint256[] wadsToSlash,
        string description
    );

    /**
     * @notice Emitted when a slashing request is cancelled by the veto committee.
     * @param requestId The unique identifier of the cancelled request (indexed).
     */
    event SlashingRequestCancelled(uint256 indexed requestId);

    /**
     * @notice Emitted when an operator is successfully slashed.
     * @param slashingRequestId The ID of the executed slashing request (indexed).
     * @param operator The address of the slashed operator (indexed).
     * @param operatorSetId The ID of the operator set involved (indexed).
     * @param wadsToSlash The amounts slashed from each strategy.
     * @param description A human-readable description of why the operator was slashed.
     */
    event OperatorSlashed(
        uint256 indexed slashingRequestId,
        address indexed operator,
        uint32 indexed operatorSetId,
        uint256[] wadsToSlash,
        string description
    );
}

interface ISlasher is ISlasherErrors, ISlasherEvents {}

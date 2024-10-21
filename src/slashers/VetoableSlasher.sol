// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {SlasherBase} from "./SlasherBase.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

contract VetoableSlashing is SlasherBase {
    struct SlashingRequest {
        IAllocationManager.SlashingParams params;
        uint256 requestTimestamp;
        SlashingStatus status;
    }

    uint256 public constant VETO_PERIOD = 3 days;
    address public vetoCommittee;
    uint256 public nextRequestId;
    mapping(uint256 => SlashingRequest) public slashingRequests;

    event SlashingRequested(
        uint256 indexed requestId,
        address indexed operator,
        uint32 indexed operatorSetId,
        uint256 wadToSlash,
        string description
    );

    event SlashingRequestCancelled(uint256 indexed requestId);

    modifier onlyVetoCommittee() {
        require(msg.sender == vetoCommittee, "VetoableSlashing: caller is not the veto committee");
        _;
    }

    function initialize(address _serviceManager, address _vetoCommittee) external virtual initializer {
        __SlasherBase_init(_serviceManager);
        vetoCommittee = _vetoCommittee;
    }

    function queueSlashingRequest(IAllocationManager.SlashingParams memory params) external virtual {
        _queueSlashingRequest(params);
    }

    function cancelSlashingRequest(uint256 requestId) external virtual onlyVetoCommittee {
        require(
            block.timestamp < slashingRequests[requestId].requestTimestamp + VETO_PERIOD,
            "VetoableSlashing: veto period has passed"
        );
        require(slashingRequests[requestId].status == SlashingStatus.Requested, "VetoableSlashing: request is not in Requested status");

        _cancelSlashingRequest(requestId);
    }

    function fulfillSlashingRequest(uint256 requestId) external virtual {
        SlashingRequest storage request = slashingRequests[requestId];
        require(
            block.timestamp >= request.requestTimestamp + VETO_PERIOD,
            "VetoableSlashing: veto period has not passed"
        );
        require(request.status == SlashingStatus.Requested, "VetoableSlashing: request has been cancelled");

        _fulfillSlashingRequest(
            request.params
        );

        emit OperatorSlashed(requestId, request.params.operator, request.params.operatorSetId, request.params.strategies, request.params.wadToSlash, request.params.description);
        slashingRequests[requestId].status = SlashingStatus.Completed;
    }

    function _queueSlashingRequest(IAllocationManager.SlashingParams memory params) internal virtual {
        uint256 requestId = nextRequestId++;
        slashingRequests[requestId] = SlashingRequest({
            params: params,
            requestTimestamp: block.timestamp,
            status: SlashingStatus.Requested
        });

        emit SlashingRequested(requestId, params.operator, params.operatorSetId, params.wadToSlash, params.description);
    }

    function _cancelSlashingRequest(uint256 requestId) internal virtual {
        slashingRequests[requestId].status = SlashingStatus.Cancelled;
        emit SlashingRequestCancelled(requestId);
    }
}
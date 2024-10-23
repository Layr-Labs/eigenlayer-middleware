// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {SlasherBase} from "./base/SlasherBase.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

contract VetoableSlashing is SlasherBase {
    uint256 public constant VETO_PERIOD = 3 days;
    address public vetoCommittee;
    address public slasher;
    uint256 public nextRequestId;
    mapping(uint256 => SlashingRequest) public slashingRequests;

    modifier onlyVetoCommittee() {
        require(msg.sender == vetoCommittee, "VetoableSlashing: caller is not the veto committee");
        _;
    }

    modifier onlySlasher() {
        require(
            msg.sender == slasher,
            "VetoableSlashing: caller is not a slashing initiator"
        );
        _;
    }

    function initialize(
        address _serviceManager,
        address _vetoCommittee,
        address _slashingInitiator
    ) external virtual initializer {
        __SlasherBase_init(_serviceManager);
        vetoCommittee = _vetoCommittee;
        slasher = _slashingInitiator;
    }

    function queueSlashingRequest(IAllocationManager.SlashingParams memory params) external virtual onlySlasher {
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

        request.status = SlashingStatus.Completed;

        _fulfillSlashingRequest(
            requestId,
            request.params
        );
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
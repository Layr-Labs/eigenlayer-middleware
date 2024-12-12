// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {SlasherBase} from "./base/SlasherBase.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

contract VetoableSlashing is SlasherBase {
    uint256 public constant VETO_PERIOD = 3 days;
    address public vetoCommittee;

    mapping(uint256 => SlashingRequest) public slashingRequests;

    modifier onlyVetoCommittee() {
        _checkVetoCommittee(msg.sender);
        _;
    }

    function initialize(
        address _serviceManager,
        address _vetoCommittee,
        address _slasher
    ) external virtual initializer {
        __SlasherBase_init(_serviceManager, _slasher);
        vetoCommittee = _vetoCommittee;
    }

    function queueSlashingRequest(IAllocationManager.SlashingParams memory params) external virtual onlySlasher {
        _queueSlashingRequest(params);
    }

    function cancelSlashingRequest(uint256 requestId) external virtual onlyVetoCommittee {
        require(
            block.timestamp < slashingRequests[requestId].requestTimestamp + VETO_PERIOD,
            "VetoableSlashing.cancelSlashingRequest: veto period has passed"
        );
        require(slashingRequests[requestId].status == SlashingStatus.Requested, "VetoableSlashing.cancelSlashingRequest: request is not in Requested status");

        _cancelSlashingRequest(requestId);
    }

    function fulfillSlashingRequest(uint256 requestId) external virtual onlySlasher {
        SlashingRequest storage request = slashingRequests[requestId];
        require(
            block.timestamp >= request.requestTimestamp + VETO_PERIOD,
            "VetoableSlashing.fulfillSlashingRequest: veto period has not passed"
        );
        require(request.status == SlashingStatus.Requested, "VetoableSlashing.fulfillSlashingRequest: request has been cancelled");

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

        emit SlashingRequested(requestId, params.operator, params.operatorSetId, params.wadsToSlash, params.description);
    }

    function _cancelSlashingRequest(uint256 requestId) internal virtual {
        slashingRequests[requestId].status = SlashingStatus.Cancelled;
        emit SlashingRequestCancelled(requestId);
    }

    function _checkVetoCommittee(address account) internal view virtual {
        require(account == vetoCommittee, "VetoableSlashing._checkVetoCommittee: caller is not the veto committee");
    }
}

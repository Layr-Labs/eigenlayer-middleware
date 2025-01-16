// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {SlasherBase} from "./base/SlasherBase.sol";
import {IServiceManager} from "../interfaces/IServiceManager.sol";


contract VetoableSlasher is SlasherBase {
    uint256 public constant VETO_PERIOD = 3 days;
    address public vetoCommittee;

    mapping(uint256 => SlashingRequest) public slashingRequests;

    modifier onlyVetoCommittee() {
        _checkVetoCommittee(msg.sender);
        _;
    }

    constructor(
        IAllocationManager _allocationManager,
        IServiceManager _serviceManager,
        address _slasher
    ) SlasherBase(_allocationManager, _serviceManager) {}

    function initialize(
        address _vetoCommittee,
        address _slasher
    ) external virtual initializer {
        __SlasherBase_init(_slasher);
        vetoCommittee = _vetoCommittee;
    }

    function queueSlashingRequest(IAllocationManager.SlashingParams memory params) external virtual onlySlasher {
        _queueSlashingRequest(params);
    }

    function cancelSlashingRequest(uint256 requestId) external virtual onlyVetoCommittee {
        require(
            block.timestamp < slashingRequests[requestId].requestTimestamp + VETO_PERIOD,
            VetoPeriodPassed()
        );
        require(slashingRequests[requestId].status == SlashingStatus.Requested, SlashingRequestNotRequested());

        _cancelSlashingRequest(requestId);
    }

    function fulfillSlashingRequest(uint256 requestId) external virtual onlySlasher {
        SlashingRequest storage request = slashingRequests[requestId];
        require(block.timestamp >= request.requestTimestamp + VETO_PERIOD, VetoPeriodNotPassed());
        require(request.status == SlashingStatus.Requested, SlashingRequestIsCancelled());

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
        require(account == vetoCommittee, OnlyVetoCommittee());
    }
}

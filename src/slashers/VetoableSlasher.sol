// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {SlasherBase} from "./SlasherBase.sol";

contract VetoableSlashing is SlasherBase {
    struct SlashingRequest {
        address operator;
        uint32 operatorSetId;
        IStrategy[] strategies;
        uint256 wadToSlash;
        string description;
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

    function queueSlashingRequest(
        address operator,
        uint32 operatorSetId,
        IStrategy[] memory strategies,
        uint256 wadToSlash,
        string memory description
    ) external virtual {
        _queueSlashingRequest(operator, operatorSetId, strategies, wadToSlash, description);
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
            request.operator,
            request.operatorSetId,
            request.strategies,
            request.wadToSlash,
            request.description
        );

        emit OperatorSlashed(requestId, request.operator, request.operatorSetId, request.strategies, request.wadToSlash, request.description);
        slashingRequests[requestId].status = SlashingStatus.Completed;
    }

    function _queueSlashingRequest(
        address operator,
        uint32 operatorSetId,
        IStrategy[] memory strategies,
        uint256 wadToSlash,
        string memory description
    ) internal virtual {
        uint256 requestId = nextRequestId++;
        slashingRequests[requestId] = SlashingRequest({
            operator: operator,
            operatorSetId: operatorSetId,
            strategies: strategies,
            wadToSlash: wadToSlash,
            description: description,
            requestTimestamp: block.timestamp,
            status: SlashingStatus.Requested
        });

        emit SlashingRequested(requestId, operator, operatorSetId, wadToSlash, description);
    }

    function _cancelSlashingRequest(uint256 requestId) internal virtual {
        slashingRequests[requestId].status = SlashingStatus.Cancelled;
        emit SlashingRequestCancelled(requestId);
    }
}
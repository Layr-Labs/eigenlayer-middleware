// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {SlasherBase} from "./SlasherBase.sol";

contract Slasher is SlasherBase {
    uint256 public nextRequestId;

    function initialize(address _serviceManager) public initializer {
        __SlasherBase_init(_serviceManager);
    }

    function fulfillSlashingRequest(
        IAllocationManager.SlashingParams memory _slashingParams
    ) external virtual {
        uint256 requestId = nextRequestId++;
        _fulfillSlashingRequest(_slashingParams);
        emit OperatorSlashed(requestId, _slashingParams.operator, _slashingParams.operatorSetId, _slashingParams.strategies, _slashingParams.wadToSlash, _slashingParams.description);
    }
}
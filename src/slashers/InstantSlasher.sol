// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {SlasherBase} from "./base/SlasherBase.sol";

contract InstantSlasher is SlasherBase {

    function initialize(address _serviceManager, address _slasher) external initializer {
        __SlasherBase_init(_serviceManager, _slasher);
    }

    function fulfillSlashingRequest(
        IAllocationManager.SlashingParams memory _slashingParams
    ) external virtual onlySlasher {
        uint256 requestId = nextRequestId++;
        _fulfillSlashingRequest(requestId, _slashingParams);
    }


}
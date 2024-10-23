// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {IServiceManager} from "../../interfaces/IServiceManager.sol";
import {SlasherStorage} from "./SlasherStorage.sol";
import {IAllocationManagerTypes, IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

abstract contract SlasherBase is Initializable, SlasherStorage {
    enum SlashingStatus {
        Null,
        Requested,
        Completed,
        Cancelled
    }

    event OperatorSlashed(
        uint256 indexed slashingRequestId,
        address indexed operator,
        uint32 indexed operatorSetId,
        IStrategy[] strategies,
        uint256 wadToSlash,
        string description
    );

    function __SlasherBase_init(address _serviceManager) internal onlyInitializing {
        serviceManager = _serviceManager;
    }

    function _fulfillSlashingRequest(
        uint256 _requestId,
        IAllocationManager.SlashingParams memory _params
    ) internal virtual {
        IServiceManager(serviceManager).slashOperator(_params);
        emit OperatorSlashed(_requestId, _params.operator, _params.operatorSetId, _params.strategies, _params.wadToSlash, _params.description);
    }
}





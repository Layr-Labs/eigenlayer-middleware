// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {IServiceManager} from "../../interfaces/IServiceManager.sol";
import {SlasherStorage} from "./SlasherStorage.sol";
import {IAllocationManagerTypes, IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

abstract contract SlasherBase is Initializable, SlasherStorage {

    modifier onlySlasher() {
        _checkSlasher(msg.sender);
        _;
    }

    function __SlasherBase_init(address _serviceManager, address _slasher) internal onlyInitializing {
        serviceManager = _serviceManager;
        slasher = _slasher;
    }

    function _fulfillSlashingRequest(
        uint256 _requestId,
        IAllocationManager.SlashingParams memory _params
    ) internal virtual {
        IServiceManager(serviceManager).slashOperator(_params);
        emit OperatorSlashed(_requestId, _params.operator, _params.operatorSetId, _params.wadsToSlash, _params.description);
    }

    function _checkSlasher(address account) internal view virtual {
        require(account == slasher, "SlasherBase._checkSlasher: caller is not the slasher");
    }
}





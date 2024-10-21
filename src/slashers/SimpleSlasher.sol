// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {IServiceManager} from "../interfaces/IServiceManager.sol";
import {SlasherStorage} from "./SlasherStorage.sol";
import {IAllocationManagerTypes} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

contract SimpleSlasher is Initializable, SlasherStorage {
    function initialize(address _serviceManager) public initializer {
        serviceManager = _serviceManager;
    }

    function slashOperator(
        address operator,
        uint32 operatorSetId,
        IStrategy[] memory strategies,
        uint256 wadToSlash,
        string memory description
    ) external {

        IAllocationManagerTypes.SlashingParams memory params = IAllocationManagerTypes.SlashingParams({
            operator: operator,
            operatorSetId: operatorSetId,
            strategies: strategies,
            wadToSlash: wadToSlash,
            description: description
        });

        IServiceManager(serviceManager).slashOperator(params);
    }
}

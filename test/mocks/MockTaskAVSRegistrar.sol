// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {TaskAVSRegistrarBase} from "../../src/avs/task/TaskAVSRegistrarBase.sol";

contract MockTaskAVSRegistrar is TaskAVSRegistrarBase {
    /**
     * @dev Constructor that passes parameters to parent TaskAVSRegistrarBase
     * @param _allocationManager The AllocationManager contract address
     * @param _keyRegistrar The KeyRegistrar contract address
     * @param _permissionController The PermissionController contract address
     */
    constructor(
        IAllocationManager _allocationManager,
        IKeyRegistrar _keyRegistrar,
        IPermissionController _permissionController
    ) TaskAVSRegistrarBase(_allocationManager, _keyRegistrar, _permissionController) {}

    /**
     * @dev Initializer that calls parent initializer
     * @param _avs The address of the AVS
     * @param _owner The owner of the contract
     * @param _initialConfig The initial AVS configuration
     */
    function initialize(
        address _avs,
        address _owner,
        AvsConfig memory _initialConfig
    ) external initializer {
        __TaskAVSRegistrarBase_init(_avs, _owner, _initialConfig);
    }
}

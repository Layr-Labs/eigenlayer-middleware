// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";

contract PermissionControllerIntermediate is IPermissionController {
    function addPendingAdmin(address account, address admin) external virtual {}

    function removePendingAdmin(address account, address admin) external virtual {}


    function removeAdmin(address account, address admin) external virtual {}

    function setAppointee(
        address account,
        address appointee,
        address target,
        bytes4 selector
    ) external virtual {}

    function removeAppointee(
        address account,
        address appointee,
        address target,
        bytes4 selector
    ) external virtual {}





    function canCall(
        address account,
        address caller,
        address target,
        bytes4 selector
    ) external virtual returns (bool) {}


}

contract PermissionControllerMock is PermissionControllerIntermediate {
    mapping(address => mapping(address => mapping(address => mapping(bytes4 => bool)))) internal
        _canCall;


    function canCall(
        address account,
        address caller,
        address target,
        bytes4 selector
    ) external override returns (bool) {
        if (account == caller) return true;
        return _canCall[account][caller][target][selector];
    }
}

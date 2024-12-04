// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IPermissionController} from "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";

contract PermissionControllerMock is IPermissionController {
    function initialize() external {}

    function addPendingAdmin(address account, address admin) external {}

    function removePendingAdmin(address account, address admin) external {}

    function acceptAdmin(address account) external {}

    function removeAdmin(address account, address admin) external {}

    function setAppointee(
        address account,
        address appointee,
        address target,
        bytes4 selector
    ) external {}

    function removeAppointee(
        address account,
        address appointee,
        address target,
        bytes4 selector
    ) external {}

    function isAdmin(address account, address caller) external view returns (bool) {}

    function isPendingAdmin(address account, address pendingAdmin) external view returns (bool) {}

    function getAdmins(address account) external view returns (address[] memory) {}

    function getPendingAdmins(address account) external view returns (address[] memory) {}

    function canCall(
        address account,
        address caller,
        address target,
        bytes4 selector
    ) external view returns (bool) {}

    function getAppointeePermissions(
        address account,
        address appointee
    ) external view returns (address[] memory targets, bytes4[] memory selectors) {}

    function getAppointees(
        address account,
        address target,
        bytes4 selector
    ) external view returns (address[] memory) {}
}

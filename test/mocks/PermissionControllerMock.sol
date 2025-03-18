// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {ISemVerMixin} from "eigenlayer-contracts/src/contracts/interfaces/ISemVerMixin.sol";

contract PermissionControllerIntermediate is IPermissionController {
    function addPendingAdmin(address account, address admin) external virtual {}

    function removePendingAdmin(address account, address admin) external virtual {}

    function acceptAdmin(
        address account
    ) external virtual {}

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

    function isAdmin(address account, address caller) external view virtual returns (bool) {}

    function isPendingAdmin(
        address account,
        address pendingAdmin
    ) external view virtual returns (bool) {}

    function getAdmins(
        address account
    ) external view virtual returns (address[] memory) {}

    function getPendingAdmins(
        address account
    ) external view virtual returns (address[] memory) {}

    function canCall(
        address account,
        address caller,
        address target,
        bytes4 selector
    ) external virtual returns (bool) {}

    function getAppointeePermissions(
        address account,
        address appointee
    ) external virtual returns (address[] memory, bytes4[] memory) {}

    function getAppointees(
        address account,
        address target,
        bytes4 selector
    ) external virtual returns (address[] memory) {}

    /**
     * @notice Returns the version of the contract
     * @return The version string
     */
    function version() external pure virtual returns (string memory) {
        return "v0.0.1";
    }
}

contract PermissionControllerMock is PermissionControllerIntermediate {
    mapping(address => mapping(address => mapping(address => mapping(bytes4 => bool)))) internal
        _canCall;

    function setCanCall(
        address account,
        address caller,
        address target,
        bytes4 selector
    ) external {
        _canCall[account][caller][target][selector] = true;
    }

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

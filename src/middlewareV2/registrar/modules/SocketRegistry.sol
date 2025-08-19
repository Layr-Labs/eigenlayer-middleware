// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ISocketRegistryV2} from "../../../interfaces/ISocketRegistryV2.sol";
import {SocketRegistryStorage} from "./SocketRegistryStorage.sol";
import {
    OperatorSetLib,
    OperatorSet
} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {PermissionControllerMixin} from
    "eigenlayer-contracts/src/contracts/mixins/PermissionControllerMixin.sol";

/// @notice A module that allows for the setting and removal of operator sockets
/// @dev This contract assumes a single socket per operator
abstract contract SocketRegistry is SocketRegistryStorage, PermissionControllerMixin {
    using OperatorSetLib for OperatorSet;

    constructor(
        IPermissionController _permissionController
    ) PermissionControllerMixin(_permissionController) {}

    /// @inheritdoc ISocketRegistryV2
    function getOperatorSocket(
        address operator
    ) external view returns (string memory) {
        return _operatorToSocket[operator];
    }

    /// @inheritdoc ISocketRegistryV2
    function updateSocket(address operator, string memory socket) external checkCanCall(operator) {
        _setOperatorSocket(operator, socket);
    }

    /**
     * @notice Sets the socket for an operator.
     * @param operator The address of the operator to set the socket for.
     * @param socket The socket (any arbitrary string as deemed useful by an AVS) to set.
     * @dev This function sets a single socket per operator, regardless of operatorSet.
     */
    function _setOperatorSocket(address operator, string memory socket) internal {
        _operatorToSocket[operator] = socket;
        emit OperatorSocketSet(operator, socket);
    }
}

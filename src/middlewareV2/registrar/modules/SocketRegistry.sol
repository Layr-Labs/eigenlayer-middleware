// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {SocketRegistryStorage} from "./SocketRegistryStorage.sol";
import {ISocketRegistry} from "../../../interfaces/ISocketRegistry.sol";

/// @notice A module that allows for the setting and removal of operator sockets
abstract contract SocketRegistry is SocketRegistryStorage {
    /// @notice Emitted when an operator socket is set
    event OperatorSocketSet(address indexed operator, string socket);

    /// @notice Emitted when an operator socket is removed
    event OperatorSocketRemoved(address indexed operator);

    /**
     * @notice Gets the socket for an operator.
     * @param operator The operator to get the socket for.
     * @return The socket for the operator.
     */
    function getOperatorSocket(
        address operator
    ) external view returns (string memory) {
        return operatorToSocket[operator];
    }

    /**
     * @notice Updates the socket for the operator.
     * @param socket The socket (any arbitrary string as deemed useful by an AVS) to set.
     * @dev This function can only be called by the operator themselves.
     */
    function updateSocket(
        string memory socket
    ) external {
        _setOperatorSocket(msg.sender, socket);
    }

    /**
     * @notice Sets the socket for an operator.
     * @param operator The address of the operator to set the socket for.
     * @param socket The socket (any arbitrary string as deemed useful by an AVS) to set.
     * @dev This function assumes a single socket per operator, for all operatorSets.
     */
    function _setOperatorSocket(address operator, string memory socket) internal {
        operatorToSocket[operator] = socket;
        emit OperatorSocketSet(operator, socket);
    }

    /**
     * @notice Deletes the socket for an operator.
     * @param operator The address of the operator to delete the socket for.
     */
    function _removeOperatorSocket(
        address operator
    ) internal {
        delete operatorToSocket[operator];
        emit OperatorSocketRemoved(operator);
    }
}

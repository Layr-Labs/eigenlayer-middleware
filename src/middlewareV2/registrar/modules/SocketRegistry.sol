// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ISocketRegistry} from "../../../interfaces/ISocketRegistryV2.sol";
import {SocketRegistryStorage} from "./SocketRegistryStorage.sol";
import {
    OperatorSetLib,
    OperatorSet
} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

/// @notice A module that allows for the setting and removal of operator sockets
/// @dev This contract assumes a single socket per operator
abstract contract SocketRegistry is SocketRegistryStorage {
    using OperatorSetLib for OperatorSet;

    /// @inheritdoc ISocketRegistry
    function getOperatorSocket(
        address operator
    ) external view returns (string memory) {
        return _operatorToSocket[operator];
    }

    /// @inheritdoc ISocketRegistry
    function updateSocket(address operator, string memory socket) external {
        require(msg.sender == operator, CallerNotOperator());
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

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ISocketRegistry} from "../../../interfaces/ISocketRegistryV2.sol";
import {SocketRegistryStorage} from "./SocketRegistryStorage.sol";
import {
    OperatorSetLib,
    OperatorSet
} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

/// @notice A module that allows for the setting and removal of operator sockets
abstract contract SocketRegistry is SocketRegistryStorage {
    using OperatorSetLib for OperatorSet;

    /// @inheritdoc ISocketRegistry
    function getOperatorSocket(
        address operator,
        OperatorSet memory operatorSet
    ) external view returns (string memory) {
        return _operatorToSocket[operator][operatorSet.key()];
    }

    /// @inheritdoc ISocketRegistry
    function updateSocket(
        address operator,
        OperatorSet memory operatorSet,
        string memory socket
    ) external {
        require(msg.sender == operator, CallerNotOperator());
        _setOperatorSocket(operator, operatorSet, socket);
    }

    /**
     * @notice Sets the socket for an operator.
     * @param operator The address of the operator to set the socket for.
     * @param operatorSet The operator set to set the socket for.
     * @param socket The socket (any arbitrary string as deemed useful by an AVS) to set.
     * @dev This function assumes a single socket per operator, for all operatorSets.
     */
    function _setOperatorSocket(
        address operator,
        OperatorSet memory operatorSet,
        string memory socket
    ) internal {
        _operatorToSocket[operator][operatorSet.key()] = socket;
        emit OperatorSocketSet(operator, operatorSet, socket);
    }

    /**
     * @notice Deletes the socket for an operator.
     * @param operator The address of the operator to delete the socket for.
     */
    function _removeOperatorSocket(address operator, OperatorSet memory operatorSet) internal {
        delete _operatorToSocket[operator][operatorSet.key()];
        emit OperatorSocketRemoved(operator, operatorSet);
    }
}

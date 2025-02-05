// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {ISlashingRegistryCoordinator} from "./interfaces/ISlashingRegistryCoordinator.sol";
import {ISocketRegistry} from "./interfaces/ISocketRegistry.sol";
import {SocketRegistryStorage} from "./SocketRegistryStorage.sol";

/**
 * @title A `Registry` that keeps track of operator sockets.
 * @author Layr Labs, Inc.
 */
contract SocketRegistry is ISocketRegistry, SocketRegistryStorage {
    /// @notice A modifier that only allows the RegistryCoordinator to call a function
    modifier onlySlashingRegistryCoordinator() {
        require(
            msg.sender == address(slashingRegistryCoordinator),
            "SocketRegistry.onlySlashingRegistryCoordinator: caller is not the SlashingRegistryCoordinator"
        );
        _;
    }

    /// @notice A modifier that only allows the owner of the SlashingRegistryCoordinator to call a function
    modifier onlyCoordinatorOwner() {
        require(
            msg.sender == ISlashingRegistryCoordinator(slashingRegistryCoordinator).owner(),
            "SocketRegistry.onlyCoordinatorOwner: caller is not the owner of the slashingRegistryCoordinator"
        );
        _;
    }

    constructor(
        ISlashingRegistryCoordinator _slashingRegistryCoordinator
    ) SocketRegistryStorage(address(_slashingRegistryCoordinator)) {}

    /// @notice sets the socket for an operator only callable by the RegistryCoordinator
    function setOperatorSocket(
        bytes32 _operatorId,
        string memory _socket
    ) external onlySlashingRegistryCoordinator {
        operatorIdToSocket[_operatorId] = _socket;
    }

    /// @notice gets the stored socket for an operator
    function getOperatorSocket(
        bytes32 _operatorId
    ) external view returns (string memory) {
        return operatorIdToSocket[_operatorId];
    }
}

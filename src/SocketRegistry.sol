// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {ISlashingRegistryCoordinator} from "./interfaces/ISlashingRegistryCoordinator.sol";
import {ISocketRegistry} from "./interfaces/ISocketRegistry.sol";
import {SocketRegistryStorage} from "./SocketRegistryStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title A `Registry` that keeps track of operator sockets (arbitrary strings).
 * @author Layr Labs, Inc.
 */
contract SocketRegistry is SocketRegistryStorage {
    /// @notice A modifier that only allows the SlashingRegistryCoordinator to call a function
    modifier onlySlashingRegistryCoordinator() {
        require(msg.sender == slashingRegistryCoordinator, OnlySlashingRegistryCoordinator());
        _;
    }

    constructor(
        ISlashingRegistryCoordinator _slashingRegistryCoordinator
    ) SocketRegistryStorage(address(_slashingRegistryCoordinator)) {}

    /// @inheritdoc ISocketRegistry
    function setOperatorSocket(
        bytes32 _operatorId,
        string memory _socket
    ) external onlySlashingRegistryCoordinator {
        operatorIdToSocket[_operatorId] = _socket;
    }

    /// @inheritdoc ISocketRegistry
    function getOperatorSocket(
        bytes32 _operatorId
    ) external view returns (string memory) {
        return operatorIdToSocket[_operatorId];
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";
import {ISocketRegistry} from "./interfaces/ISocketRegistry.sol";

/**
 * @title A `Registry` that keeps track of operator sockets.
 * @author Layr Labs, Inc.
 */
contract SocketRegistry is ISocketRegistry {

    /// @notice The address of the RegistryCoordinator
    address public immutable registryCoordinator;

    /// @notice A mapping from operator IDs to their sockets
    mapping(bytes32 => string) public operatorIdToSocket;

    /// @notice A modifier that only allows the RegistryCoordinator to call a function
    modifier onlyRegistryCoordinator() {
        require(msg.sender == address(registryCoordinator), "SocketRegistry.onlyRegistryCoordinator: caller is not the RegistryCoordinator");
        _;
    }

    /// @notice A modifier that only allows the owner of the RegistryCoordinator to call a function
    modifier onlyCoordinatorOwner() {
        require(msg.sender == IRegistryCoordinator(registryCoordinator).owner(), "SocketRegistry.onlyCoordinatorOwner: caller is not the owner of the registryCoordinator");
        _;
    }

    constructor(IRegistryCoordinator _registryCoordinator) {
        registryCoordinator = address(_registryCoordinator);
    }

    /// @notice sets the socket for an operator only callable by the RegistryCoordinator
    function setOperatorSocket(bytes32 _operatorId, string memory _socket) external onlyRegistryCoordinator {
        operatorIdToSocket[_operatorId] = _socket;
    }

    /// @notice migrates the sockets for a list of operators only callable by the owner of the RegistryCoordinator
    function migrateOperatorSockets(bytes32[] memory _operatorIds, string[] memory _sockets) external onlyCoordinatorOwner {
        for (uint256 i = 0; i < _operatorIds.length; i++) {
            operatorIdToSocket[_operatorIds[i]] = _sockets[i];
        }
    }

    /// @notice gets the stored socket for an operator
    function getOperatorSocket(bytes32 _operatorId) external view returns (string memory) {
        return operatorIdToSocket[_operatorId];
    }

}

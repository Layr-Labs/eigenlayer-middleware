// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

/**
 * @title Storage contract for SocketRegistry
 * @author Layr Labs, Inc.
 */
contract SocketRegistryStorage {
    /// @notice The address of the RegistryCoordinator
    address public immutable registryCoordinator;

    /// @notice A mapping from operator IDs to their sockets
    mapping(bytes32 => string) public operatorIdToSocket;

    constructor(
        address _registryCoordinator
    ) {
        registryCoordinator = _registryCoordinator;
    }

    uint256[48] private __GAP;
}

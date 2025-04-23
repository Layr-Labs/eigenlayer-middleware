// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

/// @title ISocketRegistry
interface ISocketRegistry {
    /**
     * @notice Updates the socket for an operator
     * @param operator The operator to update the socket for
     * @param socket The new socket to set
     */
    function updateSocket(address operator, string memory socket) external;

    /**
     * @notice Gets the socket for an operator
     * @param operator The operator to get the socket for
     * @return The socket for the operator
     */
    function getSocket(
        address operator
    ) external view returns (string memory);
}

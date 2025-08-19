// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

interface ISocketRegistryEvents {
    /// @notice Emitted when an operator socket is set
    event OperatorSocketSet(address indexed operator, string socket);
}

interface ISocketRegistryV2 is ISocketRegistryEvents {
    /**
     * @notice Gets the socket for an operator.
     * @param operator The operator to get the socket for.
     * @return The socket for the operator.
     */
    function getOperatorSocket(
        address operator
    ) external view returns (string memory);

    /**
     * @notice Updates the socket for an operator.
     * @param operator The operator to set the socket for.
     * @param socket The socket to set for the operator.
     * @dev This function can only be called by the operator themselves.
     * @dev Reverts for:
     *      - InvalidPermissions: The caller does not have permission to call this function (via core `PermissionController`)
     */
    function updateSocket(address operator, string memory socket) external;
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

interface ISocketRegistryErrors {
    /// @notice Thrown when the caller is not the operator
    error CallerNotOperator();

    /// @notice Thrown when the data length mismatch
    error DataLengthMismatch();
}

interface ISocketRegistryEvents {
    /// @notice Emitted when an operator socket is set
    event OperatorSocketSet(address indexed operator, string socket);
}

interface ISocketRegistry is ISocketRegistryErrors, ISocketRegistryEvents {
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
     */
    function updateSocket(address operator, string memory socket) external;
}

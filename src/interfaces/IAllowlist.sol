// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

interface IAllowlistErrors {
    /// @notice Thrown when the operator is already in the allowlist
    error OperatorAlreadyInAllowlist();
    /// @notice Thrown when the operator is not in the allowlist
    error OperatorNotInAllowlist();
}

interface IAllowlistEvents {
    /// @notice Emitted when an operator is added to the allowlist
    event OperatorAddedToAllowlist(address indexed operator);
    /// @notice Emitted when an operator is removed from the allowlist
    event OperatorRemovedFromAllowlist(address indexed operator);
}

interface IAllowlist is IAllowlistErrors, IAllowlistEvents {
    /**
     * @notice Adds an operator to the allowlist
     * @param operator The operator to add to the allowlist
     * @dev Only callable by the owner
     */
    function addOperatorToAllowlist(
        address operator
    ) external;

    /**
     * @notice Removes an operator from the allowlist
     * @param operator The operator to remove from the allowlist
     * @dev If an operator is removed from the allowlist and is already registered, the avs
     *      must then handle state changes appropriately (ie. eject the operator)
     * @dev Only callable by the owner
     */
    function removeOperatorFromAllowlist(
        address operator
    ) external;

    /**
     * @notice Checks if an operator is in the allowlist
     * @param operator The operator to check
     * @return True if the operator is in the allowlist, false otherwise
     */
    function isOperatorAllowed(
        address operator
    ) external view returns (bool);

    /**
     * @notice Returns all operators in the allowlist
     * @return An array of all operators in the allowlist
     * @dev This function should be used with caution, as it can be expensive to call on-chain
     */
    function getAllowedOperators() external view returns (address[] memory);
}

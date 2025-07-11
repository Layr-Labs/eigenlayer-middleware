// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

interface IAllowlistErrors {
    /// @notice Thrown when the operator is already in the allowlist
    error OperatorAlreadyInAllowlist();
    /// @notice Thrown when the operator is not in the allowlist
    error OperatorNotInAllowlist();
}

interface IAllowlistEvents {
    /// @notice Emitted when an operator is added to the allowlist
    event OperatorAddedToAllowlist(OperatorSet indexed operatorSet, address indexed operator);
    /// @notice Emitted when an operator is removed from the allowlist
    event OperatorRemovedFromAllowlist(OperatorSet indexed operatorSet, address indexed operator);
}

interface IAllowlist is IAllowlistErrors, IAllowlistEvents {
    /**
     * @notice Adds an operator to the allowlist
     * @param operatorSet The operator set to add the operator to
     * @param operator The operator to add to the allowlist
     * @dev Only callable by the owner
     */
    function addOperatorToAllowlist(OperatorSet memory operatorSet, address operator) external;

    /**
     * @notice Removes an operator from the allowlist
     * @param operatorSet The operator set to remove the operator from
     * @param operator The operator to remove from the allowlist
     * @dev If an operator is removed from the allowlist and is already registered, the avs
     *      must then handle state changes appropriately (ie. eject the operator)
     * @dev Only callable by the owner
     */
    function removeOperatorFromAllowlist(
        OperatorSet memory operatorSet,
        address operator
    ) external;

    /**
     * @notice Checks if an operator is in the allowlist
     * @param operatorSet The operator set to check the operator in
     * @param operator The operator to check
     * @return True if the operator is in the allowlist, false otherwise
     */
    function isOperatorAllowed(
        OperatorSet memory operatorSet,
        address operator
    ) external view returns (bool);

    /**
     * @notice Returns all operators in the allowlist
     * @param operatorSet The operator set to get the allowed operators from
     * @return An array of all operators in the allowlist
     * @dev This function should be used with caution, as it can be expensive to call on-chain
     */
    function getAllowedOperators(
        OperatorSet memory operatorSet
    ) external view returns (address[] memory);
}

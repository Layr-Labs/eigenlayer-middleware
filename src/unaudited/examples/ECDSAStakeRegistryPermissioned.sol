// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {ECDSAStakeRegistry} from "../ECDSAStakeRegistry.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

/// @title ECDSA Stake Registry with an Operator Allowlist
/// @dev THIS CONTRACT IS NOT AUDITED
/// @notice This contract extends ECDSAStakeRegistry by adding functionality to allowlist and remove operators
contract ECDSAStakeRegistryPermissioned is ECDSAStakeRegistry {
    /// @notice A mapping to keep track of whether an operator can register with this AVS or not.
    mapping(address => bool) public allowlistedOperators;

    /// @dev Emits when an operator is added to the allowlist.
    event OperatorPermitted(address indexed operator);

    /// @dev Emits when an operator is removed from the allowlist.
    event OperatorRevoked(address indexed operator);

    /// @dev Emits when an operator is removed from the active operator set.
    event OperatorEjected(address indexed operator);

    /// @dev Custom error to signal that an operator is not allowlisted.
    error OperatorNotAllowlisted();

    /// @dev Custom error to signal that an operator is already allowlisted.
    error OperatorAlreadyAllowlisted();

    constructor(
        IDelegationManager _delegationManager
    ) ECDSAStakeRegistry(_delegationManager) {
        // _disableInitializers();
    }

    /// @notice Adds an operator to the allowlisted operator set
    /// @dev An allowlisted operator isn't a part of the operator set. They must subsequently register themselves
    /// @param _operator The address of the operator to be allowlisted
    function permitOperator(
        address _operator
    ) external onlyOwner {
        _permitOperator(_operator);
    }

    /// @notice Revokes an operator's permission and deregisters them
    /// @dev Emits the OperatorRevoked event if the operator was previously allowlisted.
    /// @param _operator The address of the operator to remove from the allowlist and deregistered.
    function revokeOperator(
        address _operator
    ) external onlyOwner {
        _revokeOperator(_operator);
    }

    /// @notice Directly deregisters an operator without removing from the allowlist
    /// @dev Does not emit an event because it does not modify the allowlist.
    /// @param _operator The address of the operator to deregister
    function ejectOperator(
        address _operator
    ) external onlyOwner {
        _ejectOperator(_operator);
    }

    /// @dev Deregisters and operator from the active operator set
    /// @param _operator The address of the operator to remove.
    function _ejectOperator(
        address _operator
    ) internal {
        _deregisterOperator(_operator);
        emit OperatorEjected(_operator);
    }

    /// @dev Adds an operator to the allowlisted operator set
    /// Doesn't register the operator into the operator set
    /// @param _operator The address of the operator to allowlist.
    function _permitOperator(
        address _operator
    ) internal {
        if (allowlistedOperators[_operator]) {
            revert OperatorAlreadyAllowlisted();
        }
        allowlistedOperators[_operator] = true;
        emit OperatorPermitted(_operator);
    }

    /// @dev Removes an operator from the allowlist.
    /// If the operator is registered, also deregisters the operator.
    /// @param _operator The address of the operator to be revoked.
    function _revokeOperator(
        address _operator
    ) internal {
        if (!allowlistedOperators[_operator]) {
            revert OperatorNotAllowlisted();
        }
        delete allowlistedOperators[_operator];
        emit OperatorRevoked(_operator);
        if (_operatorRegistered[_operator]) {
            _ejectOperator(_operator);
        }
    }

    /// @inheritdoc ECDSAStakeRegistry
    function _registerOperatorWithSig(
        address _operator,
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory _operatorSignature,
        address _operatorSigningKey
    ) internal override {
        if (allowlistedOperators[_operator] != true) {
            revert OperatorNotAllowlisted();
        }
        super._registerOperatorWithSig(_operator, _operatorSignature, _operatorSigningKey);
    }
}

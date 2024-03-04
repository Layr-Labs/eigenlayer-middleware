// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {ECDSAStakeRegistry} from "../ECDSAStakeRegistry.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

/// @title ECDSA Stake Registry with an Operator Allowlist
/// @notice This contract extends ECDSAStakeRegistry by adding functionality to allowlist and remove operators
contract ECDSAStakeRegistryPermissioned is ECDSAStakeRegistry {
    mapping(address => bool) public allowlistedOperators;

    /// @dev Custom error to signal that an operator is not allowlisted.
    error OperatorNotAllowlisted();

    constructor(IDelegationManager _delegationManager) ECDSAStakeRegistry(_delegationManager) {
        // _disableInitializers();
    }

    /// @notice Adds an operator to the allowlisted operator set
    /// @dev An allowlisted operator isn't a part of the operator set. They must subsequently register themselves
    /// @param _operator The address of the operator to be allowlisted
    function permitOperator(address _operator) external onlyOwner {
        allowlistedOperators[_operator] = true;
    }

    /// @notice Revokes an operator's permission and deregisters them
    /// @param _operator The address of the operator to remove from the allowlist and deregistered.
    function revokeOperator(address _operator) external onlyOwner {
        delete allowlistedOperators[_operator];
        _deregisterOperator(_operator);
    }

    /// @notice Directly deregisters an operator without removing from the allowlist
    /// @param _operator The address of the operator to deregister
    function ejectOperator(address _operator) external onlyOwner {
        _deregisterOperator(_operator);
    }

    /// @inheritdoc ECDSAStakeRegistry
    function _registerOperatorWithSig(
        address _operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory _operatorSignature
    ) internal override {
        if (allowlistedOperators[_operator] != true) revert OperatorNotAllowlisted();
        super._registerOperatorWithSig(_operator, _operatorSignature);
    }
}

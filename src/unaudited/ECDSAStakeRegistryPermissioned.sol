// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {ECDSAStakeRegistry} from "./ECDSAStakeRegistry.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

contract ECDSAStakeRegistryPermissioned is ECDSAStakeRegistry {
    mapping(address => bool) public allowlistedOperators;

    error OperatorNotAllowlisted();
    constructor(IDelegationManager _delegationManager) ECDSAStakeRegistry(_delegationManager) {
        // _disableInitializers();
    }

    function permitOperator(address _operator) external onlyOwner {
        allowlistedOperators[_operator] = true;
    }

    function revokeOperator(address _operator) external onlyOwner {
        delete allowlistedOperators[_operator];
        _deregisterOperator(_operator);
    }

    function ejectOperator(address _operator) external onlyOwner {
        _deregisterOperator(_operator);
    }

    function _registerOperatorWithSig(
        address _operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory _operatorSignature
    ) internal override {
        if (allowlistedOperators[_operator] != true) revert OperatorNotAllowlisted();
        super._registerOperatorWithSig(_operator, _operatorSignature);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";

import {AVSRegistrar} from "../AVSRegistrar.sol";
import {Allowlist} from "../modules/Allowlist.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

contract AVSRegistrarWithAllowlist is AVSRegistrar, Allowlist {
    constructor(
        address _avs,
        IAllocationManager _allocationManager,
        IKeyRegistrar _keyRegistrar
    ) AVSRegistrar(_avs, _allocationManager, _keyRegistrar) {}

    function initialize(
        address admin
    ) public override initializer {
        _initializeAllowlist(admin);
    }

    /// @notice Before registering operator, check if the operator is in the allowlist
    function _beforeRegisterOperator(
        address operator,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) internal override {
        super._beforeRegisterOperator(operator, operatorSetIds, data);

        for (uint32 i; i < operatorSetIds.length; ++i) {
            require(
                isOperatorAllowed(OperatorSet({avs: avs, id: operatorSetIds[i]}), operator),
                OperatorNotInAllowlist()
            );
        }
    }
}

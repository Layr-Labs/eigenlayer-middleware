// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

import {IKeyRegistrar} from "../../../interfaces/IKeyRegistrar.sol";
import {AVSRegistrar} from "../AVSRegistrar.sol";
import {Allowlist} from "../modules/Allowlist.sol";

contract AVSRegistrarWithAllowlist is AVSRegistrar, Allowlist {
    constructor(
        address _avs,
        IAllocationManager _allocationManager,
        IKeyRegistrar _keyRegistrar,
        IKeyRegistrar.CurveType _curveType
    ) AVSRegistrar(_avs, _allocationManager, _keyRegistrar, _curveType) {}

    function initialize(
        address admin
    ) public override initializer {
        _initializeAllowlist(admin);
    }

    /// @notice Set the socket for the operator
    function _beforeRegisterOperator(
        address operator,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) internal override {
        super._beforeRegisterOperator(operator, operatorSetIds, data);

        require(isOperatorAllowed(operator), "Operator not in allowlist");
    }
}

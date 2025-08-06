// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAVSRegistrarWithAllowlist} from "../../../interfaces/IAVSRegistrarWithAllowlist.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";

import {AVSRegistrar} from "../AVSRegistrar.sol";
import {Allowlist} from "../modules/Allowlist.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

contract AVSRegistrarWithAllowlist is AVSRegistrar, Allowlist, IAVSRegistrarWithAllowlist {
    constructor(
        IAllocationManager _allocationManager,
        IKeyRegistrar _keyRegistrar
    ) AVSRegistrar(_allocationManager, _keyRegistrar) {}

    function initialize(address avs, address admin) external initializer {
        // Initialize the AVSRegistrar
        __AVSRegistrar_init(avs);

        // Initialize the allowlist
        __Allowlist_init(admin);
    }

    /// @notice Before registering operator, check if the operator is in the allowlist
    /// @dev Reverts for:
    ///      - OperatorNotInAllowlist: The operator is not in the allowlist
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

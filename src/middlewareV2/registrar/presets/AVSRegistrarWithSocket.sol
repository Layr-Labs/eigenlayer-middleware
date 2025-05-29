// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

import {IKeyRegistrar} from "../../../interfaces/IKeyRegistrar.sol";
import {AVSRegistrar} from "../AVSRegistrar.sol";
import {SocketRegistry} from "../modules/SocketRegistry.sol";

contract AVSRegistrarWithSocket is AVSRegistrar, SocketRegistry {
    constructor(
        address _avs,
        IAllocationManager _allocationManager,
        IKeyRegistrar _keyRegistrar
    ) AVSRegistrar(_avs, _allocationManager, _keyRegistrar) {}

    /// @notice Set the socket for the operator
    function _afterRegisterOperator(
        address operator,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) internal override {
        super._afterRegisterOperator(operator, operatorSetIds, data);

        string memory socket = abi.decode(data, (string));
        _setOperatorSocket(operator, socket);
    }

    /// @notice Remove the socket for the operator
    function _afterDeregisterOperator(
        address operator,
        uint32[] calldata operatorSetIds
    ) internal override {
        super._afterDeregisterOperator(operator, operatorSetIds);

        _removeOperatorSocket(operator);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";

import {AVSRegistrar} from "../AVSRegistrar.sol";
import {SocketRegistry} from "../modules/SocketRegistry.sol";
import {
    OperatorSetLib,
    OperatorSet
} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

contract AVSRegistrarWithSocket is AVSRegistrar, SocketRegistry {
    constructor(
        address _avs,
        IAllocationManager _allocationManager,
        IKeyRegistrar _keyRegistrar
    ) AVSRegistrar(_avs, _allocationManager, _keyRegistrar) {}

    /// @notice Set the socket for the operator
    /// @dev This function sets the socket even if the operator is already registered
    /// @dev Operators should make sure to always provide the socket when registering
    function _afterRegisterOperator(
        address operator,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) internal override {
        super._afterRegisterOperator(operator, operatorSetIds, data);

        // Set operator socket
        string memory socket = abi.decode(data, (string));
        _setOperatorSocket(operator, socket);
    }
}

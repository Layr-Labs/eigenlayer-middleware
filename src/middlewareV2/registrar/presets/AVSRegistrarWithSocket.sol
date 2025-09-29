// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";

import {IAVSRegistrarWithSocket} from "../../../interfaces/IAVSRegistrarWithSocket.sol";
import {AVSRegistrar} from "../AVSRegistrar.sol";
import {SocketRegistry} from "../modules/SocketRegistry.sol";

contract AVSRegistrarWithSocket is AVSRegistrar, SocketRegistry, IAVSRegistrarWithSocket {
    constructor(
        IAllocationManager _allocationManager,
        IKeyRegistrar _keyRegistrar,
        IPermissionController _permissionController
    ) AVSRegistrar(_allocationManager, _keyRegistrar) SocketRegistry(_permissionController) {}

    function initialize(
        address avs
    ) external initializer {
        __AVSRegistrar_init(avs);
    }

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

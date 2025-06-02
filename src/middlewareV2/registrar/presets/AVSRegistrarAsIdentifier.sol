// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";

import {AVSRegistrar} from "../AVSRegistrar.sol";
import {SocketRegistry} from "../modules/SocketRegistry.sol";

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

/// @notice An AVSRegistrar that is the identifier for the AVS in EigenLayer core.
/// @dev Once deployed, the `admin` will control other parameters of the AVS, such as creating operatorSets, slashing, etc.
contract AVSRegistrarAsIdentifier is Initializable, AVSRegistrar, SocketRegistry {
    /// @notice The permission controller for the AVS
    IPermissionController public immutable permissionController;

    constructor(
        address _avs,
        IAllocationManager _allocationManager,
        IPermissionController _permissionController,
        IKeyRegistrar _keyRegistrar
    ) AVSRegistrar(_avs, _allocationManager, _keyRegistrar) {
        // Set the permission controller for future interactions
        permissionController = _permissionController;
    }

    function initialize(address admin, string memory metadataURI) public initializer {
        // Set the metadataURI and the registrar for the AVS to this registrar contract
        allocationManager.updateAVSMetadataURI(address(this), metadataURI);
        allocationManager.setAVSRegistrar(address(this), this);

        // Set the admin for the AVS
        permissionController.addPendingAdmin(address(this), admin);
    }
}

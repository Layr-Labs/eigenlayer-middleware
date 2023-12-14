// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {IServiceManager} from "src/interfaces/IServiceManager.sol";
import {IRegistryCoordinator} from "src/interfaces/IRegistryCoordinator.sol";

/**
 * @title Minimal implementation of a ServiceManager-type contract.
 * This contract can inherited from or simply used as a point-of-reference.
 * @author Layr Labs, Inc.
 */
contract ServiceManagerBase is IServiceManager, OwnableUpgradeable {
    address immutable registryCoordinator;
    IDelegationManager immutable delegationManager;

    /// @notice when applied to a function, only allows the RegistryCoordinator to call it
    modifier onlyRegistryCoordinator() {
        require(
            msg.sender == address(registryCoordinator),
            "ServiceManagerBase.onlyRegistryCoordinator: caller is not the registry coordinator"
        );
        _;
    }

    /// @notice Sets the (immutable) `registryCoordinator` address
    constructor(
        IDelegationManager _delegationManager,
        IRegistryCoordinator _registryCoordinator
    ) {
        delegationManager = _delegationManager;
        registryCoordinator = address(_registryCoordinator);
        _disableInitializers();
    }


    /**
     * @notice Sets the metadata URI for the AVS
     * @param _metadataURI is the metadata URI for the AVS
     * @dev only callable by the owner
     */
    function setMetadataURI(string memory _metadataURI) public virtual onlyOwner {
        delegationManager.updateAVSMetadataURI(_metadataURI);
    }

    /**
     * @notice Forwards a call to EigenLayer's DelegationManager contract to confirm operator registration with the AVS
     * @param operator The address of the operator to register.
     * @param operatorSignature The signature, salt, and expiry of the operator's signature.
     */
    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) public virtual onlyOwner {
        delegationManager.registerOperatorToAVS(operator, operatorSignature);
    }

    /**
     * @notice Forwards a call to EigenLayer's DelegationManager contract to confirm operator deregistration from the AVS
     * @param operator The address of the operator to deregister.
     */
    function deregisterOperatorFromAVS(address operator) public virtual onlyOwner {
        delegationManager.deregisterOperatorFromAVS(operator);
    }
}

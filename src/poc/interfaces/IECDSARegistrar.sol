// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";

/// @title ISignatureRegistrar
/// @notice Interface for common getters on for SignatureRegistrars, namely ECDSA and BLS
interface IECDSARegistrar {

    // TODO: Move to types/events/errors
    struct OperatorMetadata {
        address signingKey;
    }
    
    /**
     * @notice Registers a new operator using a provided operators signature and signing key.
     * @param operatorSignature Contains the operator's signature, salt, and expiry.
     * @param signingKey The signing key associated with the operator
     */
    function registerOperatorWithSig(address operator, ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature, address signingKey) external;

    /**
     * @notice Deregisters an existing operator.
     * @param operator The operator to deregister
     */
    function deregisterOperator(address operator) external;
}
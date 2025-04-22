// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

/// @title ISignatureRegistrar
/// @notice Interface for common getters on for SignatureRegistrars, namely ECDSA and BLS
interface ISignatureRegistrar {
    function registerOperator(address operator, address avs, uint32[] calldata operatorSetIds, bytes calldata data) external;
    function deregisterOperator(address operator, address avs, uint32[] calldata operatorSetIds) external;
    function supportsAVS(address avs) external view returns (bool);
}
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

interface IEOChainManager {
    /// @notice Registers a new data validator
    /// @param operator The address of the operator to register as a data validator
    /// @param stakes An array of stake amounts
    function registerDataValidator(address operator, uint96[] calldata stakes) external;

    /// @notice Registers a new chain validator
    /// @param operator The address of the operator to register as a chain validator
    /// @param stakes An array of stake amounts
    /// @param signature A 2-element array representing a signature
    /// @param pubkey A 4-element array representing a public key
    function registerChainValidator(
        address operator,
        uint96[] calldata stakes,
        uint256[2] memory signature,
        uint256[4] memory pubkey
    ) external;

    /// @notice Deregisters a validator (data validators only)
    /// @param operator The address of the operator to deregister
    function deregisterValidator(address operator) external;

    /// @notice Updates the stake weights of a validator
    /// @param operator The address of the operator to update
    /// @param newStakeWeights An array of new stake amounts
    function updateOperator(address operator, uint96[] calldata newStakeWeights) external;
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

interface IAVSRegistrarErrors {
    /// @notice Thrown when a key is not registered
    error KeyNotRegistered();
    /// @notice Thrown when the caller is not the allocation manager
    error NotAllocationManager();
}

interface IAVSRegistrarEvents {
    /// @notice Emitted when a new operator is registered
    event OperatorRegistered(address indexed operator, uint32[] operatorSetIds);

    /// @notice Emitted when an operator is deregistered
    event OperatorDeregistered(address indexed operator, uint32[] operatorSetIds);
}

/// @notice Since we have already defined a public interface, we add the events and errors here
interface IAVSRegistrarInternal is IAVSRegistrarErrors, IAVSRegistrarEvents {}

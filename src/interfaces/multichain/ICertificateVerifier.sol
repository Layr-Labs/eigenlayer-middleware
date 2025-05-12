// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

interface ICertificateVerifierErrors {
    /// @notice Thrown when the table updater is not caller
    error OnlyTableUpdater();
    /// @notice Thrown when the table is too stale
    error TableStale();
    /// @notice Thrown when certificate verification fails
    error CertVerificationFailed();
}

/// @notice A base interface that verifies certificates for a given operatorSet
/// @notice This is a base interface that all curve certificate verifiers (eg. BN254, ECDSA) must implement
/// @dev A single `CertificateVerifier` can be used for ONLY 1 operatorSet
interface ICertificateVerifier is ICertificateVerifierErrors {
    /**
     * @notice sets the operator table updater
     * @param operatorTableUpdater the address of the operator table updater
     * @dev only callable by the owner
     */
    function setOperatorTableUpdater(
        address operatorTableUpdater
    ) external;

    /**
     * @notice Sets the ejector
     * @param ejector the address of the ejector
     * @dev only callable by the owner
     */
    function setEjector(
        address ejector
    ) external;

    /**
     * @notice sets the max operator table staleness
     * @param maxOperatorTableStaleness the max operator table staleness
     * @dev only callable by the owner
     */
    function setMaxOperatorTableStaleness(
        uint32 maxOperatorTableStaleness
    ) external;

    /// @notice the operatorSet the CertificateVerifier is for
    function operatorSet() external returns (OperatorSet memory);

    /// @notice the address of the entity that can update the operator table
    function operatorTableUpdater() external returns (address);

    /// @notice the address of the entity that can eject operators
    function ejector() external returns (address);

    /// @return the maximum amount of seconds that a operator table can be in the past
    function maxOperatorTableStaleness() external returns (uint32);

    /// @notice The latest reference timestamp of the operator table
    function latestReferenceTimestamp() external returns (uint32);
}

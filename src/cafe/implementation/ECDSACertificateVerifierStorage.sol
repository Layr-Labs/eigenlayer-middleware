// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./interfaces/IECDSATypes.sol";
import "./interfaces/IECDSACertificateVerifier.sol";

/**
 * @title ECDSACertificateVerifierStorage
 * @notice Storage contract for the ECDSA Certificate Verifier
 * @dev Following the Diamond storage pattern to isolate storage variables
 *      This prevents storage collision issues during upgrades
 */
abstract contract ECDSACertificateVerifierStorage is IECDSACertificateVerifierEvents {
    /// @notice The operator set this verifier is for
    IECDSATypes.OperatorSet internal _operatorSet;
    
    /// @notice The address authorized to update the operator table
    address internal _operatorTableUpdater;
    
    /// @notice The maximum time (in seconds) an operator table can be stale
    uint32 internal _maxOperatorTableStaleness;
    
    /// @notice The timestamp at which the current operator table was sourced
    uint32 internal _currentTableReferenceTimestamp;
    
    /// @notice The current operator table
    IECDSATypes.ECDSAOperatorInfo[] internal _operatorTable;
    
    /// @notice Total weights for each weight type across all operators
    uint96[] internal _totalWeights;
    
    /**
     * @notice Constructor for the storage contract
     * @param operatorSet_ The operator set this verifier is for
     * @param operatorTableUpdater_ The address authorized to update the operator table
     * @param maxOperatorTableStaleness_ The maximum operator table staleness in seconds
     */
    constructor(
        IECDSATypes.OperatorSet memory operatorSet_,
        address operatorTableUpdater_,
        uint32 maxOperatorTableStaleness_
    ) {
        _operatorSet = operatorSet_;
        _operatorTableUpdater = operatorTableUpdater_;
        _maxOperatorTableStaleness = maxOperatorTableStaleness_;
    }
} 
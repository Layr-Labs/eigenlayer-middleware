// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./IECDSATypes.sol";

/**
 * @title IECDSACertificateVerifierErrors
 * @notice Interface defining errors for the ECDSA Certificate Verifier
 */
interface IECDSACertificateVerifierErrors {
    /**
     * @notice Error thrown when the operator table is too stale for verification
     * @param referenceTimestamp The timestamp in the certificate
     * @param currentTimestamp The current block timestamp
     * @param maxStaleness The maximum allowed staleness
     */
    error StaleOperatorTable(uint32 referenceTimestamp, uint256 currentTimestamp, uint32 maxStaleness);
    
    /**
     * @notice Error thrown when the caller is not the authorized table updater
     * @param caller The address that called the function
     * @param authorizedUpdater The address authorized to update the table
     */
    error UnauthorizedTableUpdater(address caller, address authorizedUpdater);
    
    /**
     * @notice Error thrown when the provided weights array length doesn't match expected
     * @param providedLength The length of the provided weights array
     * @param expectedLength The expected length
     */
    error InvalidWeightsLength(uint256 providedLength, uint256 expectedLength);
    
    /**
     * @notice Error thrown when signatures are not sorted in ascending order
     */
    error UnsortedOperators();
    
    /**
     * @notice Error thrown when a signature verification fails
     * @param operatorIndex The index of the operator with invalid signature
     */
    error InvalidSignature(uint256 operatorIndex);
    
    /**
     * @notice Error thrown when a threshold check fails
     * @param thresholdIndex The index of the threshold that wasn't met
     * @param signedStake The total signed stake
     * @param requiredStake The required stake threshold
     */
    error ThresholdNotMet(uint256 thresholdIndex, uint256 signedStake, uint256 requiredStake);
}

/**
 * @title IECDSACertificateVerifierEvents
 * @notice Interface defining events for the ECDSA Certificate Verifier
 */
interface IECDSACertificateVerifierEvents {
    /**
     * @notice Emitted when the operator table is updated
     * @param referenceTimestamp The timestamp at which the table was sourced
     * @param operatorCount The number of operators in the updated table
     */
    event OperatorTableUpdated(uint32 indexed referenceTimestamp, uint256 operatorCount);
    
    /**
     * @notice Emitted when operators are ejected from the table
     * @param referenceTimestamp The timestamp of the table the operators were ejected from
     * @param operatorIndices The indices of the ejected operators
     * @param operatorAddresses The addresses of the ejected operators
     */
    event OperatorsEjected(
        uint32 indexed referenceTimestamp, 
        uint32[] operatorIndices, 
        address[] operatorAddresses
    );
    
    /**
     * @notice Emitted when a certificate is verified successfully
     * @param referenceTimestamp The timestamp of the operator table used for verification
     * @param messageHash The hash of the message that was signed
     * @param signedStakes The amounts of stake that signed the certificate
     */
    event CertificateVerified(
        uint32 indexed referenceTimestamp,
        bytes32 indexed messageHash,
        uint96[] signedStakes
    );
    
    /**
     * @notice Emitted when the operator table updater address is changed
     * @param previousUpdater The previous updater address
     * @param newUpdater The new updater address
     */
    event OperatorTableUpdaterChanged(address indexed previousUpdater, address indexed newUpdater);
    
    /**
     * @notice Emitted when the maximum operator table staleness is changed
     * @param previousStaleness The previous maximum staleness in seconds
     * @param newStaleness The new maximum staleness in seconds
     */
    event MaxStalenessPeriodChanged(uint32 previousStaleness, uint32 newStaleness);
}

/**
 * @title IECDSACertificateVerifier
 * @notice Interface for verifying certificates using ECDSA signatures
 * @dev This contract maintains an operator table and verifies certificates
 *      against it using both proportional and nominal thresholds
 */
interface IECDSACertificateVerifier is 
    IECDSACertificateVerifierErrors, 
    IECDSACertificateVerifierEvents 
{
    /* STORAGE ACCESSORS */

    /**
     * @notice Returns the operator set this verifier is for
     * @return The operator set details
     */
    function operatorSet() external view returns(IECDSATypes.OperatorSet memory);
    
    /**
     * @notice Returns the address authorized to update the operator table
     * @return The updater address
     */
    function operatorTableUpdater() external view returns(address);
    
    /**
     * @notice Returns the maximum staleness allowed for an operator table
     * @return The maximum staleness in seconds
     */
    function maxOperatorTableStaleness() external view returns(uint32);
    
    /**
     * @notice Returns the timestamp at which the current operator table was sourced
     * @return The reference timestamp
     */
    function currentTableReferenceTimestamp() external view returns(uint32);
    
    /**
     * @notice Returns the total weights for each weight type across all operators
     * @return Array of total weights
     */
    function totalWeights() external view returns(uint96[] memory);
    
    /* ACTIONS */
    
    /**
     * @notice Updates the operator table
     * @param referenceTimestamp The timestamp at which the operator infos were sourced
     * @param operatorInfos The new operator information array
     * @dev Only callable by the operatorTableUpdater
     * @dev Operators must be sorted in ascending order by pubkey
     */
    function updateOperatorTable(
        uint32 referenceTimestamp, 
        IECDSATypes.ECDSAOperatorInfo[] memory operatorInfos
    ) external;
    
    /**
     * @notice Ejects operators from the operator set
     * @param referenceTimestamp The timestamp of the operator table to eject from
     * @param operatorIndices The indices of the operators to eject
     * @dev Only callable by the operatorTableUpdater
     */
    function ejectOperators(
        uint32 referenceTimestamp,
        uint32[] memory operatorIndices
    ) external;
    
    /**
     * @notice Updates the address authorized to update the operator table
     * @param newOperatorTableUpdater The new updater address
     * @dev Only callable by the owner
     */
    function setOperatorTableUpdater(address newOperatorTableUpdater) external;
    
    /**
     * @notice Updates the maximum operator table staleness
     * @param newMaxStaleness The new maximum staleness in seconds
     * @dev Only callable by the owner
     */
    function setMaxOperatorTableStaleness(uint32 newMaxStaleness) external;
    
    /* VIEW */
    
    /**
     * @notice Verifies a certificate and returns the stake that signed it
     * @param cert The certificate to verify
     * @return signedStakes Array of signed stakes for each stake type
     * @dev This is the base verification function used by the other verification methods
     */
    function verifyCertificate(IECDSATypes.ECDSACertificate memory cert) 
        external view returns(uint96[] memory signedStakes);
        
    /**
     * @notice Verifies a certificate against proportional stake thresholds
     * @param cert The certificate to verify
     * @param totalStakeProportionThresholds The proportion thresholds in basis points
     * @return True if the certificate is valid and meets all thresholds
     * @dev Each threshold in the array corresponds to a stake type in the weights array
     */
    function verifyCertificateProportion(
        IECDSATypes.ECDSACertificate memory cert, 
        uint16[] memory totalStakeProportionThresholds
    ) external returns(bool);
    
    /**
     * @notice Verifies a certificate against nominal stake thresholds
     * @param cert The certificate to verify
     * @param totalStakeNominalThresholds The absolute stake amount thresholds
     * @return True if the certificate is valid and meets all thresholds
     * @dev Each threshold in the array corresponds to a stake type in the weights array
     */
    function verifyCertificateNominal(
        IECDSATypes.ECDSACertificate memory cert, 
        uint96[] memory totalStakeNominalThresholds
    ) external returns(bool);
    
    /**
     * @notice Gets the operator information at a specific index
     * @param index The index of the operator in the table
     * @return The operator information
     */
    function getOperatorInfoAt(uint256 index) 
        external view returns(IECDSATypes.ECDSAOperatorInfo memory);
    
    /**
     * @notice Gets the current number of operators in the table
     * @return The number of operators
     */
    function getOperatorCount() external view returns(uint256);
} 
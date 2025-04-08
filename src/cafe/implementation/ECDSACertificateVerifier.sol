// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./interfaces/IECDSATypes.sol";
import "./interfaces/IECDSACertificateVerifier.sol";
import "./ECDSACertificateVerifierStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title ECDSACertificateVerifier
 * @notice Verifies certificates issued by operators in an AVS
 * @dev Manages an operator table and verifies ECDSA signatures against operator
 *      weights, supporting both proportional and nominal threshold validation
 */
contract ECDSACertificateVerifier is 
    ECDSACertificateVerifierStorage, 
    IECDSACertificateVerifier, 
    Ownable, 
    ReentrancyGuard 
{
    using ECDSA for bytes32;

    /* ========== CONSTANTS ========== */
    
    /// @dev Denominator for proportion calculations in basis points
    uint16 private constant BPS_DENOMINATOR = 10000;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructs a new certificate verifier
     * @param operatorSet_ The operator set this verifier is for
     * @param operatorTableUpdater_ The address authorized to update operator tables
     * @param maxOperatorTableStaleness_ Maximum allowed operator table staleness in seconds
     */
    constructor(
        IECDSATypes.OperatorSet memory operatorSet_,
        address operatorTableUpdater_,
        uint32 maxOperatorTableStaleness_
    ) ECDSACertificateVerifierStorage(operatorSet_, operatorTableUpdater_, maxOperatorTableStaleness_) {
        // Validate input parameters
        if (operatorTableUpdater_ == address(0)) {
            revert UnauthorizedTableUpdater(address(0), address(0));
        }
        
        if (maxOperatorTableStaleness_ == 0) {
            revert StaleOperatorTable(0, block.timestamp, 0);
        }
        
        if (operatorSet_.avs == address(0)) {
            revert StaleOperatorTable(0, block.timestamp, maxOperatorTableStaleness_);
        }
        
        // Transfer ownership to msg.sender
        _transferOwnership(msg.sender);
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function operatorSet() external view returns (IECDSATypes.OperatorSet memory) {
        return _operatorSet;
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function operatorTableUpdater() external view returns (address) {
        return _operatorTableUpdater;
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function maxOperatorTableStaleness() external view returns (uint32) {
        return _maxOperatorTableStaleness;
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function currentTableReferenceTimestamp() external view returns (uint32) {
        return _currentTableReferenceTimestamp;
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function totalWeights() external view returns (uint96[] memory) {
        return _totalWeights;
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function getOperatorInfoAt(uint256 index) 
        external view returns (IECDSATypes.ECDSAOperatorInfo memory) 
    {
        if (index >= _operatorTable.length) {
            revert InvalidWeightsLength(index, _operatorTable.length);
        }
        return _operatorTable[index];
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function getOperatorCount() external view returns (uint256) {
        return _operatorTable.length;
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function verifyCertificate(IECDSATypes.ECDSACertificate memory cert) 
        public view returns (uint96[] memory) 
    {
        // Check that the certificate's fields are valid
        if (cert.referenceTimestamp == 0 || cert.messageHash == bytes32(0) || cert.sig.length == 0) {
            revert InvalidSignature(0);
        }
        
        // Check that the table isn't stale
        _validateTableFreshness(cert.referenceTimestamp);
        
        // Decode signatures from the certificate
        (address[] memory signers, bytes[] memory signatures) = _decodeSignatures(cert.sig);
        
        // Initialize stakes array with same length as total weights
        uint96[] memory signedStakes = new uint96[](_totalWeights.length);
        
        // Validate signatures and accumulate weights
        for (uint256 i = 0; i < signers.length; i++) {
            // Verify the signature
            bool isValid = _verifySignature(signers[i], cert.messageHash, signatures[i]);
            if (!isValid) {
                revert InvalidSignature(i);
            }
            
            // Find operator in the table (binary search)
            int256 index = _findOperatorIndex(signers[i]);
            if (index >= 0) {
                // Add operator's weights to signed stakes
                IECDSATypes.ECDSAOperatorInfo memory operator = _operatorTable[uint256(index)];
                for (uint256 j = 0; j < signedStakes.length; j++) {
                    signedStakes[j] += operator.weights[j];
                }
            }
        }
        
        return signedStakes;
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function updateOperatorTable(
        uint32 referenceTimestamp,
        IECDSATypes.ECDSAOperatorInfo[] memory operatorInfos
    ) external nonReentrant {
        // Check caller authorization
        if (msg.sender != _operatorTableUpdater) {
            revert UnauthorizedTableUpdater(msg.sender, _operatorTableUpdater);
        }

        // Basic validation
        if (operatorInfos.length == 0) {
            revert InvalidWeightsLength(0, 1);
        }
        
        if (referenceTimestamp > block.timestamp) {
            revert StaleOperatorTable(referenceTimestamp, block.timestamp, _maxOperatorTableStaleness);
        }
        
        // Validate operator sorting and weights consistency
        _validateOperatorTable(operatorInfos);
        
        // Store the table reference timestamp
        _currentTableReferenceTimestamp = referenceTimestamp;
        
        // Clear previous operator table
        delete _operatorTable;
        
        // Calculate total weights
        uint96[] memory newTotalWeights;
        if (operatorInfos.length > 0) {
            // Initialize total weights array with same length as first operator's weights
            uint256 weightCount = operatorInfos[0].weights.length;
            newTotalWeights = new uint96[](weightCount);
            
            // Add each operator's weights to the total
            for (uint256 i = 0; i < operatorInfos.length; i++) {
                for (uint256 j = 0; j < weightCount; j++) {
                    newTotalWeights[j] += operatorInfos[i].weights[j];
                }
                
                // Add operator to the table
                _operatorTable.push(operatorInfos[i]);
            }
        }
        
        // Update total weights
        _totalWeights = newTotalWeights;
        
        emit OperatorTableUpdated(referenceTimestamp, operatorInfos.length);
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function ejectOperators(
        uint32 referenceTimestamp,
        uint32[] memory operatorIndices
    ) external nonReentrant {
        // Check caller authorization
        if (msg.sender != _operatorTableUpdater) {
            revert UnauthorizedTableUpdater(msg.sender, _operatorTableUpdater);
        }
        
        // Verify reference timestamp matches current table
        if (referenceTimestamp != _currentTableReferenceTimestamp) {
            revert StaleOperatorTable(referenceTimestamp, block.timestamp, _maxOperatorTableStaleness);
        }
        
        // Validate indices
        for (uint256 i = 0; i < operatorIndices.length; i++) {
            if (operatorIndices[i] >= _operatorTable.length) {
                revert InvalidWeightsLength(operatorIndices[i], _operatorTable.length);
            }
        }
        
        // Sort indices in descending order for safe removal
        _sortIndicesDescending(operatorIndices);
        
        // Collect operator addresses for event
        address[] memory operatorAddresses = new address[](operatorIndices.length);
        
        // Remove operators from highest index to lowest
        for (uint256 i = 0; i < operatorIndices.length; i++) {
            uint32 index = operatorIndices[i];
            
            // Store operator address for event
            operatorAddresses[i] = _operatorTable[index].pubkey;
            
            // Subtract operator's weights from total weights
            for (uint256 j = 0; j < _totalWeights.length; j++) {
                _totalWeights[j] -= _operatorTable[index].weights[j];
            }
            
            // Remove operator by replacing with the last element and popping
            if (index < _operatorTable.length - 1) {
                _operatorTable[index] = _operatorTable[_operatorTable.length - 1];
            }
            _operatorTable.pop();
        }
        
        emit OperatorsEjected(referenceTimestamp, operatorIndices, operatorAddresses);
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function setOperatorTableUpdater(address newOperatorTableUpdater) external onlyOwner {
        if (newOperatorTableUpdater == address(0)) {
            revert UnauthorizedTableUpdater(address(0), _operatorTableUpdater);
        }
        address previousUpdater = _operatorTableUpdater;
        _operatorTableUpdater = newOperatorTableUpdater;
        
        emit OperatorTableUpdaterChanged(previousUpdater, newOperatorTableUpdater);
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function setMaxOperatorTableStaleness(uint32 newMaxStaleness) external onlyOwner {
        if (newMaxStaleness == 0) {
            revert StaleOperatorTable(0, block.timestamp, _maxOperatorTableStaleness);
        }
        uint32 previousStaleness = _maxOperatorTableStaleness;
        _maxOperatorTableStaleness = newMaxStaleness;
        
        emit MaxStalenessPeriodChanged(previousStaleness, newMaxStaleness);
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function verifyCertificateProportion(
        IECDSATypes.ECDSACertificate memory cert,
        uint16[] memory totalStakeProportionThresholds
    ) external returns (bool) {
        // Get signed stakes
        uint96[] memory signedStakes = verifyCertificate(cert);
        
        // Validate thresholds length
        if (totalStakeProportionThresholds.length != signedStakes.length) {
            revert InvalidWeightsLength(totalStakeProportionThresholds.length, signedStakes.length);
        }
        
        // Check if each stake type meets its proportion threshold
        for (uint256 i = 0; i < signedStakes.length; i++) {
            // Skip if no threshold (0 means no validation)
            if (totalStakeProportionThresholds[i] == 0) continue;
            
            // Calculate required stake based on proportion
            uint256 requiredStake = (uint256(_totalWeights[i]) * totalStakeProportionThresholds[i]) / BPS_DENOMINATOR;
            
            // Check if signed stake meets required stake
            if (signedStakes[i] < requiredStake) {
                revert ThresholdNotMet(i, signedStakes[i], requiredStake);
            }
        }

        // Emit the verification event
        emit CertificateVerified(cert.referenceTimestamp, cert.messageHash, signedStakes);
        
        return true;
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function verifyCertificateNominal(
        IECDSATypes.ECDSACertificate memory cert,
        uint96[] memory totalStakeNominalThresholds
    ) external returns (bool) {
        // Get signed stakes
        uint96[] memory signedStakes = verifyCertificate(cert);
        
        // Validate thresholds length
        if (totalStakeNominalThresholds.length != signedStakes.length) {
            revert InvalidWeightsLength(totalStakeNominalThresholds.length, signedStakes.length);
        }
        
        // Check if each stake type meets its nominal threshold
        for (uint256 i = 0; i < signedStakes.length; i++) {
            // Skip if no threshold (0 means no validation)
            if (totalStakeNominalThresholds[i] == 0) continue;
            
            // Check if signed stake meets required stake
            if (signedStakes[i] < totalStakeNominalThresholds[i]) {
                revert ThresholdNotMet(i, signedStakes[i], totalStakeNominalThresholds[i]);
            }
        }

        // Emit the verification event
        emit CertificateVerified(cert.referenceTimestamp, cert.messageHash, signedStakes);
        
        return true;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice Validates the operator table by checking sorting and weights consistency
     * @param operatorInfos The operator table to validate
     */
    function _validateOperatorTable(IECDSATypes.ECDSAOperatorInfo[] memory operatorInfos) internal pure {
        // Check that operators are sorted by pubkey
        for (uint256 i = 1; i < operatorInfos.length; i++) {
            if (operatorInfos[i - 1].pubkey >= operatorInfos[i].pubkey) {
                revert UnsortedOperators();
            }
        }
        
        // Check that all operators have the same weights length
        uint256 weightCount = operatorInfos[0].weights.length;
        for (uint256 i = 1; i < operatorInfos.length; i++) {
            if (operatorInfos[i].weights.length != weightCount) {
                revert InvalidWeightsLength(operatorInfos[i].weights.length, weightCount);
            }
        }
    }

    /**
     * @notice Validates that the operator table is not stale
     * @param referenceTimestamp The timestamp to check against
     */
    function _validateTableFreshness(uint32 referenceTimestamp) internal view {
        // Check that referenceTimestamp matches current table
        if (referenceTimestamp != _currentTableReferenceTimestamp) {
            revert StaleOperatorTable(
                referenceTimestamp, 
                block.timestamp, 
                _maxOperatorTableStaleness
            );
        }
        
        // Check that the table is not too old
        if (block.timestamp > _currentTableReferenceTimestamp + _maxOperatorTableStaleness) {
            revert StaleOperatorTable(
                _currentTableReferenceTimestamp, 
                block.timestamp, 
                _maxOperatorTableStaleness
            );
        }
    }

    /**
     * @notice Decodes signatures from a certificate
     * @param sigData The encoded signature data
     * @return signers The addresses that signed the certificate
     * @return signatures The signatures corresponding to each signer
     */
    function _decodeSignatures(bytes memory sigData) internal pure returns (address[] memory, bytes[] memory) {
        // Decode the array
        (address[] memory signers, bytes[] memory signatures) = abi.decode(sigData, (address[], bytes[]));
        
        // Validate arrays
        if (signers.length == 0 || signatures.length == 0) {
            revert InvalidSignature(0);
        }
        
        if (signers.length != signatures.length) {
            revert InvalidWeightsLength(signers.length, signatures.length);
        }
        
        // Validate signers are sorted
        for (uint256 i = 1; i < signers.length; i++) {
            if (signers[i - 1] >= signers[i]) {
                revert UnsortedOperators();
            }
        }
        
        return (signers, signatures);
    }

    /**
     * @notice Verifies an ECDSA signature
     * @param signer The address that supposedly signed the message
     * @param messageHash The hash of the message that was signed
     * @param signature The signature to verify
     * @return True if the signature is valid, false otherwise
     */
    function _verifySignature(
        address signer, 
        bytes32 messageHash, 
        bytes memory signature
    ) internal pure returns (bool) {
        // Validate signature length to prevent malleability
        if (signature.length != 65) {
            return false;
        }
        
        // Hash the message according to EIP-191
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        
        // Recover signer address from signature
        address recoveredAddress = ethSignedMessageHash.recover(signature);
        
        // Guard against zero address (invalid signature)
        if (recoveredAddress == address(0)) {
            return false;
        }
        
        // Verify recovered address matches expected signer
        return recoveredAddress == signer;
    }

    /**
     * @notice Finds an operator in the operator table by pubkey
     * @param pubkey The pubkey to search for
     * @return The index of the operator in the table, or -1 if not found
     */
    function _findOperatorIndex(address pubkey) internal view returns (int256) {
        // Binary search for the operator
        int256 left = 0;
        int256 right = int256(_operatorTable.length) - 1;
        
        while (left <= right) {
            int256 mid = left + (right - left) / 2;
            
            if (_operatorTable[uint256(mid)].pubkey == pubkey) {
                return mid;
            }
            
            if (_operatorTable[uint256(mid)].pubkey < pubkey) {
                left = mid + 1;
            } else {
                right = mid - 1;
            }
        }
        
        return -1; // Not found
    }

    /**
     * @notice Sorts indices in descending order
     * @param indices The indices to sort
     */
    function _sortIndicesDescending(uint32[] memory indices) internal pure {
        // Simple bubble sort for small arrays
        for (uint256 i = 0; i < indices.length; i++) {
            for (uint256 j = 0; j < indices.length - i - 1; j++) {
                if (indices[j] < indices[j + 1]) {
                    uint32 temp = indices[j];
                    indices[j] = indices[j + 1];
                    indices[j + 1] = temp;
                }
            }
        }
    }
} 
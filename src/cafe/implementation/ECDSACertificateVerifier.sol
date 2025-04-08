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
        // Transfer ownership to msg.sender
        _transferOwnership(msg.sender);
    }

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
    function updateOperatorTable(
        uint32 referenceTimestamp,
        IECDSATypes.ECDSAOperatorInfo[] memory operatorInfos
    ) external nonReentrant {
        // Check caller authorization
        if (msg.sender != _operatorTableUpdater) {
            revert UnauthorizedTableUpdater(msg.sender, _operatorTableUpdater);
        }

        // Basic validation
        require(operatorInfos.length > 0, "Empty operator table");
        require(referenceTimestamp <= block.timestamp, "Future timestamp");
        
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
        require(referenceTimestamp == _currentTableReferenceTimestamp, "Timestamp mismatch");
        
        // Validate indices
        for (uint256 i = 0; i < operatorIndices.length; i++) {
            require(operatorIndices[i] < _operatorTable.length, "Invalid operator index");
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
        require(newOperatorTableUpdater != address(0), "Zero address");
        address previousUpdater = _operatorTableUpdater;
        _operatorTableUpdater = newOperatorTableUpdater;
        
        emit OperatorTableUpdaterChanged(previousUpdater, newOperatorTableUpdater);
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function setMaxOperatorTableStaleness(uint32 newMaxStaleness) external onlyOwner {
        require(newMaxStaleness > 0, "Zero staleness");
        uint32 previousStaleness = _maxOperatorTableStaleness;
        _maxOperatorTableStaleness = newMaxStaleness;
        
        emit MaxStalenessPeriodChanged(previousStaleness, newMaxStaleness);
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function verifyCertificate(
        IECDSATypes.ECDSACertificate memory cert
    ) public view returns (uint96[] memory) {
        return _verifyCertificate(cert);
    }

    /**
     * @dev Internal implementation of certificate verification
     * @param cert The certificate to verify
     * @return Array of stake amounts for each strategy signed by authenticated operators
     */
    function _verifyCertificate(
        IECDSATypes.ECDSACertificate memory cert
    ) internal view returns (uint96[] memory) {
        // Ensure that all of the necessary fields in the certificate are not the zero value or empty
        _verifyNonZeroCertificateFields(cert);

        // Validate that the certificate matches the current operator table
        _validateOperatorTable(cert.operatorTableHash);

        // Initialize arrays to track signer status and total signed stake
        uint256 numOperators = cert.signatures.length;
        uint96[] memory totalSignedStakeInStrategy = new uint96[](numStrategies);

        // Check signatures and accumulate stake
        for (uint256 i = 0; i < numOperators; i++) {
            address signer = _recoverSigner(cert.signatures[i], cert.digestHash);
            uint256 operatorId = _operatorIdForAddress[signer];
            
            // Skip if not a registered operator or already counted
            if (operatorId == 0) {
                continue;
            }

            // Get operator's stake across different strategies
            uint96[] memory operatorStakes = _operatorStakesByStrategy[operatorId];

            // Add operator's stake to each strategy's total
            for (uint256 strategyIdx = 0; strategyIdx < numStrategies; strategyIdx++) {
                totalSignedStakeInStrategy[strategyIdx] += operatorStakes[strategyIdx];
            }
        }

        emit CertificateVerified(cert.digestHash, cert.operatorTableHash);
        return totalSignedStakeInStrategy;
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function verifyCertificateProportion(
        IECDSATypes.ECDSACertificate memory cert,
        uint16[] memory totalStakeProportionThresholds
    ) external view returns (bool) {
        // Get signed stakes by calling the internal implementation
        uint96[] memory signedStakes = _verifyCertificate(cert);
        
        // Validate thresholds length
        if (totalStakeProportionThresholds.length != signedStakes.length) {
            revert InvalidWeightsLength(totalStakeProportionThresholds.length, signedStakes.length);
        }
        
        // Check if each stake type meets its proportion threshold
        for (uint256 i = 0; i < signedStakes.length; i++) {
            // Skip if no threshold (0 means no validation)
            if (totalStakeProportionThresholds[i] == 0) continue;
            
            // Calculate required stake based on proportion
            uint256 requiredStake = (uint256(_totalWeights[i]) * totalStakeProportionThresholds[i]) / 10000;
            
            // Check if signed stake meets required stake
            if (signedStakes[i] < requiredStake) {
                revert ThresholdNotMet(i, signedStakes[i], requiredStake);
            }
        }
        
        return true;
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function verifyCertificateNominal(
        IECDSATypes.ECDSACertificate memory cert,
        uint96[] memory totalStakeNominalThresholds
    ) external view returns (bool) {
        // Get signed stakes by calling the internal implementation
        uint96[] memory signedStakes = _verifyCertificate(cert);
        
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
        
        return true;
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function getOperatorInfoAt(uint256 index) 
        external view returns (IECDSATypes.ECDSAOperatorInfo memory) 
    {
        require(index < _operatorTable.length, "Index out of bounds");
        return _operatorTable[index];
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function getOperatorCount() external view returns (uint256) {
        return _operatorTable.length;
    }

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
        require(signers.length == signatures.length, "Length mismatch");
        require(signers.length > 0, "No signatures");
        
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
        // Hash the message according to EIP-191
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        
        // Recover signer address from signature
        address recoveredAddress = ethSignedMessageHash.recover(signature);
        
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
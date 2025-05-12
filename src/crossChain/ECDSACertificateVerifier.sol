// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {
    IECDSATableCalculator, IECDSATableCalculatorTypes
} from "../interfaces/IECDSATableCalculator.sol";
import {
    IECDSACertificateVerifier,
    IECDSACertificateVerifierTypes
} from "../interfaces/IECDSACertificateVerifier.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title ECDSACertificateVerifier
 * @notice Verifies ECDSA certificates against a given operator table
 * @dev This contract uses ECDSA for signature verification and stores all operator information in storage
 */
contract ECDSACertificateVerifier is IECDSACertificateVerifier, Ownable {
    using ECDSA for bytes32;

    // The operator set this verifier is for
    OperatorSet private _operatorSet;

    // The address that can update the operator table
    address private _operatorTableUpdater;

    // The latest reference timestamp of the operator table
    uint32 public latestReferenceTimestamp;

    // Maximum staleness allowed for an operator table (in seconds)
    uint32 private _maxOperatorTableStaleness;

    // Mapping from reference timestamp to number of operators
    mapping(uint32 => uint256) public operatorCount;
    
    // Mapping from reference timestamp to operator index to operator info
    mapping(uint32 => mapping(uint256 => IECDSATableCalculatorTypes.ECDSAOperatorInfo)) public operatorInfos;

    // Modifier to restrict access to the operator table updater
    modifier onlyTableUpdater() {
        if (msg.sender != _operatorTableUpdater) revert OnlyTableUpdater();
        _;
    }

    /**
     * @notice Constructor for the certificate verifier
     * @param __operatorSet The operator set this verifier is for
     * @param __operatorTableUpdater The address that can update the operator table
     * @param __maxOperatorTableStaleness Maximum staleness allowed for an operator table (in seconds)
     */
    constructor(
        OperatorSet memory __operatorSet,
        address __operatorTableUpdater,
        uint32 __maxOperatorTableStaleness
    ) {
        _operatorSet = __operatorSet;
        _operatorTableUpdater = __operatorTableUpdater;
        _maxOperatorTableStaleness = __maxOperatorTableStaleness;
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function operatorSet() external view returns (OperatorSet memory) {
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
    function updateOperatorTable(
        uint32 referenceTimestamp,
        IECDSATableCalculatorTypes.ECDSAOperatorInfo[] memory _operatorInfos
    ) external onlyTableUpdater {
        // Require that the new timestamp is greater than the latest reference timestamp
        require(referenceTimestamp > latestReferenceTimestamp, "Invalid timestamp");

        // Store the operator count
        operatorCount[referenceTimestamp] = _operatorInfos.length;
        
        // Store each operator info
        for (uint256 i = 0; i < _operatorInfos.length; i++) {
            operatorInfos[referenceTimestamp][i].pubkey = _operatorInfos[i].pubkey;
            
            // Delete any existing weights array data
            delete operatorInfos[referenceTimestamp][i].weights;
            
            // Copy each weight
            for (uint256 j = 0; j < _operatorInfos[i].weights.length; j++) {
                operatorInfos[referenceTimestamp][i].weights.push(_operatorInfos[i].weights[j]);
            }
        }

        // Update the latest reference timestamp
        latestReferenceTimestamp = referenceTimestamp;

        // Emit event
        emit TableUpdated(referenceTimestamp, _operatorInfos.length);
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function ejectOperators(
        uint32 referenceTimestamp,
        uint32[] calldata operatorIndices
    ) external onlyTableUpdater {
        // Ensure the reference timestamp exists
        require(operatorCount[referenceTimestamp] > 0, "Reference timestamp does not exist");

        // Process each operator to eject
        for (uint256 i = 0; i < operatorIndices.length; i++) {
            uint32 operatorIndex = operatorIndices[i];

            // Ensure index is valid
            require(operatorIndex < operatorCount[referenceTimestamp], "Operator index not valid");

            // Zero out the operator's weights
            uint96[] storage weights = operatorInfos[referenceTimestamp][operatorIndex].weights;
            for (uint256 j = 0; j < weights.length; j++) {
                weights[j] = 0;
            }

            // Emit event
            emit OperatorEjected(referenceTimestamp, operatorIndex);
        }
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function verifyCertificate(
        IECDSACertificateVerifierTypes.ECDSACertificate memory cert
    ) external view returns (uint96[] memory signedStakes) {
        return _verifyCertificate(cert);
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function verifyCertificateProportion(
        IECDSACertificateVerifierTypes.ECDSACertificate memory cert,
        uint16[] memory totalStakeProportionThresholds
    ) external view returns (bool) {
        // Get signed stakes
        uint96[] memory signedStakes = _verifyCertificate(cert);

        // Get total stakes
        uint96[] memory totalStakes = _getTotalStakes(cert.referenceTimestamp);

        // Verify that each stake meets the threshold
        require(signedStakes.length == totalStakeProportionThresholds.length, "Length mismatch");

        for (uint256 i = 0; i < signedStakes.length; i++) {
            // Calculate threshold as proportion of total stake
            // totalStakeProportionThresholds is a percentage with 2 decimal places (e.g. 6600 = 66%)
            uint96 threshold =
                uint96(uint256(totalStakes[i]) * uint256(totalStakeProportionThresholds[i]) / 10000);

            // If signed stake doesn't meet threshold, return false
            if (signedStakes[i] < threshold) {
                return false;
            }
        }

        return true;
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function verifyCertificateNominal(
        IECDSACertificateVerifierTypes.ECDSACertificate memory cert,
        uint96[] memory totalStakeNominalThresholds
    ) external view returns (bool) {
        // Get signed stakes
        uint96[] memory signedStakes = _verifyCertificate(cert);

        // Verify that each stake meets the threshold
        require(signedStakes.length == totalStakeNominalThresholds.length, "Length mismatch");

        for (uint256 i = 0; i < signedStakes.length; i++) {
            // If signed stake doesn't meet nominal threshold, return false
            if (signedStakes[i] < totalStakeNominalThresholds[i]) {
                return false;
            }
        }

        return true;
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function setOperatorTableUpdater(
        address _newOperatorTableUpdater
    ) external onlyOwner {
        _operatorTableUpdater = _newOperatorTableUpdater;
    }

    /**
     * @inheritdoc IECDSACertificateVerifier
     */
    function setMaxOperatorTableStaleness(
        uint32 _newMaxOperatorTableStaleness
    ) external onlyOwner {
        _maxOperatorTableStaleness = _newMaxOperatorTableStaleness;
    }

    /**
     * @notice Internal function to verify a certificate
     * @param cert The certificate to verify
     * @return signedStakes The amount of stake that signed the certificate for each stake type
     */
    function _verifyCertificate(
        IECDSACertificateVerifierTypes.ECDSACertificate memory cert
    ) internal view returns (uint96[] memory signedStakes) {
        // Check that the reference timestamp is not too stale
        if (block.timestamp > cert.referenceTimestamp + _maxOperatorTableStaleness) {
            revert TableStale();
        }

        // Check that the reference timestamp exists
        uint256 _operatorCount = operatorCount[cert.referenceTimestamp];
        require(_operatorCount > 0, "Reference timestamp does not exist");

        // Get the length of stakes arrays by checking the first operator
        uint96[] memory totalStakes = _getTotalStakes(cert.referenceTimestamp);
        signedStakes = new uint96[](totalStakes.length);

        // Parse the signatures
        (address[] memory signers, bool validSignatures) = _parseSignatures(cert.messageHash, cert.sig);
        
        if (!validSignatures) {
            revert CertVerificationFailed();
        }

        // Process each operator to check if they signed
        for (uint256 i = 0; i < _operatorCount; i++) {
            // Check if this operator is in the signers list
            bool isSigner = false;
            for (uint256 j = 0; j < signers.length; j++) {
                if (operatorInfos[cert.referenceTimestamp][i].pubkey == signers[j]) {
                    isSigner = true;
                    break;
                }
            }
            
            if (isSigner) {
                // Add this operator's weights to the signed stakes
                uint96[] storage weights = operatorInfos[cert.referenceTimestamp][i].weights;
                for (uint256 j = 0; j < weights.length && j < signedStakes.length; j++) {
                    signedStakes[j] += weights[j];
                }
            }
        }

        return signedStakes;
    }

    /**
     * @notice Parse signatures from the concatenated signature bytes
     * @param messageHash The message hash that was signed
     * @param signatures The concatenated signatures
     * @return signers Array of addresses that signed the message
     * @return valid Whether all signatures are valid
     */
    function _parseSignatures(
        bytes32 messageHash, 
        bytes memory signatures
    ) internal pure returns (address[] memory signers, bool valid) {
        // Each ECDSA signature is 65 bytes: r (32 bytes) + s (32 bytes) + v (1 byte)
        require(signatures.length % 65 == 0, "Invalid signature length");
        
        uint256 signatureCount = signatures.length / 65;
        signers = new address[](signatureCount);
        
        for (uint256 i = 0; i < signatureCount; i++) {
            bytes memory signature = new bytes(65);
            for (uint256 j = 0; j < 65; j++) {
                signature[j] = signatures[i * 65 + j];
            }
            
            // Recover the signer
            address signer = messageHash.recover(signature);
            
            // If any signature is invalid (returns address(0)), the whole certificate is invalid
            if (signer == address(0)) {
                return (signers, false);
            }
            
            // Check for duplicate signers
            for (uint256 j = 0; j < i; j++) {
                if (signers[j] == signer) {
                    return (signers, false);
                }
            }
            
            signers[i] = signer;
        }
        
        return (signers, true);
    }

    /**
     * @notice Calculate the total stakes for all operators at a given reference timestamp
     * @param referenceTimestamp The reference timestamp
     * @return totalStakes The total stakes for all operators
     */
    function _getTotalStakes(
        uint32 referenceTimestamp
    ) internal view returns (uint96[] memory totalStakes) {
        // Ensure the reference timestamp exists
        uint256 _operatorCount = operatorCount[referenceTimestamp];
        require(_operatorCount > 0, "Reference timestamp does not exist");
        
        // Use the first operator to determine the number of stake types
        uint256 stakeTypesCount = operatorInfos[referenceTimestamp][0].weights.length;
        totalStakes = new uint96[](stakeTypesCount);
        
        // Sum up all stakes for all operators
        for (uint256 i = 0; i < _operatorCount; i++) {
            uint96[] storage weights = operatorInfos[referenceTimestamp][i].weights;
            for (uint256 j = 0; j < weights.length && j < stakeTypesCount; j++) {
                totalStakes[j] += weights[j];
            }
        }
        
        return totalStakes;
    }

    /**
     * @notice Get operator info for a specific index at a reference timestamp
     * @param referenceTimestamp The reference timestamp
     * @param operatorIndex The index of the operator
     * @return The operator info
     */
    function getOperatorInfo(
        uint32 referenceTimestamp,
        uint256 operatorIndex
    ) external view returns (IECDSATableCalculatorTypes.ECDSAOperatorInfo memory) {
        require(operatorIndex < operatorCount[referenceTimestamp], "Invalid operator index");
        return operatorInfos[referenceTimestamp][operatorIndex];
    }

    /**
     * @notice Get all operator infos at a reference timestamp
     * @param referenceTimestamp The reference timestamp
     * @return The array of operator infos
     */
    function getAllOperatorInfos(
        uint32 referenceTimestamp
    ) external view returns (IECDSATableCalculatorTypes.ECDSAOperatorInfo[] memory) {
        uint256 count = operatorCount[referenceTimestamp];
        IECDSATableCalculatorTypes.ECDSAOperatorInfo[] memory infos = 
            new IECDSATableCalculatorTypes.ECDSAOperatorInfo[](count);
            
        for (uint256 i = 0; i < count; i++) {
            infos[i] = operatorInfos[referenceTimestamp][i];
        }
        
        return infos;
    }
}
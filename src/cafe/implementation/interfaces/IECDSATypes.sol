// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IECDSATypes
 * @notice Interface containing core data structures for ECDSA certificate verification
 * @dev This interface separates type definitions for better organization and reusability
 */
interface IECDSATypes {
    /**
     * @notice Represents an operator set within an AVS (Actively Validated Service)
     * @param avs The address of the AVS that this operator set belongs to
     * @param id The unique identifier for this operator set within the AVS
     */
    struct OperatorSet {
        address avs;
        uint32 id;
    }

    /**
     * @notice Information about an operator in the operator table
     * @param pubkey The ECDSA public key (address) of the operator
     * @param weights Array of stake weights that can be used for verification
     * @dev The weights array can have different configurations:
     *      - Single value [slashable_weight]
     *      - Two values [slashable_weight, delegated_weight]
     *      - Multiple values for different strategies [weight_1, weight_2, ...]
     */
    struct ECDSAOperatorInfo {
        address pubkey;
        uint96[] weights;
    }

    /**
     * @notice Contains the data needed to verify a certificate
     * @param referenceTimestamp The timestamp identifying which operator table to verify against
     * @param messageHash The hash of the message that was signed
     * @param sig The concatenated signatures of all operators that signed
     */
    struct ECDSACertificate {
        uint32 referenceTimestamp;
        bytes32 messageHash;
        bytes sig;
    }
}

/**
 * @title ECDSAConstants
 * @notice Library with constants for ECDSA certificate verification
 * @dev Contains constants that can be used across multiple contracts
 */
library ECDSAConstants {
    /**
     * @dev Constants for weight array indices
     * These constants help provide semantic meaning to weight array indices
     */
    uint8 constant SLASHABLE_WEIGHT_INDEX = 0;
    uint8 constant DELEGATED_WEIGHT_INDEX = 1;

    /**
     * @dev Constants for basis points calculations
     */
    uint16 constant BPS_DENOMINATOR = 10000;
} 
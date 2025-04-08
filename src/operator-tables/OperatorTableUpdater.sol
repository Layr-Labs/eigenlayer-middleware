// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet, OperatorSetLib} from "lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IECDSAOperatorTableCalculator, ECDSAOperatorInfo} from "./ECDSAOperatorTableCalculator.sol";
import {IBN254OperatorTableCalculator, BN254OperatorSetInfo, BN254OperatorInfo} from "./BN254OperatorTableCalculator.sol";
import {BN254OperatorInfoWitness} from "../certificate-verifiers/BN254CertificateVerifier.sol";

/**
 * @title OperatorTableUpdater
 * @notice Updater contract that calculates operator tables and updates certificate verifiers
 * @dev This contract would be controlled by a secure mechanism (e.g., multisig, another AVS)
 */
contract OperatorTableUpdater {
    /// @notice The owner of the updater
    address public owner;
    
    /// @notice ECDSA operator table calculator
    IECDSAOperatorTableCalculator public ecdsaCalculator;
    
    /// @notice BN254 operator table calculator
    IBN254OperatorTableCalculator public bn254Calculator;
    
    /// @notice Mapping from operator set key to ECDSA verifier
    mapping(bytes32 => address) public ecdsaVerifiers;
    
    /// @notice Mapping from operator set key to BN254 verifier
    mapping(bytes32 => address) public bn254Verifiers;
    
    /**
     * @notice Event emitted when a verifier is registered
     * @param operatorSetKey The key for the operator set
     * @param verifierAddress The address of the registered verifier
     * @param isECDSA Whether the verifier is ECDSA (true) or BN254 (false)
     */
    event VerifierRegistered(bytes32 indexed operatorSetKey, address indexed verifierAddress, bool isECDSA);
    
    /**
     * @notice Event emitted when an ECDSA operator table is updated
     * @param operatorSet The operator set that was updated
     * @param verifier The verifier that was updated
     * @param referenceTimestamp The timestamp of the update
     * @param numOperators The number of operators in the table
     */
    event ECDSAOperatorTableUpdated(
        OperatorSet operatorSet,
        address indexed verifier,
        uint32 referenceTimestamp,
        uint32 numOperators
    );
    
    /**
     * @notice Event emitted when a BN254 operator table is updated
     * @param operatorSet The operator set that was updated
     * @param verifier The verifier that was updated
     * @param referenceTimestamp The timestamp of the update
     * @param numOperators The number of operators in the table
     */
    event BN254OperatorTableUpdated(
        OperatorSet operatorSet,
        address indexed verifier,
        uint32 referenceTimestamp,
        uint32 numOperators
    );
    
    /**
     * @dev Constructor to initialize the updater
     * @param _ecdsaCalculator The ECDSA operator table calculator
     * @param _bn254Calculator The BN254 operator table calculator
     */
    constructor(
        IECDSAOperatorTableCalculator _ecdsaCalculator,
        IBN254OperatorTableCalculator _bn254Calculator
    ) {
        owner = msg.sender;
        ecdsaCalculator = _ecdsaCalculator;
        bn254Calculator = _bn254Calculator;
    }
    
    /**
     * @notice Register a verifier for an operator set
     * @param operatorSet The operator set to register the verifier for
     * @param verifierAddress The address of the verifier
     * @param isECDSA Whether the verifier is ECDSA (true) or BN254 (false)
     */
    function registerVerifier(
        OperatorSet calldata operatorSet,
        address verifierAddress,
        bool isECDSA
    ) external {
        require(msg.sender == owner, "Not authorized");
        
        bytes32 operatorSetKey = OperatorSetLib.key(operatorSet);
        
        if (isECDSA) {
            ecdsaVerifiers[operatorSetKey] = verifierAddress;
        } else {
            bn254Verifiers[operatorSetKey] = verifierAddress;
        }
        
        emit VerifierRegistered(operatorSetKey, verifierAddress, isECDSA);
    }
    
    /**
     * @notice Update the ECDSA operator table for an operator set
     * @param operatorSet The operator set to update
     * @param referenceTimestamp The timestamp of the update
     */
    function updateECDSAOperatorTable(
        OperatorSet calldata operatorSet,
        uint32 referenceTimestamp
    ) external {
        require(msg.sender == owner, "Not authorized");
        
        bytes32 operatorSetKey = OperatorSetLib.key(operatorSet);
        address verifier = ecdsaVerifiers[operatorSetKey];
        
        require(verifier != address(0), "Verifier not registered");
        
        // Calculate the operator table
        ECDSAOperatorInfo[] memory operatorInfos = ecdsaCalculator.calculateOperatorTable(operatorSet);
        
        // Update the verifier
        (bool success,) = verifier.call(
            abi.encodeWithSignature(
                "updateOperatorTable(uint32,(address,uint96[])[])",
                referenceTimestamp,
                operatorInfos
            )
        );
        
        require(success, "Verifier update failed");
        
        emit ECDSAOperatorTableUpdated(
            operatorSet,
            verifier,
            referenceTimestamp,
            uint32(operatorInfos.length)
        );
    }
    
    /**
     * @notice Update the BN254 operator table for an operator set
     * @param operatorSet The operator set to update
     * @param referenceTimestamp The timestamp of the update
     */
    function updateBN254OperatorTable(
        OperatorSet calldata operatorSet,
        uint32 referenceTimestamp
    ) external {
        require(msg.sender == owner, "Not authorized");
        
        bytes32 operatorSetKey = OperatorSetLib.key(operatorSet);
        address verifier = bn254Verifiers[operatorSetKey];
        
        require(verifier != address(0), "Verifier not registered");
        
        // Calculate the operator table
        BN254OperatorSetInfo memory operatorSetInfo = bn254Calculator.calculateOperatorTable(operatorSet);
        
        // Update the verifier
        (bool success,) = verifier.call(
            abi.encodeWithSignature(
                "updateOperatorTable(uint32,(bytes32,uint32,(uint256,uint256),uint96[]))",
                referenceTimestamp,
                operatorSetInfo.operatorInfoTreeRoot,
                operatorSetInfo.numOperators,
                operatorSetInfo.aggregatePubkey,
                operatorSetInfo.totalWeights
            )
        );
        
        require(success, "Verifier update failed");
        
        emit BN254OperatorTableUpdated(
            operatorSet,
            verifier,
            referenceTimestamp,
            operatorSetInfo.numOperators
        );
    }
    
    /**
     * @notice Eject operators from an ECDSA operator set
     * @param operatorSet The operator set to eject from
     * @param referenceTimestamp The timestamp of the operator table to eject from
     * @param operatorIndices The indices of the operators to eject
     */
    function ejectECDSAOperators(
        OperatorSet calldata operatorSet,
        uint32 referenceTimestamp,
        uint32[] calldata operatorIndices
    ) external {
        require(msg.sender == owner, "Not authorized");
        
        bytes32 operatorSetKey = OperatorSetLib.key(operatorSet);
        address verifier = ecdsaVerifiers[operatorSetKey];
        
        require(verifier != address(0), "Verifier not registered");
        
        // Eject the operators
        (bool success,) = verifier.call(
            abi.encodeWithSignature(
                "ejectOperators(uint32,uint32[])",
                referenceTimestamp,
                operatorIndices
            )
        );
        
        require(success, "Verifier eject failed");
    }
    
    /**
     * @notice Eject operators from a BN254 operator set
     * @param operatorSet The operator set to eject from
     * @param referenceTimestamp The timestamp of the operator table to eject from
     * @param operatorIndices The indices of the operators to eject
     * @param witnesses The witnesses for operators not already in storage
     */
    function ejectBN254Operators(
        OperatorSet calldata operatorSet,
        uint32 referenceTimestamp,
        uint32[] calldata operatorIndices,
        BN254OperatorInfoWitness[] calldata witnesses
    ) external {
        require(msg.sender == owner, "Not authorized");
        
        bytes32 operatorSetKey = OperatorSetLib.key(operatorSet);
        address verifier = bn254Verifiers[operatorSetKey];
        
        require(verifier != address(0), "Verifier not registered");
        
        // Eject the operators
        (bool success,) = verifier.call(
            abi.encodeWithSignature(
                "ejectOperators(uint32,uint32[],(uint32,bytes,(uint256,uint256,uint96[])[]))",
                referenceTimestamp,
                operatorIndices,
                witnesses
            )
        );
        
        require(success, "Verifier eject failed");
    }
    
    /**
     * @notice Transfer ownership of the updater
     * @param newOwner The new owner address
     */
    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "Not authorized");
        require(newOwner != address(0), "Invalid owner");
        
        owner = newOwner;
    }
}
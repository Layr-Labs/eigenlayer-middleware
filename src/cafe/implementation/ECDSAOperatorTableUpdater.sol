// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./interfaces/IECDSATypes.sol";
import "./interfaces/IECDSAOperatorTableCalculator.sol";
import "./interfaces/IECDSACertificateVerifier.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title ECDSAOperatorTableUpdater
 * @notice Coordinates updates to operator tables across multiple certificate verifiers
 * @dev This contract is responsible for retrieving operator tables from a calculator
 *      and updating multiple certificate verifiers in a single transaction
 */
contract ECDSAOperatorTableUpdater is Ownable, ReentrancyGuard {
    /// @notice Error thrown when the calculator address is zero
    error ZeroCalculatorAddress();
    
    /// @notice Error thrown when a verifier update fails
    error VerifierUpdateFailed(address verifier, string reason);
    
    /// @notice The calculator used to generate operator tables
    IECDSAOperatorTableCalculator public calculator;
    
    /**
     * @notice Emitted when the calculator is updated
     * @param previousCalculator The previous calculator address
     * @param newCalculator The new calculator address
     */
    event CalculatorUpdated(address indexed previousCalculator, address indexed newCalculator);
    
    /**
     * @notice Emitted when tables are updated across multiple verifiers
     * @param operatorSet The operator set that was updated
     * @param verifiers The addresses of the verifiers that were updated
     * @param referenceTimestamp The timestamp used for the update
     * @param operatorCount The number of operators in the table
     */
    event TablesUpdated(
        IECDSATypes.OperatorSet indexed operatorSet,
        address[] verifiers,
        uint32 indexed referenceTimestamp,
        uint256 operatorCount
    );
    
    /**
     * @notice Emitted when operators are ejected from multiple verifiers
     * @param operatorSet The operator set that was updated
     * @param verifiers The addresses of the verifiers that were updated
     * @param operatorIndices The indices of the operators that were ejected
     */
    event OperatorsEjected(
        IECDSATypes.OperatorSet indexed operatorSet,
        address[] verifiers,
        uint32[] operatorIndices
    );
    
    /**
     * @notice Constructs the updater with the initial calculator
     * @param calculator_ The address of the calculator to use
     */
    constructor(address calculator_) {
        _setCalculator(calculator_);
    }
    
    /**
     * @notice Updates the calculator used to generate operator tables
     * @param newCalculator The address of the new calculator
     * @dev Only the owner can call this function
     */
    function setCalculator(address newCalculator) external onlyOwner {
        _setCalculator(newCalculator);
    }
    
    /**
     * @notice Updates operator tables for multiple verifiers in a single transaction
     * @param operatorSet The operator set to calculate tables for
     * @param verifiers The addresses of the verifiers to update
     * @return referenceTimestamp The timestamp used for the update
     */
    function updateTablesForVerifiers(
        IECDSATypes.OperatorSet calldata operatorSet,
        address[] calldata verifiers
    ) external nonReentrant returns (uint32 referenceTimestamp) {
        require(verifiers.length > 0, "No verifiers specified");
        
        // Set the reference timestamp to the current block timestamp
        referenceTimestamp = uint32(block.timestamp);
        
        // Calculate the operator table using the calculator
        IECDSATypes.ECDSAOperatorInfo[] memory operatorInfos = 
            calculator.calculateOperatorTable(operatorSet);
        
        // Update each verifier
        for (uint256 i = 0; i < verifiers.length; i++) {
            try IECDSACertificateVerifier(verifiers[i]).updateOperatorTable(
                referenceTimestamp, 
                operatorInfos
            ) {
                // Update succeeded
            } catch Error(string memory reason) {
                revert VerifierUpdateFailed(verifiers[i], reason);
            }
        }
        
        // Emit event for successful update
        emit TablesUpdated(
            operatorSet, 
            verifiers, 
            referenceTimestamp,
            operatorInfos.length
        );
        
        return referenceTimestamp;
    }
    
    /**
     * @notice Ejects operators from multiple verifiers in a single transaction
     * @param operatorSet The operator set to eject operators from
     * @param verifiers The addresses of the verifiers to update
     * @param operatorIndices The indices of the operators to eject
     * @return success True if all ejections were successful
     */
    function ejectOperatorsFromVerifiers(
        IECDSATypes.OperatorSet calldata operatorSet,
        address[] calldata verifiers,
        uint32[] calldata operatorIndices
    ) external nonReentrant returns (bool success) {
        require(verifiers.length > 0, "No verifiers specified");
        require(operatorIndices.length > 0, "No operators to eject");
        
        // Get the current timestamp from the first verifier
        uint32 referenceTimestamp = IECDSACertificateVerifier(verifiers[0]).currentTableReferenceTimestamp();
        
        // Eject operators from each verifier
        for (uint256 i = 0; i < verifiers.length; i++) {
            try IECDSACertificateVerifier(verifiers[i]).ejectOperators(
                referenceTimestamp, 
                operatorIndices
            ) {
                // Ejection succeeded
            } catch Error(string memory reason) {
                revert VerifierUpdateFailed(verifiers[i], reason);
            }
        }
        
        // Emit event for successful ejection
        emit OperatorsEjected(operatorSet, verifiers, operatorIndices);
        
        return true;
    }
    
    /**
     * @notice Internal function to update the calculator
     * @param newCalculator The address of the new calculator
     */
    function _setCalculator(address newCalculator) internal {
        if (newCalculator == address(0)) {
            revert ZeroCalculatorAddress();
        }
        
        address previousCalculator = address(calculator);
        calculator = IECDSAOperatorTableCalculator(newCalculator);
        
        emit CalculatorUpdated(previousCalculator, newCalculator);
    }
} 
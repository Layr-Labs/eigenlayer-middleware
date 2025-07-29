// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";

// Registrar imports
import {AVSRegistrar} from "../src/middlewareV2/registrar/AVSRegistrar.sol";
import {AVSRegistrarWithAllowlist} from "../src/middlewareV2/registrar/presets/AVSRegistrarWithAllowlist.sol";
import {AVSRegistrarAsIdentifier} from "../src/middlewareV2/registrar/presets/AVSRegistrarAsIdentifier.sol";
import {AVSRegistrarWithSocket} from "../src/middlewareV2/registrar/presets/AVSRegistrarWithSocket.sol";

// Optional table calculator imports - only used if DEPLOY_TABLE_CALCULATOR = true
import {BN254TableCalculator} from "../src/middlewareV2/tableCalculator/BN254TableCalculator.sol";
import {BN254WeightedTableCalculator} from "../src/middlewareV2/tableCalculator/BN254WeightedTableCalculator.sol";
import {BN254TableCalculatorWithCaps} from "../src/middlewareV2/tableCalculator/BN254TableCalculatorWithCaps.sol";
import {ECDSATableCalculator} from "../src/middlewareV2/tableCalculator/ECDSATableCalculator.sol";

// Interface imports
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IPermissionController} from "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";

/**
 * @title AVSDeployment
 * @notice Flexible deployment script for AVS middleware
 * @dev Deploy registrars and optionally table calculators with maximum flexibility
 * 
 * Registrar Types:
 * 1 = AVSRegistrar (basic)
 * 2 = AVSRegistrarWithAllowlist (operator allowlist)
 * 3 = AVSRegistrarAsIdentifier (identifier-based)
 * 4 = AVSRegistrarWithSocket (socket management)
 */
contract AVSDeployment is Script {
    
    // ======================== CONFIGURATION ========================
    
    // Component deployment options
    uint8 constant REGISTRAR_TYPE = 1;  // 1=Basic, 2=Allowlist, 3=AsIdentifier, 4=Socket, 0=Skip
    bool constant DEPLOY_TABLE_CALCULATOR = false; // Set to true to deploy a new table calculator
    uint8 constant TABLE_CALCULATOR_TYPE = 1; // 1=BN254Basic, 2=BN254Weighted, 3=BN254WithCaps, 4=ECDSA (only used if DEPLOY_TABLE_CALCULATOR=true)
    
    // Required addresses
    address constant AVS_ADDRESS = address(0); // The AVS address for the registrar
    address constant KEY_REGISTRAR = address(0); // KeyRegistrar address
    address constant ALLOCATION_MANAGER = address(0); // AllocationManager address
    
    // Optional addresses (set only if required by component types)
    address constant PERMISSION_CONTROLLER = address(0); // Required for REGISTRAR_TYPE = 3 or TABLE_CALCULATOR_TYPE = 2,3
    
    // Table calculator configuration (only used if DEPLOY_TABLE_CALCULATOR=true)
    uint256 constant LOOKAHEAD_BLOCKS = 100; // Blocks to look ahead for stake calculations
    
    // ======================== DEPLOYMENT ========================
    
    function run() external {
        require(REGISTRAR_TYPE > 0 || DEPLOY_TABLE_CALCULATOR, "Must deploy at least one component");
        
        // Validate requirements
        require(KEY_REGISTRAR != address(0), "KEY_REGISTRAR not set");
        require(ALLOCATION_MANAGER != address(0), "ALLOCATION_MANAGER not set");
        
        if (REGISTRAR_TYPE > 0) {
            require(AVS_ADDRESS != address(0), "AVS_ADDRESS not set for registrar");
            if (REGISTRAR_TYPE == 3) {
                require(PERMISSION_CONTROLLER != address(0), "PERMISSION_CONTROLLER required for AsIdentifier registrar");
            }
        }
        
        if (DEPLOY_TABLE_CALCULATOR && (TABLE_CALCULATOR_TYPE == 2 || TABLE_CALCULATOR_TYPE == 3)) {
            require(PERMISSION_CONTROLLER != address(0), "PERMISSION_CONTROLLER required for table calculator types 2,3");
        }
        
        vm.startBroadcast();
        
        address tableCalculator = address(0);
        address registrar = address(0);
        
        // Deploy table calculator if requested
        if (DEPLOY_TABLE_CALCULATOR) {
            tableCalculator = _deployTableCalculator();
        }
        
        // Deploy registrar if requested
        if (REGISTRAR_TYPE > 0) {
            registrar = _deployRegistrar();
        }
        
        console.log("=== AVS Middleware Deployment ===");
        console.log("");
        
        if (tableCalculator != address(0)) {
            console.log("Table Calculator:");
            console.log("  Type:", _getTableCalculatorTypeName(TABLE_CALCULATOR_TYPE));
            console.log("  Address:", tableCalculator);
            console.log("");
        }
        
        if (registrar != address(0)) {
            console.log("Registrar:");
            console.log("  Type:", _getRegistrarTypeName(REGISTRAR_TYPE));
            console.log("  Address:", registrar);
            console.log("");
        }
        
        console.log("Configuration:");
        if (AVS_ADDRESS != address(0)) {
            console.log("  AVS Address:", AVS_ADDRESS);
        }
        console.log("  Key Registrar:", KEY_REGISTRAR);
        console.log("  Allocation Manager:", ALLOCATION_MANAGER);
        if (PERMISSION_CONTROLLER != address(0)) {
            console.log("  Permission Controller:", PERMISSION_CONTROLLER);
        }
        if (DEPLOY_TABLE_CALCULATOR) {
            console.log("  Lookahead Blocks:", LOOKAHEAD_BLOCKS);
        }
        
        // Post-deployment instructions
        if (TABLE_CALCULATOR_TYPE == 2 && tableCalculator != address(0)) {
            console.log("");
            console.log("Next steps for Weighted Calculator:");
            console.log("- Use setStrategyMultipliers() to configure custom strategy weights");
            console.log("- Default multiplier is 10000 (1x) for all strategies");
        } else if (TABLE_CALCULATOR_TYPE == 3 && tableCalculator != address(0)) {
            console.log("");
            console.log("Next steps for Capped Calculator:");
            console.log("- Use setWeightCap() for simple total weight caps");
            console.log("- Use setWeightCaps() for per-stake-type caps");
        }
        
        if (REGISTRAR_TYPE == 2) {
            console.log("");
            console.log("Next steps for Allowlist Registrar:");
            console.log("- Call initialize(admin) to set up the allowlist admin");
            console.log("- Use allowlist functions to manage operator permissions");
        } else if (REGISTRAR_TYPE == 3) {
            console.log("");
            console.log("Next steps for AsIdentifier Registrar:");
            console.log("- Call initialize(admin, metadataURI) to complete AVS setup");
            console.log("- This registrar becomes the AVS identifier in EigenLayer core");
        }
        
        vm.stopBroadcast();
    }
    
    function _deployRegistrar() internal returns (address) {
        if (REGISTRAR_TYPE == 1) {
            // Basic AVSRegistrar
            return address(new AVSRegistrar(
                AVS_ADDRESS,
                IAllocationManager(ALLOCATION_MANAGER),
                IKeyRegistrar(KEY_REGISTRAR)
            ));
        } else if (REGISTRAR_TYPE == 2) {
            // AVSRegistrarWithAllowlist
            return address(new AVSRegistrarWithAllowlist(
                AVS_ADDRESS,
                IAllocationManager(ALLOCATION_MANAGER),
                IKeyRegistrar(KEY_REGISTRAR)
            ));
        } else if (REGISTRAR_TYPE == 3) {
            // AVSRegistrarAsIdentifier
            return address(new AVSRegistrarAsIdentifier(
                AVS_ADDRESS,
                IAllocationManager(ALLOCATION_MANAGER),
                IPermissionController(PERMISSION_CONTROLLER),
                IKeyRegistrar(KEY_REGISTRAR)
            ));
        } else if (REGISTRAR_TYPE == 4) {
            // AVSRegistrarWithSocket
            return address(new AVSRegistrarWithSocket(
                AVS_ADDRESS,
                IAllocationManager(ALLOCATION_MANAGER),
                IKeyRegistrar(KEY_REGISTRAR)
            ));
        } else {
            revert("Invalid REGISTRAR_TYPE. Use 1-4.");
        }
    }
    
    function _deployTableCalculator() internal returns (address) {
        if (TABLE_CALCULATOR_TYPE == 1) {
            return address(new BN254TableCalculator(
                IKeyRegistrar(KEY_REGISTRAR),
                IAllocationManager(ALLOCATION_MANAGER),
                LOOKAHEAD_BLOCKS
            ));
        } else if (TABLE_CALCULATOR_TYPE == 2) {
            return address(new BN254WeightedTableCalculator(
                IKeyRegistrar(KEY_REGISTRAR),
                IAllocationManager(ALLOCATION_MANAGER),
                IPermissionController(PERMISSION_CONTROLLER),
                LOOKAHEAD_BLOCKS
            ));
        } else if (TABLE_CALCULATOR_TYPE == 3) {
            return address(new BN254TableCalculatorWithCaps(
                IKeyRegistrar(KEY_REGISTRAR),
                IAllocationManager(ALLOCATION_MANAGER),
                IPermissionController(PERMISSION_CONTROLLER),
                LOOKAHEAD_BLOCKS
            ));
        } else if (TABLE_CALCULATOR_TYPE == 4) {
            return address(new ECDSATableCalculator(
                IKeyRegistrar(KEY_REGISTRAR),
                IAllocationManager(ALLOCATION_MANAGER),
                LOOKAHEAD_BLOCKS
            ));
        } else {
            revert("Invalid TABLE_CALCULATOR_TYPE. Use 1-4.");
        }
    }

    function _getRegistrarTypeName(uint8 registrarType) internal pure returns (string memory) {
        if (registrarType == 1) return "AVSRegistrar";
        if (registrarType == 2) return "AVSRegistrarWithAllowlist";
        if (registrarType == 3) return "AVSRegistrarAsIdentifier";
        if (registrarType == 4) return "AVSRegistrarWithSocket";
        return "Unknown";
    }
    
    function _getTableCalculatorTypeName(uint8 calculatorType) internal pure returns (string memory) {
        if (calculatorType == 1) return "BN254TableCalculator";
        if (calculatorType == 2) return "BN254WeightedTableCalculator";
        if (calculatorType == 3) return "BN254TableCalculatorWithCaps";
        if (calculatorType == 4) return "ECDSATableCalculator";
        return "Unknown";
    }
} 
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Core EigenLayer imports
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IPermissionController} from "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// Middleware imports - Registrars
import {AVSRegistrar} from "../src/middlewareV2/registrar/AVSRegistrar.sol";
import {AVSRegistrarWithAllowlist} from "../src/middlewareV2/registrar/presets/AVSRegistrarWithAllowlist.sol";
import {AVSRegistrarWithSocket} from "../src/middlewareV2/registrar/presets/AVSRegistrarWithSocket.sol";
import {AVSRegistrarAsIdentifier} from "../src/middlewareV2/registrar/presets/AVSRegistrarAsIdentifier.sol";

// Middleware imports - Table Calculators
import {BN254TableCalculator} from "../src/middlewareV2/tableCalculator/BN254TableCalculator.sol";
import {BN254WeightedTableCalculator} from "../src/middlewareV2/tableCalculator/BN254WeightedTableCalculator.sol";
import {BN254TableCalculatorWithCaps} from "../src/middlewareV2/tableCalculator/BN254TableCalculatorWithCaps.sol";
import {ECDSATableCalculator} from "../src/middlewareV2/tableCalculator/ECDSATableCalculator.sol";

/**
 * @title AVSMiddlewareDeploy
 * @notice Comprehensive deployment script for AVS middleware contracts
 * @dev Supports multiple registrar types and table calculator configurations
 */
contract AVSMiddlewareDeploy is Script {
    
    // Deployment configuration struct
    struct DeploymentConfig {
        // Core protocol addresses
        address allocationManager;
        address keyRegistrar;
        address avsDirectory;
        address permissionController;
        address proxyAdmin;
        
        // AVS configuration
        address avsOwner;
        string metadataURI;
        
        // Registrar configuration
        RegistrarType registrarType;
        bool useProxy; // Whether to deploy registrar behind proxy
        
        // Table calculator configuration
        CalculatorType calculatorType;
        uint256 lookaheadBlocks;
        
        // Optional: for weighted calculator
        address[] strategies;
        uint256[] multipliers; // In basis points (10000 = 1x)
    }
    
    enum RegistrarType {
        BASIC,           // Basic AVSRegistrar
        WITH_ALLOWLIST,  // AVSRegistrarWithAllowlist
        WITH_SOCKET,     // AVSRegistrarWithSocket
        AS_IDENTIFIER    // AVSRegistrarAsIdentifier
    }
    
    enum CalculatorType {
        BN254_BASIC,     // BN254TableCalculator
        BN254_WEIGHTED,  // BN254WeightedTableCalculator  
        BN254_WITH_CAPS, // BN254TableCalculatorWithCaps
        ECDSA_BASIC      // ECDSATableCalculator
    }
    
    // Deployed contract addresses
    struct DeployedContracts {
        address registrarImplementation;
        address registrarProxy;
        address tableCalculator;
        address proxyAdmin;
    }
    
    DeployedContracts public deployedContracts;
    
    function run() external {
        // Load configuration from file
        string memory configFile = vm.envString("CONFIG_FILE");
        DeploymentConfig memory config = _loadConfig(configFile);
        
        vm.startBroadcast();
        
        console.log("=== AVS Middleware Deployment ===");
        console.log("AVS Owner:", config.avsOwner);
        console.log("Metadata URI:", config.metadataURI);
        
        // Deploy ProxyAdmin if needed
        if (config.useProxy && config.proxyAdmin == address(0)) {
            deployedContracts.proxyAdmin = address(new ProxyAdmin());
            console.log("Deployed ProxyAdmin:", deployedContracts.proxyAdmin);
        } else {
            deployedContracts.proxyAdmin = config.proxyAdmin;
        }
        
        // Deploy Table Calculator
        deployedContracts.tableCalculator = _deployTableCalculator(config);
        console.log("Deployed Table Calculator:", deployedContracts.tableCalculator);
        console.log("Calculator Type:", _calculatorTypeToString(config.calculatorType));
        
        // Deploy AVS Registrar
        (deployedContracts.registrarImplementation, deployedContracts.registrarProxy) = 
            _deployAVSRegistrar(config);
        
        console.log("Deployed Registrar Implementation:", deployedContracts.registrarImplementation);
        if (config.useProxy) {
            console.log("Deployed Registrar Proxy:", deployedContracts.registrarProxy);
        }
        console.log("Registrar Type:", _registrarTypeToString(config.registrarType));
        
        // Initialize registrar if needed
        _initializeRegistrar(config);
        
        vm.stopBroadcast();
        
        // Output deployment summary
        _outputDeploymentSummary(config);
    }
    
    function _deployTableCalculator(DeploymentConfig memory config) internal returns (address) {
        if (config.calculatorType == CalculatorType.BN254_BASIC) {
            return address(new BN254TableCalculator(
                IKeyRegistrar(config.keyRegistrar),
                IAllocationManager(config.allocationManager),
                config.lookaheadBlocks
            ));
        } else if (config.calculatorType == CalculatorType.BN254_WEIGHTED) {
            return address(new BN254WeightedTableCalculator(
                IKeyRegistrar(config.keyRegistrar),
                IAllocationManager(config.allocationManager),
                IPermissionController(config.permissionController),
                config.lookaheadBlocks
            ));
        } else if (config.calculatorType == CalculatorType.BN254_WITH_CAPS) {
            return address(new BN254TableCalculatorWithCaps(
                IKeyRegistrar(config.keyRegistrar),
                IAllocationManager(config.allocationManager),
                IPermissionController(config.permissionController),
                config.lookaheadBlocks
            ));
        } else if (config.calculatorType == CalculatorType.ECDSA_BASIC) {
            return address(new ECDSATableCalculator(
                IKeyRegistrar(config.keyRegistrar),
                IAllocationManager(config.allocationManager),
                config.lookaheadBlocks
            ));
        } else {
            revert("Unsupported calculator type");
        }
    }
    
    function _deployAVSRegistrar(DeploymentConfig memory config) 
        internal 
        returns (address implementation, address proxy) 
    {
        // Deploy implementation
        if (config.registrarType == RegistrarType.BASIC) {
            implementation = address(new AVSRegistrar(
                config.avsOwner,
                IAllocationManager(config.allocationManager),
                IKeyRegistrar(config.keyRegistrar)
            ));
        } else if (config.registrarType == RegistrarType.WITH_ALLOWLIST) {
            implementation = address(new AVSRegistrarWithAllowlist(
                config.avsOwner,
                IAllocationManager(config.allocationManager),
                IKeyRegistrar(config.keyRegistrar)
            ));
        } else if (config.registrarType == RegistrarType.WITH_SOCKET) {
            implementation = address(new AVSRegistrarWithSocket(
                config.avsOwner,
                IAllocationManager(config.allocationManager),
                IKeyRegistrar(config.keyRegistrar)
            ));
        } else if (config.registrarType == RegistrarType.AS_IDENTIFIER) {
            implementation = address(new AVSRegistrarAsIdentifier(
                config.avsOwner,
                IAllocationManager(config.allocationManager),
                IPermissionController(config.permissionController),
                IKeyRegistrar(config.keyRegistrar)
            ));
        } else {
            revert("Unsupported registrar type");
        }
        
        // Deploy proxy if requested
        if (config.useProxy) {
            proxy = address(new TransparentUpgradeableProxy(
                implementation,
                deployedContracts.proxyAdmin,
                "" // No initialization data for now
            ));
        } else {
            proxy = implementation;
        }
        
        return (implementation, proxy);
    }
    
    function _initializeRegistrar(DeploymentConfig memory config) internal {
        address registrar = deployedContracts.registrarProxy;
        
        if (config.registrarType == RegistrarType.WITH_ALLOWLIST) {
            AVSRegistrarWithAllowlist(registrar).initialize(config.avsOwner);
        } else if (config.registrarType == RegistrarType.AS_IDENTIFIER) {
            AVSRegistrarAsIdentifier(registrar).initialize(config.avsOwner, config.metadataURI);
        }
        // Basic and WithSocket registrars don't need initialization
    }
    
    function _loadConfig(string memory configPath) internal view returns (DeploymentConfig memory config) {
        string memory json = vm.readFile(configPath);
        
        // Core protocol addresses
        config.allocationManager = vm.parseJsonAddress(json, ".allocationManager");
        config.keyRegistrar = vm.parseJsonAddress(json, ".keyRegistrar");
        config.avsDirectory = vm.parseJsonAddress(json, ".avsDirectory");
        config.permissionController = vm.parseJsonAddress(json, ".permissionController");
        
        // Optional proxy admin
        try vm.parseJsonAddress(json, ".proxyAdmin") returns (address addr) {
            config.proxyAdmin = addr;
        } catch {}
        
        // AVS configuration
        config.avsOwner = vm.parseJsonAddress(json, ".avsOwner");
        config.metadataURI = vm.parseJsonString(json, ".metadataURI");
        
        // Registrar configuration
        config.registrarType = RegistrarType(vm.parseJsonUint(json, ".registrarType"));
        config.useProxy = vm.parseJsonBool(json, ".useProxy");
        
        // Calculator configuration
        config.calculatorType = CalculatorType(vm.parseJsonUint(json, ".calculatorType"));
        config.lookaheadBlocks = vm.parseJsonUint(json, ".lookaheadBlocks");
        
        // Optional weighted calculator config
        try vm.parseJsonAddress(json, ".strategies") {
            config.strategies = vm.parseJsonAddressArray(json, ".strategies");
            config.multipliers = vm.parseJsonUintArray(json, ".multipliers");
        } catch {}
        
        return config;
    }
    
    function _outputDeploymentSummary(DeploymentConfig memory config) internal view {
        console.log("\n=== Deployment Summary ===");
        console.log("Network:", block.chainid);
        console.log("Deployer:", msg.sender);
        console.log("");
        
        console.log("Contracts Deployed:");
        console.log("- Table Calculator:", deployedContracts.tableCalculator);
        console.log("- Registrar Implementation:", deployedContracts.registrarImplementation);
        if (config.useProxy) {
            console.log("- Registrar Proxy:", deployedContracts.registrarProxy);
            console.log("- Proxy Admin:", deployedContracts.proxyAdmin);
        }
        console.log("");
        
        console.log("Next Steps:");
        console.log("1. Set up operator sets in AllocationManager");
        console.log("2. Configure CrossChainRegistry if using multichain");
        console.log("3. Register strategies in your table calculator if weighted");
        if (config.registrarType == RegistrarType.WITH_ALLOWLIST) {
            console.log("4. Configure allowlist for operators");
        }
    }
    
    function _registrarTypeToString(RegistrarType rType) internal pure returns (string memory) {
        if (rType == RegistrarType.BASIC) return "Basic";
        if (rType == RegistrarType.WITH_ALLOWLIST) return "WithAllowlist";
        if (rType == RegistrarType.WITH_SOCKET) return "WithSocket";
        if (rType == RegistrarType.AS_IDENTIFIER) return "AsIdentifier";
        return "Unknown";
    }
    
    function _calculatorTypeToString(CalculatorType cType) internal pure returns (string memory) {
        if (cType == CalculatorType.BN254_BASIC) return "BN254Basic";
        if (cType == CalculatorType.BN254_WEIGHTED) return "BN254Weighted";
        if (cType == CalculatorType.BN254_WITH_CAPS) return "BN254WithCaps";
        if (cType == CalculatorType.ECDSA_BASIC) return "ECDSABasic";
        return "Unknown";
    }
} 
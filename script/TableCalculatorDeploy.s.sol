// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {BN254TableCalculator} from "../src/middlewareV2/tableCalculator/BN254TableCalculator.sol";
import {ECDSATableCalculator} from "../src/middlewareV2/tableCalculator/ECDSATableCalculator.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";

contract TableCalculatorDeploy is Script {
    // Default parameters that can be overridden via environment variables or config
    uint256 public constant DEFAULT_LOOKAHEAD_BLOCKS = 50;
    
    // Deployed contract addresses (will be populated during deployment)
    BN254TableCalculator public bn254TableCalculator;
    ECDSATableCalculator public ecdsaTableCalculator;
    
    function run() external {
        // Read configuration from environment variables
        address keyRegistrarAddress = 0xA4dB30D08d8bbcA00D40600bee9F029984dB162a;       
        address allocationManagerAddress = 0x42583067658071247ec8CE0A516A58f682002d07;
        uint256 lookaheadBlocks = DEFAULT_LOOKAHEAD_BLOCKS;
        
        // Validate required parameters
        require(keyRegistrarAddress != address(0), "KEY_REGISTRAR address must be provided");
        require(allocationManagerAddress != address(0), "ALLOCATION_MANAGER address must be provided");
        
        console.log("=== Table Calculator Deployment ===");
        console.log("Key Registrar:", keyRegistrarAddress);
        console.log("Allocation Manager:", allocationManagerAddress);
        console.log("Lookahead Blocks:", lookaheadBlocks);
        console.log("Deployer:", msg.sender);
        
        vm.startBroadcast();
        
        // Deploy BN254TableCalculator
        console.log("\nDeploying BN254TableCalculator...");
        bn254TableCalculator = new BN254TableCalculator(
            IKeyRegistrar(keyRegistrarAddress),
            IAllocationManager(allocationManagerAddress),
            lookaheadBlocks
        );
        console.log("BN254TableCalculator deployed at:", address(bn254TableCalculator));
        
        // Deploy ECDSATableCalculator
        console.log("\nDeploying ECDSATableCalculator...");
        ecdsaTableCalculator = new ECDSATableCalculator(
            IKeyRegistrar(keyRegistrarAddress),
            IAllocationManager(allocationManagerAddress),
            lookaheadBlocks
        );
        console.log("ECDSATableCalculator deployed at:", address(ecdsaTableCalculator));
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Summary ===");
        console.log("BN254TableCalculator:", address(bn254TableCalculator));
        console.log("ECDSATableCalculator:", address(ecdsaTableCalculator));
        console.log("Deployment completed successfully!");
    }
    
    // Helper function to deploy with custom parameters
    function deployWithParams(
        address keyRegistrarAddress,
        address allocationManagerAddress,
        uint256 lookaheadBlocks
    ) external {
        require(keyRegistrarAddress != address(0), "KEY_REGISTRAR address must be provided");
        require(allocationManagerAddress != address(0), "ALLOCATION_MANAGER address must be provided");
        
        vm.startBroadcast();
        
        bn254TableCalculator = new BN254TableCalculator(
            IKeyRegistrar(keyRegistrarAddress),
            IAllocationManager(allocationManagerAddress),
            lookaheadBlocks
        );
        
        ecdsaTableCalculator = new ECDSATableCalculator(
            IKeyRegistrar(keyRegistrarAddress),
            IAllocationManager(allocationManagerAddress),
            lookaheadBlocks
        );
        
        vm.stopBroadcast();
    }
} 
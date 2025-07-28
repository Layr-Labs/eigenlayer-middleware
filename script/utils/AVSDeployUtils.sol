// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Core EigenLayer imports
import {IAllocationManager, IAllocationManagerTypes} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";

// Middleware imports
import {BN254WeightedTableCalculator} from "../../src/middlewareV2/tableCalculator/BN254WeightedTableCalculator.sol";
import {AVSRegistrarWithAllowlist} from "../../src/middlewareV2/registrar/presets/AVSRegistrarWithAllowlist.sol";

/**
 * @title AVSDeployUtils
 * @notice Utility functions for configuring AVS middleware contracts post-deployment
 */
contract AVSDeployUtils is Script {
    
    struct OperatorSetConfig {
        uint32 operatorSetId;
        IStrategy[] strategies;
    }
    
    struct WeightedCalculatorConfig {
        address calculator;
        OperatorSet operatorSet;
        IStrategy[] strategies;
        uint256[] multipliers;
    }
    
    struct AllowlistConfig {
        address registrar;
        OperatorSet operatorSet;
        address[] operators;
        bool[] allowed;
    }
    
    /**
     * @notice Configure operator sets in the AllocationManager
     * @param allocationManager The AllocationManager contract address
     * @param avs The AVS address
     * @param configs Array of operator set configurations
     */
    function configureOperatorSets(
        address allocationManager,
        address avs,
        OperatorSetConfig[] memory configs
    ) external {
        vm.startBroadcast();
        
        console.log("Configuring operator sets for AVS:", avs);
        
        IAllocationManager manager = IAllocationManager(allocationManager);
        
        for (uint256 i = 0; i < configs.length; i++) {
            OperatorSetConfig memory config = configs[i];
            
            console.log("Creating operator set:", config.operatorSetId);
            console.log("- Strategies count:", config.strategies.length);
            
            IAllocationManagerTypes.CreateSetParams[] memory params = new IAllocationManagerTypes.CreateSetParams[](1);
            params[0] = IAllocationManagerTypes.CreateSetParams({
                operatorSetId: config.operatorSetId,
                strategies: config.strategies
            });
            
            manager.createOperatorSets(avs, params);
            
            console.log("Successfully created operator set", config.operatorSetId);
        }
        
        vm.stopBroadcast();
    }
    
    /**
     * @notice Configure strategy multipliers for weighted table calculators
     * @param configs Array of weighted calculator configurations
     */
    function configureWeightedCalculators(
        WeightedCalculatorConfig[] memory configs
    ) external {
        vm.startBroadcast();
        
        console.log("Configuring weighted table calculators");
        
        for (uint256 i = 0; i < configs.length; i++) {
            WeightedCalculatorConfig memory config = configs[i];
            
            console.log("Setting multipliers for calculator:", config.calculator);
            console.log("- OperatorSet:", config.operatorSet.avs, config.operatorSet.id);
            console.log("- Strategies count:", config.strategies.length);
            
            BN254WeightedTableCalculator calculator = BN254WeightedTableCalculator(config.calculator);
            
            calculator.setStrategyMultipliers(
                config.operatorSet,
                config.strategies,
                config.multipliers
            );
            
            console.log("Successfully set multipliers for calculator");
            
            // Log the multipliers for verification
            for (uint256 j = 0; j < config.strategies.length; j++) {
                uint256 multiplier = calculator.getStrategyMultiplier(
                    config.operatorSet,
                    config.strategies[j]
                );
                console.log("  Strategy", j, "multiplier:", multiplier);
            }
        }
        
        vm.stopBroadcast();
    }
    
    /**
     * @notice Configure allowlists for registrars with allowlist functionality
     * @param configs Array of allowlist configurations
     */
    function configureAllowlists(
        AllowlistConfig[] memory configs
    ) external {
        vm.startBroadcast();
        
        console.log("Configuring operator allowlists");
        
        for (uint256 i = 0; i < configs.length; i++) {
            AllowlistConfig memory config = configs[i];
            
            console.log("Setting allowlist for registrar:", config.registrar);
            console.log("- OperatorSet:", config.operatorSet.avs, config.operatorSet.id);
            console.log("- Operators count:", config.operators.length);
            
            AVSRegistrarWithAllowlist registrar = AVSRegistrarWithAllowlist(config.registrar);
            
            for (uint256 j = 0; j < config.operators.length; j++) {
                if (config.allowed[j]) {
                    registrar.addOperatorToAllowlist(
                        config.operatorSet,
                        config.operators[j]
                    );
                } else {
                    registrar.removeOperatorFromAllowlist(
                        config.operatorSet,
                        config.operators[j]
                    );
                }
                
                console.log(
                    config.allowed[j] ? "  Allowed:" : "  Denied:",
                    config.operators[j]
                );
            }
            
            console.log("Successfully configured allowlist");
        }
        
        vm.stopBroadcast();
    }
    
    /**
     * @notice Helper function to create standard operator set configurations
     */
    function createStandardOperatorSetConfig(
        uint32 operatorSetId,
        address[] memory strategyAddresses
    ) external pure returns (OperatorSetConfig memory) {
        IStrategy[] memory strategies = new IStrategy[](strategyAddresses.length);
        for (uint256 i = 0; i < strategyAddresses.length; i++) {
            strategies[i] = IStrategy(strategyAddresses[i]);
        }
        
        return OperatorSetConfig({
            operatorSetId: operatorSetId,
            strategies: strategies
        });
    }
    
    /**
     * @notice Helper function to verify deployed contract configurations
     */
    function verifyDeployment(
        address registrar,
        address tableCalculator,
        address allocationManager,
        address avs
    ) external view {
        console.log("=== Deployment Verification ===");
        console.log("Registrar:", registrar);
        console.log("Table Calculator:", tableCalculator);
        console.log("AllocationManager:", allocationManager);
        console.log("AVS:", avs);
        
        // Verify registrar supports the AVS
        try AVSRegistrarWithAllowlist(registrar).supportsAVS(avs) returns (bool supported) {
            console.log("Registrar supports AVS:", supported);
        } catch {
            console.log("Could not verify registrar AVS support");
        }
        
        // Check if AVS is configured in AllocationManager
        try IAllocationManager(allocationManager).getAVSRegistrar(avs) returns (IAVSRegistrar configuredRegistrar) {
            console.log("Configured registrar in AllocationManager:", address(configuredRegistrar));
            console.log("Registrar matches:", address(configuredRegistrar) == registrar);
        } catch {
            console.log("Could not retrieve configured registrar");
        }
        
        console.log("=== Verification Complete ===");
    }
    
    /**
     * @notice Save deployment addresses to a JSON file
     */
    function saveDeploymentOutput(
        string memory outputPath,
        address registrarImpl,
        address registrarProxy, 
        address tableCalculator,
        address proxyAdmin
    ) external {
        string memory json = string.concat(
            '{\n',
            '  "timestamp": "', vm.toString(block.timestamp), '",\n',
            '  "chainId": "', vm.toString(block.chainid), '",\n',
            '  "registrarImplementation": "', vm.toString(registrarImpl), '",\n',
            '  "registrarProxy": "', vm.toString(registrarProxy), '",\n',
            '  "tableCalculator": "', vm.toString(tableCalculator), '",\n',
            '  "proxyAdmin": "', vm.toString(proxyAdmin), '"\n',
            '}'
        );
        
        vm.writeFile(outputPath, json);
        console.log("Deployment output saved to:", outputPath);
    }
} 
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import {OperatorSet, OperatorSetLib} from "../lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import "../src/operator-tables/ECDSAOperatorTableCalculator.sol";
import "../src/operator-tables/BN254OperatorTableCalculator.sol";
import "../src/certificate-verifiers/ECDSACertificateVerifier.sol";
import "../src/certificate-verifiers/BN254CertificateVerifier.sol";
import "../src/operator-tables/OperatorTableUpdater.sol";
import "../src/examples/CertificateConsumer.sol";

contract DeployOperatorTables is Script {
    // Configuration
    address public allocationManager;
    address public deployer;
    uint32 public maxOperatorTableStaleness = 86400; // 1 day in seconds
    uint8 public numWeightTypes = 2; // Example: slashable and delegated
    
    // Deployed contracts
    ECDSAOperatorTableCalculator public ecdsaCalculator;
    BN254OperatorTableCalculator public bn254Calculator;
    OperatorTableUpdater public tableUpdater;
    
    function setUp() public {
        // Load environment variables
        allocationManager = vm.envAddress("ALLOCATION_MANAGER");
        deployer = vm.envAddress("DEPLOYER");
        
        // Default to hardhat account if not specified
        if (deployer == address(0)) {
            deployer = vm.addr(uint256(keccak256("deployer")));
        }
    }
    
    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        
        // Deploy operator table calculators
        ecdsaCalculator = deployECDSACalculator();
        bn254Calculator = deployBN254Calculator();
        
        // Deploy operator table updater
        tableUpdater = new OperatorTableUpdater(
            IECDSAOperatorTableCalculator(address(ecdsaCalculator)),
            IBN254OperatorTableCalculator(address(bn254Calculator))
        );
        
        // Log deployments
        console.log("Deployed ECDSAOperatorTableCalculator at:", address(ecdsaCalculator));
        console.log("Deployed BN254OperatorTableCalculator at:", address(bn254Calculator));
        console.log("Deployed OperatorTableUpdater at:", address(tableUpdater));
        
        vm.stopBroadcast();
    }
    
    function deployECDSACalculator() internal returns (ECDSAOperatorTableCalculator) {
        // In a real deployment, you would configure the strategies and multipliers based on your needs
        // For now, we'll use dummy values
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(address(0x1234)); // Replace with real strategy addresses
        
        uint256[] memory multipliers = new uint256[](1);
        multipliers[0] = 1e18; // 1.0 multiplier
        
        return new ECDSAOperatorTableCalculator(
            IAllocationManager(allocationManager),
            strategies,
            multipliers,
            numWeightTypes
        );
    }
    
    function deployBN254Calculator() internal returns (BN254OperatorTableCalculator) {
        // In a real deployment, you would configure the strategies and multipliers based on your needs
        // For now, we'll use dummy values
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(address(0x1234)); // Replace with real strategy addresses
        
        uint256[] memory multipliers = new uint256[](1);
        multipliers[0] = 1e18; // 1.0 multiplier
        
        return new BN254OperatorTableCalculator(
            IAllocationManager(allocationManager),
            strategies,
            multipliers,
            numWeightTypes
        );
    }
}

contract DeployVerifiers is Script {
    // Configuration
    address public operatorTableUpdater;
    address public deployer;
    uint32 public maxOperatorTableStaleness = 86400; // 1 day in seconds
    
    // Deployed contracts
    ECDSACertificateVerifier public ecdsaVerifier;
    BN254CertificateVerifier public bn254Verifier;
    CertificateConsumer public consumer;
    
    function setUp() public {
        // Load environment variables
        operatorTableUpdater = vm.envAddress("OPERATOR_TABLE_UPDATER");
        deployer = vm.envAddress("DEPLOYER");
        
        // Default to hardhat account if not specified
        if (deployer == address(0)) {
            deployer = vm.addr(uint256(keccak256("deployer")));
        }
    }
    
    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        
        // Example AVS and operator set ID
        address avs = address(0x1234); // Replace with real AVS address
        uint32 operatorSetId = 1;
        OperatorSet memory operatorSet = OperatorSet(avs, operatorSetId);
        
        // Deploy certificate verifiers
        ecdsaVerifier = new ECDSACertificateVerifier(
            operatorSet,
            operatorTableUpdater,
            maxOperatorTableStaleness
        );
        
        bn254Verifier = new BN254CertificateVerifier(
            operatorSet,
            operatorTableUpdater,
            maxOperatorTableStaleness
        );
        
        // Set up proportion and nominal thresholds for the consumer
        uint16[] memory proportionThresholds = new uint16[](2);
        proportionThresholds[0] = 6600; // 66%
        proportionThresholds[1] = 6600; // 66%
        
        uint96[] memory nominalThresholds = new uint96[](2);
        nominalThresholds[0] = 1000 * 10**18; // Example threshold
        nominalThresholds[1] = 1000 * 10**18; // Example threshold
        
        // Deploy consumer
        consumer = new CertificateConsumer(
            address(ecdsaVerifier),
            address(bn254Verifier),
            proportionThresholds,
            nominalThresholds
        );
        
        // Register verifiers with the updater
        OperatorTableUpdater updater = OperatorTableUpdater(operatorTableUpdater);
        updater.registerVerifier(operatorSet, address(ecdsaVerifier), true);
        updater.registerVerifier(operatorSet, address(bn254Verifier), false);
        
        // Log deployments
        console.log("Deployed ECDSACertificateVerifier at:", address(ecdsaVerifier));
        console.log("Deployed BN254CertificateVerifier at:", address(bn254Verifier));
        console.log("Deployed CertificateConsumer at:", address(consumer));
        
        vm.stopBroadcast();
    }
}
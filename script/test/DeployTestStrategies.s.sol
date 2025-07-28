// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Simple strategy mock for testing
contract StrategyMock {
    string public name;
    
    constructor(string memory _name) {
        name = _name;
    }
    
    function underlyingToken() external pure returns (address) {
        return address(0); // Mock token
    }
    
    function shares(address) external pure returns (uint256) {
        return 100e18; // Mock shares
    }
}

/**
 * @title DeployTestStrategies
 * @notice Deploy test strategy contracts for weighted calculator testing
 */
contract DeployTestStrategies is Script {
    
    function run() external {
        vm.startBroadcast();
        
        console.log("=== Deploying Test Strategies ===");
        
        // Deploy test strategies
        StrategyMock strategy1 = new StrategyMock("ETH Strategy");
        console.log("Strategy deployed:", address(strategy1));
        
        StrategyMock strategy2 = new StrategyMock("BTC Strategy");
        console.log("Strategy deployed:", address(strategy2));
        
        vm.stopBroadcast();
        
        console.log("=== Strategy deployment complete ===");
    }
} 
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Import test mocks since we don't have full core contracts
import "../../test/mocks/AllocationManagerMock.sol";
import "../../test/mocks/AVSDirectoryMock.sol";
import "../../test/mocks/PermissionControllerMock.sol";

// For a real KeyRegistrar, we'll need to create a simple mock
contract KeyRegistrarMock {
    mapping(address => bool) public isRegistered;
    
    function registerKey(address operator, bytes calldata) external {
        isRegistered[operator] = true;
    }
    
    function deregisterKey(address operator) external {
        isRegistered[operator] = false;
    }
}

/**
 * @title DeployTestCore
 * @notice Deploy minimal core contracts for testing AVS middleware
 */
contract DeployTestCore is Script {
    
    function run() external {
        vm.startBroadcast();
        
        console.log("=== Deploying Test Core Contracts ===");
        
        // Deploy mock core contracts
        AllocationManagerMock allocationManager = new AllocationManagerMock();
        console.log("AllocationManager deployed:", address(allocationManager));
        
        KeyRegistrarMock keyRegistrar = new KeyRegistrarMock();
        console.log("KeyRegistrar deployed:", address(keyRegistrar));
        
        AVSDirectoryMock avsDirectory = new AVSDirectoryMock();
        console.log("AVSDirectory deployed:", address(avsDirectory));
        
        PermissionControllerMock permissionController = new PermissionControllerMock();
        console.log("PermissionController deployed:", address(permissionController));
        
        vm.stopBroadcast();
        
        // Save deployment output
        _saveOutput(
            address(allocationManager),
            address(keyRegistrar),
            address(avsDirectory),
            address(permissionController)
        );
        
        console.log("=== Core deployment complete ===");
    }
    
    function _saveOutput(
        address allocationManager,
        address keyRegistrar,
        address avsDirectory,
        address permissionController
    ) internal {
        string memory json = string.concat(
            '{\n',
            '  "timestamp": "', vm.toString(block.timestamp), '",\n',
            '  "chainId": "', vm.toString(block.chainid), '",\n',
            '  "allocationManager": "', vm.toString(allocationManager), '",\n',
            '  "keyRegistrar": "', vm.toString(keyRegistrar), '",\n',
            '  "avsDirectory": "', vm.toString(avsDirectory), '",\n',
            '  "permissionController": "', vm.toString(permissionController), '"\n',
            '}'
        );
        
        string memory outputDir = "script/output";
        string memory outputPath = string.concat(outputDir, "/test-core-output.json");
        
        // Create output directory if it doesn't exist
        try vm.createDir(outputDir, true) {} catch {}
        
        vm.writeFile(outputPath, json);
        console.log("Output saved to:", outputPath);
    }
} 
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IRegistryCoordinator} from "../../src/interfaces/IRegistryCoordinator.sol";

import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

/// Replace with your ServiceManager
contract ServiceManagerV2 {
    constructor(
        IRegistryCoordinator _registryCoordinator,
        IAVSDirectory _avsDirectory
    ) {}
}

contract UpgradeServiceManager is Script, Test {
    bytes32 internal constant ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    ProxyAdmin internal serviceProxyAdmin;
    address internal serviceManagerProxy;
    address internal serviceImplementationV2;

    function run() public virtual {
        string memory network = vm.envString("NETWORK");
        string memory deploymentOutputPath = string(
            abi.encodePacked(
                "lib/eigenlayer-contracts/script/output/",
                network,
                "/deployment_output.json"
            )
        );
        string memory localDeploymentPath = string(
            abi.encodePacked("script/output/", network, "/deployment.json")
        );

        // Load deployment data
        string memory deploymentOutput = vm.readFile(deploymentOutputPath);
        string memory localDeployment = vm.readFile(localDeploymentPath);

        // Parse deployment data
        address registryCoordinator = vm.parseJsonAddress(
            deploymentOutput,
            ".addresses.registryCoordinator"
        );
        address avsDirectory = vm.parseJsonAddress(
            deploymentOutput,
            ".addresses.avsDirectory"
        );
        address serviceManager = vm.parseJsonAddress(
            localDeployment,
            ".addresses.serviceManager"
        );

        serviceManagerProxy = serviceManager;
        serviceProxyAdmin = ProxyAdmin(getAdminAddress(serviceManagerProxy));
        vm.label(msg.sender, "Caller");
        vm.label(address(serviceProxyAdmin), "Proxy Admin");
        vm.label(serviceProxyAdmin.owner(), "Proxy Admin Owner");
        vm.label(serviceManagerProxy, "Service Manager Upgradeable Proxy");

        vm.startBroadcast();
        serviceImplementationV2 = address(
            new ServiceManagerV2(
                IRegistryCoordinator(registryCoordinator),
                IAVSDirectory(avsDirectory)
            )
        );
        _upgradeContract(serviceManagerProxy, serviceImplementationV2);
        vm.stopBroadcast();
    }

    function _upgradeContract(
        address proxy,
        address newImplementation
    ) internal {
        address preUpgradeOwner = Ownable(proxy).owner();

        require(
            msg.sender == serviceProxyAdmin.owner(),
            "Call with private key for owner of the proxy admin"
        );
        serviceProxyAdmin.upgrade({
            proxy: TransparentUpgradeableProxy(payable(proxy)),
            implementation: newImplementation
        });

        address postUpgradeOwner = Ownable(proxy).owner();

        assertEq(preUpgradeOwner, postUpgradeOwner, "Owner changed");
    }

    function getAdminAddress(address proxy) internal view returns (address) {
        bytes32 adminSlot = vm.load(proxy, ADMIN_SLOT);
        return address(uint160(uint256(adminSlot)));
    }

    function getImplementationAddress(
        address proxy
    ) internal view returns (address) {
        bytes32 implSlot = vm.load(proxy, IMPLEMENTATION_SLOT);
        return address(uint160(uint256(implSlot)));
    }
}

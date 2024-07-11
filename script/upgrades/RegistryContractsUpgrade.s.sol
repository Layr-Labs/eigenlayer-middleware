// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IRegistryCoordinator} from "../../src/interfaces/IRegistryCoordinator.sol";
import {IBLSApkRegistry} from "../../src/interfaces/IBLSApkRegistry.sol";
import {IIndexRegistry} from "../../src/interfaces/IIndexRegistry.sol";
import {IStakeRegistry} from "../../src/interfaces/IStakeRegistry.sol";

import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

contract UpgradeContracts is Script, Test {
    bytes32 internal constant ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    ProxyAdmin internal proxyAdmin;
    address internal registryCoordinatorProxy;
    address internal blsApkRegistryProxy;
    address internal indexRegistryProxy;
    address internal stakeRegistryProxy;
    address internal newImplementationV2;

    function run() public virtual {
        string memory network = vm.envString("NETWORK");
        string memory deploymentOutputPath = string(
            abi.encodePacked(
                "lib/eigenlayer-contracts/script/output/",
                network,
                "/deployment_output.json"
            )
        );

        /// This is your local path, so you can import this script into your repo
        string memory localDeploymentPath = string(
            abi.encodePacked("script/output/", network, "/deployment.json")
        );

        // Load deployment data
        string memory deploymentOutput = vm.readFile(deploymentOutputPath);
        string memory localDeployment = vm.readFile(localDeploymentPath);

        // Parse deployment data
        registryCoordinatorProxy = vm.parseJsonAddress(
            deploymentOutput,
            ".addresses.registryCoordinator"
        );
        blsApkRegistryProxy = vm.parseJsonAddress(
            deploymentOutput,
            ".addresses.blsApkRegistry"
        );
        indexRegistryProxy = vm.parseJsonAddress(
            deploymentOutput,
            ".addresses.indexRegistry"
        );
        stakeRegistryProxy = vm.parseJsonAddress(
            deploymentOutput,
            ".addresses.stakeRegistry"
        );

        proxyAdmin = ProxyAdmin(getAdminAddress(registryCoordinatorProxy));
        vm.label(msg.sender, "Caller");
        vm.label(address(proxyAdmin), "Proxy Admin");
        vm.label(proxyAdmin.owner(), "Proxy Admin Owner");

        vm.startBroadcast();
        newImplementationV2 = deployNewImplementation("YourContractV2", "");

        _upgradeContract(registryCoordinatorProxy, newImplementationV2);
        _upgradeContract(blsApkRegistryProxy, newImplementationV2);
        _upgradeContract(indexRegistryProxy, newImplementationV2);
        _upgradeContract(stakeRegistryProxy, newImplementationV2);

        vm.stopBroadcast();
    }

    function _upgradeContract(
        address proxy,
        address newImplementation
    ) internal {
        address preUpgradeOwner = Ownable(proxy).owner();

        require(
            msg.sender == proxyAdmin.owner(),
            "Call with private key for owner of the proxy admin"
        );
        proxyAdmin.upgrade({
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

    function deployNewImplementation(
        string memory contractName,
        bytes memory constructorArgs
    ) internal returns (address) {
        bytes memory bytecode = abi.encodePacked(
            vm.getCode(contractName),
            constructorArgs
        );
        address newImplementation;
        assembly {
            newImplementation := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(
            newImplementation != address(0),
            "Deployment of new implementation failed"
        );
        return newImplementation;
    }
}

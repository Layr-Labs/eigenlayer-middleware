// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Vm} from "forge-std/Vm.sol";

library EigenUpgradesLib {
    Vm internal constant vm =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes32 internal constant ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function upgradeContract(
        ProxyAdmin proxyAdmin,
        address proxy,
        address newImplementation
    ) internal {
        address preUpgradeOwner = Ownable(proxy).owner();

        require(
            msg.sender == proxyAdmin.owner(),
            "Caller is not the owner of the proxy admin"
        );
        proxyAdmin.upgrade({
            proxy: TransparentUpgradeableProxy(payable(proxy)),
            implementation: newImplementation
        });

        address postUpgradeOwner = Ownable(proxy).owner();

        require(
            preUpgradeOwner == postUpgradeOwner,
            "Owner changed after upgrade"
        );
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

    function getEigenlayerCoreConfigPath(
        string memory network
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "lib/eigenlayer-contracts/script/output/",
                    network,
                    "/deployment_output.json"
                )
            );
    }

    function getLocalDeploymentConfigPath(
        string memory network
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked("script/output/", network, "/deployment.json")
            );
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {EigenUpgradesLib} from "./EigenUpgradesLib.sol";

abstract contract MiddlewareBaseScript is Script, Test {
    ProxyAdmin internal proxyAdmin;
    address internal proxyAddress;
    address internal newImplementation;

    function setUp() public virtual {
        string memory network = vm.envString("NETWORK");
        string memory eigenlayerConfigPath = EigenUpgradesLib
            .getEigenlayerCoreConfigPath(network);
        string memory localConfigPath = EigenUpgradesLib
            .getLocalDeploymentConfigPath(network);

        string memory eigenlayerConfig = vm.readFile(eigenlayerConfigPath);
        string memory localConfig = vm.readFile(localConfigPath);

        proxyAddress = getProxyAddress(eigenlayerConfig, localConfig);
        proxyAdmin = ProxyAdmin(EigenUpgradesLib.getAdminAddress(proxyAddress));

        vm.label(msg.sender, "Caller");
        vm.label(address(proxyAdmin), "Proxy Admin");
        vm.label(proxyAdmin.owner(), "Proxy Admin Owner");
        vm.label(proxyAddress, "Proxy Address");
    }

    function getProxyAddress(
        string memory eigenlayerConfig,
        string memory localConfig
    ) internal virtual returns (address);

    function deployNewImplementation(
        string memory contractName,
        bytes memory constructorArgs
    ) internal virtual returns (address) {
        return
            EigenUpgradesLib.deployNewImplementation(
                contractName,
                constructorArgs
            );
    }

    function upgradeContract() internal virtual {
        EigenUpgradesLib.upgradeContract(
            proxyAdmin,
            proxyAddress,
            newImplementation
        );
    }
}

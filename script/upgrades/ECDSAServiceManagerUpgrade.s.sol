// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MiddlewareBaseScript} from "./MiddlewareBaseScript.s.sol";
import {EigenUpgradesLib} from "./EigenUpgradesLib.sol";

/// Replace with your ECDSAServiceManagerBase
contract ECDSAServiceManagerBaseV2 {
    constructor() {}
}

contract UpgradeECDSAServiceManager is MiddlewareBaseScript {
    function setUp() public virtual override {
        super.setUp();
        string memory network = vm.envString("NETWORK");
        string memory localDeploymentPath = EigenUpgradesLib
            .getLocalDeploymentConfigPath(network);

        // Load deployment data
        string memory localDeployment = vm.readFile(localDeploymentPath);

        // Parse deployment data
        proxyAddress = vm.parseJsonAddress(
            localDeployment,
            ".addresses.serviceManager"
        );
    }

    function run() public {
        newImplementation = deployNewImplementation();
        upgradeContract();
        address currentImplementation = EigenUpgradesLib
            .getImplementationAddress(proxyAddress);
        require(
            currentImplementation == newImplementation,
            "Upgrade failed: Implementation address mismatch"
        );
    }

    function getProxyAddress(
        string memory,
        string memory
    ) internal view override returns (address) {
        return proxyAddress;
    }

    function deployNewImplementation() internal returns (address) {
        return deployNewImplementation("ECDSAServiceManagerBaseV2", "");
    }
}

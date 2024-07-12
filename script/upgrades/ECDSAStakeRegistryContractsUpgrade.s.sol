// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MiddlewareBaseScript} from "./MiddlewareBaseScript.s.sol";
import {EigenUpgradesLib} from "./EigenUpgradesLib.sol";

contract ECDSAStakeRegistryBaseV2 {
    constructor() {}
}

contract UpgradeECDSAStakeRegistry is MiddlewareBaseScript {
    function setUp() public virtual override {
        super.setUp();
        string memory network = vm.envString("NETWORK");
        string memory localDeploymentPath = EigenUpgradesLib
            .getLocalDeploymentConfigPath(network);

        string memory localDeployment = vm.readFile(localDeploymentPath);

        proxyAddress = vm.parseJsonAddress(
            localDeployment,
            ".addresses.stakeRegistry"
        );
    }

    function run() public {
        newImplementation = EigenUpgradesLib.deployNewImplementation(
            "ECDSAStakeRegistryBaseV2",
            ""
        );

        upgradeContract();

        address currentImplementation = EigenUpgradesLib
            .getImplementationAddress(proxyAddress);
        require(
            currentImplementation == newImplementation,
            "Upgrade failed: Implementation address mismatch"
        );
    }
}

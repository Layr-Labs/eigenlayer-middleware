// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {MockAVSDeployer} from "../utils/MockAVSDeployer.sol";
import {BN254} from "../../src/libraries/BN254.sol";
import {IRegistryCoordinator} from "../../src/interfaces/IRegistryCoordinator.sol";
import {IStakeRegistry} from "../../src/interfaces/IStakeRegistry.sol";
import {BitmapUtils} from "../../src/libraries/BitmapUtils.sol";

contract AVSRegistrarTest is MockAVSDeployer {
    using BN254 for BN254.G1Point;

    function setUp() public virtual {
        _deployMockEigenLayerAndAVS();
    }

    function testTrue() public {
        assertTrue(true);
    }
}

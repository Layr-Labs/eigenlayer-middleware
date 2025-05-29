// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {AllocationManagerMock} from "eigenlayer-contracts/src/test/mocks/AllocationManagerMock.sol";
import {KeyRegistrarMock} from "../../mocks/KeyRegistrarMock.sol";
import {Randomness, Random} from "eigenlayer-contracts/src/test/utils/Random.sol";

import "forge-std/Test.sol";

abstract contract MockEigenLayerDeployer is Test {
    /// @dev addresses that should be excluded from fuzzing
    mapping(address => bool) public isExcludedFuzzAddress;

    modifier filterFuzzedAddressInputs(address addr) {
        cheats.assume(!isExcludedFuzzAddress[addr]);
        _;
    }

    /// @dev set the random seed for the current test
    modifier rand(Randomness r) {
        r.set();
        _;
    }

    function random() internal returns (Randomness) {
        return Randomness.wrap(Random.SEED).shuffle();
    }

    Vm cheats = Vm(VM_ADDRESS);

    // State Variables
    AllocationManagerMock public allocationManagerMock;

    function _deployMockEigenLayer() internal {
        allocationManagerMock = new AllocationManagerMock();
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "test/mocks/KeyRegistrarMock.sol";
import "test/mocks/AllocationManagerMock.sol";
import "test/utils/Random.sol";

import "forge-std/Test.sol";

abstract contract MockEigenLayerDeployer is Test {
    Vm cheats = Vm(VM_ADDRESS);

    /// @dev addresses that should be excluded from fuzzing
    mapping(address => bool) public isExcludedFuzzAddress;

    modifier filterFuzzedAddressInputs(
        address addr
    ) {
        cheats.assume(!isExcludedFuzzAddress[addr]);
        _;
    }

    /// @dev set the random seed for the current test
    modifier rand(
        Randomness r
    ) {
        r.set();
        _;
    }

    function random() internal returns (Randomness) {
        return Randomness.wrap(Random.SEED).shuffle();
    }

    // State Variables
    ProxyAdmin public proxyAdmin;
    AllocationManagerMock public allocationManagerMock;
    KeyRegistrarMock public keyRegistrarMock;

    function _deployMockEigenLayer() internal {
        // Deploy the proxy admin
        proxyAdmin = new ProxyAdmin();

        // Deploy mocks
        allocationManagerMock = new AllocationManagerMock();
        keyRegistrarMock = new KeyRegistrarMock();
    }
}

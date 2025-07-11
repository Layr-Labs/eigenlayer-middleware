// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {KeyRegistrar} from "eigenlayer-contracts/src/contracts/permissions/KeyRegistrar.sol";
import {PermissionController} from
    "eigenlayer-contracts/src/contracts/permissions/PermissionController.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

import {AllocationManagerMock} from "test/mocks/AllocationManagerMock.sol";
import "test/mocks/KeyRegistrarMock.sol";
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

    /// @dev In order to test key functionality, for the table calculators, we also deploy the actual KeyRegistrar implementation
    PermissionController permissionController;
    PermissionController permissionControllerImplementation;
    KeyRegistrar keyRegistrarImplementation;
    KeyRegistrar keyRegistrar;

    function _deployMockEigenLayer() internal {
        // Deploy the proxy admin
        proxyAdmin = new ProxyAdmin();

        // Deploy mocks
        allocationManagerMock = new AllocationManagerMock();
        keyRegistrarMock = new KeyRegistrarMock();

        // Deploy the actual PermissionController & KeyRegistrar implementations
        permissionControllerImplementation = new PermissionController("9.9.9");
        permissionController = PermissionController(
            address(
                new TransparentUpgradeableProxy(
                    address(permissionControllerImplementation), address(proxyAdmin), ""
                )
            )
        );

        keyRegistrarImplementation = new KeyRegistrar(
            permissionController, IAllocationManager(address(allocationManagerMock)), "9.9.9"
        );
        keyRegistrar = KeyRegistrar(
            address(
                new TransparentUpgradeableProxy(
                    address(keyRegistrarImplementation), address(proxyAdmin), ""
                )
            )
        );

        // Filter our proxyAdmin from fuzzing
        isExcludedFuzzAddress[address(proxyAdmin)] = true;
    }
}

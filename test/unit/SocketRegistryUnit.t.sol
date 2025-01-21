// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {SocketRegistry} from "../../src/SocketRegistry.sol";
import {IRegistryCoordinator} from "../../src/interfaces/IRegistryCoordinator.sol";
import "../utils/MockAVSDeployer.sol";

contract SocketRegistryUnitTests is MockAVSDeployer {

    function setUp() virtual public {
        _deployMockEigenLayerAndAVS();
    }

    function test_setOperatorSocket() public {
        vm.startPrank(address(registryCoordinator));
        socketRegistry.setOperatorSocket(defaultOperatorId, "testSocket");
        assertEq(socketRegistry.getOperatorSocket(defaultOperatorId), "testSocket");
    }

    function test_setOperatorSocket_revert_notRegistryCoordinator() public {
        vm.startPrank(address(0));
        vm.expectRevert("SocketRegistry.onlyRegistryCoordinator: caller is not the RegistryCoordinator");
        socketRegistry.setOperatorSocket(defaultOperatorId, "testSocket");
    }

}
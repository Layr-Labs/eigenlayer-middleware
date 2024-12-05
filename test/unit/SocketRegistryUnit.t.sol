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

    function test_migrateOperatorSockets() public {
        bytes32[] memory operatorIds = new bytes32[](1);
        operatorIds[0] = defaultOperatorId;
        string[] memory sockets = new string[](1);
        sockets[0] = "testSocket";

        vm.startPrank(registryCoordinator.owner());
        socketRegistry.migrateOperatorSockets(operatorIds, sockets);
        assertEq(socketRegistry.getOperatorSocket(defaultOperatorId), "testSocket");
    }

    function test_migrateOperatorSockets_revert_notCoordinatorOwner() public {
        bytes32[] memory operatorIds = new bytes32[](1);
        operatorIds[0] = defaultOperatorId;
        string[] memory sockets = new string[](1);
        sockets[0] = "testSocket";

        vm.startPrank(address(0));
        vm.expectRevert("SocketRegistry.onlyCoordinatorOwner: caller is not the owner of the registryCoordinator");
        socketRegistry.migrateOperatorSockets(operatorIds, sockets);
    }

}
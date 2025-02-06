// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {SocketRegistry, ISlashingRegistryCoordinator} from "../../src/SocketRegistry.sol";
import {ISocketRegistry, ISocketRegistryErrors} from "../../src/interfaces/ISocketRegistry.sol";
import {IRegistryCoordinator} from "../../src/interfaces/IRegistryCoordinator.sol";
import "../utils/MockAVSDeployer.sol";

interface IOwnable {
    function owner() external view returns (address);
}

contract MockSocketRegistry is SocketRegistry {
    constructor(
        ISlashingRegistryCoordinator _slashingRegistryCoordinator
    ) SocketRegistry(_slashingRegistryCoordinator) {}

    function onlyCoordinatorOwnerFn() external view onlyCoordinatorOwner {}
}

contract SocketRegistryUnitTests is MockAVSDeployer {
    function setUp() public virtual {
        _deployMockEigenLayerAndAVS();
    }

    function testFuzz_revert_onlyCoordinatorOwner(
        address caller
    ) public {
        MockSocketRegistry _socketRegistry = new MockSocketRegistry(registryCoordinator);

        vm.prank(caller);
        vm.assume(caller != IOwnable(address(registryCoordinator)).owner());
        vm.expectRevert(ISocketRegistryErrors.OnlySlashingRegistryCoordinatorOwner.selector);
        _socketRegistry.onlyCoordinatorOwnerFn();
    }

    function test_setOperatorSocket() public {
        vm.startPrank(address(registryCoordinator));
        socketRegistry.setOperatorSocket(defaultOperatorId, "testSocket");
        assertEq(socketRegistry.getOperatorSocket(defaultOperatorId), "testSocket");
    }

    function test_setOperatorSocket_revert_notSlashingRegistryCoordinator() public {
        vm.startPrank(address(0));
        vm.expectRevert(ISocketRegistryErrors.OnlySlashingRegistryCoordinator.selector);
        socketRegistry.setOperatorSocket(defaultOperatorId, "testSocket");
    }
}

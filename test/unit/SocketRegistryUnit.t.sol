// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {SocketRegistry, ISlashingRegistryCoordinator} from "../../src/SocketRegistry.sol";
import {ISocketRegistry, ISocketRegistryErrors} from "../../src/interfaces/ISocketRegistry.sol";
import {IRegistryCoordinator} from "../../src/interfaces/IRegistryCoordinator.sol";
import "../utils/MockAVSDeployer.sol";

interface IOwnable {
    function owner() external view returns (address);
}

contract SocketRegistryUnitTests is MockAVSDeployer {
    function setUp() public virtual {
        _deployMockEigenLayerAndAVS();
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

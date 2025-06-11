// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import "./AVSRegistrarBase.t.sol";
import {AVSRegistrarWithSocket} from "src/middlewareV2/registrar/presets/AVSRegistrarWithSocket.sol";
import {ISocketRegistryEvents, ISocketRegistryErrors} from "src/interfaces/ISocketRegistryV2.sol";

contract AVSRegistrarSocketUnitTests is
    AVSRegistrarBase,
    ISocketRegistryEvents,
    ISocketRegistryErrors
{
    AVSRegistrarWithSocket public avsRegistrarWithSocket;

    string defaultSocket = "Socket";
    bytes socketData;

    function setUp() public override {
        super.setUp();

        avsRegistrarImplementation = new AVSRegistrarWithSocket(
            AVS,
            IAllocationManager(address(allocationManagerMock)),
            IKeyRegistrar(address(keyRegistrarMock))
        );

        avsRegistrarWithSocket = AVSRegistrarWithSocket(
            address(
                new TransparentUpgradeableProxy(
                    address(avsRegistrarImplementation), address(proxyAdmin), ""
                )
            )
        );

        // Encode defaultSocker into data
        socketData = abi.encode(defaultSocket);
    }

    function _registerOperator(
        uint32[] memory operatorSetIds
    ) internal {
        // Register operator
        _registerKey(defaultOperator, operatorSetIds);
        cheats.prank(address(allocationManagerMock));
        avsRegistrarWithSocket.registerOperator(defaultOperator, AVS, operatorSetIds, socketData);
    }
}

contract AVSRegistrarSocketUnitTests_registerOperator is AVSRegistrarSocketUnitTests {
    using ArrayLib for *;

    function testFuzz_revert_notAllocationManager(
        address notAllocationManager
    ) public {
        cheats.assume(notAllocationManager != address(allocationManagerMock));

        cheats.prank(notAllocationManager);
        cheats.expectRevert(NotAllocationManager.selector);
        avsRegistrarWithSocket.registerOperator(
            defaultOperator, AVS, defaultOperatorSetId.toArrayU32(), socketData
        );
    }

    function test_revert_keyNotRegistered() public {
        cheats.expectRevert(KeyNotRegistered.selector);
        cheats.prank(address(allocationManagerMock));
        avsRegistrarWithSocket.registerOperator(
            defaultOperator, AVS, defaultOperatorSetId.toArrayU32(), socketData
        );
    }

    function testFuzz_correctness(
        Randomness r
    ) public rand(r) {
        // Generate random operator set ids & register keys
        uint32 numOperatorSetIds = r.Uint32(1, 50);
        uint32[] memory operatorSetIds = r.Uint32Array(numOperatorSetIds, 0, type(uint32).max);
        _registerKey(defaultOperator, operatorSetIds);

        // Register operator
        cheats.expectEmit(true, true, true, true);
        emit OperatorSocketSet(defaultOperator, defaultSocket);
        cheats.expectEmit(true, true, true, true);
        emit OperatorRegistered(defaultOperator, operatorSetIds);

        cheats.prank(address(allocationManagerMock));
        avsRegistrarWithSocket.registerOperator(defaultOperator, AVS, operatorSetIds, socketData);

        // Check that the socket is set
        string memory socket = avsRegistrarWithSocket.getOperatorSocket(defaultOperator);
        assertEq(socket, defaultSocket, "Socket mismatch");
    }
}

contract AVSRegistrarSocketUnitTests_DeregisterOperator is AVSRegistrarSocketUnitTests {
    using ArrayLib for *;

    function testFuzz_revert_notAllocationManager(
        address notAllocationManager
    ) public {
        cheats.assume(notAllocationManager != address(allocationManagerMock));

        cheats.prank(notAllocationManager);
        cheats.expectRevert(NotAllocationManager.selector);
        avsRegistrarWithSocket.deregisterOperator(
            defaultOperator, AVS, defaultOperatorSetId.toArrayU32()
        );
    }

    function testFuzz_correctness(
        Randomness r
    ) public rand(r) {
        // Generate random operator set ids
        uint32 numOperatorSetIds = r.Uint32(1, 50);
        uint32[] memory operatorSetIds = r.Uint32Array(numOperatorSetIds, 0, type(uint32).max);

        _registerOperator(operatorSetIds);

        cheats.expectEmit(true, true, true, true);
        emit OperatorDeregistered(defaultOperator, operatorSetIds);
        cheats.prank(address(allocationManagerMock));
        avsRegistrarWithSocket.deregisterOperator(defaultOperator, AVS, operatorSetIds);

        // Check that the socket still exists
        string memory socket = avsRegistrarWithSocket.getOperatorSocket(defaultOperator);
        assertEq(socket, defaultSocket, "Socket mismatch");
    }
}

contract AVSRegistrarSocketUnitTests_updateSocket is AVSRegistrarSocketUnitTests {
    using ArrayLib for *;

    function testFuzz_revert_notOperator(
        address notOperator
    ) public {
        _registerOperator(defaultOperatorSetId.toArrayU32());
        cheats.assume(notOperator != defaultOperator);
        cheats.assume(notOperator != address(proxyAdmin));

        cheats.prank(notOperator);
        cheats.expectRevert(CallerNotOperator.selector);
        avsRegistrarWithSocket.updateSocket(defaultOperator, defaultSocket);
    }

    function test_updateSocket() public {
        _registerOperator(defaultOperatorSetId.toArrayU32());

        string memory newSocket = "NewSocket";

        cheats.expectEmit(true, true, true, true);
        emit OperatorSocketSet(defaultOperator, newSocket);
        cheats.prank(defaultOperator);
        avsRegistrarWithSocket.updateSocket(defaultOperator, newSocket);

        // Check that the socket is updated
        string memory socket = avsRegistrarWithSocket.getOperatorSocket(defaultOperator);
        assertEq(socket, newSocket, "Socket mismatch");
    }
}

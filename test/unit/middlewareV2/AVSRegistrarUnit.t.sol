// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import "./AVSRegistrarBase.t.sol";

contract AVSRegistrarUnitTests is AVSRegistrarBase {
    function setUp() public override {
        super.setUp();

        avsRegistrarImplementation = new AVSRegistrar(
            AVS,
            IAllocationManager(address(allocationManagerMock)),
            IKeyRegistrar(address(keyRegistrarMock))
        );

        avsRegistrar = AVSRegistrar(
            address(
                new TransparentUpgradeableProxy(
                    address(avsRegistrarImplementation), address(proxyAdmin), ""
                )
            )
        );
    }
}

contract AVSRegistrarUnitTests_RegisterOperator is AVSRegistrarUnitTests {
    using ArrayLib for *;

    function testFuzz_revert_notAllocationManager(
        address notAllocationManager
    ) public {
        cheats.assume(notAllocationManager != address(allocationManagerMock));
        cheats.assume(notAllocationManager != address(proxyAdmin));

        cheats.prank(notAllocationManager);
        cheats.expectRevert(NotAllocationManager.selector);
        avsRegistrar.registerOperator(defaultOperator, AVS, defaultOperatorSetId.toArrayU32(), "0x");
    }

    function test_revert_keyNotRegistered() public {
        cheats.expectRevert(KeyNotRegistered.selector);
        cheats.prank(address(allocationManagerMock));
        avsRegistrar.registerOperator(defaultOperator, AVS, defaultOperatorSetId.toArrayU32(), "0x");
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
        emit OperatorRegistered(defaultOperator, operatorSetIds);
        cheats.prank(address(allocationManagerMock));
        avsRegistrar.registerOperator(defaultOperator, AVS, operatorSetIds, "0x");
    }
}

contract AVSRegistrarUnitTests_DeregisterOperator is AVSRegistrarUnitTests {
    using ArrayLib for *;

    function testFuzz_revert_notAllocationManager(
        address notAllocationManager
    ) public {
        cheats.assume(notAllocationManager != address(allocationManagerMock));
        cheats.assume(notAllocationManager != address(proxyAdmin));

        cheats.prank(notAllocationManager);
        cheats.expectRevert(NotAllocationManager.selector);
        avsRegistrar.deregisterOperator(defaultOperator, AVS, defaultOperatorSetId.toArrayU32());
    }

    function testFuzz_correctness(
        Randomness r
    ) public rand(r) {
        // Generate random operator set ids
        uint32 numOperatorSetIds = r.Uint32(1, 50);
        uint32[] memory operatorSetIds = r.Uint32Array(numOperatorSetIds, 0, type(uint32).max);

        // Deregister operator
        cheats.expectEmit(true, true, true, true);
        emit OperatorDeregistered(defaultOperator, operatorSetIds);
        cheats.prank(address(allocationManagerMock));
        avsRegistrar.deregisterOperator(defaultOperator, AVS, operatorSetIds);
    }
}

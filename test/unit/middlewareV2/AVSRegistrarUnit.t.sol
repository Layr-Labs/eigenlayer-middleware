// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import "./AVSRegistrarBase.t.sol";

contract AVSRegistrarUnitTests is AVSRegistrarBase {
    function setUp() public override {
        super.setUp();

        avsRegistrarImplementation = AVSRegistrar(
            new AVSRegistrarImplementation(
                IAllocationManager(address(allocationManagerMock)),
                IKeyRegistrar(address(keyRegistrarMock))
            )
        );

        avsRegistrar = AVSRegistrar(
            address(
                new TransparentUpgradeableProxy(
                    address(avsRegistrarImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(AVSRegistrarImplementation.initialize.selector, AVS)
                )
            )
        );
    }
}

contract AVSRegistrarUnitTests_RegisterOperator is AVSRegistrarUnitTests {
    using ArrayLib for *;

    function testFuzz_revert_notAllocationManager(
        address notAllocationManager
    ) public filterFuzzedAddressInputs(notAllocationManager) {
        cheats.assume(notAllocationManager != address(allocationManagerMock));

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
    ) public filterFuzzedAddressInputs(notAllocationManager) {
        cheats.assume(notAllocationManager != address(allocationManagerMock));

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

contract AVSRegistrarUnitTests_ViewFunctions is AVSRegistrarUnitTests {
    function test_supportsAVS_true() public {
        // Should return true when checking against the configured AVS
        assertTrue(
            avsRegistrar.supportsAVS(AVS), "supportsAVS: should return true for configured AVS"
        );
    }

    function test_supportsAVS_false() public {
        // Should return false for any other address
        assertFalse(
            avsRegistrar.supportsAVS(address(0)),
            "supportsAVS: should return false for zero address"
        );
        assertFalse(
            avsRegistrar.supportsAVS(address(1)),
            "supportsAVS: should return false for random address"
        );
        assertFalse(
            avsRegistrar.supportsAVS(address(avsRegistrar)),
            "supportsAVS: should return false for registrar address"
        );
        assertFalse(
            avsRegistrar.supportsAVS(defaultOperator),
            "supportsAVS: should return false for operator"
        );
    }

    function testFuzz_supportsAVS(
        address randomAddress
    ) public {
        if (randomAddress == AVS) {
            assertTrue(
                avsRegistrar.supportsAVS(randomAddress),
                "supportsAVS: should return true for configured AVS"
            );
        } else {
            assertFalse(
                avsRegistrar.supportsAVS(randomAddress),
                "supportsAVS: should return false for non-AVS address"
            );
        }
    }
}

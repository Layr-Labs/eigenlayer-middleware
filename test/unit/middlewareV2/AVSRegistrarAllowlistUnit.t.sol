// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./AVSRegistrarBase.t.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import {AVSRegistrarWithAllowlist} from
    "src/middlewareV2/registrar/presets/AVSRegistrarWithAllowlist.sol";
import {IAllowlistErrors, IAllowlistEvents} from "src/interfaces/IAllowlist.sol";

contract AVSRegistrarWithAllowlistUnitTests is
    AVSRegistrarBase,
    IAllowlistErrors,
    IAllowlistEvents
{
    AVSRegistrarWithAllowlist public avsRegistrarWithAllowlist;
    address public allowlistAdmin = address(this);

    function setUp() public override {
        super.setUp();

        avsRegistrarImplementation = new AVSRegistrarWithAllowlist(
            IAllocationManager(address(allocationManagerMock)),
            IKeyRegistrar(address(keyRegistrarMock))
        );

        avsRegistrarWithAllowlist = AVSRegistrarWithAllowlist(
            address(
                new TransparentUpgradeableProxy(
                    address(avsRegistrarImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        AVSRegistrarWithAllowlist.initialize.selector, AVS, address(this)
                    )
                )
            )
        );
    }

    function _addOperatorToAllowlist(address operator, uint32[] memory operatorSetIds) internal {
        for (uint32 i; i < operatorSetIds.length; ++i) {
            cheats.prank(allowlistAdmin);
            avsRegistrarWithAllowlist.addOperatorToAllowlist(
                OperatorSet({avs: AVS, id: operatorSetIds[i]}), operator
            );
        }
    }
}

contract AVSRegistrarWithAllowlistUnitTests_initialize is AVSRegistrarWithAllowlistUnitTests {
    function test_initialization() public view {
        // Check the admin is set
        assertEq(
            avsRegistrarWithAllowlist.owner(), allowlistAdmin, "Initialization: owner incorrect"
        );
    }

    function test_revert_alreadyInitialized() public {
        cheats.expectRevert("Initializable: contract is already initialized");
        avsRegistrarWithAllowlist.initialize(AVS, allowlistAdmin);
    }
}

contract AVSRegistrarWithAllowlistUnitTests_addOperatorToAllowlist is
    AVSRegistrarWithAllowlistUnitTests
{
    using ArrayLib for *;

    function testFuzz_revert_notOwner(
        address notOwner
    ) public {
        cheats.assume(notOwner != allowlistAdmin);

        cheats.expectRevert("Ownable: caller is not the owner");
        cheats.prank(notOwner);
        avsRegistrarWithAllowlist.addOperatorToAllowlist(
            OperatorSet({avs: AVS, id: 0}), defaultOperator
        );
    }

    function test_revert_operatorAlreadyInAllowlist() public {
        _addOperatorToAllowlist(defaultOperator, defaultOperatorSetId.toArrayU32());

        cheats.expectRevert(OperatorAlreadyInAllowlist.selector);
        cheats.prank(allowlistAdmin);
        avsRegistrarWithAllowlist.addOperatorToAllowlist(
            OperatorSet({avs: AVS, id: 0}), defaultOperator
        );
    }

    function testFuzz_correctness(
        Randomness r
    ) public rand(r) {
        // Generate random operator set ids
        uint32 numOperatorSetIds = r.Uint32(1, 50);
        uint32[] memory operatorSetIds = r.Uint32Array(numOperatorSetIds, 0, type(uint32).max);

        // Add operator to allowlist
        for (uint32 i; i < operatorSetIds.length; ++i) {
            cheats.expectEmit(true, true, true, true);
            emit OperatorAddedToAllowlist(
                OperatorSet({avs: AVS, id: operatorSetIds[i]}), defaultOperator
            );
            cheats.prank(allowlistAdmin);
            avsRegistrarWithAllowlist.addOperatorToAllowlist(
                OperatorSet({avs: AVS, id: operatorSetIds[i]}), defaultOperator
            );
        }

        // Check the operator is in the allowlist
        for (uint32 i; i < operatorSetIds.length; ++i) {
            assertTrue(
                avsRegistrarWithAllowlist.isOperatorAllowed(
                    OperatorSet({avs: AVS, id: operatorSetIds[i]}), defaultOperator
                ),
                "Operator not in allowlist"
            );
        }
    }
}

contract AVSRegistrarWithAllowlistUnitTests_removeOperatorFromAllowlist is
    AVSRegistrarWithAllowlistUnitTests
{
    using ArrayLib for *;

    function testFuzz_revert_notOwner(
        address notOwner
    ) public view {
        cheats.assume(notOwner != allowlistAdmin);
    }

    function test_revert_operatorNotInAllowlist() public {
        cheats.expectRevert(OperatorNotInAllowlist.selector);
        cheats.prank(allowlistAdmin);
        avsRegistrarWithAllowlist.removeOperatorFromAllowlist(
            OperatorSet({avs: AVS, id: 0}), defaultOperator
        );
    }

    function testFuzz_correctness(
        Randomness r
    ) public rand(r) {
        // Generate random operator set ids
        uint32 numOperatorSetIds = r.Uint32(1, 50);
        uint32[] memory operatorSetIds = r.Uint32Array(numOperatorSetIds, 0, type(uint32).max);

        // Add operator to allowlist
        _addOperatorToAllowlist(defaultOperator, operatorSetIds);

        // Remove operator from allowlist
        for (uint32 i; i < operatorSetIds.length; ++i) {
            cheats.expectEmit(true, true, true, true);
            emit OperatorRemovedFromAllowlist(
                OperatorSet({avs: AVS, id: operatorSetIds[i]}), defaultOperator
            );
            cheats.prank(allowlistAdmin);
            avsRegistrarWithAllowlist.removeOperatorFromAllowlist(
                OperatorSet({avs: AVS, id: operatorSetIds[i]}), defaultOperator
            );
        }

        // Check the operator is not in the allowlist
        for (uint32 i; i < operatorSetIds.length; ++i) {
            assertFalse(
                avsRegistrarWithAllowlist.isOperatorAllowed(
                    OperatorSet({avs: AVS, id: operatorSetIds[i]}), defaultOperator
                ),
                "Operator still in allowlist"
            );
        }
    }
}

contract AVSRegistrarAllowistUnitTest_getRegisteredOperators is
    AVSRegistrarWithAllowlistUnitTests
{
    using ArrayLib for *;

    function testFuzz_correctness(
        Randomness r
    ) public rand(r) {
        // Generate random addresses
        uint32 numAddresses = r.Uint32(1, 50);
        address[] memory operators = new address[](numAddresses);
        for (uint32 i; i < numAddresses; ++i) {
            operators[i] = r.Address();
        }

        // Generate random operator set ids
        uint32 numOperatorSetIds = r.Uint32(1, 50);
        uint32[] memory operatorSetIds = r.Uint32Array(numOperatorSetIds, 0, type(uint32).max);

        // Add operators to allowlist
        for (uint32 i; i < operators.length; ++i) {
            _addOperatorToAllowlist(operators[i], operatorSetIds);
        }

        // Get the allowed operators
        for (uint32 i; i < operatorSetIds.length; ++i) {
            // Note: although ordering is not guaranteed generally, it works here since we do not do any removes.
            address[] memory allowedOperators = avsRegistrarWithAllowlist.getAllowedOperators(
                OperatorSet({avs: AVS, id: operatorSetIds[i]})
            );
            assertEq(
                allowedOperators.length, operators.length, "Incorrect number of allowed operators"
            );
            for (uint32 j; j < allowedOperators.length; ++j) {
                assertTrue(allowedOperators[j] == operators[j], "Allowed operator incorrect");
            }
        }
    }
}

contract AVSRegistrarWithAllowlistUnitTests_registerOperator is
    AVSRegistrarWithAllowlistUnitTests
{
    using ArrayLib for *;

    function testFuzz_revert_notAllocationManager(
        address notAllocationManager
    ) public filterFuzzedAddressInputs(notAllocationManager) {
        cheats.assume(notAllocationManager != address(allocationManagerMock));

        cheats.prank(notAllocationManager);
        cheats.expectRevert(NotAllocationManager.selector);
        avsRegistrarWithAllowlist.registerOperator(
            defaultOperator, AVS, defaultOperatorSetId.toArrayU32(), "0x"
        );
    }

    function test_revert_operatorNotInAllowlist() public {
        // Register operator
        cheats.expectRevert(OperatorNotInAllowlist.selector);
        cheats.prank(address(allocationManagerMock));
        avsRegistrarWithAllowlist.registerOperator(
            defaultOperator, AVS, defaultOperatorSetId.toArrayU32(), "0x"
        );
    }

    function test_revert_keyNotRegistered() public {
        // Add operator to allowlist
        _addOperatorToAllowlist(defaultOperator, defaultOperatorSetId.toArrayU32());

        // Register operator
        cheats.expectRevert(KeyNotRegistered.selector);
        cheats.prank(address(allocationManagerMock));
        avsRegistrarWithAllowlist.registerOperator(
            defaultOperator, AVS, defaultOperatorSetId.toArrayU32(), "0x"
        );
    }

    function testFuzz_correctness(
        Randomness r
    ) public rand(r) {
        // Generate random operator set ids & register keys
        uint32 numOperatorSetIds = r.Uint32(1, 50);
        uint32[] memory operatorSetIds = r.Uint32Array(numOperatorSetIds, 0, type(uint32).max);
        _registerKey(defaultOperator, operatorSetIds);

        // Add operator to allowlist
        _addOperatorToAllowlist(defaultOperator, operatorSetIds);

        // Register operator
        cheats.expectEmit(true, true, true, true);
        emit OperatorRegistered(defaultOperator, operatorSetIds);
        cheats.prank(address(allocationManagerMock));
        avsRegistrarWithAllowlist.registerOperator(defaultOperator, AVS, operatorSetIds, "0x");
    }
}

contract AVSRegistrarWithAllowlistUnitTests_deregisterOperator is
    AVSRegistrarWithAllowlistUnitTests
{
    using ArrayLib for *;

    function testFuzz_revert_notAllocationManager(
        address notAllocationManager
    ) public {
        cheats.assume(notAllocationManager != address(allocationManagerMock));
        cheats.assume(notAllocationManager != address(proxyAdmin));

        cheats.prank(notAllocationManager);
        cheats.expectRevert(NotAllocationManager.selector);
        avsRegistrarWithAllowlist.deregisterOperator(
            defaultOperator, AVS, defaultOperatorSetId.toArrayU32()
        );
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
        avsRegistrarWithAllowlist.deregisterOperator(defaultOperator, AVS, operatorSetIds);
    }
}

contract AVSRegistrarWithAllowlistUnitTests_ViewFunctions is AVSRegistrarWithAllowlistUnitTests {
    function test_supportsAVS_true() public {
        // Should return true when checking against the configured AVS
        assertTrue(
            avsRegistrarWithAllowlist.supportsAVS(AVS),
            "supportsAVS: should return true for configured AVS"
        );
    }

    function test_supportsAVS_false() public {
        // Should return false for any other address
        assertFalse(
            avsRegistrarWithAllowlist.supportsAVS(address(0)),
            "supportsAVS: should return false for zero address"
        );
        assertFalse(
            avsRegistrarWithAllowlist.supportsAVS(address(1)),
            "supportsAVS: should return false for random address"
        );
        assertFalse(
            avsRegistrarWithAllowlist.supportsAVS(address(avsRegistrarWithAllowlist)),
            "supportsAVS: should return false for registrar address"
        );
        assertFalse(
            avsRegistrarWithAllowlist.supportsAVS(defaultOperator),
            "supportsAVS: should return false for operator"
        );
    }

    function testFuzz_supportsAVS(
        address randomAddress
    ) public {
        if (randomAddress == AVS) {
            assertTrue(
                avsRegistrarWithAllowlist.supportsAVS(randomAddress),
                "supportsAVS: should return true for configured AVS"
            );
        } else {
            assertFalse(
                avsRegistrarWithAllowlist.supportsAVS(randomAddress),
                "supportsAVS: should return false for non-AVS address"
            );
        }
    }
}

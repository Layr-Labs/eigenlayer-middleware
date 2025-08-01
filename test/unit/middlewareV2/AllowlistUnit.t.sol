// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Allowlist} from "src/middlewareV2/registrar/modules/Allowlist.sol";
import {IAllowlist, IAllowlistErrors, IAllowlistEvents} from "src/interfaces/IAllowlist.sol";
import {
    OperatorSet,
    OperatorSetLib
} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {Random, Randomness} from "test/utils/Random.sol";

// Concrete implementation for testing
contract AllowlistImplementation is Allowlist {
    function initialize(
        address _owner
    ) external initializer {
        __Allowlist_init(_owner);
    }

    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}

contract AllowlistUnitTests is Test, IAllowlistErrors, IAllowlistEvents {
    using OperatorSetLib for OperatorSet;

    Vm cheats = Vm(VM_ADDRESS);

    // Contracts
    AllowlistImplementation public allowlistImplementation;
    AllowlistImplementation public allowlist;
    ProxyAdmin public proxyAdmin;

    // Test addresses
    address public allowlistOwner = address(this);
    address public avs1 = address(0x1);
    address public avs2 = address(0x2);
    address public operator1 = address(0x3);
    address public operator2 = address(0x4);
    address public operator3 = address(0x5);
    address public defaultOperator = operator1;

    // Test operator sets
    OperatorSet defaultOperatorSet;
    OperatorSet alternativeOperatorSet;
    uint32 public defaultOperatorSetId = 0;

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

    function setUp() public virtual {
        // Deploy proxy admin
        proxyAdmin = new ProxyAdmin();

        // Deploy implementation
        allowlistImplementation = new AllowlistImplementation();

        // Deploy proxy
        allowlist = AllowlistImplementation(
            address(
                new TransparentUpgradeableProxy(
                    address(allowlistImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        AllowlistImplementation.initialize.selector, allowlistOwner
                    )
                )
            )
        );

        // Set up operator sets
        defaultOperatorSet = OperatorSet({avs: avs1, id: defaultOperatorSetId});
        alternativeOperatorSet = OperatorSet({avs: avs2, id: 1});
    }

    function _addOperatorToAllowlist(address operator, OperatorSet memory operatorSet) internal {
        cheats.prank(allowlistOwner);
        allowlist.addOperatorToAllowlist(operatorSet, operator);
    }

    function _addOperatorsToAllowlist(
        address[] memory operators,
        OperatorSet memory operatorSet
    ) internal {
        for (uint256 i = 0; i < operators.length; i++) {
            _addOperatorToAllowlist(operators[i], operatorSet);
        }
    }
}

contract AllowlistUnitTests_initialize is AllowlistUnitTests {
    function test_initialization() public view {
        // Check the owner is set correctly
        assertEq(allowlist.owner(), allowlistOwner, "Initialization: owner incorrect");
    }

    function test_revert_alreadyInitialized() public {
        cheats.expectRevert("Initializable: contract is already initialized");
        allowlist.initialize(allowlistOwner);
    }

    function testFuzz_initialization(
        address randomOwner
    ) public {
        // Deploy new instance with random owner
        AllowlistImplementation newAllowlist = AllowlistImplementation(
            address(
                new TransparentUpgradeableProxy(
                    address(allowlistImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(AllowlistImplementation.initialize.selector, randomOwner)
                )
            )
        );

        assertEq(newAllowlist.owner(), randomOwner, "Owner should be set to randomOwner");
    }
}

contract AllowlistUnitTests_addOperatorToAllowlist is AllowlistUnitTests {
    function testFuzz_revert_notOwner(
        address notOwner
    ) public {
        cheats.assume(notOwner != allowlistOwner);

        cheats.expectRevert("Ownable: caller is not the owner");
        cheats.prank(notOwner);
        allowlist.addOperatorToAllowlist(defaultOperatorSet, defaultOperator);
    }

    function test_revert_operatorAlreadyInAllowlist() public {
        // Add operator first time
        _addOperatorToAllowlist(defaultOperator, defaultOperatorSet);

        // Try to add again
        cheats.expectRevert(OperatorAlreadyInAllowlist.selector);
        cheats.prank(allowlistOwner);
        allowlist.addOperatorToAllowlist(defaultOperatorSet, defaultOperator);
    }

    function test_correctness_singleOperator() public {
        // Add operator
        cheats.expectEmit(true, true, true, true);
        emit OperatorAddedToAllowlist(defaultOperatorSet, defaultOperator);
        cheats.prank(allowlistOwner);
        allowlist.addOperatorToAllowlist(defaultOperatorSet, defaultOperator);

        // Check operator is in allowlist
        assertTrue(
            allowlist.isOperatorAllowed(defaultOperatorSet, defaultOperator),
            "Operator should be in allowlist"
        );
    }

    function testFuzz_correctness_multipleOperatorSets(
        Randomness r
    ) public rand(r) {
        // Generate random operator set ids
        uint32 numOperatorSets = r.Uint32(1, 50);
        uint32[] memory operatorSetIds = r.Uint32Array(numOperatorSets, 0, type(uint32).max);

        // Add operator to multiple operator sets
        for (uint32 i = 0; i < operatorSetIds.length; i++) {
            OperatorSet memory operatorSet = OperatorSet({avs: avs1, id: operatorSetIds[i]});

            cheats.expectEmit(true, true, true, true);
            emit OperatorAddedToAllowlist(operatorSet, defaultOperator);
            cheats.prank(allowlistOwner);
            allowlist.addOperatorToAllowlist(operatorSet, defaultOperator);
        }

        // Verify operator is in all operator sets
        for (uint32 i = 0; i < operatorSetIds.length; i++) {
            OperatorSet memory operatorSet = OperatorSet({avs: avs1, id: operatorSetIds[i]});
            assertTrue(
                allowlist.isOperatorAllowed(operatorSet, defaultOperator),
                "Operator should be in all operator sets"
            );
        }
    }

    function testFuzz_correctness_multipleOperators(
        Randomness r
    ) public rand(r) {
        // Generate random operators
        uint32 numOperators = r.Uint32(1, 50);
        address[] memory operators = new address[](numOperators);
        for (uint32 i = 0; i < numOperators; i++) {
            operators[i] = r.Address();
        }

        // Add all operators to the default operator set
        for (uint32 i = 0; i < operators.length; i++) {
            cheats.expectEmit(true, true, true, true);
            emit OperatorAddedToAllowlist(defaultOperatorSet, operators[i]);
            cheats.prank(allowlistOwner);
            allowlist.addOperatorToAllowlist(defaultOperatorSet, operators[i]);
        }

        // Verify all operators are in the allowlist
        for (uint32 i = 0; i < operators.length; i++) {
            assertTrue(
                allowlist.isOperatorAllowed(defaultOperatorSet, operators[i]),
                "All operators should be in allowlist"
            );
        }
    }
}

contract AllowlistUnitTests_removeOperatorFromAllowlist is AllowlistUnitTests {
    function testFuzz_revert_notOwner(
        address notOwner
    ) public {
        cheats.assume(notOwner != allowlistOwner);

        cheats.expectRevert("Ownable: caller is not the owner");
        cheats.prank(notOwner);
        allowlist.removeOperatorFromAllowlist(defaultOperatorSet, defaultOperator);
    }

    function test_revert_operatorNotInAllowlist() public {
        cheats.expectRevert(OperatorNotInAllowlist.selector);
        cheats.prank(allowlistOwner);
        allowlist.removeOperatorFromAllowlist(defaultOperatorSet, defaultOperator);
    }

    function test_correctness_removeAfterAdd() public {
        // Add operator first
        _addOperatorToAllowlist(defaultOperator, defaultOperatorSet);

        // Remove operator
        cheats.expectEmit(true, true, true, true);
        emit OperatorRemovedFromAllowlist(defaultOperatorSet, defaultOperator);
        cheats.prank(allowlistOwner);
        allowlist.removeOperatorFromAllowlist(defaultOperatorSet, defaultOperator);

        // Check operator is not in allowlist
        assertFalse(
            allowlist.isOperatorAllowed(defaultOperatorSet, defaultOperator),
            "Operator should not be in allowlist after removal"
        );
    }

    function testFuzz_correctness_multipleOperatorSets(
        Randomness r
    ) public rand(r) {
        // Generate random operator set ids
        uint32 numOperatorSets = r.Uint32(1, 50);
        uint32[] memory operatorSetIds = r.Uint32Array(numOperatorSets, 0, type(uint32).max);

        // Add operator to all operator sets
        for (uint32 i = 0; i < operatorSetIds.length; i++) {
            OperatorSet memory operatorSet = OperatorSet({avs: avs1, id: operatorSetIds[i]});
            _addOperatorToAllowlist(defaultOperator, operatorSet);
        }

        // Remove operator from all operator sets
        for (uint32 i = 0; i < operatorSetIds.length; i++) {
            OperatorSet memory operatorSet = OperatorSet({avs: avs1, id: operatorSetIds[i]});

            cheats.expectEmit(true, true, true, true);
            emit OperatorRemovedFromAllowlist(operatorSet, defaultOperator);
            cheats.prank(allowlistOwner);
            allowlist.removeOperatorFromAllowlist(operatorSet, defaultOperator);
        }

        // Verify operator is not in any operator set
        for (uint32 i = 0; i < operatorSetIds.length; i++) {
            OperatorSet memory operatorSet = OperatorSet({avs: avs1, id: operatorSetIds[i]});
            assertFalse(
                allowlist.isOperatorAllowed(operatorSet, defaultOperator),
                "Operator should not be in any operator set"
            );
        }
    }

    function test_correctness_partialRemoval() public {
        // Add operator to multiple operator sets
        _addOperatorToAllowlist(defaultOperator, defaultOperatorSet);
        _addOperatorToAllowlist(defaultOperator, alternativeOperatorSet);

        // Remove from only one operator set
        cheats.prank(allowlistOwner);
        allowlist.removeOperatorFromAllowlist(defaultOperatorSet, defaultOperator);

        // Check operator is removed from one but not the other
        assertFalse(
            allowlist.isOperatorAllowed(defaultOperatorSet, defaultOperator),
            "Operator should be removed from default operator set"
        );
        assertTrue(
            allowlist.isOperatorAllowed(alternativeOperatorSet, defaultOperator),
            "Operator should still be in alternative operator set"
        );
    }
}

contract AllowlistUnitTests_isOperatorAllowed is AllowlistUnitTests {
    function test_returnsFalse_whenNotAdded() public view {
        assertFalse(
            allowlist.isOperatorAllowed(defaultOperatorSet, defaultOperator),
            "Should return false for operator not in allowlist"
        );
    }

    function test_returnsTrue_whenAdded() public {
        _addOperatorToAllowlist(defaultOperator, defaultOperatorSet);

        assertTrue(
            allowlist.isOperatorAllowed(defaultOperatorSet, defaultOperator),
            "Should return true for operator in allowlist"
        );
    }

    function testFuzz_correctness(
        Randomness r
    ) public rand(r) {
        // Generate random operators and operator sets
        uint32 numOperators = r.Uint32(5, 20);
        uint32 numOperatorSets = r.Uint32(5, 20);

        address[] memory operators = new address[](numOperators);
        for (uint32 i = 0; i < numOperators; i++) {
            operators[i] = r.Address();
        }

        OperatorSet[] memory operatorSets = new OperatorSet[](numOperatorSets);
        for (uint32 i = 0; i < numOperatorSets; i++) {
            operatorSets[i] = OperatorSet({avs: r.Address(), id: r.Uint32(0, type(uint32).max)});
        }

        // Randomly add some operators to some operator sets
        for (uint32 i = 0; i < operators.length; i++) {
            for (uint32 j = 0; j < operatorSets.length; j++) {
                if (r.Boolean()) {
                    // 50% chance
                    _addOperatorToAllowlist(operators[i], operatorSets[j]);
                }
            }
        }

        // Verify the state is correct by re-checking
        for (uint32 i = 0; i < operators.length; i++) {
            for (uint32 j = 0; j < operatorSets.length; j++) {
                // The state should be consistent with what we set
                bool shouldBeAllowed = allowlist.isOperatorAllowed(operatorSets[j], operators[i]);

                // If allowed, removing should work
                if (shouldBeAllowed) {
                    cheats.prank(allowlistOwner);
                    allowlist.removeOperatorFromAllowlist(operatorSets[j], operators[i]);
                    assertFalse(
                        allowlist.isOperatorAllowed(operatorSets[j], operators[i]),
                        "After removal, operator should not be allowed"
                    );
                }
            }
        }
    }
}

contract AllowlistUnitTests_getAllowedOperators is AllowlistUnitTests {
    function test_returnsEmptyArray_whenNoOperators() public view {
        address[] memory allowedOperators = allowlist.getAllowedOperators(defaultOperatorSet);
        assertEq(allowedOperators.length, 0, "Should return empty array when no operators");
    }

    function test_returnsSingleOperator() public {
        _addOperatorToAllowlist(defaultOperator, defaultOperatorSet);

        address[] memory allowedOperators = allowlist.getAllowedOperators(defaultOperatorSet);
        assertEq(allowedOperators.length, 1, "Should return array with one operator");
        assertEq(allowedOperators[0], defaultOperator, "Should return the correct operator");
    }

    function test_returnsMultipleOperators() public {
        address[] memory operators = new address[](3);
        operators[0] = operator1;
        operators[1] = operator2;
        operators[2] = operator3;

        // Add all operators
        _addOperatorsToAllowlist(operators, defaultOperatorSet);

        address[] memory allowedOperators = allowlist.getAllowedOperators(defaultOperatorSet);
        assertEq(allowedOperators.length, 3, "Should return all operators");

        // Note: Order may not be preserved, so we check membership
        bool found1 = false;
        bool found2 = false;
        bool found3 = false;

        for (uint256 i = 0; i < allowedOperators.length; i++) {
            if (allowedOperators[i] == operator1) found1 = true;
            if (allowedOperators[i] == operator2) found2 = true;
            if (allowedOperators[i] == operator3) found3 = true;
        }

        assertTrue(found1 && found2 && found3, "All operators should be in the returned array");
    }

    function testFuzz_correctness(
        Randomness r
    ) public rand(r) {
        // Generate random operators
        uint32 numOperators = r.Uint32(1, 50);
        address[] memory operators = new address[](numOperators);
        for (uint32 i = 0; i < numOperators; i++) {
            operators[i] = r.Address();
        }

        // Add all operators to default operator set
        _addOperatorsToAllowlist(operators, defaultOperatorSet);

        // Get allowed operators
        address[] memory allowedOperators = allowlist.getAllowedOperators(defaultOperatorSet);

        assertEq(allowedOperators.length, operators.length, "Should return all added operators");

        // Check all operators are in the returned array
        for (uint32 i = 0; i < operators.length; i++) {
            bool found = false;
            for (uint32 j = 0; j < allowedOperators.length; j++) {
                if (allowedOperators[j] == operators[i]) {
                    found = true;
                    break;
                }
            }
            assertTrue(found, "All added operators should be in the returned array");
        }
    }

    function test_independentOperatorSets() public {
        // Add different operators to different operator sets
        _addOperatorToAllowlist(operator1, defaultOperatorSet);
        _addOperatorToAllowlist(operator2, defaultOperatorSet);
        _addOperatorToAllowlist(operator3, alternativeOperatorSet);

        // Check default operator set
        address[] memory defaultAllowed = allowlist.getAllowedOperators(defaultOperatorSet);
        assertEq(defaultAllowed.length, 2, "Default operator set should have 2 operators");

        // Check alternative operator set
        address[] memory alternativeAllowed = allowlist.getAllowedOperators(alternativeOperatorSet);
        assertEq(alternativeAllowed.length, 1, "Alternative operator set should have 1 operator");
        assertEq(
            alternativeAllowed[0], operator3, "Alternative operator set should contain operator3"
        );
    }

    function test_afterRemoval() public {
        // Add multiple operators
        _addOperatorToAllowlist(operator1, defaultOperatorSet);
        _addOperatorToAllowlist(operator2, defaultOperatorSet);
        _addOperatorToAllowlist(operator3, defaultOperatorSet);

        // Remove one operator
        cheats.prank(allowlistOwner);
        allowlist.removeOperatorFromAllowlist(defaultOperatorSet, operator2);

        // Check the result
        address[] memory allowedOperators = allowlist.getAllowedOperators(defaultOperatorSet);
        assertEq(allowedOperators.length, 2, "Should have 2 operators after removal");

        // Verify operator2 is not in the array
        for (uint256 i = 0; i < allowedOperators.length; i++) {
            assertTrue(
                allowedOperators[i] != operator2, "Removed operator should not be in the array"
            );
        }
    }
}

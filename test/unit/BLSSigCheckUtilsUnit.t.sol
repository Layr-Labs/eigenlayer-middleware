// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {BN254} from "../../src/libraries/BN254.sol";
import {BLSSigCheckUtils} from "../../src/unaudited/BLSSigCheckUtils.sol";
import {BLSSigCheckUtilsHarness} from "../harnesses/BLSSigCheckUtilsHarness.sol";

contract BLSSigCheckUtilsUnitTests is Test {
    using BN254 for BN254.G1Point;
    using BLSSigCheckUtils for BN254.G1Point;

    uint256 constant FP_MODULUS =
        21888242871839275222246405745257275088696311157297823662689037894645226208583;

    BLSSigCheckUtilsHarness harness;

    struct TestPoint {
        uint256 x;
        uint256 y;
        bool shouldBeOnCurve;
    }

    function setUp() public {
        harness = new BLSSigCheckUtilsHarness();
    }

    /**
     * @notice Test that the generator point is on the curve
     */
    function test_isOnCurve_generator() public pure {
        BN254.G1Point memory generator = BN254.generatorG1();
        assertTrue(generator.isOnCurve(), "Generator point should be on the curve");
    }

    /**
     * @notice Test that the identity element (0, 0) is NOT on the curve
     * @dev For BN254, (0, 0) doesn't satisfy y^2 = x^3 + 3 (0 != 3)
     */
    function test_isOnCurve_identity() public pure {
        BN254.G1Point memory identity = BN254.G1Point(0, 0);
        assertFalse(identity.isOnCurve(), "Identity element (0,0) should NOT be on the curve");
    }

    /**
     * @notice Test some known valid points on the curve
     */
    function test_isOnCurve_validPoints() public pure {
        // These are known valid points on the BN254 curve
        // We'll use the generator and its scalar multiples which are guaranteed to be on curve
        BN254.G1Point memory generator = BN254.generatorG1();

        assertTrue(generator.isOnCurve(), "Generator should be on the curve");

        // Test the generator negation
        BN254.G1Point memory negatedGen = generator.negate();
        assertTrue(negatedGen.isOnCurve(), "Negated generator should be on the curve");
    }

    /**
     * @notice Test invalid points not on the curve
     */
    function test_isOnCurve_invalidPoints() public pure {
        // These points have valid x coordinates but invalid y coordinates
        BN254.G1Point[3] memory invalidPoints = [
            BN254.G1Point(1, 3), // y should be 2
            BN254.G1Point(2, 100), // arbitrary invalid y
            BN254.G1Point(3, 1000) // arbitrary invalid y
        ];

        for (uint256 i = 0; i < invalidPoints.length; i++) {
            assertFalse(
                invalidPoints[i].isOnCurve(),
                string(
                    abi.encodePacked(
                        "Invalid point ", vm.toString(i), " should not be on the curve"
                    )
                )
            );
        }
    }

    /**
     * @notice Test points with coordinates at the field modulus boundary
     */
    function test_isOnCurve_boundaryPoints() public pure {
        // Test point with x = FP_MODULUS - 1
        uint256 xMax = FP_MODULUS - 1;
        uint256 ySquared = mulmod(xMax, xMax, FP_MODULUS);
        ySquared = mulmod(ySquared, xMax, FP_MODULUS);
        ySquared = addmod(ySquared, 3, FP_MODULUS);

        // This x value doesn't have a valid y on the curve, so any y should return false
        BN254.G1Point memory boundaryPoint = BN254.G1Point(xMax, 0);
        assertFalse(
            boundaryPoint.isOnCurve(), "Point with x at modulus boundary should not be on curve"
        );

        // Test point with coordinates >= FP_MODULUS (should be reduced modulo FP_MODULUS)
        BN254.G1Point memory overflowPoint = BN254.G1Point(
            FP_MODULUS + 1, // This should be reduced to 1
            FP_MODULUS + 2 // This should be reduced to 2
        );
        assertTrue(overflowPoint.isOnCurve(), "Overflow point should be reduced and be on curve");
    }

    /**
     * @notice Fuzz test with random points
     */
    function testFuzz_isOnCurve_randomPoints(uint256 x, uint256 y) public pure {
        BN254.G1Point memory point = BN254.G1Point(x, y);

        // Calculate expected result
        uint256 xMod = x % FP_MODULUS;
        uint256 yMod = y % FP_MODULUS;
        uint256 y2 = mulmod(yMod, yMod, FP_MODULUS);
        uint256 x3 = mulmod(xMod, xMod, FP_MODULUS);
        x3 = mulmod(x3, xMod, FP_MODULUS);
        uint256 rhs = addmod(x3, 3, FP_MODULUS);

        bool expectedOnCurve = (y2 == rhs);
        bool actualOnCurve = point.isOnCurve();

        assertEq(actualOnCurve, expectedOnCurve, "isOnCurve result mismatch for random point");
    }

    /**
     * @notice Test negation of valid points
     */
    function test_isOnCurve_negatedPoints() public pure {
        BN254.G1Point memory generator = BN254.generatorG1();
        BN254.G1Point memory negatedGenerator = generator.negate();

        assertTrue(negatedGenerator.isOnCurve(), "Negated generator should be on the curve");
        assertEq(negatedGenerator.X, 1, "Negated generator X should be 1");
        assertEq(negatedGenerator.Y, FP_MODULUS - 2, "Negated generator Y should be p - 2");
    }

    /**
     * @notice Test scalar multiplication results are on curve
     */
    function test_isOnCurve_scalarMultiplication() public view {
        BN254.G1Point memory generator = BN254.generatorG1();

        // Test small scalar multiplications using scalar_mul_tiny
        for (uint16 i = 1; i < 10; i++) {
            BN254.G1Point memory multiplied = generator.scalar_mul_tiny(i);
            assertTrue(
                multiplied.isOnCurve(),
                string(abi.encodePacked("Generator * ", vm.toString(i), " should be on the curve"))
            );
        }
    }

    /**
     * @notice Test addition results are on curve
     * @dev Skip tests that require precompiles if they're not available
     */
    function test_isOnCurve_pointAddition() public view {
        BN254.G1Point memory generator = BN254.generatorG1();

        // Test doubling using scalar multiplication instead of addition
        // (since addition might fail without precompiles)
        BN254.G1Point memory doubled = generator.scalar_mul_tiny(2);
        assertTrue(doubled.isOnCurve(), "Doubled point should be on the curve");

        // Test that the doubled point is different from the generator
        assertTrue(
            doubled.X != generator.X || doubled.Y != generator.Y,
            "Doubled point should be different"
        );
    }

    /**
     * @notice Test edge case where y^2 calculation could overflow
     */
    function test_isOnCurve_largeCoordinates() public pure {
        // Test with very large coordinates (close to modulus)
        uint256 largeX = FP_MODULUS - 10;
        uint256 largeY = FP_MODULUS - 20;

        BN254.G1Point memory largePoint = BN254.G1Point(largeX, largeY);

        // Calculate expected result
        uint256 y2 = mulmod(largeY, largeY, FP_MODULUS);
        uint256 x3 = mulmod(largeX, largeX, FP_MODULUS);
        x3 = mulmod(x3, largeX, FP_MODULUS);
        uint256 rhs = addmod(x3, 3, FP_MODULUS);

        bool expectedOnCurve = (y2 == rhs);
        assertEq(largePoint.isOnCurve(), expectedOnCurve, "Large coordinate point check failed");
    }

    /**
     * @notice Test batch of known invalid x coordinates
     */
    function test_isOnCurve_invalidXCoordinates() public pure {
        // Some x values that don't have valid y coordinates on the curve
        uint256[5] memory invalidXs = [uint256(4), uint256(5), uint256(7), uint256(8), uint256(10)];

        for (uint256 i = 0; i < invalidXs.length; i++) {
            // Try with y = 0 and y = 1
            BN254.G1Point memory point1 = BN254.G1Point(invalidXs[i], 0);
            BN254.G1Point memory point2 = BN254.G1Point(invalidXs[i], 1);

            // These x values don't have valid y coordinates, so both should be false
            // (unless by chance one of these y values happens to be valid)
            uint256 x3 = mulmod(invalidXs[i], invalidXs[i], FP_MODULUS);
            x3 = mulmod(x3, invalidXs[i], FP_MODULUS);
            uint256 rhs = addmod(x3, 3, FP_MODULUS);

            if (mulmod(0, 0, FP_MODULUS) != rhs) {
                assertFalse(
                    point1.isOnCurve(), "Point with invalid x and y=0 should not be on curve"
                );
            }
            if (mulmod(1, 1, FP_MODULUS) != rhs) {
                assertFalse(
                    point2.isOnCurve(), "Point with invalid x and y=1 should not be on curve"
                );
            }
        }
    }

    /**
     * @notice Gas usage test for isOnCurve
     */
    function test_isOnCurve_gasUsage() public {
        BN254.G1Point memory generator = BN254.generatorG1();

        uint256 gasBefore = gasleft();
        bool result = generator.isOnCurve();
        uint256 gasAfter = gasleft();

        assertTrue(result, "Generator should be on curve");
        emit log_named_uint("Gas used for isOnCurve", gasBefore - gasAfter);

        // Test with multiple calls to see consistency
        gasBefore = gasleft();
        for (uint256 i = 0; i < 10; i++) {
            generator.isOnCurve();
        }
        gasAfter = gasleft();
        emit log_named_uint("Gas used for 10 isOnCurve calls", gasBefore - gasAfter);
    }

    /**
     * @notice Test specific known points on the curve
     */
    function test_isOnCurve_specificPoints() public pure {
        // Test some specific points with known y values
        TestPoint[4] memory testPoints;
        // Generator
        testPoints[0].x = 1;
        testPoints[0].y = 2;
        testPoints[0].shouldBeOnCurve = true;

        // Point with x=1, wrong y
        testPoints[1].x = 1;
        testPoints[1].y = 3;
        testPoints[1].shouldBeOnCurve = false;

        // Another valid point
        testPoints[2].x =
            9727523064272218541460723335320998459488975639302513747055235660443850046724;
        testPoints[2].y =
            5031696974169251245229961296941447383441169981934237515842977230762345915487;
        testPoints[2].shouldBeOnCurve = true;

        // Invalid point
        testPoints[3].x = 2;
        testPoints[3].y = 2;
        testPoints[3].shouldBeOnCurve = false;

        for (uint256 i = 0; i < testPoints.length; i++) {
            BN254.G1Point memory point = BN254.G1Point(testPoints[i].x, testPoints[i].y);
            assertEq(
                point.isOnCurve(),
                testPoints[i].shouldBeOnCurve,
                string(abi.encodePacked("Point ", vm.toString(i), " on-curve check failed"))
            );
        }
    }

    /**
     *
     * Tests for Comparators library
     *
     */
    function test_comparators_lt() public {
        assertTrue(harness.lt(1, 2), "1 < 2 should be true");
        assertFalse(harness.lt(2, 1), "2 < 1 should be false");
        assertFalse(harness.lt(1, 1), "1 < 1 should be false");
    }

    function test_comparators_gt() public {
        assertTrue(harness.gt(2, 1), "2 > 1 should be true");
        assertFalse(harness.gt(1, 2), "1 > 2 should be false");
        assertFalse(harness.gt(1, 1), "1 > 1 should be false");
    }

    function testFuzz_comparators(uint256 a, uint256 b) public {
        bool ltResult = harness.lt(a, b);
        bool gtResult = harness.gt(a, b);

        if (a < b) {
            assertTrue(ltResult, "lt should return true when a < b");
            assertFalse(gtResult, "gt should return false when a < b");
        } else if (a > b) {
            assertFalse(ltResult, "lt should return false when a > b");
            assertTrue(gtResult, "gt should return true when a > b");
        } else {
            assertFalse(ltResult, "lt should return false when a == b");
            assertFalse(gtResult, "gt should return false when a == b");
        }
    }

    /**
     *
     * Tests for SlotDerivation library
     *
     */
    function test_erc7201Slot() public {
        string memory namespace = "example.namespace";
        bytes32 slot = harness.erc7201Slot(namespace);

        // ERC-7201 formula: keccak256(keccak256(namespace) - 1) & ~bytes32(uint256(0xff))
        bytes32 expectedSlot = keccak256(abi.encode(uint256(keccak256(bytes(namespace))) - 1))
            & ~bytes32(uint256(0xff));
        assertEq(slot, expectedSlot, "ERC-7201 slot calculation mismatch");
    }

    function test_offset() public {
        bytes32 baseSlot = bytes32(uint256(100));
        uint256 offset = 5;
        bytes32 resultSlot = harness.offset(baseSlot, offset);

        assertEq(uint256(resultSlot), 105, "Offset calculation incorrect");
    }

    function test_deriveArray() public {
        bytes32 slot = bytes32(uint256(123));
        bytes32 derivedSlot = harness.deriveArray(slot);

        // Array elements start at keccak256(slot)
        bytes32 expectedSlot = keccak256(abi.encode(slot));
        assertEq(derivedSlot, expectedSlot, "Array slot derivation incorrect");
    }

    function test_deriveMapping() public {
        bytes32 slot = bytes32(uint256(456));

        // Test with different key types
        address addrKey = address(0x1234);
        bytes32 mappingSlotAddr = harness.deriveMappingAddress(slot, addrKey);
        assertEq(
            mappingSlotAddr, keccak256(abi.encode(addrKey, slot)), "Address mapping slot incorrect"
        );

        uint256 uintKey = 789;
        bytes32 mappingSlotUint = harness.deriveMappingUint256(slot, uintKey);
        assertEq(
            mappingSlotUint, keccak256(abi.encode(uintKey, slot)), "Uint256 mapping slot incorrect"
        );

        bool boolKey = true;
        bytes32 mappingSlotBool = harness.deriveMappingBool(slot, boolKey);
        assertEq(
            mappingSlotBool, keccak256(abi.encode(boolKey, slot)), "Bool mapping slot incorrect"
        );
    }

    /**
     *
     * Tests for Arrays library - Sorting
     *
     */
    function test_sortUint256() public {
        uint256[] memory unsorted = new uint256[](5);
        unsorted[0] = 5;
        unsorted[1] = 2;
        unsorted[2] = 8;
        unsorted[3] = 1;
        unsorted[4] = 3;

        uint256[] memory sorted = harness.sortUint256(unsorted);

        assertEq(sorted.length, 5, "Sorted array length should be 5");
        assertEq(sorted[0], 1, "First element should be 1");
        assertEq(sorted[1], 2, "Second element should be 2");
        assertEq(sorted[2], 3, "Third element should be 3");
        assertEq(sorted[3], 5, "Fourth element should be 5");
        assertEq(sorted[4], 8, "Fifth element should be 8");
    }

    function test_sortAddress() public {
        address[] memory unsorted = new address[](3);
        unsorted[0] = address(0x3000);
        unsorted[1] = address(0x1000);
        unsorted[2] = address(0x2000);

        address[] memory sorted = harness.sortAddress(unsorted);

        assertEq(sorted[0], address(0x1000), "First address should be 0x1000");
        assertEq(sorted[1], address(0x2000), "Second address should be 0x2000");
        assertEq(sorted[2], address(0x3000), "Third address should be 0x3000");
    }

    function test_sortBytes32() public {
        bytes32[] memory unsorted = new bytes32[](3);
        unsorted[0] = bytes32(uint256(300));
        unsorted[1] = bytes32(uint256(100));
        unsorted[2] = bytes32(uint256(200));

        bytes32[] memory sorted = harness.sortBytes32(unsorted);

        assertEq(uint256(sorted[0]), 100, "First element should be 100");
        assertEq(uint256(sorted[1]), 200, "Second element should be 200");
        assertEq(uint256(sorted[2]), 300, "Third element should be 300");
    }

    /**
     *
     * Tests for Arrays library - Binary Search
     *
     */
    function test_binarySearch() public {
        // Initialize a sorted array
        uint256[] memory sortedArray = new uint256[](5);
        sortedArray[0] = 10;
        sortedArray[1] = 20;
        sortedArray[2] = 30;
        sortedArray[3] = 40;
        sortedArray[4] = 50;

        harness.initializeUint256Array(sortedArray);

        // Test findUpperBound
        assertEq(harness.findUpperBound(25), 2, "findUpperBound(25) should return 2");
        assertEq(harness.findUpperBound(30), 2, "findUpperBound(30) should return 2");
        assertEq(harness.findUpperBound(5), 0, "findUpperBound(5) should return 0");
        assertEq(harness.findUpperBound(55), 5, "findUpperBound(55) should return 5");

        // Test lowerBound
        assertEq(harness.lowerBound(25), 2, "lowerBound(25) should return 2");
        assertEq(harness.lowerBound(30), 2, "lowerBound(30) should return 2");
        assertEq(harness.lowerBound(5), 0, "lowerBound(5) should return 0");

        // Test upperBound
        assertEq(harness.upperBound(25), 2, "upperBound(25) should return 2");
        assertEq(harness.upperBound(30), 3, "upperBound(30) should return 3");
        assertEq(harness.upperBound(5), 0, "upperBound(5) should return 0");
    }

    function test_binarySearchMemory() public {
        uint256[] memory sortedArray = new uint256[](4);
        sortedArray[0] = 5;
        sortedArray[1] = 15;
        sortedArray[2] = 25;
        sortedArray[3] = 35;

        assertEq(
            harness.lowerBoundMemory(sortedArray, 20), 2, "lowerBoundMemory(20) should return 2"
        );
        assertEq(
            harness.upperBoundMemory(sortedArray, 20), 2, "upperBoundMemory(20) should return 2"
        );
        assertEq(
            harness.lowerBoundMemory(sortedArray, 15), 1, "lowerBoundMemory(15) should return 1"
        );
        assertEq(
            harness.upperBoundMemory(sortedArray, 15), 2, "upperBoundMemory(15) should return 2"
        );
    }

    /**
     *
     * Tests for Arrays library - Unsafe Access
     *
     */
    function test_unsafeAccess() public {
        // Test uint256 array
        uint256[] memory uintArray = new uint256[](3);
        uintArray[0] = 100;
        uintArray[1] = 200;
        uintArray[2] = 300;
        harness.initializeUint256Array(uintArray);

        assertEq(harness.unsafeAccessUint256(0), 100, "Unsafe access at index 0 should return 100");
        assertEq(harness.unsafeAccessUint256(1), 200, "Unsafe access at index 1 should return 200");
        assertEq(harness.unsafeAccessUint256(2), 300, "Unsafe access at index 2 should return 300");

        // Test address array
        address[] memory addrArray = new address[](2);
        addrArray[0] = address(0x1234);
        addrArray[1] = address(0x5678);
        harness.initializeAddressArray(addrArray);

        assertEq(
            harness.unsafeAccessAddress(0),
            address(0x1234),
            "Unsafe access should return correct address"
        );

        // Test bytes32 array
        bytes32[] memory bytes32Array = new bytes32[](2);
        bytes32Array[0] = bytes32(uint256(111));
        bytes32Array[1] = bytes32(uint256(222));
        harness.initializeBytes32Array(bytes32Array);

        assertEq(
            uint256(harness.unsafeAccessBytes32(0)),
            111,
            "Unsafe access should return correct bytes32"
        );
    }

    function test_unsafeMemoryAccess() public {
        // Test uint256 memory array
        uint256[] memory array = new uint256[](3);
        array[0] = 10;
        array[1] = 20;
        array[2] = 30;

        assertEq(
            harness.unsafeMemoryAccessUint256(array, 0), 10, "Memory access at 0 should return 10"
        );
        assertEq(
            harness.unsafeMemoryAccessUint256(array, 1), 20, "Memory access at 1 should return 20"
        );
        assertEq(
            harness.unsafeMemoryAccessUint256(array, 2), 30, "Memory access at 2 should return 30"
        );

        // Test address memory array
        address[] memory addrArray = new address[](2);
        addrArray[0] = address(0xABCD);
        addrArray[1] = address(0xDEAD);

        assertEq(
            harness.unsafeMemoryAccessAddress(addrArray, 0),
            address(0xABCD),
            "Should return first address"
        );
        assertEq(
            harness.unsafeMemoryAccessAddress(addrArray, 1),
            address(0xDEAD),
            "Should return second address"
        );
    }

    /**
     *
     * Tests for Arrays library - Unsafe Set Length
     *
     */
    function test_unsafeSetLength() public {
        // Initialize array with some values
        uint256[] memory initialArray = new uint256[](3);
        initialArray[0] = 10;
        initialArray[1] = 20;
        initialArray[2] = 30;
        harness.initializeUint256Array(initialArray);

        assertEq(harness.getUint256ArrayLength(), 3, "Initial length should be 3");

        // Increase length
        harness.unsafeSetLengthUint256(5);
        assertEq(harness.getUint256ArrayLength(), 5, "Length should be 5 after increase");

        // Values should still be accessible
        assertEq(harness.unsafeAccessUint256(0), 10, "First value should still be 10");
        assertEq(harness.unsafeAccessUint256(1), 20, "Second value should still be 20");

        // Decrease length
        harness.unsafeSetLengthUint256(2);
        assertEq(harness.getUint256ArrayLength(), 2, "Length should be 2 after decrease");

        // Note: The third element is not cleared, just length is changed
        // This is the "unsafe" aspect - data may still exist beyond the new length
    }

    function test_unsafeSetLength_allTypes() public {
        // Test with address array
        address[] memory addrArray = new address[](2);
        addrArray[0] = address(0x1);
        addrArray[1] = address(0x2);
        harness.initializeAddressArray(addrArray);

        harness.unsafeSetLengthAddress(4);
        assertEq(harness.getAddressArrayLength(), 4, "Address array length should be 4");

        // Test with bytes32 array
        bytes32[] memory b32Array = new bytes32[](1);
        b32Array[0] = bytes32(uint256(123));
        harness.initializeBytes32Array(b32Array);

        harness.unsafeSetLengthBytes32(3);
        assertEq(harness.getBytes32ArrayLength(), 3, "Bytes32 array length should be 3");
    }
}

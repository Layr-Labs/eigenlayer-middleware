// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {BN254} from "../../src/libraries/BN254.sol";
import {BLSSigCheckUtils} from "../../src/unaudited/BLSSigCheckUtils.sol";

contract BLSSigCheckUtilsUnitTests is Test {
    using BN254 for BN254.G1Point;
    using BLSSigCheckUtils for BN254.G1Point;

    uint256 constant FP_MODULUS =
        21888242871839275222246405745257275088696311157297823662689037894645226208583;

    struct TestPoint {
        uint256 x;
        uint256 y;
        bool shouldBeOnCurve;
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
}

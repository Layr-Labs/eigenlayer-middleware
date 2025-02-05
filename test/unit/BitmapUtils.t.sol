// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../harnesses/BitmapUtilsWrapper.sol";
// import "../../contracts/libraries/BitmapUtils.sol";

import "forge-std/Test.sol";

contract BitmapUtilsUnitTests is Test {
    Vm cheats = Vm(VM_ADDRESS);

    BitmapUtilsWrapper public bitmapUtilsWrapper;

    function setUp() public {
        bitmapUtilsWrapper = new BitmapUtilsWrapper();
    }
}

contract BitmapUtilsUnitTests_bitwiseOperations is BitmapUtilsUnitTests {
    /// @notice check for consistency of `countNumOnes` function
    function testFuzz_countNumOnes(
        uint256 input
    ) public {
        uint16 libraryOutput = bitmapUtilsWrapper.countNumOnes(input);
        // run dumb routine
        uint16 numOnes = 0;
        for (uint256 i = 0; i < 256; ++i) {
            if ((input >> i) & 1 == 1) {
                ++numOnes;
            }
        }
        assertEq(libraryOutput, numOnes, "inconsistency in countNumOnes function");
    }

    /// @notice some simple sanity checks on the `isSet` function
    function test_isSet() public {
        assertTrue(bitmapUtilsWrapper.isSet(2 ** 6, 6), "isSet function is broken 0");
        assertTrue(bitmapUtilsWrapper.isSet(1, 0), "isSet function is broken 1");
        assertTrue(bitmapUtilsWrapper.isSet(255, 7), "isSet function is broken 2");
        assertTrue(bitmapUtilsWrapper.isSet(1024, 10), "isSet function is broken 3");
        for (uint256 i = 0; i < 256; ++i) {
            assertTrue(
                bitmapUtilsWrapper.isSet(type(uint256).max, uint8(i)), "isSet function is broken 4"
            );
            assertFalse(bitmapUtilsWrapper.isSet(0, uint8(i)), "isSet function is broken 5");
        }
    }

    function test_setBit(uint256 bitmap, uint8 bitToSet) public {
        // Ensure that numberToAdd isn't already in the bitmap
        cheats.assume(bitmap | (1 << bitToSet) != bitmap);
        uint256 updatedBitmap = bitmapUtilsWrapper.setBit(bitmap, bitToSet);
        assertTrue(bitmapUtilsWrapper.isSet(updatedBitmap, bitToSet), "setBit function is broken");
    }

    function testFuzz_isEmpty(
        uint256 input
    ) public {
        if (input == 0) {
            // assertTrue(bitmapUtilsWrapper.isEmpty(input), "isEmpty function is broken");
            assertTrue(bitmapUtilsWrapper.isEmpty(input), "isEmpty function is broken");
        } else {
            assertFalse(bitmapUtilsWrapper.isEmpty(input), "isEmpty function is broken");
        }
    }

    function testFuzz_noBitsInCommon(uint256 a, uint256 b) public {
        // 1000 and 0111 have no bits in common
        assertTrue(bitmapUtilsWrapper.noBitsInCommon(8, 7), "noBitsInCommon function is broken");
        // 1101 and 0010 have no bits in common
        assertTrue(bitmapUtilsWrapper.noBitsInCommon(13, 2), "noBitsInCommon function is broken");
        // 11010 and 00101 have no bits in common
        assertTrue(bitmapUtilsWrapper.noBitsInCommon(26, 5), "noBitsInCommon function is broken");
        // 1000 and 1000 have bits in common
        assertFalse(bitmapUtilsWrapper.noBitsInCommon(8, 8), "noBitsInCommon function is broken");
        // 1000001 and 0000001 have bits in common
        assertFalse(bitmapUtilsWrapper.noBitsInCommon(65, 1), "noBitsInCommon function is broken");
        // 11010 and 100 have bits in common
        assertFalse(bitmapUtilsWrapper.noBitsInCommon(26, 9), "noBitsInCommon function is broken");
        // performing bitwise subtraction should always return true for noBitsInCommon
        a = a & ~b;
        assertTrue(bitmapUtilsWrapper.noBitsInCommon(a, b), "noBitsInCommon function is broken");
    }

    function testFuzz_isSubsetOf(uint256 a, uint256 b) public {
        // 1000 is a subset of 1000
        assertTrue(bitmapUtilsWrapper.isSubsetOf(8, 8), "isSubsetOf function is broken");
        // 1000 is a subset of 1001
        assertTrue(bitmapUtilsWrapper.isSubsetOf(8, 15), "isSubsetOf function is broken");
        // 10000111 is a subset of 11100111
        assertTrue(bitmapUtilsWrapper.isSubsetOf(135, 231), "isSubsetOf function is broken");

        // a cannot be a subset of b if its > b
        if (a > b) {
            assertFalse(bitmapUtilsWrapper.isSubsetOf(a, b), "isSubsetOf function is broken");
        } else if (a == b) {
            assertTrue(bitmapUtilsWrapper.isSubsetOf(a, b), "isSubsetOf function is broken");
        }
    }

    function testFuzz_plus(uint256 a, uint256 b) public {
        uint256 bitwisePlus = bitmapUtilsWrapper.plus(a, b);
        for (uint256 i = 0; i < 256; ++i) {
            if ((a >> i) & 1 == 1 || (b >> i) & 1 == 1) {
                // If either of the bits of a or b are set, then bitwisePlus should have that bit set
                assertTrue((bitwisePlus >> i) & 1 == 1, "plus function is broken");
            }
        }
    }

    function testFuzz_minus(uint256 a, uint256 b) public {
        uint256 bitwiseMinus = bitmapUtilsWrapper.minus(a, b);
        for (uint256 i = 0; i < 256; ++i) {
            if ((a >> i) & 1 == 1 && (b >> i) & 1 == 0) {
                // If the ith bit of a is set and the ith bit of b is not set, then bitwiseMinus should have that bit set
                assertTrue((bitwiseMinus >> i) & 1 == 1, "minus function is broken");
            } else {
                // Otherwise, the ith bit of bitwiseMinus should not be set
                assertTrue((bitwiseMinus >> i) & 1 == 0, "minus function is broken");
            }
        }
    }
}

contract BitmapUtilsUnitTests_bytesArrayToBitmap is BitmapUtilsUnitTests {
    // ensure that the bitmap encoding of an empty bytes array is an empty bitmap (function doesn't revert and approriately returns uint256(0))
    function test_EmptyArrayEncoding() public {
        bytes memory emptyBytesArray;
        uint256 returnedBitMap = bitmapUtilsWrapper.orderedBytesArrayToBitmap(emptyBytesArray);
        assertEq(
            returnedBitMap,
            0,
            "BitmapUtilsUnitTests.testEmptyArrayEncoding: empty array not encoded to empty bitmap"
        );
    }

    // ensure that the bitmap encoding of a single uint8 (i.e. a single byte) matches the expected output
    function testFuzz_SingleByteEncoding(
        uint8 fuzzedNumber
    ) public {
        bytes1 singleByte = bytes1(fuzzedNumber);
        bytes memory bytesArray = abi.encodePacked(singleByte);
        uint256 returnedBitMap = bitmapUtilsWrapper.orderedBytesArrayToBitmap(bytesArray);
        uint256 bitMask = uint256(1 << fuzzedNumber);
        assertEq(
            returnedBitMap, bitMask, "BitmapUtilsUnitTests.testSingleByteEncoding: non-equivalence"
        );
    }

    // ensure that the bitmap encoding of a two uint8's (i.e. a two byte array) matches the expected output
    function testFuzz_TwoByteEncoding(uint8 firstFuzzedNumber, uint8 secondFuzzedNumber) public {
        cheats.assume(secondFuzzedNumber > firstFuzzedNumber);
        bytes1 firstSingleByte = bytes1(firstFuzzedNumber);
        bytes1 secondSingleByte = bytes1(secondFuzzedNumber);
        bytes memory bytesArray = abi.encodePacked(firstSingleByte, secondSingleByte);
        if (firstFuzzedNumber == secondFuzzedNumber) {
            cheats.expectRevert(
                bytes("BitmapUtils.orderedBytesArrayToBitmap: repeat entry in bytesArray")
            );
            bitmapUtilsWrapper.orderedBytesArrayToBitmap(bytesArray);
        } else {
            uint256 returnedBitMap = bitmapUtilsWrapper.orderedBytesArrayToBitmap(bytesArray);
            uint256 firstBitMask = uint256(1 << firstFuzzedNumber);
            uint256 secondBitMask = uint256(1 << secondFuzzedNumber);
            uint256 combinedBitMask = firstBitMask | secondBitMask;
            assertEq(
                returnedBitMap,
                combinedBitMask,
                "BitmapUtilsUnitTests.testTwoByteEncoding: non-equivalence"
            );
        }
    }

    // ensure that converting bytes array => bitmap => bytes array returns the original bytes array (i.e. is lossless and artifactless)
    // note that this only works on ordered arrays, because unordered arrays will be returned ordered
    function testFuzz_BytesArrayToBitmapToBytesArray(uint8 a, uint8 b, uint8 c) public view {
        a = uint8(bound(a, 0, 31));
        b = uint8(bound(b, 0, 31));
        c = uint8(bound(c, 0, 31));

        // Create ordered bytes array
        bytes memory originalBytesArray = new bytes(a);
        uint8 currentValue = b;

        for (uint8 i = 0; i < a; i++) {
            originalBytesArray[i] = bytes1(currentValue);
            currentValue++;
        }

        uint256 bitmap = bitmapUtilsWrapper.orderedBytesArrayToBitmap(originalBytesArray);
        bytes memory returnedBytesArray = bitmapUtilsWrapper.bitmapToBytesArray(bitmap);
        assertEq(
            keccak256(abi.encodePacked(originalBytesArray)),
            keccak256(abi.encodePacked(returnedBytesArray)),
            "BitmapUtilsUnitTests.testBytesArrayToBitmapToBytesArray: output does not match input"
        );
    }

    // ensure that converting bytes array => bitmap => bytes array returns the original bytes array (i.e. is lossless and artifactless)
    // note that this only works on ordered arrays
    function testFuzz_BytesArrayToBitmapToBytesArray_OrderedVersion(
        uint8 a,
        uint8 b,
        uint8 c
    ) public view {
        a = uint8(bound(a, 0, 31));
        b = uint8(bound(b, 0, 31));
        c = uint8(bound(c, 0, 31));

        // Create ordered bytes array
        bytes memory originalBytesArray = new bytes(a);
        uint8 currentValue = b;

        for (uint8 i = 0; i < a; i++) {
            originalBytesArray[i] = bytes1(currentValue);
            currentValue++;
        }
        uint256 bitmap = bitmapUtilsWrapper.orderedBytesArrayToBitmap(originalBytesArray);
        bytes memory returnedBytesArray = bitmapUtilsWrapper.bitmapToBytesArray(bitmap);
        assertEq(
            keccak256(abi.encodePacked(originalBytesArray)),
            keccak256(abi.encodePacked(returnedBytesArray)),
            "BitmapUtilsUnitTests.testBytesArrayToBitmapToBytesArray: output does not match input"
        );
    }

    /// @notice Test that for non-strictly ascending bytes array ordering always reverts
    /// when calling orderedBytesArrayToBitmap
    function testFuzz_OrderedBytesArrayToBitmap_Revert_WhenNotOrdered(
        bytes memory originalBytesArray
    ) public {
        cheats.assume(!bitmapUtilsWrapper.isArrayStrictlyAscendingOrdered(originalBytesArray));
        cheats.expectRevert(BitmapUtils.BytesArrayNotOrdered.selector);
        bitmapUtilsWrapper.orderedBytesArrayToBitmap(originalBytesArray);
    }

    // ensure that converting bytes array => bitmap => bytes array returns the original bytes array (i.e. is lossless and artifactless)
    // note that this only works on ordered arrays
    function testFuzz_BytesArrayToBitmapToBytesArray_OrderedVersion_Yul(
        uint8 a,
        uint8 b,
        uint8 c
    ) public view {
        a = uint8(bound(a, 0, 31));
        b = uint8(bound(b, 0, 31));
        c = uint8(bound(c, 0, 31));

        // Create ordered bytes array
        bytes memory originalBytesArray = new bytes(a);
        uint8 currentValue = b;

        for (uint8 i = 0; i < a; i++) {
            originalBytesArray[i] = bytes1(currentValue);
            currentValue++;
        }
        uint256 bitmap = bitmapUtilsWrapper.orderedBytesArrayToBitmap(originalBytesArray);
        bytes memory returnedBytesArray = bitmapUtilsWrapper.bitmapToBytesArray(bitmap);
        assertEq(
            keccak256(abi.encodePacked(originalBytesArray)),
            keccak256(abi.encodePacked(returnedBytesArray)),
            "BitmapUtilsUnitTests.testBytesArrayToBitmapToBytesArray: output does not match input"
        );
    }

    // testing one function for a specific input. used for comparing gas costs
    function test_BytesArrayToBitmap_OrderedVersion_SpecificInput() public {
        bytes memory originalBytesArray = abi.encodePacked(
            bytes1(uint8(5)),
            bytes1(uint8(6)),
            bytes1(uint8(7)),
            bytes1(uint8(8)),
            bytes1(uint8(9)),
            bytes1(uint8(10)),
            bytes1(uint8(11)),
            bytes1(uint8(12))
        );
        uint256 gasLeftBefore = gasleft();
        uint256 bitmap = bitmapUtilsWrapper.orderedBytesArrayToBitmap(originalBytesArray);
        uint256 gasLeftAfter = gasleft();
        uint256 gasSpent = gasLeftBefore - gasLeftAfter;
        assertEq(bitmap, 8160);
        emit log_named_uint("gasSpent", gasSpent);
    }

    // testing one function for a specific input. used for comparing gas costs
    function test_BytesArrayToBitmap_SpecificInput() public {
        bytes memory originalBytesArray = abi.encodePacked(
            bytes1(uint8(5)),
            bytes1(uint8(6)),
            bytes1(uint8(7)),
            bytes1(uint8(8)),
            bytes1(uint8(9)),
            bytes1(uint8(10)),
            bytes1(uint8(11)),
            bytes1(uint8(12))
        );
        uint256 gasLeftBefore = gasleft();
        uint256 bitmap = bitmapUtilsWrapper.orderedBytesArrayToBitmap(originalBytesArray);
        uint256 gasLeftAfter = gasleft();
        uint256 gasSpent = gasLeftBefore - gasLeftAfter;
        assertEq(bitmap, 8160);
        emit log_named_uint("gasSpent", gasSpent);
    }

    function testFuzz_bitmapToBytesArrayToBitmap(
        uint256 originalBitmap
    ) public {
        uint256 gasLeftBefore = gasleft();
        bytes memory bytesArray = bitmapUtilsWrapper.bitmapToBytesArray(originalBitmap);
        uint256 gasLeftAfter = gasleft();
        uint256 gasSpent = gasLeftBefore - gasLeftAfter;
        emit log_named_uint("gas spent by bitmapToBytesArray operation", gasSpent);
        uint256 bitmapOutput = bitmapUtilsWrapper.orderedBytesArrayToBitmap(bytesArray);
        assertEq(originalBitmap, bitmapOutput, "bitmap output does not match original bitmap!");
    }

    function test_bitmapToBytesArrayToBitmap_maxBitmap() public {
        uint256 originalBitmap = type(uint256).max;
        testFuzz_bitmapToBytesArrayToBitmap(originalBitmap);
    }

    function test_bitmapToBytesArrayToBitmap_emptyBitmap() public {
        uint256 originalBitmap = 0;
        testFuzz_bitmapToBytesArrayToBitmap(originalBitmap);
    }

    function test_bitmapToBytesArrayToBitmap_firstTenEntriesBitmap() public {
        uint256 originalBitmap = 2047;
        testFuzz_bitmapToBytesArrayToBitmap(originalBitmap);
    }

    function test_bitmapToBytesArrayToBitmap_distributedTenEntriesBitmap() public {
        // 2^0+2^10+2^20+2^30+2^40+2^50+2^60+2^70+2^80+2^90
        uint256 originalBitmap = 1239150146850664126585242625;
        testFuzz_bitmapToBytesArrayToBitmap(originalBitmap);
    }
}

contract BitmapUtilsUnitTests_isArrayStrictlyAscendingOrdered is BitmapUtilsUnitTests {
    function test_DifferentBytesArrayOrdering() public {
        // Descending order and duplicate element bytes arrays should return false
        bytes memory descendingBytesArray = abi.encodePacked(
            bytes1(uint8(12)),
            bytes1(uint8(11)),
            bytes1(uint8(10)),
            bytes1(uint8(9)),
            bytes1(uint8(8)),
            bytes1(uint8(7)),
            bytes1(uint8(6)),
            bytes1(uint8(5))
        );
        assertFalse(bitmapUtilsWrapper.isArrayStrictlyAscendingOrdered(descendingBytesArray));
        bytes memory duplicateBytesArray = abi.encodePacked(
            bytes1(uint8(5)),
            bytes1(uint8(5)),
            bytes1(uint8(5)),
            bytes1(uint8(5)),
            bytes1(uint8(5)),
            bytes1(uint8(5)),
            bytes1(uint8(5)),
            bytes1(uint8(5))
        );
        assertFalse(bitmapUtilsWrapper.isArrayStrictlyAscendingOrdered(duplicateBytesArray));
        // Strictly ascending returns true
        bytes memory ascendingBytesArray = abi.encodePacked(
            bytes1(uint8(5)),
            bytes1(uint8(6)),
            bytes1(uint8(7)),
            bytes1(uint8(8)),
            bytes1(uint8(9)),
            bytes1(uint8(10)),
            bytes1(uint8(11)),
            bytes1(uint8(12))
        );
        assertTrue(bitmapUtilsWrapper.isArrayStrictlyAscendingOrdered(ascendingBytesArray));
        // Empty bytes array and single element bytes array returns true
        bytes memory emptyBytesArray;
        assertTrue(bitmapUtilsWrapper.isArrayStrictlyAscendingOrdered(emptyBytesArray));
        bytes memory singleBytesArray = abi.encodePacked(bytes1(uint8(1)));
        assertTrue(bitmapUtilsWrapper.isArrayStrictlyAscendingOrdered(singleBytesArray));
    }
}

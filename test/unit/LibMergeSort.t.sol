// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../../src/libraries/LibMergeSort.sol";

contract LibMergeSortTest is Test {
    using LibMergeSort for address[];

    function testMergeSortArrays() public {
        address[] memory left = new address[](3);
        address[] memory right = new address[](3);

        left[0] = address(0x1);
        left[1] = address(0x3);
        left[2] = address(0x5);

        right[0] = address(0x2);
        right[1] = address(0x4);
        right[2] = address(0x6);

        address[] memory expected = new address[](6);
        expected[0] = address(0x1);
        expected[1] = address(0x2);
        expected[2] = address(0x3);
        expected[3] = address(0x4);
        expected[4] = address(0x5);
        expected[5] = address(0x6);

        address[] memory result = left.mergeSortArrays(right);

        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(result[i], expected[i], "Array elements are not sorted correctly");
        }
    }

    function testMergeSortArraysWithDuplicates() public {
        address[] memory left = new address[](3);
        address[] memory right = new address[](3);

        left[0] = address(0x1);
        left[1] = address(0x3);
        left[2] = address(0x5);

        right[0] = address(0x1);
        right[1] = address(0x3);
        right[2] = address(0x5);

        address[] memory expected = new address[](3);
        expected[0] = address(0x1);
        expected[1] = address(0x3);
        expected[2] = address(0x5);

        address[] memory result = left.mergeSortArrays(right);
        assertEq(expected, result, "Not sorted");
    }

    function testMergeSortArraysWithEmptyLeft() public {
        address[] memory left = new address[](0);
        address[] memory right = new address[](3);

        right[0] = address(0x2);
        right[1] = address(0x4);
        right[2] = address(0x6);

        address[] memory expected = new address[](3);
        expected[0] = address(0x2);
        expected[1] = address(0x4);
        expected[2] = address(0x6);

        address[] memory result = left.mergeSortArrays(right);

        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(result[i], expected[i], "Array elements are not sorted correctly");
        }
    }

    function testMergeSortArraysWithEmptyRight() public {
        address[] memory left = new address[](3);
        address[] memory right = new address[](0);

        left[0] = address(0x1);
        left[1] = address(0x3);
        left[2] = address(0x5);

        address[] memory expected = new address[](3);
        expected[0] = address(0x1);
        expected[1] = address(0x3);
        expected[2] = address(0x5);

        address[] memory result = left.mergeSortArrays(right);

        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(result[i], expected[i], "Array elements are not sorted correctly");
        }
    }

    function testMergeSortArrays_Sort() public {
        address[] memory left = new address[](3);
        address[] memory right = new address[](3);

        left[0] = address(0x3);
        left[1] = address(0x1);
        left[2] = address(0x2);

        right[0] = address(0x6);
        right[1] = address(0x4);
        right[2] = address(0x5);

        left = left.sort();
        right = right.sort();

        address[] memory expected = new address[](6);
        expected[0] = address(0x1);
        expected[1] = address(0x2);
        expected[2] = address(0x3);
        expected[3] = address(0x4);
        expected[4] = address(0x5);
        expected[5] = address(0x6);

        address[] memory result = left.mergeSortArrays(right);

        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(result[i], expected[i], "Array elements are not sorted correctly");
        }
    }

    /// NOTE: we're assuming the input arrays themselves are unique.
    /// Demonstrating behavior of library
    function testMergeSortArraysWithDuplicateInLeft() public {
        address[] memory left = new address[](4);
        address[] memory right = new address[](3);

        left[0] = address(0x1);
        left[1] = address(0x3);
        left[2] = address(0x3); // Duplicate
        left[3] = address(0x5);

        right[0] = address(0x2);
        right[1] = address(0x4);
        right[2] = address(0x6);

        address[] memory expected = new address[](7);
        expected[0] = address(0x1);
        expected[1] = address(0x2);
        expected[2] = address(0x3);
        expected[3] = address(0x3);
        expected[4] = address(0x4);
        expected[5] = address(0x5);
        expected[6] = address(0x6);

        address[] memory result = left.mergeSortArrays(right);

        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(result[i], expected[i], "Array elements are not sorted correctly");
        }
    }

    function testMergeSortArraysWithDuplicateInRight() public {
        address[] memory left = new address[](3);
        address[] memory right = new address[](4);

        left[0] = address(0x1);
        left[1] = address(0x3);
        left[2] = address(0x5);

        right[0] = address(0x2);
        right[1] = address(0x4);
        right[2] = address(0x4); // Duplicate
        right[3] = address(0x6);

        address[] memory expected = new address[](7);
        expected[0] = address(0x1);
        expected[1] = address(0x2);
        expected[2] = address(0x3);
        expected[3] = address(0x4);
        expected[4] = address(0x4);
        expected[5] = address(0x5);
        expected[6] = address(0x6);

        address[] memory result = left.mergeSortArrays(right);

        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(result[i], expected[i], "Array elements are not sorted correctly");
        }
    }
}

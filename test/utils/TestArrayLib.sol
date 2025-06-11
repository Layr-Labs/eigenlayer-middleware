// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

/**
 * @title TestArrayLib
 * @notice Simple array helper functions for test files
 * @dev Replaces ArrayLib to avoid compilation issues with sort function
 */
library TestArrayLib {
    /// @notice Converts a single uint32 to an array
    function toArrayU32(uint32 x) internal pure returns (uint32[] memory array) {
        array = new uint32[](1);
        array[0] = x;
    }

    /// @notice Converts a single uint256 to an array
    function toArrayU256(uint256 x) internal pure returns (uint256[] memory array) {
        array = new uint256[](1);
        array[0] = x;
    }

    /// @notice Converts a single address to an array
    function toArray(address x) internal pure returns (address[] memory array) {
        array = new address[](1);
        array[0] = x;
    }
} 
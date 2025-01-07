// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../../src/libraries/BitmapUtils.sol";

// wrapper around the BitmapUtils library that exposes the internal functions
contract BitmapUtilsWrapper {
    function orderedBytesArrayToBitmap(
        bytes calldata orderedBytesArray
    ) external pure returns (uint256) {
        return BitmapUtils.orderedBytesArrayToBitmap(orderedBytesArray);
    }

    function isArrayStrictlyAscendingOrdered(
        bytes calldata bytesArray
    ) external pure returns (bool) {
        return BitmapUtils.isArrayStrictlyAscendingOrdered(bytesArray);
    }

    function bitmapToBytesArray(
        uint256 bitmap
    ) external pure returns (bytes memory bytesArray) {
        return BitmapUtils.bitmapToBytesArray(bitmap);
    }

    function countNumOnes(
        uint256 n
    ) external pure returns (uint16) {
        return BitmapUtils.countNumOnes(n);
    }

    function isSet(uint256 bitmap, uint8 numberToCheckForInclusion) external pure returns (bool) {
        return BitmapUtils.isSet(bitmap, numberToCheckForInclusion);
    }

    function setBit(uint256 bitmap, uint8 bit) external pure returns (uint256) {
        return BitmapUtils.setBit(bitmap, bit);
    }

    function isEmpty(
        uint256 bitmap
    ) external pure returns (bool) {
        return BitmapUtils.isEmpty(bitmap);
    }

    function noBitsInCommon(uint256 a, uint256 b) external pure returns (bool) {
        return BitmapUtils.noBitsInCommon(a, b);
    }

    function isSubsetOf(uint256 a, uint256 b) external pure returns (bool) {
        return BitmapUtils.isSubsetOf(a, b);
    }

    function plus(uint256 a, uint256 b) external pure returns (uint256) {
        return BitmapUtils.plus(a, b);
    }

    function minus(uint256 a, uint256 b) external pure returns (uint256) {
        return BitmapUtils.minus(a, b);
    }
}

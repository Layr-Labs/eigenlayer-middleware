// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "src/RegistryCoordinator.sol";

contract RegistryCoordinatorHarness is RegistryCoordinator {
    constructor(
        IServiceManager _serviceManager,
        IStakeRegistry _stakeRegistry,
        IBLSApkRegistry _blsApkRegistry,
        IIndexRegistry _indexRegistry
    ) RegistryCoordinator(_serviceManager, _stakeRegistry, _blsApkRegistry, _indexRegistry) {}

    // @notice function based upon `BitmapUtils.bytesArrayToBitmap`, used to determine if an array contains any duplicates
    function bytesArrayContainsDuplicates(bytes memory bytesArray) public pure returns (bool) {
        // sanity-check on input. a too-long input would fail later on due to having duplicate entry(s)
        if (bytesArray.length > 256) {
            return false;
        }

        // initialize the empty bitmap, to be built inside the loop
        uint256 bitmap;
        // initialize an empty uint256 to be used as a bitmask inside the loop
        uint256 bitMask;

        // loop through each byte in the array to construct the bitmap
        for (uint256 i = 0; i < bytesArray.length; ++i) {
            // construct a single-bit mask from the numerical value of the next byte out of the array
            bitMask = uint256(1 << uint8(bytesArray[i]));
            // check that the entry is not a repeat
            if (bitmap & bitMask != 0) {
                return false;
            }
            // add the entry to the bitmap
            bitmap = (bitmap | bitMask);
        }

        // if the loop is completed without returning early, then the array contains no duplicates
        return true;
    }

    // @notice verifies that a bytes array is a (non-strict) subset of a bitmap
    function bytesArrayIsSubsetOfBitmap(uint256 referenceBitmap, bytes memory arrayWhichShouldBeASubsetOfTheReference) public pure returns (bool) {
        uint256 arrayWhichShouldBeASubsetOfTheReferenceBitmap = BitmapUtils.orderedBytesArrayToBitmap(arrayWhichShouldBeASubsetOfTheReference);
        if (referenceBitmap | arrayWhichShouldBeASubsetOfTheReferenceBitmap == referenceBitmap) {
            return true;
        } else {
            return false;
        }
    }

    function quorumInBitmap(uint256 bitmap, uint8 numberToCheckForInclusion) public pure returns (bool) {
        return BitmapUtils.isSet(bitmap, numberToCheckForInclusion);
    }

    function hashToG1Harness(bytes32 x) public pure returns (BN254.G1Point memory) {
        return BN254.G1Point(uint256(keccak256(abi.encodePacked(x))), 2);
    }
}

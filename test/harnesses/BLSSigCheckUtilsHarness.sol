// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {BN254} from "../../src/libraries/BN254.sol";
import {
    BLSSigCheckUtils,
    Comparators,
    SlotDerivation,
    Arrays
} from "../../src/unaudited/BLSSigCheckUtils.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

/**
 * @title BLSSigCheckUtilsHarness
 * @notice Test harness to expose internal functions from BLSSigCheckUtils and its libraries for testing
 */
contract BLSSigCheckUtilsHarness {
    using BN254 for BN254.G1Point;
    using BLSSigCheckUtils for BN254.G1Point;
    using SlotDerivation for bytes32;
    using SlotDerivation for string;
    using Arrays for uint256[];
    using Arrays for address[];
    using Arrays for bytes32[];
    using Arrays for bytes[];
    using Arrays for string[];

    // Storage arrays for testing storage-related functions
    uint256[] public uint256Array;
    address[] public addressArray;
    bytes32[] public bytes32Array;
    bytes[] public bytesArray;
    string[] public stringArray;

    /**
     *
     * BLSSigCheckUtils functions
     *
     */
    function isOnCurve(
        BN254.G1Point memory p
    ) public pure returns (bool) {
        return p.isOnCurve();
    }

    /**
     *
     * Comparators library functions
     *
     */
    function lt(uint256 a, uint256 b) public pure returns (bool) {
        return Comparators.lt(a, b);
    }

    function gt(uint256 a, uint256 b) public pure returns (bool) {
        return Comparators.gt(a, b);
    }

    /**
     *
     * SlotDerivation library functions
     *
     */
    function erc7201Slot(
        string memory namespace
    ) public pure returns (bytes32) {
        return namespace.erc7201Slot();
    }

    function offset(bytes32 slot, uint256 pos) public pure returns (bytes32) {
        return slot.offset(pos);
    }

    function deriveArray(
        bytes32 slot
    ) public pure returns (bytes32) {
        return slot.deriveArray();
    }

    function deriveMappingAddress(bytes32 slot, address key) public pure returns (bytes32) {
        return slot.deriveMapping(key);
    }

    function deriveMappingBool(bytes32 slot, bool key) public pure returns (bytes32) {
        return slot.deriveMapping(key);
    }

    function deriveMappingBytes32(bytes32 slot, bytes32 key) public pure returns (bytes32) {
        return slot.deriveMapping(key);
    }

    function deriveMappingUint256(bytes32 slot, uint256 key) public pure returns (bytes32) {
        return slot.deriveMapping(key);
    }

    function deriveMappingInt256(bytes32 slot, int256 key) public pure returns (bytes32) {
        return slot.deriveMapping(key);
    }

    function deriveMappingString(bytes32 slot, string memory key) public pure returns (bytes32) {
        return slot.deriveMapping(key);
    }

    function deriveMappingBytes(bytes32 slot, bytes memory key) public pure returns (bytes32) {
        return slot.deriveMapping(key);
    }

    /**
     *
     * Arrays library functions - Sorting
     *
     */
    function sortUint256(
        uint256[] memory array
    ) public pure returns (uint256[] memory) {
        return array.sort();
    }

    function sortAddress(
        address[] memory array
    ) public pure returns (address[] memory) {
        return array.sort();
    }

    function sortBytes32(
        bytes32[] memory array
    ) public pure returns (bytes32[] memory) {
        return array.sort();
    }

    /**
     *
     * Arrays library functions - Binary Search
     *
     */
    function findUpperBound(
        uint256 element
    ) public view returns (uint256) {
        return uint256Array.findUpperBound(element);
    }

    function lowerBound(
        uint256 element
    ) public view returns (uint256) {
        return uint256Array.lowerBound(element);
    }

    function upperBound(
        uint256 element
    ) public view returns (uint256) {
        return uint256Array.upperBound(element);
    }

    function lowerBoundMemory(
        uint256[] memory array,
        uint256 element
    ) public pure returns (uint256) {
        return array.lowerBoundMemory(element);
    }

    function upperBoundMemory(
        uint256[] memory array,
        uint256 element
    ) public pure returns (uint256) {
        return array.upperBoundMemory(element);
    }

    /**
     *
     * Arrays library functions - Unsafe Access
     *
     */
    function unsafeAccessAddress(
        uint256 pos
    ) public view returns (address) {
        return addressArray.unsafeAccess(pos).value;
    }

    function unsafeAccessBytes32(
        uint256 pos
    ) public view returns (bytes32) {
        return bytes32Array.unsafeAccess(pos).value;
    }

    function unsafeAccessUint256(
        uint256 pos
    ) public view returns (uint256) {
        return uint256Array.unsafeAccess(pos).value;
    }

    function unsafeAccessBytes(
        uint256 pos
    ) public view returns (bytes memory) {
        return bytesArray.unsafeAccess(pos).value;
    }

    function unsafeAccessString(
        uint256 pos
    ) public view returns (string memory) {
        return stringArray.unsafeAccess(pos).value;
    }

    function unsafeMemoryAccessAddress(
        address[] memory arr,
        uint256 pos
    ) public pure returns (address) {
        return arr.unsafeMemoryAccess(pos);
    }

    function unsafeMemoryAccessBytes32(
        bytes32[] memory arr,
        uint256 pos
    ) public pure returns (bytes32) {
        return arr.unsafeMemoryAccess(pos);
    }

    function unsafeMemoryAccessUint256(
        uint256[] memory arr,
        uint256 pos
    ) public pure returns (uint256) {
        return arr.unsafeMemoryAccess(pos);
    }

    function unsafeMemoryAccessBytes(
        bytes[] memory arr,
        uint256 pos
    ) public pure returns (bytes memory) {
        return arr.unsafeMemoryAccess(pos);
    }

    function unsafeMemoryAccessString(
        string[] memory arr,
        uint256 pos
    ) public pure returns (string memory) {
        return arr.unsafeMemoryAccess(pos);
    }

    /**
     *
     * Arrays library functions - Unsafe Set Length
     *
     */
    function unsafeSetLengthAddress(
        uint256 len
    ) public {
        addressArray.unsafeSetLength(len);
    }

    function unsafeSetLengthBytes32(
        uint256 len
    ) public {
        bytes32Array.unsafeSetLength(len);
    }

    function unsafeSetLengthUint256(
        uint256 len
    ) public {
        uint256Array.unsafeSetLength(len);
    }

    function unsafeSetLengthBytes(
        uint256 len
    ) public {
        bytesArray.unsafeSetLength(len);
    }

    function unsafeSetLengthString(
        uint256 len
    ) public {
        stringArray.unsafeSetLength(len);
    }

    /**
     *
     * Helper functions for testing
     *
     */

    // Initialize test arrays
    function initializeUint256Array(
        uint256[] memory values
    ) public {
        delete uint256Array;
        for (uint256 i = 0; i < values.length; i++) {
            uint256Array.push(values[i]);
        }
    }

    function initializeAddressArray(
        address[] memory values
    ) public {
        delete addressArray;
        for (uint256 i = 0; i < values.length; i++) {
            addressArray.push(values[i]);
        }
    }

    function initializeBytes32Array(
        bytes32[] memory values
    ) public {
        delete bytes32Array;
        for (uint256 i = 0; i < values.length; i++) {
            bytes32Array.push(values[i]);
        }
    }

    function initializeBytesArray(
        bytes[] memory values
    ) public {
        delete bytesArray;
        for (uint256 i = 0; i < values.length; i++) {
            bytesArray.push(values[i]);
        }
    }

    function initializeStringArray(
        string[] memory values
    ) public {
        delete stringArray;
        for (uint256 i = 0; i < values.length; i++) {
            stringArray.push(values[i]);
        }
    }

    // Getters for array lengths
    function getUint256ArrayLength() public view returns (uint256) {
        return uint256Array.length;
    }

    function getAddressArrayLength() public view returns (uint256) {
        return addressArray.length;
    }

    function getBytes32ArrayLength() public view returns (uint256) {
        return bytes32Array.length;
    }

    function getBytesArrayLength() public view returns (uint256) {
        return bytesArray.length;
    }

    function getStringArrayLength() public view returns (uint256) {
        return stringArray.length;
    }

    // Getters for full arrays
    function getUint256Array() public view returns (uint256[] memory) {
        return uint256Array;
    }

    function getAddressArray() public view returns (address[] memory) {
        return addressArray;
    }

    function getBytes32Array() public view returns (bytes32[] memory) {
        return bytes32Array;
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

library Sort {
    /**
     * @notice Sorts an array of addresses in ascending order. h/t ChatGPT take 2
     * @dev This function uses the Bubble Sort algorithm, which is simple but has O(n^2) complexity.
     * @param addresses The array of addresses to be sorted.
     * @return sortedAddresses The array of addresses sorted in ascending order.
     */
    function sortAddresses(
        address[] memory addresses
    ) internal pure returns (address[] memory) {
        uint256 n = addresses.length;
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = 0; j < n - 1; j++) {
                // Compare and swap if the current address is greater than the next one
                if (addresses[j] > addresses[j + 1]) {
                    address temp = addresses[j];
                    addresses[j] = addresses[j + 1];
                    addresses[j + 1] = temp;
                }
            }
        }
        return addresses;
    }
}

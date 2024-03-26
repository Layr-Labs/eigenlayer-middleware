// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

library Sort {

    /// @dev In-place insertion sort of addrs, h/t ChatGPT
    function sort(address[] memory addrs) internal pure {
        for (uint i = 1; i < addrs.length; i++) {
            address key = addrs[i];
            uint j = i - 1;

            // Move elements of addrs[0..i-1], that are greater than key,
            // to one position ahead of their current position
            while (j >= 0 && addrs[j] > key) {
                addrs[j + 1] = addrs[j];
                if(j == 0) {
                    break;
                }
                j--;
            }
            addrs[j + 1] = key;
        }
    }
}

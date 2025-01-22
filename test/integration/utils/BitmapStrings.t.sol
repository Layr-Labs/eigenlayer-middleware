// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/utils/Strings.sol";

library BitmapStrings {
    using Strings for *;

    /// @dev Given an input quorum array, returns a nice, readable string:
    /// e.g. [0, 1, 2, ...]
    /// (This is way more readable than logging with log_named_bytes)
    function toString(
        bytes memory bitmapArr
    ) internal pure returns (string memory) {
        string memory result = "[";

        for (uint256 i = 0; i < bitmapArr.length; i++) {
            if (i == bitmapArr.length - 1) {
                result = string.concat(result, uint256(uint8(bitmapArr[i])).toString());
            } else {
                result = string.concat(result, uint256(uint8(bitmapArr[i])).toString(), ", ");
            }
        }

        result = string.concat(result, "]");
        return result;
    }
}

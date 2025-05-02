// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {BN254} from "../libraries/BN254.sol";

/**
 * @title ECUtils
 * @notice Library containing utility functions for elliptic curve operations
 */
library ECUtils {
    /**
     * @notice Checks if a point lies on the BN254 elliptic curve
     * @dev The curve equation is y^2 = x^3 + 3 (mod p)
     * @param p The point to check, in G1
     * @return true if the point lies on the curve, false otherwise
     */
    function isOnCurve(
        BN254.G1Point memory p
    ) internal pure returns (bool) {
        uint256 y2 = mulmod(p.Y, p.Y, BN254.FP_MODULUS);
        uint256 x2 = mulmod(p.X, p.X, BN254.FP_MODULUS);
        uint256 x3 = mulmod(p.X, x2, BN254.FP_MODULUS);
        uint256 rhs = addmod(x3, 3, BN254.FP_MODULUS);
        return y2 == rhs;
    }
}

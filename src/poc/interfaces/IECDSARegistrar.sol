// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";

/// @title IECDSARegistrar
interface IECDSARegistrar {
    /**
     * @notice Gets the signing key for an operator
     * @param operator The operator to get the signing key for
     * @return The signing key for the operator
     */
    function getSigningKey(
        address operator
    ) external view returns (address);
}

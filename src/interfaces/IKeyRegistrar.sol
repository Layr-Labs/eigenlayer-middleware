// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

/// @notice A dummy interface for the KeyRegistrar
interface IKeyRegistrar {
    enum CurveType {
        ECDSA,
        BN254
    }

    /// TODO: inherit from actual KeyRegistrar
    function isRegistered(
        address operator,
        OperatorSet calldata operatorSet,
        CurveType curveType
    ) external view returns (bool);
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

/// @notice A dummy interface for the KeyRegistrar
interface IKeyRegistrar {
    enum CurveType {
        ECDSA,
        BN254
    }

    function checkAndUpdateKey(
        OperatorSet calldata operatorSet,
        address operator
    ) external returns (bool);

    function removeKey(OperatorSet calldata operatorSet, address operator) external;

    function isRegistered(
        OperatorSet calldata operatorSet,
        address operator
    ) external view returns (bool);
}

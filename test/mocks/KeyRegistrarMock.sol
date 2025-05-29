// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet, OperatorSetLib} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IKeyRegistrar} from "src/interfaces/IKeyRegistrar.sol";


contract KeyRegistrarMock is IKeyRegistrar {
    using OperatorSetLib for OperatorSet;

    mapping(bytes32 operatorSetKey => mapping(address => bool)) internal _operatorRegistered;

    function setIsRegistered(
        address operator,
        OperatorSet calldata operatorSet,
        bool _isRegistered
    ) external {
        bytes32 operatorSetKey = operatorSet.key();
        _operatorRegistered[operatorSetKey][operator] = _isRegistered;
    }

    function isRegistered(
        OperatorSet calldata operatorSet,
        address operator
    ) external view returns (bool) {
        return _operatorRegistered[operatorSet.key()][operator];
    }

    function checkAndUpdateKey(
        OperatorSet calldata operatorSet,
        address operator
    ) external view returns (bool) {
        return _operatorRegistered[operatorSet.key()][operator];
    }

    function removeKey(
        OperatorSet calldata operatorSet,
        address operator
    ) external {
        _operatorRegistered[operatorSet.key()][operator] = false;
    }
}
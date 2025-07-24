// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllowlist} from "../../../interfaces/IAllowlist.sol";
import {AllowlistStorage} from "./AllowlistStorage.sol";

import {OwnableUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {EnumerableSetUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/utils/structs/EnumerableSetUpgradeable.sol";

import {
    OperatorSet,
    OperatorSetLib
} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

abstract contract Allowlist is OwnableUpgradeable, AllowlistStorage {
    using OperatorSetLib for OperatorSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    function __Allowlist_init(
        address _owner
    ) internal onlyInitializing {
        __Ownable_init();
        _transferOwnership(_owner);
    }

    /// @inheritdoc IAllowlist
    function addOperatorToAllowlist(
        OperatorSet memory operatorSet,
        address operator
    ) external onlyOwner {
        require(_allowedOperators[operatorSet.key()].add(operator), OperatorAlreadyInAllowlist());
        emit OperatorAddedToAllowlist(operatorSet, operator);
    }

    /// @inheritdoc IAllowlist
    function removeOperatorFromAllowlist(
        OperatorSet memory operatorSet,
        address operator
    ) external onlyOwner {
        require(_allowedOperators[operatorSet.key()].remove(operator), OperatorNotInAllowlist());
        emit OperatorRemovedFromAllowlist(operatorSet, operator);
    }

    /// @inheritdoc IAllowlist
    function isOperatorAllowed(
        OperatorSet memory operatorSet,
        address operator
    ) public view returns (bool) {
        return _allowedOperators[operatorSet.key()].contains(operator);
    }

    /// @inheritdoc IAllowlist
    function getAllowedOperators(
        OperatorSet memory operatorSet
    ) external view returns (address[] memory) {
        return _allowedOperators[operatorSet.key()].values();
    }
}

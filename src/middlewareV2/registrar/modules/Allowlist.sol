// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllowlist} from "../../../interfaces/IAllowlist.sol";
import {AllowlistStorage} from "./AllowlistStorage.sol";

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {EnumerableSetUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/utils/structs/EnumerableSetUpgradeable.sol";

contract Allowlist is Initializable, OwnableUpgradeable, AllowlistStorage {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner
    ) external initializer {
        __Ownable_init();
        _transferOwnership(_owner);
    }

    /// @inheritdoc IAllowlist
    function addOperatorToAllowlist(
        address operator
    ) external onlyOwner {
        EnumerableSetUpgradeable.AddressSet storage allowedOperators = _allowedOperators;
        require(allowedOperators.add(operator), OperatorAlreadyInAllowlist());
    }

    /// @inheritdoc IAllowlist
    function removeOperatorFromAllowlist(
        address operator
    ) external onlyOwner {
        EnumerableSetUpgradeable.AddressSet storage allowedOperators = _allowedOperators;
        require(allowedOperators.remove(operator), OperatorNotInAllowlist());
    }

    /// @inheritdoc IAllowlist
    function isOperatorAllowed(
        address operator
    ) public view returns (bool) {
        EnumerableSetUpgradeable.AddressSet storage allowedOperators = _allowedOperators;
        return allowedOperators.contains(operator);
    }

    /// @inheritdoc IAllowlist
    function getAllowedOperators() external view returns (address[] memory) {
        EnumerableSetUpgradeable.AddressSet storage allowedOperators = _allowedOperators;
        return allowedOperators.values();
    }
}

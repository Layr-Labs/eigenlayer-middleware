// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllowlist} from "../../../interfaces/IAllowlist.sol";

import {EnumerableSetUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/utils/structs/EnumerableSetUpgradeable.sol";

abstract contract AllowlistStorage is IAllowlist {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    /// @dev This data structure takes up 2 storage slots
    EnumerableSetUpgradeable.AddressSet internal _allowedOperators;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[48] private __GAP;
}

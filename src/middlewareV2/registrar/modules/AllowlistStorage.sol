// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllowlist} from "../../../interfaces/IAllowlist.sol";

import {EnumerableSetUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/utils/structs/EnumerableSetUpgradeable.sol";

abstract contract AllowlistStorage is IAllowlist {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    /// @dev Mapping from operatorSet to the allowed operators for that operatorSet
    mapping(bytes32 operatorSetKey => EnumerableSetUpgradeable.AddressSet allowedOperators) internal
        _allowedOperators;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __GAP;
}

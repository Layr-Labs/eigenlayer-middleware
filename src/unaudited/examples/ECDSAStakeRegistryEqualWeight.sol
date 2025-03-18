// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {ECDSAStakeRegistryPermissioned} from "./ECDSAStakeRegistryPermissioned.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {CheckpointsUpgradeable} from
    "@openzeppelin-upgrades/contracts/utils/CheckpointsUpgradeable.sol";

/// @title ECDSA Stake Registry with Equal Weight
/// @dev THIS CONTRACT IS NOT AUDITED
/// @notice A contract to manage operator stakes with equal weighting for operators
contract ECDSAStakeRegistryEqualWeight is ECDSAStakeRegistryPermissioned {
    using CheckpointsUpgradeable for CheckpointsUpgradeable.History;

    /// @notice Initializes the contract with a specified delegation manager.
    /// @dev Passes the delegation manager to the parent constructor.
    /// @param _delegationManager The address of the delegation manager contract.
    constructor(
        IDelegationManager _delegationManager
    ) ECDSAStakeRegistryPermissioned(_delegationManager) {
        // _disableInitializers();
    }

    /// @notice Updates the weight of an operator in the stake registry.
    /// @dev Overrides the _updateOperatorWeight function from the parent class to implement equal weighting.
    ///      Emits an OperatorWeightUpdated event upon successful update.
    /// @param _operator The address of the operator whose weight is being updated.
    function _updateOperatorWeight(
        address _operator
    ) internal override returns (int256) {
        uint256 oldWeight;
        uint256 newWeight;
        int256 delta;
        if (_operatorRegistered[_operator]) {
            (oldWeight,) = _operatorWeightHistory[_operator].push(1);
            delta = int256(1) - int256(oldWeight); // handles if they were already registered
        } else {
            (oldWeight,) = _operatorWeightHistory[_operator].push(0);
            delta = int256(0) - int256(oldWeight);
        }
        emit OperatorWeightUpdated(_operator, oldWeight, newWeight);
        return delta;
    }
}

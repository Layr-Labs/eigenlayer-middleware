// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {ECDSAStakeRegistryPermissioned} from "./ECDSAStakeRegistryPermissioned.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {CheckpointsUpgradeable} from "@openzeppelin-upgrades/contracts/utils/CheckpointsUpgradeable.sol";

contract ECDSAStakeRegistryEqualWeight is ECDSAStakeRegistryPermissioned {
    using CheckpointsUpgradeable for CheckpointsUpgradeable.History;
    constructor(
        IDelegationManager _delegationManager
    ) ECDSAStakeRegistryPermissioned(_delegationManager) {
        // _disableInitializers();
    }

    function _updateOperatorWeight(address _operator) internal override {
        uint256 oldWeight;
        uint256 newWeight;
        int256 delta;
        /// TODO: Need to fix this logic
        if (_operatorRegistered[_operator]) {
            (oldWeight, ) = _operatorWeightHistory[_operator].push(1);
            delta = int256(1) - int(oldWeight); // handles if they were already registered
        } else {
            (oldWeight, ) = _operatorWeightHistory[_operator].push(0);
            delta = int256(0) - int(oldWeight);
        }
        _updateTotalWeight(delta);
        emit OperatorWeightUpdated(_operator, oldWeight, newWeight);
    }
}

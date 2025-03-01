// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ECDSAStakeRegistry} from "../ECDSAStakeRegistry.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IAVSDirectory} from "../ECDSAStakeRegistry.sol";

/// @title ECDSAStakeRegistryRatioWeight
/// @notice An example implementation of ECDSAStakeRegistry that allows setting different weight ratios
/// for quorum weight and operator set weight
/// @dev The total weight ratio is 10000 (100%). The quorum weight ratio can be set between 0 and 10000,
/// and the operator set weight ratio will be (10000 - quorumWeightRatio)
contract ECDSAStakeRegistryRatioWeight is ECDSAStakeRegistry {
    /// @notice Event emitted when the weight ratio is updated
    event WeightRatioUpdated(uint256 oldRatio, uint256 newRatio);

    /// @notice The weight ratio for quorum weight (0-10000)
    uint256 private _quorumWeightRatio;

    error InvalidWeightRatio(uint256 ratio);

    constructor(
        IDelegationManager _delegationManager,
        IAllocationManager _allocationManager,
        address _avsRegistrar,
        IAVSDirectory _avsDirectory
    ) ECDSAStakeRegistry(_delegationManager, _allocationManager, _avsRegistrar, _avsDirectory) {}

    /// @notice External function to set the weight ratio, only callable by owner
    /// @param ratio The new ratio (0-10000)
    /// @dev The operator set weight ratio will be (10000 - ratio)
    function setWeightRatio(
        uint256 ratio
    ) external onlyOwner {
        _setWeightRatio(ratio);
    }

    /// @notice Returns the current weight ratio
    /// @return The current quorum weight ratio (0-10000)
    function getWeightRatio() external view returns (uint256) {
        return _quorumWeightRatio;
    }

    /// @inheritdoc ECDSAStakeRegistry
    /// @dev Overrides the weight calculation to apply the configured ratios
    function getOperatorWeight(
        address _operator
    ) public view virtual override returns (uint256) {
        uint256 quorumWeight = getQuorumWeight(_operator);
        uint256 operatorSetWeight = getOperatorSetWeight(_operator);

        uint256 weightedQuorumWeight = (quorumWeight * _quorumWeightRatio) / 10000;
        uint256 weightedOperatorSetWeight =
            (operatorSetWeight * (10000 - _quorumWeightRatio)) / 10000;

        return weightedQuorumWeight + weightedOperatorSetWeight;
    }

    /// @notice Sets the weight ratio for quorum weight
    /// @param ratio The new ratio (0-10000)
    /// @dev The operator set weight ratio will be (10000 - ratio)
    function _setWeightRatio(
        uint256 ratio
    ) internal {
        if (ratio > 10000) {
            revert InvalidWeightRatio(ratio);
        }
        uint256 oldRatio = _quorumWeightRatio;
        _quorumWeightRatio = ratio;
        emit WeightRatioUpdated(oldRatio, ratio);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../../src/unaudited/ECDSAStakeRegistry.sol";
import {CheckpointsUpgradeable} from
    "@openzeppelin-upgrades/contracts/utils/CheckpointsUpgradeable.sol";

/**
 * @title Mock for ECDSAStakeRegistry
 * @dev This contract is a mock implementation of the ECDSAStakeRegistry for testing purposes.
 */
contract ECDSAStakeRegistryMock is ECDSAStakeRegistry {
    using CheckpointsUpgradeable for CheckpointsUpgradeable.History;

    constructor(
        IDelegationManager _delegationManager
    ) ECDSAStakeRegistry(_delegationManager) {}

    /**
     * @notice Sets the total weight at a specific block for testing
     * @param blockNumber The block number
     * @param weight The weight to set
     */
    function setTotalWeightAtBlock(uint32 blockNumber, uint256 weight) external {
        _totalWeightHistory.push(weight);
    }

    /**
     * @notice Sets the threshold weight at a specific block for testing
     * @param blockNumber The block number
     * @param weight The weight to set
     */
    function setThresholdWeightAtBlock(uint32 blockNumber, uint256 weight) external {
        _thresholdWeightHistory.push(weight);
    }
}

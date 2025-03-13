// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IStakeRegistry, IStrategy} from "../../src/interfaces/IStakeRegistry.sol";

interface IStakeRegistryEvents {
    /// @notice emitted whenever the stake of `operator` is updated
    event OperatorStakeUpdate(bytes32 indexed operatorId, uint8 quorumNumber, uint96 stake);
    /// @notice emitted when the minimum stake for a quorum is updated
    event MinimumStakeForQuorumUpdated(uint8 indexed quorumNumber, uint96 minimumStake);
    /// @notice emitted when a new quorum is created
    event QuorumCreated(uint8 indexed quorumNumber);
    /// @notice emitted when `strategy` has been added to the array at `strategyParams[quorumNumber]`
    event StrategyAddedToQuorum(uint8 indexed quorumNumber, IStrategy strategy);
    /// @notice emitted when `strategy` has removed from the array at `strategyParams[quorumNumber]`
    event StrategyRemovedFromQuorum(uint8 indexed quorumNumber, IStrategy strategy);
    /// @notice emitted when `strategy` has its `multiplier` updated in the array at `strategyParams[quorumNumber]`
    event StrategyMultiplierUpdated(
        uint8 indexed quorumNumber, IStrategy strategy, uint256 multiplier
    );
    /// @notice Emitted when the look ahead period for checking operator shares is updated.
    event LookAheadPeriodChanged(uint32 oldLookAheadBlocks, uint32 newLookAheadBlocks);
}

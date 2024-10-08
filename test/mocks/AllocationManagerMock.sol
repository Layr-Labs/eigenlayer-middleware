// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";

contract AllocationManagerMock is IAllocationManager {
  function setAllocationDelay(
    address operator,
    uint32 delay
  ) external override {}

  function setAllocationDelay(uint32 delay) external override {}

  function allocationDelay(
    address operator
  ) external view override returns (bool isSet, uint32 delay) {}

  function getAllocatableMagnitude(
    address operator,
    IStrategy strategy
  ) external view override returns (uint64) {}

  function getSlashableMagnitudes(
    address operator,
    IStrategy[] calldata strategies
  ) external view override returns (OperatorSet[] memory, uint64[][] memory) {}

  function getTotalMagnitudes(
    address operator,
    IStrategy[] calldata strategies
  ) external view override returns (uint64[] memory) {}

  function getTotalMagnitudesAtTimestamp(
    address operator,
    IStrategy[] calldata strategies,
    uint32 timestamp
  ) external view override returns (uint64[] memory) {}

  function modifyAllocations(
    MagnitudeAllocation[] calldata allocations
  ) external override {}

  function clearModificationQueue(
    address operator,
    IStrategy[] calldata strategies,
    uint16[] calldata numToComplete
  ) external override {}

  function slashOperator(SlashingParams calldata params) external override {}

  function getPendingModifications(
    address operator,
    IStrategy strategy,
    OperatorSet[] calldata operatorSets
  )
    external
    view
    override
    returns (uint32[] memory timestamps, int128[] memory pendingMagnitudeDeltas)
  {}
}
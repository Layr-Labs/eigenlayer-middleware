// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";

contract AllocationManagerMock is IAllocationManager {
  function initialize(
    address initialOwner,
    IPauserRegistry _pauserRegistry,
    uint256 initialPausedStatus
  ) external override {}

  function slashOperator(SlashingParams calldata params) external override {}

  function modifyAllocations(
    MagnitudeAllocation[] calldata allocations
  ) external override {}

  function clearDeallocationQueue(
    address operator,
    IStrategy[] calldata strategies,
    uint16[] calldata numToComplete
  ) external override {}

  function setAllocationDelay(
    address operator,
    uint32 delay
  ) external override {}

  function setAllocationDelay(uint32 delay) external override {}

  function getAllocationInfo(
    address operator,
    IStrategy strategy
  )
    external
    view
    override
    returns (OperatorSet[] memory, MagnitudeInfo[] memory)
  {}

  function getAllocationInfo(
    address operator,
    IStrategy strategy,
    OperatorSet[] calldata operatorSets
  ) external view override returns (MagnitudeInfo[] memory) {}

  function getAllocationInfo(
    OperatorSet calldata operatorSet,
    IStrategy[] calldata strategies,
    address[] calldata operators
  ) external view override returns (MagnitudeInfo[][] memory) {}

  function getAllocatableMagnitude(
    address operator,
    IStrategy strategy
  ) external view override returns (uint64) {}

  function getMaxMagnitudes(
    address operator,
    IStrategy[] calldata strategies
  ) external view override returns (uint64[] memory) {}

  function getMaxMagnitudesAtTimestamp(
    address operator,
    IStrategy[] calldata strategies,
    uint32 timestamp
  ) external view override returns (uint64[] memory) {}

  function getAllocationDelay(
    address operator
  ) external view override returns (bool isSet, uint32 delay) {}

  function getMinDelegatedAndSlashableOperatorShares(
    OperatorSet calldata operatorSet,
    address[] calldata operators,
    IStrategy[] calldata strategies,
    uint32 beforeTimestamp
  ) external view override returns (uint256[][] memory, uint256[][] memory) {}
}
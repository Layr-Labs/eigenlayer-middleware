// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IAllocationManager, OperatorSet} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IAVSRegistrar } from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";

contract AllocationManagerMock is IAllocationManager {
  function initialize(
    address initialOwner,
    uint256 initialPausedStatus
  ) external override {}

  function slashOperator(SlashingParams calldata params) external override {}

  function modifyAllocations(
    AllocateParams[] calldata params
  ) external override {}

  function clearDeallocationQueue(
    address operator,
    IStrategy[] calldata strategies,
    uint16[] calldata numToClear
  ) external override {}

  function registerForOperatorSets(
    RegisterParams calldata params
  ) external override {}

  function deregisterFromOperatorSets(
    DeregisterParams calldata params
  ) external override {}

  function setAllocationDelay(
    address operator,
    uint32 delay
  ) external override {}

  function setAllocationDelay(uint32 delay) external override {}

  function setAVSRegistrar(IAVSRegistrar registrar) external override {}

  function updateAVSMetadataURI(
    string calldata metadataURI
  ) external override {}

  function createOperatorSets(
    CreateSetParams[] calldata params
  ) external override {}

  function addStrategiesToOperatorSet(
    uint32 operatorSetId,
    IStrategy[] calldata strategies
  ) external override {}

  function removeStrategiesFromOperatorSet(
    uint32 operatorSetId,
    IStrategy[] calldata strategies
  ) external override {}

  function getAllocatedSets(
    address operator
  ) external view override returns (OperatorSet[] memory) {}

  function getAllocatedStrategies(
    address operator,
    OperatorSet memory operatorSet
  ) external view override returns (IStrategy[] memory) {}

  function getAllocation(
    address operator,
    OperatorSet memory operatorSet,
    IStrategy strategy
  ) external view override returns (Allocation memory) {}

  function getAllocations(
    address[] memory operators,
    OperatorSet memory operatorSet,
    IStrategy strategy
  ) external view override returns (Allocation[] memory) {}

  function getStrategyAllocations(
    address operator,
    IStrategy strategy
  )
    external
    view
    override
    returns (OperatorSet[] memory, Allocation[] memory)
  {}

  function getAllocatableMagnitude(
    address operator,
    IStrategy strategy
  ) external view override returns (uint64) {}

  function getMaxMagnitude(
    address operator,
    IStrategy strategy
  ) external view override returns (uint64) {}

  function getMaxMagnitudes(
    address operator,
    IStrategy[] calldata strategies
  ) external view override returns (uint64[] memory) {}

  function getMaxMagnitudes(
    address[] calldata operators,
    IStrategy strategy
  ) external view override returns (uint64[] memory) {}

  function getMaxMagnitudesAtBlock(
    address operator,
    IStrategy[] calldata strategies,
    uint32 blockNumber
  ) external view override returns (uint64[] memory) {}

  function getAllocationDelay(
    address operator
  ) external view override returns (bool isSet, uint32 delay) {}

  function getRegisteredSets(
    address operator
  ) external view override returns (OperatorSet[] memory operatorSets) {}

  function isOperatorSet(
    OperatorSet memory operatorSet
  ) external view override returns (bool) {}

  function getMembers(
    OperatorSet memory operatorSet
  ) external view override returns (address[] memory operators) {}

  function getMemberCount(
    OperatorSet memory operatorSet
  ) external view override returns (uint256) {}

  function getAVSRegistrar(
    address avs
  ) external view override returns (IAVSRegistrar) {}

  function getStrategiesInOperatorSet(
    OperatorSet memory operatorSet
  ) external view override returns (IStrategy[] memory strategies) {}

  function getMinimumSlashableStake(
    OperatorSet memory operatorSet,
    address[] memory operators,
    IStrategy[] memory strategies,
    uint32 futureBlock
  ) external view override returns (uint256[][] memory slashableStake) {}
}
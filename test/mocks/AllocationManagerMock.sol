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

  function modifyAllocations(
    address operator,
    MagnitudeAllocation[] calldata allocations,
    SignatureWithSaltAndExpiry calldata operatorSignature
  ) external override {}

  function updateFreeMagnitude(
    address operator,
    IStrategy[] calldata strategies,
    uint16[] calldata numToComplete
  ) external override {}

  function slashOperator(
    address operator,
    uint32 operatorSetId,
    IStrategy[] calldata strategies,
    uint16 bipsToSlash
  ) external override {}

  function cancelSalt(bytes32 salt) external override {}

  function allocationDelay(
    address operator
  ) external view override returns (bool isSet, uint32 delay) {}

  function getAllocatableMagnitude(
    address operator,
    IStrategy strategy
  ) external view override returns (uint64) {}

  function getPendingAllocations(
    address operator,
    IStrategy strategy,
    OperatorSet[] calldata operatorSets
  ) external view override returns (uint64[] memory, uint32[] memory) {}

  function getPendingDeallocations(
    address operator,
    IStrategy strategy,
    OperatorSet[] calldata operatorSets
  ) external view override returns (PendingFreeMagnitude[] memory) {}

  function isOperatorSlashable(
    address operator,
    OperatorSet memory operatorSet
  ) external view override returns (bool) {}

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

  function getTotalMagnitude(
    address operator,
    IStrategy strategy
  ) external view override returns (uint64) {}

  function calculateMagnitudeAllocationDigestHash(
    address operator,
    MagnitudeAllocation[] calldata allocations,
    bytes32 salt,
    uint256 expiry
  ) external view override returns (bytes32) {}

  function domainSeparator() external view override returns (bytes32) {}
}
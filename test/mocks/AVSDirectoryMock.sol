// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IAVSDirectory, OperatorSet} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";

contract AVSDirectoryMock is IAVSDirectory {
  function createOperatorSets(
    uint32[] calldata operatorSetIds
  ) external {}

  function becomeOperatorSetAVS() external  {}

  function migrateOperatorsToOperatorSets(
    address[] calldata operators,
    uint32[][] calldata operatorSetIds
  ) external {}

  function registerOperatorToOperatorSets(
    address operator,
    uint32[] calldata operatorSetIds,
    ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
  ) external {}

  function deregisterOperatorFromOperatorSets(
    address operator,
    uint32[] calldata operatorSetIds
  ) external {}

  function forceDeregisterFromOperatorSets(
    address operator,
    address avs,
    uint32[] calldata operatorSetIds,
    ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
  ) external {}

  function registerOperatorToAVS(
    address operator,
    ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
  ) external {}

  function deregisterOperatorFromAVS(address operator) external {}

  function updateAVSMetadataURI(
    string calldata metadataURI
  ) external {}

  function cancelSalt(bytes32 salt) external  {}

  function operatorSaltIsSpent(
    address operator,
    bytes32 salt
  ) external view returns (bool) {}

  function isMember(
    address operator,
    OperatorSet memory operatorSet
  ) external view returns (bool) {}

  function isOperatorSlashable(
    address operator,
    OperatorSet memory operatorSet
  ) external view returns (bool) {}

  function isOperatorSetAVS(
    address avs
  ) external view returns (bool) {}

  function isOperatorSet(
    address avs,
    uint32 operatorSetId
  ) external view returns (bool) {}

  function isOperatorSetBatch(
    OperatorSet[] calldata operatorSets
  ) external view returns (bool) {}

  function operatorSetsMemberOfAtIndex(
    address operator,
    uint256 index
  ) external view returns (OperatorSet memory) {}

  function operatorSetMemberAtIndex(
    OperatorSet memory operatorSet,
    uint256 index
  ) external view returns (address) {}

  function getOperatorSetsOfOperator(
    address operator,
    uint256 start,
    uint256 length
  ) external view returns (OperatorSet[] memory operatorSets) {}

  function getOperatorsInOperatorSet(
    OperatorSet memory operatorSet,
    uint256 start,
    uint256 length
  ) external view returns (address[] memory operators) {}

  function getNumOperatorsInOperatorSet(
    OperatorSet memory operatorSet
  ) external view  returns (uint256) {}

  function inTotalOperatorSets(
    address operator
  ) external view returns (uint256) {}

  function calculateOperatorAVSRegistrationDigestHash(
    address operator,
    address avs,
    bytes32 salt,
    uint256 expiry
  ) external view returns (bytes32) {}

  function calculateOperatorSetRegistrationDigestHash(
    address avs,
    uint32[] calldata operatorSetIds,
    bytes32 salt,
    uint256 expiry
  ) external view returns (bytes32) {}

  function calculateOperatorSetForceDeregistrationTypehash(
    address avs,
    uint32[] calldata operatorSetIds,
    bytes32 salt,
    uint256 expiry
  ) external view returns (bytes32) {}

  function OPERATOR_AVS_REGISTRATION_TYPEHASH()
    external
    view
    returns (bytes32)
  {}

  function OPERATOR_SET_REGISTRATION_TYPEHASH()
    external
    view
    returns (bytes32)
  {}

  function operatorSetStatus(
    address avs,
    address operator,
    uint32 operatorSetId
  )
    external
    view
    returns (bool registered, uint32 lastDeregisteredTimestamp)
  {}

  function getNumOperatorSetsOfOperator(
    address operator
  ) external view returns (uint256) {}

  function getStrategiesInOperatorSet(
    OperatorSet memory operatorSet
  ) external view returns (IStrategy[] memory) {}

  function initialize(
    address initialOwner,
    IPauserRegistry _pauserRegistry,
    uint256 initialPausedStatus
  ) external {}

  function removeStrategiesFromOperatorSet(
    uint32 operatorSetId,
    IStrategy[] calldata strategies
  ) external {}

   function addStrategiesToOperatorSet(uint32 operatorSetId, IStrategy[] calldata strategies) external {}
}

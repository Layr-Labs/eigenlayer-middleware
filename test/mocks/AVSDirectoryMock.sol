// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";

contract AVSDirectoryMock is IAVSDirectory {
    function initialize(address initialOwner, uint256 initialPausedStatus) external {}

    function createOperatorSets(
        uint32[] calldata operatorSetIds
    ) external {}

    function deregisterOperatorFromOperatorSets(
        address operator,
        uint32[] calldata operatorSetIds
    ) external {}

    function addStrategiesToOperatorSet(
        uint32 operatorSetId,
        IStrategy[] calldata strategies
    ) external {}

    function removeStrategiesFromOperatorSet(
        uint32 operatorSetId,
        IStrategy[] calldata strategies
    ) external {}

    function updateAVSMetadataURI(
        string calldata metadataURI
    ) external {}

    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external {}

    function deregisterOperatorFromAVS(
        address operator
    ) external {}

    function operatorSetsEnabled(
        address avs
    ) external view returns (bool) {}

    function isOperatorSet(address avs, uint32 operatorSetId) external view returns (bool) {}

    function calculateOperatorAVSRegistrationDigestHash(
        address operator,
        address avs,
        bytes32 salt,
        uint256 expiry
    ) external view returns (bytes32) {}

    function initialize(
        address initialOwner,
        IPauserRegistry _pauserRegistry,
        uint256 initialPausedStatus
    ) external {}

    function getStrategiesInOperatorSet(
        OperatorSet memory operatorSet
    ) external view returns (IStrategy[] memory strategies) {}

    function isMember(
        address operator,
        OperatorSet memory operatorSet
    ) external view returns (bool) {}
}

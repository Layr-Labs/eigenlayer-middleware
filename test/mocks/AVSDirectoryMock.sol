// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {ISemVerMixin} from "eigenlayer-contracts/src/contracts/interfaces/ISemVerMixin.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";

contract AVSDirectoryMock is IAVSDirectory {
    function initialize(address initialOwner, uint256 initialPausedStatus) external {}

    function createOperatorSets(
        uint32[] calldata operatorSetIds
    ) external {}

    function becomeOperatorSetAVS() external {}

    function migrateOperatorsToOperatorSets(
        address[] calldata operators,
        uint32[][] calldata operatorSetIds
    ) external {}

    function registerOperatorToOperatorSets(
        address operator,
        uint32[] calldata operatorSetIds,
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature
    ) external {}

    function forceDeregisterFromOperatorSets(
        address operator,
        address avs,
        uint32[] calldata operatorSetIds,
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature
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

    function cancelSalt(
        bytes32 salt
    ) external {}

    function registerOperatorToAVS(
        address operator,
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature
    ) external {}

    function deregisterOperatorFromAVS(
        address operator
    ) external {}

    function operatorSaltIsSpent(address operator, bytes32 salt) external view returns (bool) {}

    function operatorSetsEnabled(
        address avs
    ) external view returns (bool) {}

    function isOperatorSet(address avs, uint32 operatorSetId) external view returns (bool) {}

    function getNumOperatorSetsOfOperator(
        address operator
    ) external view returns (uint256) {}

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

    function OPERATOR_AVS_REGISTRATION_TYPEHASH() external view returns (bytes32) {}

    function OPERATOR_SET_REGISTRATION_TYPEHASH() external view returns (bytes32) {}

    function operatorSetStatus(
        address avs,
        address operator,
        uint32 operatorSetId
    ) external view returns (bool registered, uint32 lastDeregisteredTimestamp) {}

    function initialize(
        address initialOwner,
        IPauserRegistry _pauserRegistry,
        uint256 initialPausedStatus
    ) external {}

    function operatorSetMemberAtIndex(
        OperatorSet memory operatorSet,
        uint256 index
    ) external view returns (address) {}

    function getOperatorsInOperatorSet(
        OperatorSet memory operatorSet,
        uint256 start,
        uint256 length
    ) external view returns (address[] memory operators) {}

    function getStrategiesInOperatorSet(
        OperatorSet memory operatorSet
    ) external view returns (IStrategy[] memory strategies) {}

    function getNumOperatorsInOperatorSet(
        OperatorSet memory operatorSet
    ) external view returns (uint256) {}

    function isMember(
        address operator,
        OperatorSet memory operatorSet
    ) external view returns (bool) {}

    function isOperatorSlashable(
        address operator,
        OperatorSet memory operatorSet
    ) external view returns (bool) {}

    function isOperatorSetBatch(
        OperatorSet[] calldata operatorSets
    ) external view returns (bool) {}

    /**
     * @notice Returns the domain separator used for EIP-712 signatures
     * @return The domain separator
     */
    function domainSeparator() external pure returns (bytes32) {
        return bytes32(0);
    }

    /**
     * @notice Returns the version of the contract
     * @return The version string
     */
    function version() external pure returns (string memory) {
        return "v0.0.1";
    }
}

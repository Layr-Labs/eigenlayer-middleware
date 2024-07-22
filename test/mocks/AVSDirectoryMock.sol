// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IAVSDirectory, ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";

contract AVSDirectoryMock is IAVSDirectory {
    function registerOperatorToOperatorSets(
        address operator,
        uint32[] calldata operatorSetIds,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external {}

    function deregisterFromAVSOperatorSets(
        address avs,
        uint32[] calldata operatorSetIds
    ) external {}

    function deregisterOperatorFromOperatorSets(
        address operator,
        uint32[] calldata operatorSetIds
    ) external {}

    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external {}

    function deregisterOperatorFromAVS(address operator) external {}

    function updateAVSMetadataURI(
        string calldata metadataURI
    ) external {}

    function cancelSalt(bytes32 salt) external {}

    function operatorSaltIsSpent(
        address operator,
        bytes32 salt
    ) external view returns (bool) {}

    function memberInfo(
        address avs,
        address operator
    )
        external
        view
        returns (uint248 inTotalSets, bool isLegacyOperator)
    {}

    function isMember(
        address avs,
        address operator,
        uint32 operatorSetId
    ) external view returns (bool) {}

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

    function domainSeparator() external view returns (bytes32) {}

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

    function becomeOperatorSetAVS() external {}

    function calculateOperatorSetForceDeregistrationTypehash(
        address avs,
        uint32[] calldata operatorSetIds,
        bytes32 salt,
        uint256 expiry
    ) external view returns (bytes32) {}

    function createOperatorSets(uint32[] calldata operatorSetIds) external {}

    function forceDeregisterFromOperatorSets(
        address avs,
        uint32[] calldata operatorSetIds
    ) external {}

    function migrateOperatorsToOperatorSets(
        address[] calldata operators,
        uint32[][] calldata operatorSetIds
    ) external {}

    function forceDeregisterFromOperatorSets(
        address operator,
        address avs,
        uint32[] calldata operatorSetIds,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external {}

}

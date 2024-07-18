// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IAVSDirectory, ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

contract AVSDirectoryMock is IAVSDirectory {
    // Mapping to track operator status in operator sets
    // Mapping structure: avs => operator => operatorSetId => isRegistered
    mapping(address => mapping(address => mapping(uint32 => bool)))
        public operatorInSet;

    // Mapping to track total registered operator sets for an operator
    // Mapping structure: avs => operator => totalRegisteredSets
    mapping(address => mapping(address => uint256)) public totalRegisteredSets;

    function registerOperatorToOperatorSets(
        address operator,
        uint32[] calldata operatorSetIds,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external {
        address avs = msg.sender;
        for (uint256 i = 0; i < operatorSetIds.length; i++) {
            if (!operatorInSet[avs][operator][operatorSetIds[i]]) {
                operatorInSet[avs][operator][operatorSetIds[i]] = true;
                totalRegisteredSets[avs][operator]++;
            }
        }
    }

    function deregisterFromAVSOperatorSets(
        address avs,
        uint32[] calldata operatorSetIds
    ) external {
        for (uint256 i = 0; i < operatorSetIds.length; i++) {
            if (operatorInSet[avs][msg.sender][operatorSetIds[i]]) {
                operatorInSet[avs][msg.sender][operatorSetIds[i]] = false;
                totalRegisteredSets[avs][msg.sender]--;
            }
        }
    }

    function deregisterOperatorFromOperatorSets(
        address operator,
        uint32[] calldata operatorSetIds
    ) external {
        address avs = msg.sender;
        for (uint256 i = 0; i < operatorSetIds.length; i++) {
            if (operatorInSet[avs][operator][operatorSetIds[i]]) {
                operatorInSet[avs][operator][operatorSetIds[i]] = false;
                totalRegisteredSets[avs][operator]--;
            }
        }
    }

    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external {}

    function deregisterOperatorFromAVS(address operator) external {}

    function updateAVSMetadataURI(string calldata metadataURI) external {}

    function cancelSalt(bytes32 salt) external {}

    function operatorSaltIsSpent(
        address operator,
        bytes32 salt
    ) external view returns (bool) {}

    function memberInfo(
        address avs,
        address operator
    ) external view returns (uint248 inTotalSets, bool isLegacyOperator) {
        return (uint248(totalRegisteredSets[avs][operator]), false);
    }

    function isMember(
        address avs,
        address operator,
        uint32 operatorSetId
    ) external view returns (bool) {
        return operatorInSet[avs][operator][operatorSetId];
    }

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
}

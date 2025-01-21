// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IAVSDirectory, ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";

contract AVSDirectoryMock is IAVSDirectory {
    mapping(address => mapping(bytes32 => bool)) public operatorSaltIsSpentMapping;
    
    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external {}

    function deregisterOperatorFromAVS(address operator) external {}

    function updateAVSMetadataURI(string calldata metadataURI) external {}

    function operatorSaltIsSpent(address operator, bytes32 salt) external view returns (bool) {
        return operatorSaltIsSpentMapping[operator][salt];
    }

    function calculateOperatorAVSRegistrationDigestHash(
        address operator,
        address avs,
        bytes32 salt,
        uint256 expiry
    ) external view returns (bytes32) {}

    function OPERATOR_AVS_REGISTRATION_TYPEHASH() external view returns (bytes32) {}

    function cancelSalt(bytes32 salt) external {}

    function domainSeparator() external view returns (bytes32) {}
}
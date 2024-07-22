// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {console} from "forge-std/Test.sol";
import {IAVSDirectory, ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";

contract AVSDirectoryMock is IAVSDirectory {
    mapping(address => bool) public isOperatorSetAVS;
    mapping(address => mapping(uint32 => bool)) public avsOperatorSets;
    mapping(address => mapping(address => mapping(uint32 => bool))) public avsOperatorStatusOperatorSet;
    mapping(address => mapping(address => IAVSDirectory.OperatorAVSRegistrationStatus)) public avsOperatorStatus;

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
        ISignatureUtils.SignatureWithSaltAndExpiry memory 
    ) external {
        avsOperatorStatus[msg.sender][operator] = IAVSDirectory.OperatorAVSRegistrationStatus.REGISTERED;
    }

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
    ) external view returns (bool) {
        return avsOperatorStatusOperatorSet[avs][operator][operatorSetId];
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

    function becomeOperatorSetAVS() external {
        isOperatorSetAVS[msg.sender] = true;
    }

    function calculateOperatorSetForceDeregistrationTypehash(
        address avs,
        uint32[] calldata operatorSetIds,
        bytes32 salt,
        uint256 expiry
    ) external view returns (bytes32) {}

    function createOperatorSets(uint32[] calldata operatorSetIds) external {
        require(isOperatorSetAVS[msg.sender], "AVS is not an operator set AVS");
        for (uint256 i = 0; i < operatorSetIds.length; i++) {
            avsOperatorSets[msg.sender][operatorSetIds[i]] = true;
        }
    }

    function forceDeregisterFromOperatorSets(
        address avs,
        uint32[] calldata operatorSetIds
    ) external {}

    function migrateOperatorsToOperatorSets(
        address[] calldata operators,
        uint32[][] calldata operatorSetIds
    ) external {
        console.log("HERE");
        require(isOperatorSetAVS[msg.sender], "AVS is not registered as an operator set AVS");
        require(operators.length == operatorSetIds.length, "Mismatched input lengths");

        for (uint256 i = 0; i < operators.length; i++) {
            address operator = operators[i];
            for (uint256 j = 0; j < operatorSetIds[i].length;j++){
                // Check that the operatorSetId exists for the AVS
                require(
                    avsOperatorSets[msg.sender][operatorSetIds[i][j]],
                    "Operator set ID does not exist for the AVS"
                );
                console.log(operator, "AVSDirectory:operator");

                // Enable the operator for the operator set
                avsOperatorStatusOperatorSet[msg.sender][operator][operatorSetIds[i][j]] = true;
            }
        }
    }

    function forceDeregisterFromOperatorSets(
        address operator,
        address avs,
        uint32[] calldata operatorSetIds,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external {}

}

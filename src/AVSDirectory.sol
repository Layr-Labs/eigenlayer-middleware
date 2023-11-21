// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "src/interfaces/IAVSDirectory.sol";

contract AVSDirectory is IAVSDirectory {
    // Storage
    mapping(address => mapping(address => bool)) public registeredWithAVS;

    constructor() {}

    /**
     * @notice Called by AVSs to register an operator with the AVS.
     * @param operator The address of the operator to register.
     */
    function registerOperatorWithAVS(address operator) external {
        require(!registeredWithAVS[msg.sender][operator], "AVSDirectory: operator already registered");
        registeredWithAVS[msg.sender][operator] = true;
        emit OperatorRegistrationStatusUpdated(operator, msg.sender, OperatorRegistrationStatus.REGISTERED);
    }

    /**
     * @notice Called by AVSs to deregister an operator with the AVS.
     * @param operator The address of the operator to deregister.
     */
    function deregisterOperatorFromAVS(address operator) external {
        require(registeredWithAVS[msg.sender][operator], "AVSDirectory: operator not registered");
        registeredWithAVS[msg.sender][operator] = false;
        emit OperatorRegistrationStatusUpdated(operator, msg.sender, OperatorRegistrationStatus.DEREGISTERED);
    }

    function updateAVSMetadataURI(string calldata metadataURI) external {
        emit AVSMetadataURIUpdated(msg.sender, metadataURI);
    }

    function addStrategiesToAVS(IVoteWeigher.StrategyAndWeightingMultiplier[] memory strategiesToAdd, uint8 quorumNumber) external {
        for (uint256 i = 0; i < strategiesToAdd.length; i++) {
            emit StrategyAddedToAVS(msg.sender, address(strategiesToAdd[i].strategy), quorumNumber);
        }
    }

    function removeStrategiesFromAVS(IVoteWeigher.StrategyAndWeightingMultiplier[] memory strategiesToRemove, uint8 quorumNumber) external {
        for (uint256 i = 0; i < strategiesToRemove.length; i++) {
            emit StrategyRemovedFromAVS(msg.sender, address(strategiesToRemove[i].strategy), quorumNumber);
        }
    }

    function addOperatorToAVSQuorums(address operator, bytes memory quorumNumbers) external {
        for (uint8 quorumNumbersIndex = 0; quorumNumbersIndex < quorumNumbers.length; quorumNumbersIndex++) {
            uint8 quorumNumber = uint8(quorumNumbers[quorumNumbersIndex]);
            emit OperatorAddedToAVSQuorum(msg.sender, operator, quorumNumber);
        }
    }

    function removeOperatorFromAVSQuorums(address operator, bytes memory quorumNumbers) external {
        for (uint8 quorumNumbersIndex = 0; quorumNumbersIndex < quorumNumbers.length; quorumNumbersIndex++) {
            uint8 quorumNumber = uint8(quorumNumbers[quorumNumbersIndex]);
            emit OperatorRemovedFromAVSQuorum(msg.sender, operator, quorumNumber);
        }
    }
}


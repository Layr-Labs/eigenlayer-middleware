// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {ECDSARegistryCoordinator} from "./ECDSARegistryCoordinator.sol";
import {ECDSAStakeRegistry} from "./ECDSAStakeRegistry.sol";
import {IECDSAIndexRegistry} from "./IECDSAIndexRegistry.sol";

import {BitmapUtils} from "../libraries/BitmapUtils.sol";

/**
 * @title ECDSAOperatorStateRetriever with view functions that allow to retrieve the state of an AVSs registry system.
 * @author Layr Labs Inc.
 */
contract ECDSAOperatorStateRetriever {
    struct Operator {
        address operator;
        address operatorId;
        uint96 stake;
    }

    /**
     * @notice This function is intended to to be called by AVS operators every time a new task is created (i.e.)
     * the AVS coordinator makes a request to AVS operators. Since all of the crucial information is kept onchain,
     * operators don't need to run indexers to fetch the data.
     * @param registryCoordinator is the registry coordinator to fetch the AVS registry information from
     * @param operatorId the id of the operator to fetch the quorums lists
     * @return 1) the quorumBitmap of the operator at the given blockNumber
     *         2) 2d array of Operator structs. For each quorum the provided operator
     *            was a part of at `blockNumber`, an ordered list of operators.
     */
    function getOperatorState(
        ECDSARegistryCoordinator registryCoordinator,
        address operatorId,
        uint32 blockNumber
    ) external view returns (uint256, Operator[][] memory) {
        address[] memory operatorIds = new address[](1);
        operatorIds[0] = operatorId;
        uint256 index = registryCoordinator.getQuorumBitmapIndicesAtBlockNumber(
            blockNumber,
            operatorIds
        )[0];

        uint256 quorumBitmap = registryCoordinator
            .getQuorumBitmapAtBlockNumberByIndex(
                operatorId,
                blockNumber,
                index
            );

        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(
            quorumBitmap
        );

        return (
            quorumBitmap,
            getOperatorState(registryCoordinator, quorumNumbers, blockNumber)
        );
    }

    /**
     * @notice returns the ordered list of operators (id and stake) for each quorum. The AVS coordinator
     * may call this function directly to get the operator state for a given block number
     * @param registryCoordinator is the registry coordinator to fetch the AVS registry information from
     * @param quorumNumbers are the ids of the quorums to get the operator state for
     * @return 2d array of Operators. For each quorum, an ordered list of Operators
     */
    function getOperatorState(
        ECDSARegistryCoordinator registryCoordinator,
        bytes memory quorumNumbers,
        uint32 blockNumber
    ) public view returns (Operator[][] memory) {
        ECDSAStakeRegistry stakeRegistry = registryCoordinator.stakeRegistry();
        IECDSAIndexRegistry indexRegistry = registryCoordinator.indexRegistry();

        Operator[][] memory operators = new Operator[][](quorumNumbers.length);
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            address[] memory operatorIds = indexRegistry
                .getOperatorListAtBlockNumber(quorumNumber, blockNumber);
            operators[i] = new Operator[](operatorIds.length);
            for (uint256 j = 0; j < operatorIds.length; j++) {
                operators[i][j] = Operator({
                    operator: registryCoordinator.getOperatorFromId(
                        operatorIds[j]
                    ),
                    operatorId: operatorIds[j],
                    stake: stakeRegistry.getStakeAtBlockNumber(
                        operatorIds[j],
                        quorumNumber,
                        blockNumber
                    )
                });
            }
        }

        return operators;
    }
}

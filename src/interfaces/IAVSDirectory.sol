// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "src/interfaces/IVoteWeigher.sol";

interface IAVSDirectory {
    /// @notice Enum representing the status of an operator's registration with the AVS
    enum OperatorRegistrationStatus {
        DEREGISTERED,
        REGISTERED
    }

    // Events
    /// @notice Emitted when an operator's registration status for an AVS is updated
    event OperatorRegistrationStatusUpdated(address indexed operator, address indexed avs, OperatorRegistrationStatus status);

    /**
     * @notice Emitted when @param operator indicates that they are updating their MetadataURI string
     * @dev Note that these strings are *never stored in storage* and are instead purely emitted in events for off-chain indexing
     */
    event AVSMetadataURIUpdated(address indexed avs, string metadataURI);  

    event StrategyAddedToAVS(address indexed avs, address indexed strategy, uint8 quorumNumber);

    event StrategyRemovedFromAVS(address indexed avs, address indexed strategy, uint8 quorumNumber);

    event OperatorAddedToAVSQuorum(address indexed avs, address indexed operator, uint8 quorumNumber);

    event OperatorRemovedFromAVSQuorum(address indexed avs, address indexed operator, uint8 quorumNumber);

    /**
     * @notice Called by AVSs to register an operator with the AVS.
     * @param operator The address of the operator to register.
     */
    function registerOperatorWithAVS(address operator) external;

    /**
     * @notice Called by AVSs to deregister an operator with the AVS.
     * @param operator The address of the operator to deregister.
     */
    function deregisterOperatorFromAVS(address operator) external;

    /**
     * @notice Called by an AVS to emit an `OperatorMetadataURIUpdated` event indicating the information has updated.
     * @param metadataURI The URI for metadata associated with an AVS
     * @dev Note that the `metadataURI` is *never stored * and is only emitted in the `OperatorMetadataURIUpdated` event
     */
    function updateAVSMetadataURI(string calldata metadataURI) external;  

    /**
     * @notice Called by an AVS' StakeRegistry contract to add strategies to the AVS
     * @param strategiesToAdd The strategies to add to the AVS
     */
    function addStrategiesToAVS(IVoteWeigher.StrategyAndWeightingMultiplier[] memory strategiesToAdd, uint8 quorumNumber) external;

    /**
     * @notice Called by an AVS' StakeRegistry contract to remove strategies from the AVS
     * @param strategiesToRemove The strategies to remove from the AVS
     */
    function removeStrategiesFromAVS(IVoteWeigher.StrategyAndWeightingMultiplier[] memory strategiesToRemove, uint8 quorumNumber) external;

    /**
     * @notice Called by an AVS' StakeRegistry contract to add an operator to the AVS' quorums
     * @param operator The operator to add to the AVS' quorums
     * @param quorumNumbers The quorums to add the operator to
     */
    function addOperatorToAVSQuorums(address operator, bytes calldata quorumNumbers) external;

    /**
     * @notice Called by an AVS' StakeRegistry contract to remove an operator from the AVS' quorums
     * @param operator The operator to remove from the AVS' quorums
     * @param quorumNumbers The quorums to remove the operator from
     */
    function removeOperatorFromAVSQuorums(address operator, bytes calldata quorumNumbers) external;
}
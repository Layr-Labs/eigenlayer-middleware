// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IStrategy} from "./IOperatorSetManager.sol"; // should be later changed to be import from core
import {IServiceManagerUI} from "./IServiceManagerUI.sol";

/**
 * @title Minimal interface for a ServiceManager-type contract that forms the single point for an AVS to push updates to EigenLayer
 * @author Layr Labs, Inc.
 */
interface IServiceManager is IServiceManagerUI {
    /**
     * @notice Creates a new rewards submission to the EigenLayer RewardsCoordinator contract, to be split amongst the
     * set of stakers delegated to operators who are registered to this `avs`
     * @param rewardsSubmissions The rewards submissions being created
     * @dev Only callabe by the permissioned rewardsInitiator address
     * @dev The duration of the `rewardsSubmission` cannot exceed `MAX_REWARDS_DURATION`
     * @dev The tokens are sent to the `RewardsCoordinator` contract
     * @dev Strategies must be in ascending order of addresses to check for duplicates
     * @dev This function will revert if the `rewardsSubmission` is malformed,
     * e.g. if the `strategies` and `weights` arrays are of non-equal lengths
     */
    function createAVSRewardsSubmission(
        IRewardsCoordinator.RewardsSubmission[] calldata rewardsSubmissions
    ) external;

    /// TODO: natspec
    function addStrategiesToOperatorSet(
        uint32 operatorSetID,
        IStrategy[] calldata strategies
    ) external;

    /// TODO: natspec
    function removeStrategiesFromOperatorSet(
        uint32 operatorSetID,
        IStrategy[] calldata strategies
    ) external;

    /// @notice migrates all existing operators and strategies to operator sets
    function migrateStrategiesToOperatorSets() external;

    /**
     * @notice the operator needs to provide a signature over the operatorSetIds they will be registering
     * for. This can be called externally by getOperatorSetIds
     */
    function migrateOperatorToOperatorSets(
        ISignatureUtils.SignatureWithSaltAndExpiry memory signature
    ) external;

    /**
     * @notice Called by this AVS's RegistryCoordinator to register an operator for its registering operatorSets
     *
     * @param operator the address of the operator to be added to the operator set
     * @param quorumNumbers quorums/operatorSetIds to add the operator to
     * @param signature the signature of the operator on their intent to register
     * @dev msg.sender is used as the AVS
     * @dev operator must not have a pending a deregistration from the operator set
     * @dev if this is the first operator set in the AVS that the operator is
     * registering for, a OperatorAVSRegistrationStatusUpdated event is emitted with
     * a REGISTERED status
     */
    function registerOperatorToOperatorSets(
        address operator,
        bytes calldata quorumNumbers,
        ISignatureUtils.SignatureWithSaltAndExpiry memory signature
    ) external;

    /**
     * @notice Called by this AVS's RegistryCoordinator to deregister an operator for its operatorSets
     *
     * @param operator the address of the operator to be removed from the
     * operator set
     * @param quorumNumbers the quorumNumbers/operatorSetIds to deregister the operator for
     *
     * @dev msg.sender is used as the AVS
     * @dev operator must be registered for msg.sender AVS and the given
     * operator set
     * @dev if this removes operator from all operator sets for the msg.sender AVS
     * then an OperatorAVSRegistrationStatusUpdated event is emitted with a DEREGISTERED
     * status
     */
    function deregisterOperatorFromOperatorSets(
        address operator,
        bytes calldata quorumNumbers
    ) external;

    // EVENTS
    event RewardsInitiatorUpdated(address prevRewardsInitiator, address newRewardsInitiator);
}

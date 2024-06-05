// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IOperatorSetManager, IStrategy} from "./IOperatorSetManager.sol"; // should be later changed to be import from core
import {IServiceManagerUI} from "./IServiceManagerUI.sol";

/**
 * @title Minimal interface for a ServiceManager-type contract that forms the single point for an AVS to push updates to EigenLayer
 * @author Layr Labs, Inc.
 */
interface IServiceManager is IServiceManagerUI {

    /// EVENTS

    event RewardsInitiatorUpdated(address prevRewardsInitiator, address newRewardsInitiator);
    event OperatorSetStrategiesMigrated(uint32 operatorSetId, IStrategy[] strategies);
    event OperatorMigratedToOperatorSets(address operator, uint32[] indexed operatorSetIds);

    /// EXTERNAL - STATE MODIFYING

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

    
    /**
     * @notice called by the AVS StakeRegistry whenever a new IStrategy
     * is added to a quorum/operatorSet
     * @dev calls operatorSetManager.addStrategiesToOperatorSet()
     */
    function addStrategiesToOperatorSet(
        uint32 operatorSetID,
        IStrategy[] calldata strategies
    ) external;

    /**
     * @notice called by the AVS StakeRegistry whenever a new IStrategy
     * is removed from a quorum/operatorSet
     * @dev calls operatorSetManager.removeStrategiesFromOperatorSet()
     */
    function removeStrategiesFromOperatorSet(
        uint32 operatorSetID,
        IStrategy[] calldata strategies
    ) external;

    /**
     * @notice One-time call that migrates all existing strategies for each quorum to their respective operator sets
     * Note: a separate migration per operator must be performed to migrate an existing operator to the operator set
     * See migrateOperatorToOperatorSets() below
     * @dev calls operatorSetManager.addStrategiesToOperatorSet()
     */
    function migrateStrategiesToOperatorSets() external;

    /**
     * @notice One-time call to migrate an existing operator to the respective operator sets.
     * The operator needs to provide a signature over the operatorSetIds they are currently registered
     * for. This can be retrieved externally by calling getOperatorSetIds.
     * @param operator the address of the operator to be migrated
     * @param signature the signature of the operator on their intent to migrate
     * @dev calls operatorSetManager.registerOperatorToOperatorSets()
     */
    function migrateOperatorToOperatorSets(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory signature
    ) external;

    /**
     * @notice Once strategies have been migrated and operators have been migrated to operator sets.
     * The ServiceManager owner can eject any operators that have yet to completely migrate fully to operator sets.
     * This final step of the migration process will ensure the full migration of all operators to operator sets.
     * @param operators The list of operators to eject for the given OperatorSet
     * @param operatorSetId This AVS's operatorSetId to eject operators from
     * @dev The RegistryCoordinator MUST set this ServiceManager contract to be the ejector address for this call to succeed
     */
    function ejectNonmigratedOperators(
        address[] calldata operators,
        uint32 operatorSetId
    ) external;

    /**
     * @notice Called by this AVS's RegistryCoordinator to register an operator for its registering operatorSets
     *
     * @param operator the address of the operator to be added to the operator set
     * @param quorumNumbers quorums/operatorSetIds to add the operator to
     * @param signature the signature of the operator on their intent to register
     * @dev msg.sender should be the RegistryCoordinator
     * @dev calls operatorSetManager.registerOperatorToOperatorSets()
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
     * @dev msg.sender should be the RegistryCoordinator
     * @dev operator must be registered for the given operator sets
     * @dev calls operatorSetManager.deregisterOperatorFromOperatorSets()
     */
    function deregisterOperatorFromOperatorSets(
        address operator,
        bytes calldata quorumNumbers
    ) external;

    /// VIEW

    /// @notice Returns the operator set IDs for the given operator address by querying the RegistryCoordinator
    function getOperatorSetIds(address operator) external view returns (uint32[] memory);
}

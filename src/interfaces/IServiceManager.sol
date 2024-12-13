// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IServiceManagerUI} from "./IServiceManagerUI.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IAllocationManagerTypes} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";


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
    function createAVSRewardsSubmission(IRewardsCoordinator.RewardsSubmission[] calldata rewardsSubmissions) external;

    function createOperatorSets(IAllocationManager.CreateSetParams[] memory params) external;

    function addStrategyToOperatorSet(uint32 operatorSetId, IStrategy[] memory strategies) external;

    function removeStrategiesFromOperatorSet(uint32 operatorSetId, IStrategy[] memory strategies) external;

    /**
     * @notice Sets the AVS registrar address in the AllocationManager
     * @param registrar The new AVS registrar address
     * @dev Only callable by the registry coordinator
     */
    function setAVSRegistrar(IAVSRegistrar registrar) external;

    /**
     * @notice Forwards a call to EigenLayer's AVSDirectory contract to deregister an operator from operator sets
     * @param operator The address of the operator to deregister.
     * @param operatorSetIds The IDs of the operator sets.
     */
    function deregisterOperatorFromOperatorSets(address operator, uint32[] calldata operatorSetIds) external;

    function slashOperator(IAllocationManagerTypes.SlashingParams memory params) external;

    // EVENTS
    event RewardsInitiatorUpdated(address prevRewardsInitiator, address newRewardsInitiator);
    event SlasherUpdated(address prevSlasher, address newSlasher);
    event SlasherProposed(address newSlasher, uint256 slasherProposalTimestamp);
}

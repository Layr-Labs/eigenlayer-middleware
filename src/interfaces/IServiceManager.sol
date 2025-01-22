// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {IRewardsCoordinator} from
    "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IServiceManagerUI} from "./IServiceManagerUI.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IAllocationManagerTypes} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";

interface IServiceManagerErrors {
    /// @dev Thrown when a function is called by an address that is not the RegistryCoordinator
    error OnlyRegistryCoordinator();
    /// @dev Thrown when a function is called by an address that is not the RewardsInitiator
    error OnlyRewardsInitiator();
    /// @dev Thrown when a function is called by an address that is not the Slasher
    error OnlyStakeRegistry();
    /// @dev Thrown when a function is called by an address that is not the Slasher
    error OnlySlasher();
    /// @dev Thrown when a slashing proposal delay has not been met yet.
    error DelayPeriodNotPassed();
}

/**
 * @title Minimal interface for a ServiceManager-type contract that forms the single point for an AVS to push updates to EigenLayer
 * @author Layr Labs, Inc.
 */
interface IServiceManager is IServiceManagerUI, IServiceManagerErrors {
    // EVENTS
    event RewardsInitiatorUpdated(address prevRewardsInitiator, address newRewardsInitiator);

    /**
     * @notice Creates a new rewards submission to the EigenLayer RewardsCoordinator contract, to be split amongst the
     * set of stakers delegated to operators who are registered to this `avs`
     * @param rewardsSubmissions The rewards submissions being created
     * @dev Only callable by the permissioned rewardsInitiator address
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
     *
     *                             PERMISSIONCONTROLLER FUNCTIONS
     *
     */
    /**
     * @notice Calls `addPendingAdmin` on the `PermissionController` contract
     * with `account` being the address of this contract.
     * @param admin The address of the admin to add
     * @dev Only callable by the owner of the contract
     */
    function addPendingAdmin(
        address admin
    ) external;

    /**
     * @notice Calls `removePendingAdmin` on the `PermissionController` contract
     * with `account` being the address of this contract.
     * @param pendingAdmin The address of the pending admin to remove
     * @dev Only callable by the owner of the contract
     */
    function removePendingAdmin(
        address pendingAdmin
    ) external;

    /**
     * @notice Calls `removeAdmin` on the `PermissionController` contract
     * with `account` being the address of this contract.
     * @param admin The address of the admin to remove
     * @dev Only callable by the owner of the contract
     */
    function removeAdmin(
        address admin
    ) external;

    /**
     * @notice Calls `setAppointee` on the `PermissionController` contract
     * with `account` being the address of this contract.
     * @param appointee The address of the appointee to set
     * @param target The address of the target to set the appointee for
     * @param selector The function selector to set the appointee for
     * @dev Only callable by the owner of the contract
     */
    function setAppointee(address appointee, address target, bytes4 selector) external;

    /**
     * @notice Calls `removeAppointee` on the `PermissionController` contract
     * with `account` being the address of this contract.
     * @param appointee The address of the appointee to remove
     * @param target The address of the target to remove the appointee for
     * @param selector The function selector to remove the appointee for
     * @dev Only callable by the owner of the contract
     */
    function removeAppointee(address appointee, address target, bytes4 selector) external;
}

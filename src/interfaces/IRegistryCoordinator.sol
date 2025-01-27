// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    ISlashingRegistryCoordinator,
    ISlashingRegistryCoordinatorErrors,
    ISlashingRegistryCoordinatorEvents,
    ISlashingRegistryCoordinatorTypes
} from "./ISlashingRegistryCoordinator.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IBLSApkRegistryTypes} from "./IBLSApkRegistry.sol";
import {IServiceManager} from "./IServiceManager.sol";

interface IRegistryCoordinatorErrors is ISlashingRegistryCoordinatorErrors {
    /// @notice Thrown when operator sets mode is already enabled.
    error OperatorSetsAlreadyEnabled();
    /// @notice Thrown when a quorum is an operator set quorum.
    error OperatorSetQuorum();
    /// @notice Thrown when M2 quorums are already disabled.
    error M2QuorumsAlreadyDisabled();
}

interface IRegistryCoordinatorTypes is ISlashingRegistryCoordinatorTypes {}

interface IRegistryCoordinatorEvents is
    ISlashingRegistryCoordinatorEvents,
    IRegistryCoordinatorTypes
{
    /**
     * @notice Emitted when operator sets mode is enabled.
     * @dev Emitted in enableOperatorSets().
     */
    event OperatorSetsEnabled();

    /**
     * @notice Emitted when M2 quorums are disabled.
     * @dev Emitted in disableM2QuorumRegistration().
     */
    event M2QuorumsDisabled();
}

interface IRegistryCoordinator is
    IRegistryCoordinatorErrors,
    IRegistryCoordinatorEvents,
    ISlashingRegistryCoordinator
{
    /**
     * @notice Reference to the ServiceManager contract.
     * @return The ServiceManager contract interface.
     * @dev This is only relevant for Pre-Slashing AVSs
     */
    function serviceManager() external view returns (IServiceManager);

    /// ACTIONS

    /**
     * @notice Registers an operator for service in specified quorums. If any quorum exceeds its maximum
     * operator capacity after the operator is registered, this method will fail.
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being registered for AVSDirectory.
     * @param socket is the socket of the operator (typically an IP address).
     * @param params contains the G1 & G2 public keys of the operator, and a signature proving their ownership.
     * @param operatorSignature is the signature of the operator used by the AVS to register the operator in the delegation manager.
     * @dev `params` is ignored if the caller has previously registered a public key.
     * @dev `operatorSignature` is ignored if the operator's status is already REGISTERED.
     * @dev This function registers operators to the AVSDirectory using the M2-registration pathway.
     */
    function registerOperator(
        bytes memory quorumNumbers,
        string memory socket,
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory params,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external;

    /**
     * @notice Registers an operator while replacing existing operators in full quorums. If any quorum reaches its maximum operator
     * capacity, `operatorKickParams` is used to replace an old operator with the new one.
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being registered for AVSDirectory.
     * @param socket is the socket of the operator (typically an IP address).
     * @param params contains the G1 & G2 public keys of the operator, and a signature proving their ownership.
     * @param operatorKickParams used to determine which operator is removed to maintain quorum capacity as the
     * operator registers for quorums.
     * @param churnApproverSignature is the signature of the churnApprover over the `operatorKickParams`.
     * @param operatorSignature is the signature of the operator used by the AVS to register the operator in the delegation manager.
     * @dev `params` is ignored if the caller has previously registered a public key.
     * @dev `operatorSignature` is ignored if the operator's status is already REGISTERED.
     * @dev This function registers operators to the AVSDirectory using the M2-registration pathway.
     */
    function registerOperatorWithChurn(
        bytes calldata quorumNumbers,
        string memory socket,
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory params,
        OperatorKickParam[] memory operatorKickParams,
        ISignatureUtils.SignatureWithSaltAndExpiry memory churnApproverSignature,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external;

    /**
     * @notice Deregisters the caller from one or more quorums. The operator will be removed from all registry contracts
     * and their quorum bitmap will be updated accordingly. If the operator is deregistered from all quorums, their status
     * will be updated to DEREGISTERED.
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being deregistered from.
     * @dev Will revert if operator is not currently registered for any of the specified quorums.
     * @dev This function deregisters operators from the AVSDirectory using the M2-registration pathway.
     */
    function deregisterOperator(
        bytes memory quorumNumbers
    ) external;

    /**
     * @notice Enables operator sets mode for the AVS. Once enabled, this cannot be disabled.
     * @dev When enabled, all existing quorums are marked as M2 quorums and future quorums must be explicitly
     * created as either M2 or operator set quorums.
     */
    function enableOperatorSets() external;

    /**
     * @notice Disables M2 quorum registration for the AVS. Once disabled, this cannot be enabled.
     * @dev When disabled, all registrations to M2 quorums will revert. Deregistrations are still possible.
     */
    function disableM2QuorumRegistration() external;
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    ISlashingRegistryCoordinator,
    ISlashingRegistryCoordinatorErrors,
    ISlashingRegistryCoordinatorEvents,
    ISlashingRegistryCoordinatorTypes
} from "./ISlashingRegistryCoordinator.sol";
import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IBLSApkRegistry, IBLSApkRegistryTypes} from "./IBLSApkRegistry.sol";
import {IServiceManager} from "./IServiceManager.sol";
import {IStakeRegistry} from "./IStakeRegistry.sol";
import {IIndexRegistry} from "./IIndexRegistry.sol";
import {ISocketRegistry} from "./ISocketRegistry.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

interface IRegistryCoordinatorErrors is ISlashingRegistryCoordinatorErrors {
    /// @notice Thrown when operator sets mode is already enabled.
    error OperatorSetsAlreadyEnabled();
    /// @notice Thrown when a quorum is an operator set quorum.
    error OperatorSetQuorum();
    /// @notice Thrown when M2 quorums are already disabled.
    error M2QuorumRegistrationIsDisabled();
    /// @notice Thrown when operator set operations are attempted while not enabled.
    error OperatorSetsNotEnabled();
    /// @notice Thrown when only M2 quorums are allowed.
    error OnlyM2QuorumsAllowed();
}

interface IRegistryCoordinatorTypes is ISlashingRegistryCoordinatorTypes {
    /**
     * @notice Parameters for initializing SlashingRegistryCoordinator
     * @param stakeRegistry The StakeRegistry contract that keeps track of operators' stakes
     * @param blsApkRegistry The BLSApkRegistry contract that keeps track of operators' BLS public keys
     * @param indexRegistry The IndexRegistry contract that keeps track of ordered operator lists
     * @param socketRegistry The SocketRegistry contract that keeps track of operators' sockets
     * @param allocationManager The AllocationManager contract for operator set management
     * @param pauserRegistry The PauserRegistry contract for pausing functionality
     */
    struct SlashingRegistryParams {
        IStakeRegistry stakeRegistry;
        IBLSApkRegistry blsApkRegistry;
        IIndexRegistry indexRegistry;
        ISocketRegistry socketRegistry;
        IAllocationManager allocationManager;
        IPauserRegistry pauserRegistry;
    }

    /**
     * @notice Parameters for initializing RegistryCoordinator
     * @param serviceManager The ServiceManager contract for this AVS
     * @param slashingParams Parameters for initializing SlashingRegistryCoordinator
     */
    struct RegistryCoordinatorParams {
        IServiceManager serviceManager;
        SlashingRegistryParams slashingParams;
    }
}

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
     * @notice Emitted when M2 quorum registration is disabled.
     * @dev Emitted in disableM2QuorumRegistration().
     */
    event M2QuorumRegistrationDisabled();
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
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature
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
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory churnApproverSignature,
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature
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
     * @notice Checks if a quorum is an M2 quorum.
     * @param quorumNumber The quorum identifier.
     * @return True if the quorum is M2, false otherwise.
     */
    function isM2Quorum(
        uint8 quorumNumber
    ) external view returns (bool);

    /**
     * @notice Disables M2 quorum registration for the AVS. Once disabled, this cannot be enabled.
     * @dev When disabled, all registrations to M2 quorums will revert. Deregistrations are still possible.
     */
    function disableM2QuorumRegistration() external;
}

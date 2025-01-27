// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    IRegistryCoordinator,
    IRegistryCoordinatorErrors,
    IRegistryCoordinatorEvents,
    IRegistryCoordinatorTypes
} from "./IRegistryCoordinator.sol";
import {IServiceManager} from "./IServiceManager.sol";
import {IBLSApkRegistry} from "./IBLSApkRegistry.sol";
import {IStakeRegistry} from "./IStakeRegistry.sol";
import {IIndexRegistry} from "./IIndexRegistry.sol";
import {BN254} from "../libraries/BN254.sol";

interface ISlashingRegistryCoordinatorErrors is IRegistryCoordinatorErrors {
    /// @notice Thrown when operator sets mode is already enabled.
    error OperatorSetsAlreadyEnabled();
    /// @notice Thrown when M2 quorums are already disabled.
    error M2QuorumsAlreadyDisabled();
    /// @notice Thrown when an invalid registration type is provided.
    error InvalidRegistrationType();
}

interface ISlashingRegistryCoordinatorTypes is IRegistryCoordinatorTypes {
    /**
     * @notice Enum representing the type of operator registration.
     * @custom:enum NORMAL Represents a normal operator registration.
     * @custom:enum CHURN Represents an operator registration during a churn event.
     */
    enum RegistrationType {
        NORMAL,
        CHURN
    }

    /**
     * @notice Data structure for storing the results of a registerOperator call.
     * @dev Contains arrays storing per-quorum information about operator counts and stakes.
     * @param numOperatorsPerQuorum For each quorum the operator registered for, stores the number of operators registered.
     * @param operatorStakes For each quorum the operator registered for, stores the stake of the operator in the quorum.
     * @param totalStakes For each quorum the operator registered for, stores the total stake of the quorum.
     */
    struct RegisterResults {
        uint32[] numOperatorsPerQuorum;
        uint96[] operatorStakes;
        uint96[] totalStakes;
    }
}

interface ISlashingRegistryCoordinatorEvents is
    IRegistryCoordinatorEvents,
    ISlashingRegistryCoordinatorTypes
{}

interface ISlashingRegistryCoordinator is
    ISlashingRegistryCoordinatorErrors,
    ISlashingRegistryCoordinatorEvents
{
    /// @notice Returns the operator set params for the given `quorumNumber`
    function getOperatorSetParams(
        uint8 quorumNumber
    ) external view returns (OperatorSetParam memory);
    /// @notice the Stake registry contract that will keep track of operators' stakes
    function stakeRegistry() external view returns (IStakeRegistry);
    /// @notice the BLS Aggregate Pubkey Registry contract that will keep track of operators' BLS aggregate pubkeys per quorum
    function blsApkRegistry() external view returns (IBLSApkRegistry);
    /// @notice the index Registry contract that will keep track of operators' indexes
    function indexRegistry() external view returns (IIndexRegistry);

    /**
     * @notice Ejects the provided operator from the provided quorums from the AVS
     * @param operator is the operator to eject
     * @param quorumNumbers are the quorum numbers to eject the operator from
     */
    function ejectOperator(address operator, bytes calldata quorumNumbers) external;

    /// @notice Returns the number of quorums the registry coordinator has created
    function quorumCount() external view returns (uint8);

    /// @notice Returns the operator struct for the given `operator`
    function getOperator(
        address operator
    ) external view returns (OperatorInfo memory);

    /// @notice Returns the operatorId for the given `operator`
    function getOperatorId(
        address operator
    ) external view returns (bytes32);

    /// @notice Returns the operator address for the given `operatorId`
    function getOperatorFromId(
        bytes32 operatorId
    ) external view returns (address operator);

    /// @notice Returns the status for the given `operator`
    function getOperatorStatus(
        address operator
    ) external view returns (OperatorStatus);

    /// @notice Returns the indices of the quorumBitmaps for the provided `operatorIds` at the given `blockNumber`
    function getQuorumBitmapIndicesAtBlockNumber(
        uint32 blockNumber,
        bytes32[] memory operatorIds
    ) external view returns (uint32[] memory);

    /**
     * @notice Returns the quorum bitmap for the given `operatorId` at the given `blockNumber` via the `index`
     * @dev reverts if `index` is incorrect
     */
    function getQuorumBitmapAtBlockNumberByIndex(
        bytes32 operatorId,
        uint32 blockNumber,
        uint256 index
    ) external view returns (uint192);

    /// @notice Returns the `index`th entry in the operator with `operatorId`'s bitmap history
    function getQuorumBitmapUpdateByIndex(
        bytes32 operatorId,
        uint256 index
    ) external view returns (QuorumBitmapUpdate memory);

    /// @notice Returns the current quorum bitmap for the given `operatorId`
    function getCurrentQuorumBitmap(
        bytes32 operatorId
    ) external view returns (uint192);

    /// @notice Returns the length of the quorum bitmap history for the given `operatorId`
    function getQuorumBitmapHistoryLength(
        bytes32 operatorId
    ) external view returns (uint256);

    /// @notice Returns the registry at the desired index
    function registries(
        uint256
    ) external view returns (address);

    /// @notice Returns the number of registries
    function numRegistries() external view returns (uint256);

    /// @notice Returns whether a quorum is an M2 quorum
    /// @param quorumNumber The quorum number to check
    /// @return True if the quorum is an M2 quorum
    function isM2Quorum(
        uint8 quorumNumber
    ) external view returns (bool);

    /**
     * @notice Returns whether operator sets mode is enabled.
     * @return True if operator sets mode is enabled, false otherwise.
     */
    function operatorSetsEnabled() external view returns (bool);

    /**
     * @notice Returns the message hash that an operator must sign to register their BLS public key.
     * @param operator is the address of the operator registering their BLS public key
     */
    function pubkeyRegistrationMessageHash(
        address operator
    ) external view returns (BN254.G1Point memory);

    /// @notice returns the blocknumber the quorum was last updated all at once for all operators
    function quorumUpdateBlockNumber(
        uint8 quorumNumber
    ) external view returns (uint256);

    /// @notice The owner of the registry coordinator
    function owner() external view returns (address);

    /**
     * @notice The account identifier for this AVS (used for UAM integration in EigenLayer).
     * @dev NOTE: Updating this value will break existing OperatorSets and UAM integration. This value should only be set once.
     * @return The account identifier address.
     */
    function accountIdentifier() external view returns (address);
}

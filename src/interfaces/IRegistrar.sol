// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IRegistryCoordinator} from "./IRegistryCoordinator.sol";
import {IServiceManager} from "./IServiceManager.sol";
import {IBLSApkRegistry} from "./IBLSApkRegistry.sol";
import {IStakeRegistry} from "./IStakeRegistry.sol";
import {IIndexRegistry} from "./IIndexRegistry.sol";
import {BN254} from "../libraries/BN254.sol";

interface IRegistrarErrors {
    /// Calldata Validation

    /// @dev Thrown when arrays do not have equal length
    error InputLengthMismatch();
    /// @dev Thrown when the operators to update for a quorum is not equal to the total operators in the quorum
    error QuorumOperatorCountMismatch();
    /// @dev Thrown when operators passed in are not sorted
    error OperatorsNotSorted();
    /// @dev Thrown when an invalid registration type is passed in
    error InvalidRegistrationType();

    /// Caller

    /// @dev Thrown when the caller is not the ejector
    error OnlyEjector();
    /// @dev Thrown when the caller is not the AllocationManager
    error OnlyAllocationManager();

    /// Quorum Input Validation

    /// @dev Thrown when a quorum does not exist in storage
    error QuorumDoesNotExist();
    /// @dev Thrown when the quorum bitmap is empty
    error BitmapEmpty();
    /// @dev Thrown when the max quorums has been reached
    error MaxQuorumsReached();

    ///  Operator Validation

    /// @dev Thrown when the operator is already registered
    error AlreadyRegisteredForQuorums();
    /// @dev Thrown when the operator has attempted to re-register prior to the ejection cooldown
    error CannotReregisterYet();
    /// @dev Thrown when an operator is attempted to be deregistered but is not registered
    error NotRegistered();
    /// @dev Thrown when an operator is not registered for a quorum
    error NotRegisteredForQuorum();

    /// Churn Validation

    /// @dev Thrown when an operator attempts to churn itself
    error CannotChurnSelf();
    /// @dev Thrown when the quorumNumber in `kickParams` doesn't match the quorumNumber
    error KickParamsQuorumMismatch();
    /// @dev Thrown when the operator has insufficient stake to churn
    error InsufficientStakeForChurn();
    /// @dev Thrown when the operator to kick cannot be churned out
    error CannotKickOperatorAboveThreshold();
    /// @dev Thrown when the salt for the churn approver has been used
    error ChurnApproverSaltUsed();
}

interface IRegistrarTypes {
    /**
     * @notice OperatorStatus
     * @dev Default is `NEVER_REGISTERED`
     */
    enum OperatorStatus {
        NEVER_REGISTERED,
        REGISTERED,
        DEREGISTERED
    }

    /**
     * @notice Registration type on registration calls from AllocationManager
     */
    enum RegistrationType {
        NORMAL,
        CHURN
    }

    /**
     * @notice Data structure for storing info on operators
     * @param operatorId the id of the operator, which is likely the keccak256 hash of the operator's public key if using BLSRegistry
     * @param status indicates whether the operator is actively registered for serving the middleware or not
     */
    struct OperatorInfo {
        bytes32 operatorId;
        OperatorStatus status;
    }

    /**
     * @notice Data structure for storing info on quorum bitmap updates
     * @param updateBlockNumber (inclusive) block at which the operator is registered for
     * @param nextBlockNumber (exclusive) block at which the quorum was updated
     * @param quorumBitmap the bitmap of the quorums the operator is registered for
     * @dev nextUpdateBlockNumber is initialized to 0 for the latest update
     */
    struct QuorumBitmapUpdate {
        uint32 updateBlockNumber;
        uint32 nextUpdateBlockNumber;
        uint192 quorumBitmap;
    }

    /**
     * @notice Data structure for storing operator set params for a given quorum
     * @param maxOperatorCount maximum number of operators that can be registered for the quorum
     * @param kickBIPsOfOperatorStake the basis points of a new operator needs to have of an operator they are trying to kick from the quorum
     * @param kickBIPsOfTotalStake the basis points of the total stake of the quorum that an operator needs to be below to be kicked
     */
    struct OperatorSetParam {
        uint32 maxOperatorCount;
        uint16 kickBIPsOfOperatorStake;
        uint16 kickBIPsOfTotalStake;
    }

    /**
     * @notice Data structure for the parameters needed to kick an operator from a quorum
     * @param quorumNumber during registration churn.
     * @param operator the address of the operator to kick
     */
    struct OperatorKickParam {
        uint8 quorumNumber;
        address operator;
    }
}

interface IRegistrarEvents is IRegistrarTypes {
    /// Emits when an operator is registered
    event OperatorRegistered(address indexed operator, bytes32 indexed operatorId);

    /// Emits when an operator is deregistered
    event OperatorDeregistered(address indexed operator, bytes32 indexed operatorId);

    event OperatorSetParamsUpdated(uint8 indexed quorumNumber, OperatorSetParam operatorSetParams);

    event ChurnApproverUpdated(address prevChurnApprover, address newChurnApprover);

    event EjectorUpdated(address prevEjector, address newEjector);

    /// @notice emitted when all the operators for a quorum are updated at once
    event QuorumBlockNumberUpdated(uint8 indexed quorumNumber, uint256 blocknumber);
}

interface IRegistrar is IRegistrarErrors, IRegistrarEvents, IAVSRegistrar {
    /**
     * @notice Register an operator for one or more quorums. This function is called by the AllocationManager
     *         The function can be used to register normally or register an operator via churning another
     * @param operator The operator to register
     * @param operatorSetIds An ordered array containing the quorum numbers (operatorSets) being registered for
     * @param data bytes containing the registration data
     * @dev `data` without churn is expected to be in the following format:
     * - `registrationType` is the type of registration
     * - `socket` is the socket of the operator (typically an IP address)
     * - `params` contains the G1 & G2 public keys of the operator, and a signature proving their ownership
     * @dev `data` with churn is expected to be in the following format:
     * - `registrationType` is the type of registration
     * - `quorumNumbers` is the quorum numbers the operator is registering for
     * - `socket` is the socket of the operator (typically an IP address)
     * - `params` contains the G1 & G2 public keys of the operator, and a signature proving their ownership
     * - `operatorKickParams` used to determine which operator is removed to maintain quorum capacity as the
     * operator registers for quorums
     * - `churnApproverSignature` is the signature of the churnApprover over the `operatorKickParams`
     * @dev  If any quorum exceeds its maximum operator capacity after the operator is registered, this method will fail.
     * @dev `params` is ignored if the caller has previously registered a public key
     */
    function registerOperator(
        address operator,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) external;

    /**
     * @notice Deregisters an operator from one or more quorums. This function is called by the AllocationManager
     * @param operator the operator to deregister
     * @param operatorSetIds An ordered array containing the quorum numbers (operatorSets) being deregistered from
     * @dev If the function fails, the operator will still be deregsitered from EigenLayer core, eject the operator
     *      from the quorum if they are still registered
     */
    function deregisterOperator(address operator, uint32[] calldata operatorSetIds) external;

    /**
     * @notice Forcibly deregisters an operator from one or more quorums
     * @param operator the operator to eject
     * @param quorumNumbers the quorum numbers to eject the operator from
     * @dev possible race condition if prior to being ejected for a set of quorums the operator self deregisters from a subset
     */
    function ejectOperator(address operator, bytes memory quorumNumbers) external;

    /**
     * @notice Updates the StakeRegistry's view of one or more operators' stakes. If any operator
     * is found to be below the minimum stake for the quorum, they are deregistered.
     * @param operators a list of operator addresses to update
     * @dev stakes are queried from the Eigenlayer core DelegationManager contract
     */
    function updateOperators(address[] memory operators) external;

    /**
     * @notice For each quorum in `quorumNumbers`, updates the StakeRegistry's view of ALL its registered operators' stakes.
     * Each quorum's `quorumUpdateBlockNumber` is also updated, which tracks the most recent block number when ALL registered
     * operators were updated.
     * @dev stakes are queried from the Eigenlayer core DelegationManager contract
     * @param operatorsPerQuorum for each quorum in `quorumNumbers`, this has a corresponding list of operators to update.
     * @dev Each list of operator addresses MUST be sorted in ascending order
     * @dev Each list of operator addresses MUST represent the entire list of registered operators for the corresponding quorum
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being updated
     * @dev invariant: Each list of `operatorsPerQuorum` MUST be a sorted version of `IndexRegistry.getOperatorListAtBlockNumber`
     * for the corresponding quorum.
     * @dev note on race condition: if an operator registers/deregisters for any quorum in `quorumNumbers` after a txn to
     * this method is broadcast (but before it is executed), the method will fail
     */
    function updateOperatorsForQuorum(
        address[][] memory operatorsPerQuorum,
        bytes calldata quorumNumbers
    ) external;

    /**
     * @notice Creates a delegated stake quorum and initializes it in each registry contract
     * @param operatorSetParams configures the quorum's max operator count and churn parameters
     * @param minimumStake sets the minimum stake required for an operator to register or remain
     * registered
     * @param strategyParams a list of strategies and multipliers used by the StakeRegistry to
     * calculate an operator's stake weight for the quorum
     */
    function createTotalDelegatedStakeQuorum(
        OperatorSetParam memory operatorSetParams,
        uint96 minimumStake,
        IStakeRegistry.StrategyParams[] memory strategyParams
    ) external;
    /**
     * @notice Updates an existing quorum's configuration with a new max operator count
     * and operator churn parameters
     * @param quorumNumber the quorum number to update
     * @param operatorSetParams the new config
     * @dev only callable by the owner
     */
    function setOperatorSetParams(
        uint8 quorumNumber,
        OperatorSetParam memory operatorSetParams
    ) external;

    /**
     * @notice Sets the churnApprover, which approves operator registration with churn
     * (see `registerOperatorWithChurn`)
     * @param _churnApprover the new churn approver
     * @dev only callable by the owner
     */
    function setChurnApprover(address _churnApprover) external;

    /**
     * @notice Sets the ejector, which can force-deregister operators from quorums
     * @param _ejector the new ejector
     * @dev only callable by the owner
     */
    function setEjector(address _ejector) external;


    /**
     * @notice Sets the ejection cooldown, which is the time an operator must wait in
     * seconds afer ejection before registering for any quorum
     * @param _ejectionCooldown the new ejection cooldown in seconds
     * @dev only callable by the owner
     */
    function setEjectionCooldown(uint256 _ejectionCooldown) external;

    /**
     * @notice Returns the operator set params for the given `quorumNumber`
     * @param quorumNumber the quorum number to get the operator set params for
     */
    function getOperatorSetParams(
        uint8 quorumNumber
    ) external view returns (OperatorSetParam memory);

    /**
     * @notice Returns the operator struct for an operator
     * @param operator to query
     */
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

    /**
     * @notice Returns the indices of the quorumBitmaps for the provided `operatorIds` at the given `blockNumber`
     * @param blockNumber the block number to query
     * @param operatorIds the operator ids to query
     * @dev Reverts if any of the `operatorIds` was not (yet) registered at `blockNumber`
     * @dev This function is designed to find proper inputs to the `getQuorumBitmapAtBlockNumberByIndex` function
     */
    function getQuorumBitmapIndicesAtBlockNumber(
        uint32 blockNumber,
        bytes32[] memory operatorIds
    ) external view returns (uint32[] memory);

    /**
     * @notice Returns the quorum bitmap for the given `operatorId` at the given `blockNumber` via the `index`
     * @param operatorId the operator id to query
     * @param blockNumber the block number to query
     * @param index the index to query
     * @dev reverts if `index` is incorrect
     */
    function getQuorumBitmapAtBlockNumberByIndex(
        bytes32 operatorId,
        uint32 blockNumber,
        uint256 index
    ) external view returns (uint192);

    /**
     * @notice Returns the quorum bitmap update at the given `index` for the given `operatorId`
     * @param operatorId the operator id to query
     * @param index the index to query
     */
    function getQuorumBitmapUpdateByIndex(
        bytes32 operatorId,
        uint256 index
    ) external view returns (IRegistryCoordinator.QuorumBitmapUpdate memory);

    /**
     * Returns the current quorum bitmap for the given `operatorId`
     * @param operatorId the operator id to query
     */
    function getCurrentQuorumBitmap(
        bytes32 operatorId
    ) external view returns (uint192);

    /**
     * @notice Returns the length of the quorum bitmap history for the given `operatorId`
     * @param operatorId the operator id to query
     */
    function getQuorumBitmapHistoryLength(
        bytes32 operatorId
    ) external view returns (uint256);

    /**
     * @notice Returns the number of registries
     */
    function numRegistries() external view returns (uint256);

    /**
     * @notice Public function for the the churnApprover signature hash calculation when operators are being kicked from quorums
     * @param registerOperator The operator registering
     * @param registeringOperatorId The id of the registering operator
     * @param operatorKickParams The parameters needed to kick the operator from the quorums that have reached their caps
     * @param salt The salt to use for the churnApprover's signature
     * @param expiry The desired expiry time of the churnApprover's signature
     */
    function calculateOperatorChurnApprovalDigestHash(
        address registerOperator,
        bytes32 registeringOperatorId,
        OperatorKickParam[] calldata operatorKickParams,
        bytes32 salt,
        uint256 expiry
    ) external view returns (bytes32);

    /**
     * @notice Returns the message hash that an operator must sign to register their BLS public key.
     * @param operator is the address of the operator registering their BLS public key
     */
    function pubkeyRegistrationMessageHash(
        address operator
    ) external view returns (BN254.G1Point memory);

    /**
     * @notice Returns the owner of the Registrar
     * @dev need to override function here since its defined in both these contracts
     */
    function owner() external view returns (address);

    /**
     * @notice Returns the block number the quorum was last updated all at once for all operators
     * @param quorumNumber quorumToCheck
     */
    function quorumUpdateBlockNumber(
        uint8 quorumNumber
    ) external view returns (uint256);

    /**
     * @notice Returns the registry at the desired index
     * @param index the index of the registry to return 
     */
    function registries(
        uint256 index
    ) external view returns (address);

    /**
     * @notice Returns the number of quorums the registry coordinator has created
     */
    function quorumCount() external view returns (uint8);
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IBLSApkRegistry} from "./interfaces/IBLSApkRegistry.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";
import {IIndexRegistry} from "./interfaces/IIndexRegistry.sol";
import {IServiceManager} from "./interfaces/IServiceManager.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {
    IAllocationManager,
    OperatorSet,
    IAllocationManagerTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {ISlashingRegistryCoordinator} from "./interfaces/ISlashingRegistryCoordinator.sol";

abstract contract SlashingRegistryCoordinatorStorage is ISlashingRegistryCoordinator {
    /**
     *
     *                            CONSTANTS AND IMMUTABLES
     *
     */

    /// @notice The EIP-712 typehash for the `DelegationApproval` struct used by the contract
    bytes32 public constant OPERATOR_CHURN_APPROVAL_TYPEHASH = keccak256(
        "OperatorChurnApproval(address registeringOperator,bytes32 registeringOperatorId,OperatorKickParam[] operatorKickParams,bytes32 salt,uint256 expiry)OperatorKickParam(uint8 quorumNumber,address operator)"
    );
    /// @notice The EIP-712 typehash used for registering BLS public keys
    bytes32 public constant PUBKEY_REGISTRATION_TYPEHASH =
        keccak256("BN254PubkeyRegistration(address operator)");
    /// @notice The maximum value of a quorum bitmap
    uint256 internal constant MAX_QUORUM_BITMAP = type(uint192).max;
    /// @notice The basis point denominator
    uint16 internal constant BIPS_DENOMINATOR = 10000;
    /// @notice Index for flag that pauses operator registration
    uint8 internal constant PAUSED_REGISTER_OPERATOR = 0;
    /// @notice Index for flag that pauses operator deregistration
    uint8 internal constant PAUSED_DEREGISTER_OPERATOR = 1;
    /// @notice Index for flag pausing operator stake updates
    uint8 internal constant PAUSED_UPDATE_OPERATOR = 2;
    /// @notice The maximum number of quorums this contract supports
    uint8 internal constant MAX_QUORUM_COUNT = 192;

    /// @notice the BLS Aggregate Pubkey Registry contract that will keep track of operators' aggregate BLS public keys per quorum
    IBLSApkRegistry public immutable blsApkRegistry;
    /// @notice the Stake Registry contract that will keep track of operators' stakes
    IStakeRegistry public immutable stakeRegistry;
    /// @notice the Index Registry contract that will keep track of operators' indexes
    IIndexRegistry public immutable indexRegistry;

    /// EigenLayer contracts
    /// @notice the AllocationManager that tracks OperatorSets and Slashing in EigenLayer
    IAllocationManager public immutable allocationManager;

    /**
     *
     *                                    STATE
     *
     */

    /// @notice the current number of quorums supported by the registry coordinator
    uint8 public quorumCount;
    /// @notice maps quorum number => operator cap and kick params
    mapping(uint8 => OperatorSetParam) internal _quorumParams;
    /// @notice maps operator id => historical quorums they registered for
    mapping(bytes32 => QuorumBitmapUpdate[]) internal _operatorBitmapHistory;
    /// @notice maps operator address => operator id and status
    mapping(address => OperatorInfo) internal _operatorInfo;
    /// @notice whether the salt has been used for an operator churn approval
    mapping(bytes32 => bool) public isChurnApproverSaltUsed;
    /// @notice mapping from quorum number to the latest block that all quorums were updated all at once
    mapping(uint8 => uint256) public quorumUpdateBlockNumber;

    /// @notice the dynamic-length array of the registries this coordinator is coordinating
    address[] public registries;
    /// @notice the address of the entity allowed to sign off on operators getting kicked out of the AVS during registration
    address public churnApprover;
    /// @notice the address of the entity allowed to eject operators from the AVS
    address public ejector;

    /// @notice the last timestamp an operator was ejected
    mapping(address => uint256) public lastEjectionTimestamp;
    /// @notice the delay in seconds before an operator can reregister after being ejected
    uint256 public ejectionCooldown;

    /// @notice Whether this AVS allows operator sets for registration
    /// @dev If true, operators may register to operator sets via the AllocationManager
    bool public operatorSetsEnabled;

    /// @notice Whether this AVS allows M2 quorums for registration
    /// @dev If true, operators may **not** register to M2 quorums. Deregistration is still allowed.
    bool public m2QuorumsDisabled;

    /// @notice The account identifier for this AVS (used for UAM integration in EigenLayer)
    /// @dev NOTE: Updating this value will break existing OperatorSets and UAM integration.
    /// This value should only be set once.
    address public accountIdentifier;

    /// @notice The bitmap containing all M2 quorums. This is only used for existing AVS middlewares that have M2 quorums
    /// and need to call `enableOperatorSets()` to enable operator sets mode.
    uint256 internal M2quorumBitmap;

    constructor(
        IStakeRegistry _stakeRegistry,
        IBLSApkRegistry _blsApkRegistry,
        IIndexRegistry _indexRegistry,
        IAllocationManager _allocationManager
    ) {
        stakeRegistry = _stakeRegistry;
        blsApkRegistry = _blsApkRegistry;
        indexRegistry = _indexRegistry;
        allocationManager = _allocationManager;
    }

    // storage gap for upgradeability
    // slither-disable-next-line shadowing-state
    uint256[37] private __GAP;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {CheckpointsUpgradeable} from
    "@openzeppelin-upgrades/contracts/utils/CheckpointsUpgradeable.sol";
import {
    IECDSAStakeRegistry, IECDSAStakeRegistryTypes
} from "../interfaces/IECDSAStakeRegistry.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IAVSDirectoryTypes} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IAVSDirectory} from "./ECDSAStakeRegistry.sol";

abstract contract ECDSAStakeRegistryStorage is IECDSAStakeRegistry {
    /// @notice Manages staking delegations through the DelegationManager interface
    IDelegationManager internal immutable DELEGATION_MANAGER;

    /// @notice The AVS Directory contract
    IAVSDirectory internal immutable AVS_DIRECTORY;

    /// @notice Manages staking delegations through the DelegationManager interface
    IAllocationManager internal allocationManager;

    /// @notice The address of the AVS Registrar of the AVS
    address internal avsRegistrar;

    /// @notice Whether M2 quorum registration is disabled
    bool public isM2QuorumRegistrationDisabled;

    /// @notice The current operator set ids
    uint32[] public currentOperatorSetIds;

    /// @notice The total amount of multipliers to weigh stakes
    uint256 public constant WAD = 1e18;

    /// @dev The total amount of multipliers to weigh stakes
    uint256 internal constant BPS = 10000;

    /// @notice The size of the current operator set
    uint256 internal _totalOperators;

    /// @notice Stores the current quorum configuration
    IECDSAStakeRegistryTypes.Quorum internal _quorum;

    /// @notice Specifies the weight required to become an operator
    uint256 internal _minimumWeight;

    /// @notice Holds the address of the service manager
    address internal _serviceManager;

    /// @notice Maps an operator to their signing key history using checkpoints
    mapping(address => CheckpointsUpgradeable.History) internal _operatorSigningKeyHistory;

    /// @notice Tracks the total stake history over time using checkpoints
    CheckpointsUpgradeable.History internal _totalWeightHistory;

    /// @notice Tracks the threshold bps history using checkpoints
    CheckpointsUpgradeable.History internal _thresholdWeightHistory;

    /// @notice Maps operator addresses to their respective stake histories using checkpoints
    mapping(address => CheckpointsUpgradeable.History) internal _operatorWeightHistory;

    /// @param _delegationManager Connects this registry with the DelegationManager
    constructor(
        IDelegationManager _delegationManager,
        IAllocationManager _allocationManager,
        address _avsRegistrar,
        IAVSDirectory _avsDirectory
    ) {
        DELEGATION_MANAGER = _delegationManager;
        allocationManager = _allocationManager;
        avsRegistrar = _avsRegistrar;
        AVS_DIRECTORY = _avsDirectory;
    }

    // slither-disable-next-line shadowing-state
    /// @dev Reserves storage slots for future upgrades
    // solhint-disable-next-line
    uint256[40] private __gap;
}

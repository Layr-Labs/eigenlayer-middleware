// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {CheckpointsUpgradeable} from
    "@openzeppelin-upgrades/contracts/utils/CheckpointsUpgradeable.sol";
import {
    IECDSAStakeRegistry, IECDSAStakeRegistryTypes
} from "../interfaces/IECDSAStakeRegistry.sol";

abstract contract ECDSAStakeRegistryStorage is IECDSAStakeRegistry {
    /// @notice Manages staking delegations through the DelegationManager interface
    IDelegationManager internal immutable DELEGATION_MANAGER;

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

    /// @notice Defines the duration after which the stake's weight expires.
    uint256 internal _stakeExpiry;

    /// @notice Maps an operator to their signing key history using checkpoints
    mapping(address => CheckpointsUpgradeable.History) internal _operatorSigningKeyHistory;

    /// @notice Tracks the total stake history over time using checkpoints
    CheckpointsUpgradeable.History internal _totalWeightHistory;

    /// @notice Tracks the threshold bps history using checkpoints
    CheckpointsUpgradeable.History internal _thresholdWeightHistory;

    /// @notice Maps operator addresses to their respective stake histories using checkpoints
    mapping(address => CheckpointsUpgradeable.History) internal _operatorWeightHistory;

    /// @notice Maps an operator to their registration status
    mapping(address => bool) internal _operatorRegistered;

    /// @param _delegationManager Connects this registry with the DelegationManager
    constructor(
        IDelegationManager _delegationManager
    ) {
        DELEGATION_MANAGER = _delegationManager;
    }

    // slither-disable-next-line shadowing-state
    /// @dev Reserves storage slots for future upgrades
    // solhint-disable-next-line
    uint256[40] private __gap;
}

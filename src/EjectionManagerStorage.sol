// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ISlashingRegistryCoordinator} from "./interfaces/ISlashingRegistryCoordinator.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";
import {IEjectionManager} from "./interfaces/IEjectionManager.sol";

abstract contract EjectionManagerStorage is IEjectionManager {
    /// @notice The basis point denominator for the ejectable stake percent
    uint16 internal constant BIPS_DENOMINATOR = 10000;
    /// @notice The max number of quorums
    uint8 internal constant MAX_QUORUM_COUNT = 192;

    /// @inheritdoc IEjectionManager
    ISlashingRegistryCoordinator public immutable slashingRegistryCoordinator;
    /// @inheritdoc IEjectionManager
    IStakeRegistry public immutable stakeRegistry;

    /// @inheritdoc IEjectionManager
    mapping(address => bool) public isEjector;
    /// @inheritdoc IEjectionManager
    mapping(uint8 => StakeEjection[]) public stakeEjectedForQuorum;
    /// @inheritdoc IEjectionManager
    mapping(uint8 => QuorumEjectionParams) public quorumEjectionParams;

    constructor(
        ISlashingRegistryCoordinator _slashingRegistryCoordinator,
        IStakeRegistry _stakeRegistry
    ) {
        slashingRegistryCoordinator = _slashingRegistryCoordinator;
        stakeRegistry = _stakeRegistry;
    }

    /// @dev This was missing before the slashing release, if your contract
    /// was deployed pre-slashing, you should double check your storage layout.
    uint256[47] private __gap;
}

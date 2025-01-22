// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";
import {IEjectionManager} from "./interfaces/IEjectionManager.sol";

abstract contract EjectionManagerStorage is IEjectionManager {
    /// @notice The basis point denominator for the ejectable stake percent
    uint16 internal constant BIPS_DENOMINATOR = 10_000;
    /// @notice The max number of quorums
    uint8 internal constant MAX_QUORUM_COUNT = 192;

    /// @inheritdoc IEjectionManager
    IRegistryCoordinator public immutable registryCoordinator;
    /// @inheritdoc IEjectionManager
    IStakeRegistry public immutable stakeRegistry;

    /// @inheritdoc IEjectionManager
    mapping(address => bool) public isEjector;
    /// @inheritdoc IEjectionManager
    mapping(uint8 => StakeEjection[]) public stakeEjectedForQuorum;
    /// @inheritdoc IEjectionManager
    mapping(uint8 => QuorumEjectionParams) public quorumEjectionParams;

    constructor(IRegistryCoordinator _registryCoordinator, IStakeRegistry _stakeRegistry) {
        registryCoordinator = _registryCoordinator;
        stakeRegistry = _stakeRegistry;
    }
}

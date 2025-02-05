// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {SlasherStorage, ISlashingRegistryCoordinator} from "./SlasherStorage.sol";
import {
    IAllocationManagerTypes,
    IAllocationManager
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

/// @title SlasherBase
/// @notice Base contract for implementing slashing functionality in EigenLayer middleware
/// @dev Provides core slashing functionality and interfaces with EigenLayer's AllocationManager
abstract contract SlasherBase is Initializable, SlasherStorage {
    /// @notice Ensures only the authorized slasher can call certain functions
    modifier onlySlasher() {
        _checkSlasher(msg.sender);
        _;
    }

    /// @notice Constructs the base slasher contract
    /// @param _allocationManager The EigenLayer allocation manager contract
    /// @param _registryCoordinator The registry coordinator for this middleware
    constructor(
        IAllocationManager _allocationManager,
        ISlashingRegistryCoordinator _registryCoordinator
    ) SlasherStorage(_allocationManager, _registryCoordinator) {
        _disableInitializers();
    }

    /// @notice Initializes the slasher contract with authorized slasher address
    /// @param _slasher Address authorized to create and fulfill slashing requests
    function __SlasherBase_init(
        address _slasher
    ) internal onlyInitializing {
        slasher = _slasher;
    }

    /// @notice Internal function to execute a slashing request
    /// @param _requestId The ID of the slashing request to fulfill
    /// @param _params Parameters defining the slashing request including operator, strategies, and amounts
    /// @dev Calls AllocationManager.slashOperator to perform the actual slashing
    function _fulfillSlashingRequest(
        uint256 _requestId,
        IAllocationManager.SlashingParams memory _params
    ) internal virtual {
        allocationManager.slashOperator({
            avs: slashingRegistryCoordinator.accountIdentifier(),
            params: _params
        });
        emit OperatorSlashed(
            _requestId,
            _params.operator,
            _params.operatorSetId,
            _params.wadsToSlash,
            _params.description
        );
    }

    /// @notice Internal function to verify if an account is the authorized slasher
    /// @param account The address to check
    /// @dev Reverts if the account is not the authorized slasher
    function _checkSlasher(
        address account
    ) internal view virtual {
        require(account == slasher, OnlySlasher());
    }
}

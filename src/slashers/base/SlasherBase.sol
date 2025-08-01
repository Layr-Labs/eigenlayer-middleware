// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {SlasherStorage, ISlashingRegistryCoordinator} from "./SlasherStorage.sol";
import {
    OperatorSet,
    IAllocationManager
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";

/// @title SlasherBase
/// @notice Base contract for implementing slashing functionality in EigenLayer middleware
/// @dev Provides core slashing functionality and interfaces with EigenLayer's AllocationManager
abstract contract SlasherBase is SlasherStorage {
    /// @notice Ensures only the authorized slasher can call certain functions
    modifier onlySlasher() {
        _checkSlasher(msg.sender);
        _;
    }

    /// @notice Constructs the base slasher contract
    /// @param _allocationManager The EigenLayer allocation manager contract
    /// @param _registryCoordinator The registry coordinator for this middleware
    /// @param _slasher The address of the slasher
    constructor(
        IAllocationManager _allocationManager,
        IStrategyManager _strategyManager,
        ISlashingRegistryCoordinator _registryCoordinator,
        address _slasher
    ) SlasherStorage(_allocationManager, _strategyManager, _registryCoordinator, _slasher) {}

    /// @notice Internal function to execute a slashing request
    /// @param params Parameters defining the slashing request including operator, strategies, and amounts
    /// @dev Calls AllocationManager.slashOperator to perform the actual slashing
    function _fulfillSlashingRequest(
        IAllocationManager.SlashingParams memory params
    ) internal virtual returns (uint256 slashId) {
        (slashId,) = allocationManager.slashOperator({
            avs: slashingRegistryCoordinator.avs(),
            params: params
        });
        emit OperatorSlashed(
            slashId, params.operator, params.operatorSetId, params.wadsToSlash, params.description
        );

        // Update operator stake weights
        address[] memory operators = new address[](1);
        operators[0] = params.operator;
        slashingRegistryCoordinator.updateOperators(operators);
    }

    /// @notice Internal function to optionally fulfill burn or redistribution instead of waiting for cron job
    function _fulfillBurnOrRedistribution(uint32 operatorSetId, uint256 slashId) internal virtual {
        strategyManager.clearBurnOrRedistributableShares({
            operatorSet: OperatorSet({avs: slashingRegistryCoordinator.avs(), id: operatorSetId}),
            slashId: slashId
        });
    }

    /// @notice Internal function to fulfill a slashing request and burn or redistribute shares
    function _fulfillSlashingRequestAndBurnOrRedistribute(
        IAllocationManager.SlashingParams memory params
    ) internal virtual returns (uint256 slashId) {
        slashId = _fulfillSlashingRequest(params);
        _fulfillBurnOrRedistribution(params.operatorSetId, slashId);
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

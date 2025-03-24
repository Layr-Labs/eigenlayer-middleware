// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {SlasherBase} from "../../slashers/base/SlasherBase.sol";
import {
    IAllocationManager,
    IAllocationManagerTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ISlashingRegistryCoordinator} from "../../interfaces/ISlashingRegistryCoordinator.sol";
import {ISelfSlasher} from "./interfaces/ISelfSlasher.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

/// @title SelfSlasher
/// @notice Example contract allowing operators to slash themselves for testing purposes
/// @dev Based on SlasherBase, provides a simplified way to test slashing effects
contract SelfSlasher is ISelfSlasher, SlasherBase {
    /// @notice Error thrown when wad to slash is invalid
    error InvalidWadToSlash();

    /// @notice Error thrown when no strategies are found in the operator set
    error NoStrategiesInOperatorSet();

    /// @notice Constructs the SelfSlasher contract
    /// @param _allocationManager The EigenLayer allocation manager contract
    /// @param _registryCoordinator The registry coordinator for this middleware
    /// @param _slasher The address of the slasher (admin)
    constructor(
        IAllocationManager _allocationManager,
        ISlashingRegistryCoordinator _registryCoordinator,
        address _slasher
    ) SlasherBase(_allocationManager, _registryCoordinator, _slasher) {}

    /// @inheritdoc ISelfSlasher
    function selfSlash(
        uint32 operatorSetId,
        uint256 wadToSlash,
        string calldata description
    ) external override {
        // Validate wad to slash
        if (wadToSlash == 0 || wadToSlash > 1e18) {
            revert InvalidWadToSlash();
        }

        // Get the operator set
        OperatorSet memory operatorSet =
            OperatorSet(slashingRegistryCoordinator.avs(), operatorSetId);

        // Get all strategies from the operator set
        IStrategy[] memory strategies = allocationManager.getStrategiesInOperatorSet(operatorSet);

        // Ensure there are strategies in the operator set
        if (strategies.length == 0) {
            revert NoStrategiesInOperatorSet();
        }

        // Create wadsToSlash array with the same value for all strategies
        uint256[] memory wadsToSlash = new uint256[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            wadsToSlash[i] = wadToSlash;
        }

        // Create slashing parameters
        IAllocationManagerTypes.SlashingParams memory params = IAllocationManagerTypes
            .SlashingParams({
            operator: msg.sender,
            operatorSetId: operatorSetId,
            strategies: strategies,
            wadsToSlash: wadsToSlash,
            description: description
        });

        // Execute slashing request
        uint256 requestId = nextRequestId++;
        _fulfillSlashingRequest(requestId, params);

        // Update operator status in registry
        _updateOperatorStatus(msg.sender);
    }

    /// @notice Updates the operator status in the registry after slashing
    /// @param operator The address of the operator to update
    function _updateOperatorStatus(
        address operator
    ) internal {
        address[] memory operators = new address[](1);
        operators[0] = operator;
        slashingRegistryCoordinator.updateOperators(operators);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {ISlasher} from "./ISlasher.sol";

/// @title IInstantSlasher
/// @notice A slashing contract that immediately executes slashing requests without any delay or veto period
/// @dev Extends base interfaces to provide access controlled slashing functionality
interface IInstantSlasher is ISlasher {
    /// @notice Immediately executes a slashing request
    /// @param params Parameters defining the slashing request including operator and amount
    /// @dev Can only be called by the authorized slasher
    /// @return slashId The ID of the slashing request
    function fulfillSlashingRequest(
        IAllocationManager.SlashingParams memory params
    ) external returns (uint256 slashId);

    /// @notice Immediately executes a slashing request and burns or redistributes shares
    /// @param params Parameters defining the slashing request including operator and amount
    /// @dev Can only be called by the authorized slasher
    /// @return slashId The ID of the slashing request
    function fulfillSlashingRequestAndBurnOrRedistribute(
        IAllocationManager.SlashingParams memory params
    ) external returns (uint256 slashId);
}

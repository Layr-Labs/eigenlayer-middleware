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
    /// @param _slashingParams Parameters defining the slashing request including operator and amount
    /// @dev Can only be called by the authorized slasher
    function fulfillSlashingRequest(
        IAllocationManager.SlashingParams memory _slashingParams
    ) external;
}

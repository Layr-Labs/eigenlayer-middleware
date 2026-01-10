// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ISlasher} from "../../../interfaces/ISlasher.sol";

/// @title ISelfSlasher
/// @notice Interface for a self-slashing contract that allows operators to slash their own stake
/// @dev This is an example implementation for testing slashing functionality
interface ISelfSlasher is ISlasher {
    /// @notice Allows an operator to slash their own stake
    /// @param operatorSetId The ID of the operator set in which to slash the operator
    /// @param wadToSlash The proportion to slash from each strategy (between 0 and 1e18)
    /// @param description A description of why the operator is slashing themselves
    function selfSlash(
        uint32 operatorSetId,
        uint256 wadToSlash,
        string calldata description
    ) external;
}

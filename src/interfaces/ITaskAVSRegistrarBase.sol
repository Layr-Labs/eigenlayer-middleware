// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IAVSRegistrarInternal} from "./IAVSRegistrarInternal.sol";
import {ISocketRegistryV2} from "./ISocketRegistryV2.sol";
import {IAllowlist} from "./IAllowlist.sol";

/**
 * @title ITaskAVSRegistrarBaseTypes
 * @notice Interface defining the type structures used in the TaskAVSRegistrarBase
 */
interface ITaskAVSRegistrarBaseTypes {
    /**
     * @notice Configuration for the Task-based AVS
     * @param aggregatorOperatorSetId The operator set ID responsible for aggregating results
     * @param executorOperatorSetIds Array of operator set IDs responsible for executing tasks
     */
    struct AvsConfig {
        uint32 aggregatorOperatorSetId;
        uint32[] executorOperatorSetIds;
    }
}

/**
 * @title ITaskAVSRegistrarBaseErrors
 * @notice Interface defining errors that can be thrown by the TaskAVSRegistrarBase
 */
interface ITaskAVSRegistrarBaseErrors {
    /// @notice Thrown when an aggregator operator set id is also an executor operator set id
    error InvalidAggregatorOperatorSetId();

    /// @notice Thrown when executor operator set ids are not in monotonically increasing order (duplicate or unsorted)
    error DuplicateExecutorOperatorSetId();

    /// @notice Thrown when executor operator set ids are empty
    error ExecutorOperatorSetIdsEmpty();
}

/**
 * @title ITaskAVSRegistrarBaseEvents
 * @notice Interface defining events emitted by the TaskAVSRegistrarBase
 */
interface ITaskAVSRegistrarBaseEvents is ITaskAVSRegistrarBaseTypes {
    /**
     * @notice Emitted when the AVS configuration is set
     * @param aggregatorOperatorSetId The operator set ID responsible for aggregating results
     * @param executorOperatorSetIds Array of operator set IDs responsible for executing tasks
     */
    event AvsConfigSet(uint32 aggregatorOperatorSetId, uint32[] executorOperatorSetIds);
}

/**
 * @title ITaskAVSRegistrarBase
 * @author Layr Labs, Inc.
 * @notice Interface for TaskAVSRegistrarBase contract that manages AVS configuration
 */
interface ITaskAVSRegistrarBase is
    ITaskAVSRegistrarBaseErrors,
    ITaskAVSRegistrarBaseEvents,
    IAVSRegistrar,
    IAVSRegistrarInternal,
    ISocketRegistryV2,
    IAllowlist
{
    /**
     * @notice Sets the configuration for this AVS
     * @param config Configuration for the AVS
     * @dev The executorOperatorSetIds must be monotonically increasing.
     */
    function setAvsConfig(
        AvsConfig memory config
    ) external;

    /**
     * @notice Gets the configuration for this AVS
     * @return Configuration for the AVS
     */
    function getAvsConfig() external view returns (AvsConfig memory);
}

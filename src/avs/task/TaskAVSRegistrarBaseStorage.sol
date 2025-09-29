// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ITaskAVSRegistrarBase} from "../../interfaces/ITaskAVSRegistrarBase.sol";

/**
 * @title TaskAVSRegistrarBaseStorage
 * @author Layr Labs, Inc.
 * @notice Storage contract for TaskAVSRegistrarBase
 * @dev This contract holds the storage variables for TaskAVSRegistrarBase
 */
abstract contract TaskAVSRegistrarBaseStorage is ITaskAVSRegistrarBase {
    /// @notice Configuration for this AVS
    AvsConfig internal avsConfig;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[48] private __gap;
}

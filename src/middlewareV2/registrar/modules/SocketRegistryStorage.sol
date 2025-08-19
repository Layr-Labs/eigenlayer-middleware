// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {ISocketRegistryV2} from "../../../interfaces/ISocketRegistryV2.sol";
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";

/**
 * @title Storage variables for the `SocketRegistry` contract.
 * @author Layr Labs, Inc.
 */
abstract contract SocketRegistryStorage is ISocketRegistryV2 {
    /**
     *
     *                                    STATE
     *
     */

    /// @notice A mapping from operator address to socket
    mapping(address operator => string operatorSocket) internal _operatorToSocket;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __GAP;
}

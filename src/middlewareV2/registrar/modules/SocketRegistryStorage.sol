// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {ISocketRegistry} from "../../../interfaces/ISocketRegistry.sol";

/**
 * @title Storage variables for the `SocketRegistry` contract.
 * @author Layr Labs, Inc.
 */
abstract contract SocketRegistryStorage {
    /**
     *
     *                                    STATE
     *
     */

    /// @notice A mapping from operator addresses to their sockets
    mapping(address => string) public operatorToSocket;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __GAP;
}

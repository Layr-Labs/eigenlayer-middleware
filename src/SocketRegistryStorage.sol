// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {ISocketRegistry} from "./interfaces/ISocketRegistry.sol";

/**
 * @title Storage variables for the `SocketRegistry` contract.
 * @author Layr Labs, Inc.
 */
abstract contract SocketRegistryStorage is ISocketRegistry {
    /**
     *
     *                            CONSTANTS AND IMMUTABLES
     *
     */

    /// @notice The address of the SlashingRegistryCoordinator
    address public immutable slashingRegistryCoordinator;

    /**
     *
     *                                    STATE
     *
     */

    /// @notice A mapping from operator IDs to their sockets
    mapping(bytes32 => string) public operatorIdToSocket;

    constructor(
        address _slashingRegistryCoordinator
    ) {
        slashingRegistryCoordinator = _slashingRegistryCoordinator;
    }

    uint256[49] private __GAP;
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {ISocketRegistry} from "../../../interfaces/ISocketRegistryV2.sol";
import {ISlashingRegistryCoordinator} from "src/interfaces/ISlashingRegistryCoordinator.sol";

/**
 * @title Storage variables for the `SocketRegistry` contract.
 * @author Layr Labs, Inc.
 */
abstract contract SocketRegistryStorage is ISocketRegistry {
    /**
     *
     *                                    STATE
     *
     */

    /// @notice The `SlashingRegistryCoordinator` for this AVS.
    ISlashingRegistryCoordinator public immutable slashingRegistryCoordinator;

    /// @notice A mapping from operator address to socket
    mapping(address operator => string operatorSocket) internal _operatorToSocket;

    constructor(
        ISlashingRegistryCoordinator _slashingRegistryCoordinator
    ) {
        slashingRegistryCoordinator = _slashingRegistryCoordinator;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __GAP;
}

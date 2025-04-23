// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ISocketRegistry} from "./interfaces/ISocketRegistry.sol";

abstract contract SocketRegistryStorage is ISocketRegistry {
    /// @custom:storage-location erc7201:eigenlayermiddleware.storage.SocketRegistrarStorage
    struct SocketRegistrarStorageStruct {
        uint256 startIndex;
        uint256 endIndex;
        mapping(address operator => string socket) _operatorSocket;
    }

    /// @dev The storage location for the SocketRegistrarStorage struct
    /// TODO: update to proper storage slot
    bytes32 private constant SocketRegistrarStorageLocation =
        0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;

    function _getSocketRegistryStorage()
        internal
        pure
        returns (SocketRegistrarStorageStruct storage $)
    {
        assembly {
            $.slot := SocketRegistrarStorageLocation
        }
    }
}

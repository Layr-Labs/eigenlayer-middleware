// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IECDSARegistrar} from "./interfaces/IECDSARegistrar.sol";

abstract contract ECDSARegistrarStorage is IECDSARegistrar {
    /// @custom:storage-location erc7201:eigenlayermiddleware.storage.ECDSARegistrarStorage
    struct ECDSARegistrarStorageStruct {
        uint256 startIndex;
        uint256 endIndex;
        mapping(address operator => address signingKey) _operatorSigningKey;
    }

    /// @dev The storage location for the ECDSARegistrarStorage struct
    /// TODO: update to proper storage slot
    bytes32 private constant ECDSARegistrarStorageLocation =
        0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;

    function _getECDSARegistrarStorage()
        internal
        pure
        returns (ECDSARegistrarStorageStruct storage $)
    {
        assembly {
            $.slot := ECDSARegistrarStorageLocation
        }
    }
}

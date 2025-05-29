// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

type Randomness is uint256;

using Random for Randomness global;

library Random {
    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    /// @dev Equivalent to: `uint256(keccak256("RANDOMNESS.SEED"))`.
    uint256 constant SEED = 0x93bfe7cafd9427243dc4fe8c6e706851eb6696ba8e48960dd74ecc96544938ce;

    /// @dev Equivalent to: `uint256(keccak256("RANDOMNESS.SLOT"))`.
    uint256 constant SLOT = 0xd0660badbab446a974e6a19901c78a2ad88d7e4f1710b85e1cfc0878477344fd;

    /// -----------------------------------------------------------------------
    /// Helpers
    /// -----------------------------------------------------------------------

    function set(
        Randomness r
    ) internal returns (Randomness) {
        /// @solidity memory-safe-assembly
        assembly {
            sstore(SLOT, r)
        }
        return r;
    }

    function shuffle(
        Randomness r
    ) internal returns (Randomness) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, sload(SLOT))
            mstore(0x20, r)
            r := keccak256(0x00, 0x20)
        }
        return r.set();
    }

    /// -----------------------------------------------------------------------
    /// Native Types
    /// -----------------------------------------------------------------------

    function Int256(Randomness r, int256 min, int256 max) internal returns (int256) {
        return max <= min ? min : r.Int256() % (max - min) + min;
    }

    function Int256(
        Randomness r
    ) internal returns (int256) {
        return r.unwrap() % 2 == 0 ? int256(r.Uint256()) : -int256(r.Uint256());
    }

    function Int128(Randomness r, int128 min, int128 max) internal returns (int128) {
        return int128(Int256(r, min, max));
    }

    function Int128(
        Randomness r
    ) internal returns (int128) {
        return int128(Int256(r));
    }

    function Int64(Randomness r, int64 min, int64 max) internal returns (int64) {
        return int64(Int256(r, min, max));
    }

    function Int64(
        Randomness r
    ) internal returns (int64) {
        return int64(Int256(r));
    }

    function Int32(Randomness r, int32 min, int32 max) internal returns (int32) {
        return int32(Int256(r, min, max));
    }

    function Uint256(Randomness r, uint256 min, uint256 max) internal returns (uint256) {
        return max <= min ? min : r.Uint256() % (max - min) + min;
    }

    function Uint256(
        Randomness r
    ) internal returns (uint256) {
        return r.shuffle().unwrap();
    }

    function Uint128(Randomness r, uint128 min, uint128 max) internal returns (uint128) {
        return uint128(Uint256(r, min, max));
    }

    function Uint128(
        Randomness r
    ) internal returns (uint128) {
        return uint128(Uint256(r));
    }

    function Uint64(Randomness r, uint64 min, uint64 max) internal returns (uint64) {
        return uint64(Uint256(r, min, max));
    }

    function Uint64(
        Randomness r
    ) internal returns (uint64) {
        return uint64(Uint256(r));
    }

    function Uint32(Randomness r, uint32 min, uint32 max) internal returns (uint32) {
        return uint32(Uint256(r, min, max));
    }

    function Uint32(
        Randomness r
    ) internal returns (uint32) {
        return uint32(Uint256(r));
    }

    function Bytes32(
        Randomness r
    ) internal returns (bytes32) {
        return bytes32(r.Uint256());
    }

    function Address(
        Randomness r
    ) internal returns (address) {
        return address(uint160(r.Uint256(1, type(uint160).max)));
    }

    function Boolean(
        Randomness r
    ) internal returns (bool) {
        return r.Uint256() % 2 == 0;
    }

    /// -----------------------------------------------------------------------
    /// Arrays
    /// -----------------------------------------------------------------------

    function Int256Array(
        Randomness r,
        uint256 len,
        int256 min,
        int256 max
    ) internal returns (int256[] memory arr) {
        arr = new int256[](len);
        for (uint256 i; i < len; ++i) {
            arr[i] = r.Int256(min, max);
        }
    }

    function Int128Array(
        Randomness r,
        uint256 len,
        int128 min,
        int128 max
    ) internal returns (int128[] memory arr) {
        arr = new int128[](len);
        for (uint256 i; i < len; ++i) {
            arr[i] = r.Int128(min, max);
        }
    }

    function Int64Array(
        Randomness r,
        uint256 len,
        int64 min,
        int64 max
    ) internal returns (int64[] memory arr) {
        arr = new int64[](len);
        for (uint256 i; i < len; ++i) {
            arr[i] = r.Int64(min, max);
        }
    }

    function Int32Array(
        Randomness r,
        uint256 len,
        int32 min,
        int32 max
    ) internal returns (int32[] memory arr) {
        arr = new int32[](len);
        for (uint256 i; i < len; ++i) {
            arr[i] = r.Int32(min, max);
        }
    }

    function Uint256Array(
        Randomness r,
        uint256 len,
        uint256 min,
        uint256 max
    ) internal returns (uint256[] memory arr) {
        arr = new uint256[](len);
        for (uint256 i; i < len; ++i) {
            arr[i] = uint256(r.Uint256(min, max));
        }
    }

    function Uint32Array(
        Randomness r,
        uint256 len,
        uint32 min,
        uint32 max
    ) internal returns (uint32[] memory arr) {
        arr = new uint32[](len);
        for (uint256 i; i < len; ++i) {
            arr[i] = r.Uint32(min, max);
        }
    }

    /// -----------------------------------------------------------------------
    /// Helpers
    /// -----------------------------------------------------------------------

    function wrap(
        uint256 r
    ) internal pure returns (Randomness) {
        return Randomness.wrap(r);
    }

    function unwrap(
        Randomness r
    ) internal pure returns (uint256) {
        return Randomness.unwrap(r);
    }
}

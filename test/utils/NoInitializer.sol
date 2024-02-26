// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

contract NoInitializer {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 public immutable a;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint256 _a) {
        a = _a;
    }
}


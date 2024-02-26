// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

contract WithConstructor {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 public immutable a;

    uint256 public b;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint256 _a) {
        a = _a;
    }

    function initialize(uint256 _b) public {
        b = _b;
    }
}


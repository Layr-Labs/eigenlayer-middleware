// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {AVSDirectory} from "eigenlayer-contracts/src/contracts/core/AVSDirectory.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";

// wrapper around the AVSDirectory contract that exposes internal functionality, for unit testing
contract AVSDirectoryHarness is AVSDirectory {
    constructor(
        IDelegationManager _dm,
        IPauserRegistry _pauser
    ) AVSDirectory(_dm, _pauser, "v0.0.1") {}
}

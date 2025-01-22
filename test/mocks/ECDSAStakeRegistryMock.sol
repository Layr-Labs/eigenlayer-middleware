// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../../src/unaudited/ECDSAStakeRegistry.sol";

/**
 * @title Mock for ECDSAStakeRegistry
 * @dev This contract is a mock implementation of the ECDSAStakeRegistry for testing purposes.
 */
contract ECDSAStakeRegistryMock is ECDSAStakeRegistry {
    constructor(
        IDelegationManager _delegationManager
    ) ECDSAStakeRegistry(_delegationManager) {}
}

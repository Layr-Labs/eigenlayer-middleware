// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../../src/unaudited/ECDSAStakeRegistry.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";

/**
 * @title Mock for ECDSAStakeRegistry
 * @dev This contract is a mock implementation of the ECDSAStakeRegistry for testing purposes.
 */
contract ECDSAStakeRegistryMock is ECDSAStakeRegistry {
    constructor(
        IDelegationManager _delegationManager,
        IAllocationManager _allocationManager,
        address _avsRegistrar,
        IAVSDirectory _avsDirectory
    ) ECDSAStakeRegistry(_delegationManager, _allocationManager, _avsRegistrar, _avsDirectory) {}
    
}

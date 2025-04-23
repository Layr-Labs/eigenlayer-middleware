// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    IAllocationManager,
    OperatorSet
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";

abstract contract AVSRegistrarStorage is IAVSRegistrar {
    // Immutables

    /// @notice The allocation manager core contract.
    IAllocationManager public immutable allocationManager;

    /// @notice The AVS the registrar is for.
    address public immutable avs;

    /// @notice The operator set id the registrar is for.
    uint32 public immutable operatorSetId;

    constructor(address _allocationManager, address _avs, uint32 _operatorSetId) {
        allocationManager = IAllocationManager(_allocationManager);
        avs = _avs;
        operatorSetId = _operatorSetId;
    }

    // TODO: Move errors to the interface
    error OnlyAllocationManager();
}

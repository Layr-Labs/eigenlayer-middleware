// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    IAllocationManager,
    OperatorSet
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";

import {AVSRegistrarStorage} from "./AVSRegistrarStorage.sol";

abstract contract AVSRegistrar is AVSRegistrarStorage {
    modifier onlyAllocationManager() {
        require(msg.sender == address(allocationManager), OnlyAllocationManager());
        _;
    }

    constructor(
        address _allocationManager,
        address _avs
    ) AVSRegistrarStorage(_allocationManager, _avs) {}

    /// @inheritdoc IAVSRegistrar
    /// @dev EigenLayer Core checks that:
    /// 1. The operator set is valid
    /// 2. The operator is not already registered for the AVS
    function registerOperator(
        address operator,
        address avs,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) external virtual override onlyAllocationManager {}

    /// @inheritdoc IAVSRegistrar
    /// @dev EigenLayer Core checks that:
    /// 1. The operator set is valid
    /// 2. The operator is registered for the AVS
    function deregisterOperator(
        address operator,
        address avs,
        uint32[] calldata operatorSetIds
    ) external virtual override onlyAllocationManager {}

    /// @inheritdoc IAVSRegistrar
    function supportsAVS(
        address _avs
    ) external view override returns (bool) {
        return avs == _avs;
    }
}

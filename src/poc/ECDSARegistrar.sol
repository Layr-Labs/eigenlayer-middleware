// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    IAllocationManager,
    OperatorSet
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

import {AVSRegistrar} from "./AVSRegistrar.sol";
import {ECDSARegistrarStorage} from "./ECDSARegistrarStorage.sol";

abstract contract ECDSARegistrar is ECDSARegistrarStorage, AVSRegistrar {

    constructor(address _allocationManager, address _avs) AVSRegistrar(_allocationManager, _avs) {}

    /// @inheritdoc AVSRegistrar
    function registerOperator(
        address operator,
        address avs,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) external virtual override onlyAllocationManager {
        ECDSARegistrarStorageStruct storage $ = _getECDSARegistrarStorage();
        $._operatorMetadata[operator] = OperatorMetadata({
            signingKey: data.signingKey
        });

        _afterRegisterOperator(operator, avs, operatorSetIds, data);
    }

    function _afterRegisterOperator(
        address operator,
        address avs,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) internal virtual {}

    function _afterDeregisterOperator(
        address operator,
        address avs,
        uint32[] calldata operatorSetIds
    ) internal virtual {}
}
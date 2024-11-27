// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";
import {IBLSApkRegistry} from "./interfaces/IBLSApkRegistry.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";
import {IIndexRegistry} from "./interfaces/IIndexRegistry.sol";

abstract contract AVSRegistrar is IAVSRegistrar {
    function registerOperator(
        address operator,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) external virtual;

    function deregisterOperator(
        address operator,
        uint32[] calldata operatorSetIds
    ) external virtual;
}

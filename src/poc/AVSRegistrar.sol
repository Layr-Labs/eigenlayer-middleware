// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    IAllocationManager,
    OperatorSet
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";

import {AVSRegistrarStorage} from "./AVSRegistrarStorage.sol";
import {Initializable} from "@openzeppelin-upgrades-v5/contracts/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin-upgrades-v5/contracts/utils/ContextUpgradeable.sol";

/// @notice A single-operator set AVS registrar
abstract contract AVSRegistrar is Initializable, ContextUpgradeable, AVSRegistrarStorage {
    modifier onlyAllocationManager() {
        require(msg.sender == address(allocationManager), OnlyAllocationManager());
        _;
    }

    constructor(
        address _allocationManager,
        address _avs,
        uint32 operatorSetId
    ) AVSRegistrarStorage(_allocationManager, _avs, operatorSetId) {}

    function __AVSRegistrar_init() internal onlyInitializing {}

    function __AVSRegistrar_init_unchained() internal onlyInitializing {}

    /// @inheritdoc IAVSRegistrar
    /// @dev EigenLayer Core checks that:
    /// 1. The operator set is valid
    /// 2. The operator is not already registered for the AVS
    function registerOperator(
        address operator,
        address avs,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) external virtual override onlyAllocationManager {
        require(supportsAVS(avs), "Invalid AVS");
        require(operatorSetIds.length == 1, "Only accepts one operator set id");
        require(operatorSetIds[0] == operatorSetId, "Invalid operator set id");
        _afterRegisterOperator(operator, data);
    }

    /// @inheritdoc IAVSRegistrar
    /// @dev EigenLayer Core checks that:
    /// 1. The operator set is valid
    /// 2. The operator is registered for the AVS
    function deregisterOperator(
        address operator,
        address avs,
        uint32[] calldata operatorSetIds
    ) external virtual override onlyAllocationManager {
        require(supportsAVS(avs), "Invalid AVS");
        require(operatorSetIds.length == 1, "Only accepts one operator set id");
        require(operatorSetIds[0] == operatorSetId, "Invalid operator set id");
        _afterDeregisterOperator(operator);
    }

    /// @inheritdoc IAVSRegistrar
    function supportsAVS(
        address _avs
    ) public view override returns (bool) {
        return avs == _avs;
    }

    function _afterRegisterOperator(address operator, bytes calldata data) internal virtual {}

    function _afterDeregisterOperator(
        address operator
    ) internal virtual {}

    function _parseRegistrationData(bytes calldata data) internal view virtual returns (bytes memory);
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin-upgrades-v5/contracts/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin-upgrades-v5/contracts/utils/ContextUpgradeable.sol";

import {
    IAllocationManager,
    OperatorSet
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

import {AVSRegistrar} from "./AVSRegistrar.sol";
import {ECDSARegistrarStorage} from "./ECDSARegistrarStorage.sol";
import {IECDSARegistrar} from "./interfaces/IECDSARegistrar.sol";

abstract contract ECDSARegistrar is AVSRegistrar, ECDSARegistrarStorage {
    function __ECDSARegistrar_init(uint256 startIndex, uint256 endIndex) public initializer {
        __ECDSARegistrar_init_unchained(startIndex, endIndex);
    }

    function __ECDSARegistrar_init_unchained(
        uint256 startIndex,
        uint256 endIndex
    ) internal onlyInitializing {
        _getECDSARegistrarStorage().startIndex = startIndex;
        _getECDSARegistrarStorage().endIndex = endIndex;
    }

    /**
     * @notice Overrides the afterRegisterOperator function to set the signing key for an operator
     * @param operator The operator to set the signing key for
     * @param data The data to set the signing key for
     */
    function _afterRegisterOperator(
        address operator,
        bytes calldata data
    ) internal virtual override {
        super._afterRegisterOperator(operator, data);

        address signingKey = abi.decode(_parseRegistrationData(data), (address));
        _getECDSARegistrarStorage()._operatorSigningKey[operator] = signingKey;
    }

    /**
     * @notice Overrides the afterDeregisterOperator function to clear the signing key for an operator
     * @param operator The operator to clear the signing key for
     */
    function _afterDeregisterOperator(
        address operator
    ) internal virtual override {
        super._afterDeregisterOperator(operator);

        _getECDSARegistrarStorage()._operatorSigningKey[operator] = address(0);
    }

    /// @inheritdoc IECDSARegistrar
    function getSigningKey(
        address operator
    ) external view returns (address) {
        return _getECDSARegistrarStorage()._operatorSigningKey[operator];
    }

    function _parseRegistrationData(
        bytes calldata data
    ) internal view virtual override returns (bytes memory) {
        return data[_getECDSARegistrarStorage().startIndex:_getECDSARegistrarStorage().endIndex];
    }
}

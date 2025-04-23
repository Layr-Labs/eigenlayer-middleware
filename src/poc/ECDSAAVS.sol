// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ECDSARegistrar} from "./ECDSARegistrar.sol";
import {AVSRegistrar} from "./AVSRegistrar.sol";
import {SocketRegistry} from "./SocketRegistry.sol";

contract AVS is ECDSARegistrar, SocketRegistry {
    constructor(
        address allocationManager,
        address avs,
        uint32 operatorSetId
    ) AVSRegistrar(allocationManager, avs, operatorSetId) {}

    /**
     * @notice Initializes the AVS contract
     * @param ecdsaRegistrarStartIndex The start index of the ECDSARegistrar
     * @param ecdsaRegistrarEndIndex The end index of the ECDSARegistrar
     * @param socketRegistryStartIndex The start index of the SocketRegistry
     * @param socketRegistryEndIndex The end index of the SocketRegistry
     */
    function initialize(
        uint256 ecdsaRegistrarStartIndex,
        uint256 ecdsaRegistrarEndIndex,
        uint256 socketRegistryStartIndex,
        uint256 socketRegistryEndIndex
    ) public virtual initializer {
        __ECDSAAVS_init(
            ecdsaRegistrarStartIndex,
            ecdsaRegistrarEndIndex,
            socketRegistryStartIndex,
            socketRegistryEndIndex
        );
    }

    function __ECDSAAVS_init(
        uint256 ecdsaRegistrarStartIndex,
        uint256 ecdsaRegistrarEndIndex,
        uint256 socketRegistryStartIndex,
        uint256 socketRegistryEndIndex
    ) internal onlyInitializing {
        __ECDSARegistrar_init(ecdsaRegistrarStartIndex, ecdsaRegistrarEndIndex);
        __SocketRegistry_init(socketRegistryStartIndex, socketRegistryEndIndex);
    }

    function _afterRegisterOperator(
        address operator,
        bytes calldata data
    ) internal override(ECDSARegistrar, SocketRegistry) {
        super._afterRegisterOperator(operator, data);
    }

    function _afterDeregisterOperator(
        address operator
    ) internal override(ECDSARegistrar, SocketRegistry) {
        super._afterDeregisterOperator(operator);
    }

    function _parseRegistrationData(
        bytes calldata data
    ) internal view override(ECDSARegistrar, SocketRegistry) returns (bytes memory) {
        return super._parseRegistrationData(data);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IAVSRegistrarInternal} from "../../interfaces/IAVSRegistrarInternal.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {
    OperatorSetLib,
    OperatorSet
} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";

import {AVSRegistrarStorage} from "./AVSRegistrarStorage.sol";

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

/// @notice A minimal AVSRegistrar contract that is used to register/deregister operators for an AVS
abstract contract AVSRegistrar is Initializable, AVSRegistrarStorage {
    using OperatorSetLib for OperatorSet;

    modifier onlyAllocationManager() {
        require(msg.sender == address(allocationManager), NotAllocationManager());
        _;
    }

    constructor(
        IAllocationManager _allocationManager,
        IKeyRegistrar _keyRegistrar
    ) AVSRegistrarStorage(_allocationManager, _keyRegistrar) {
        _disableInitializers();
    }

    /// @dev This initialization function MUST be added to a child's `initialize` function to avoid uninitialized storage.
    function __AVSRegistrar_init(
        address _avs
    ) internal virtual onlyInitializing {
        avs = _avs;
    }

    /// @inheritdoc IAVSRegistrar
    /// @dev Reverts for:
    ///      - NotAllocationManager: The caller is not the allocation manager
    ///      - KeyNotRegistered: The operator has not registered a key for the given operator sets in the `KeyRegistrar`
    function registerOperator(
        address operator,
        address, /* avs */
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) external virtual onlyAllocationManager {
        _beforeRegisterOperator(operator, operatorSetIds, data);

        // Check that the operator has a valid key
        _validateOperatorKeys(operator, operatorSetIds);

        _afterRegisterOperator(operator, operatorSetIds, data);

        emit OperatorRegistered(operator, operatorSetIds);
    }

    /// @inheritdoc IAVSRegistrar
    /// @dev Reverts for:
    ///      - NotAllocationManager: The caller is not the allocation manager
    function deregisterOperator(
        address operator,
        address, /* avs */
        uint32[] calldata operatorSetIds
    ) external virtual onlyAllocationManager {
        _beforeDeregisterOperator(operator, operatorSetIds);

        _afterDeregisterOperator(operator, operatorSetIds);

        emit OperatorDeregistered(operator, operatorSetIds);
    }

    /// @inheritdoc IAVSRegistrar
    function supportsAVS(
        address _avs
    ) public view virtual returns (bool) {
        return _avs == avs;
    }

    /*
     *
     *                            INTERNAL FUNCTIONS
     *
     */

    /**
     * @notice Validates that the operator has registered a key for the given operator sets in the `KeyRegistrar`
     * @param operator The operator to validate
     * @param operatorSetIds The operator sets to validate
     * @dev Reverts for:
     *      - KeyNotRegistered: The operator has not registered a key for the given operator sets in the `KeyRegistrar`
     */
    function _validateOperatorKeys(
        address operator,
        uint32[] calldata operatorSetIds
    ) internal view {
        for (uint32 i = 0; i < operatorSetIds.length; i++) {
            OperatorSet memory operatorSet = OperatorSet({avs: avs, id: operatorSetIds[i]});
            require(keyRegistrar.isRegistered(operatorSet, operator), KeyNotRegistered());
        }
    }

    /**
     * @notice Hook called before the operator is registered
     * @param operator The operator to register
     * @param operatorSetIds The operator sets to register
     * @param data The data to register
     */
    function _beforeRegisterOperator(
        address operator,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) internal virtual {}

    /**
     * @notice Hook called after the operator is registered
     * @param operator The operator to register
     * @param operatorSetIds The operator sets to register
     * @param data The data to register
     */
    function _afterRegisterOperator(
        address operator,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) internal virtual {}

    /**
     * @notice Hook called before the operator is deregistered
     * @param operator The operator to deregister
     * @param operatorSetIds The operator sets to deregister
     */
    function _beforeDeregisterOperator(
        address operator,
        uint32[] calldata operatorSetIds
    ) internal virtual {}

    /**
     * @notice Hook called after the operator is deregistered
     * @param operator The operator to deregister
     * @param operatorSetIds The operator sets to deregister
     */
    function _afterDeregisterOperator(
        address operator,
        uint32[] calldata operatorSetIds
    ) internal virtual {}
}

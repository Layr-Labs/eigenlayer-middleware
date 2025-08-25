// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

import {AVSRegistrar} from "../../middlewareV2/registrar/AVSRegistrar.sol";
import {SocketRegistry} from "../../middlewareV2/registrar/modules/SocketRegistry.sol";
import {Allowlist} from "../../middlewareV2/registrar/modules/Allowlist.sol";
import {ITaskAVSRegistrarBase} from "../../interfaces/ITaskAVSRegistrarBase.sol";
import {TaskAVSRegistrarBaseStorage} from "./TaskAVSRegistrarBaseStorage.sol";

/**
 * @title TaskAVSRegistrarBase
 * @author Layr Labs, Inc.
 * @notice Abstract AVS Registrar for task-based AVSs
 */
abstract contract TaskAVSRegistrarBase is
    AVSRegistrar,
    SocketRegistry,
    Allowlist,
    TaskAVSRegistrarBaseStorage
{
    /**
     * @dev Constructor that passes parameters to parent
     * @param _allocationManager The AllocationManager contract address
     * @param _keyRegistrar The KeyRegistrar contract address
     * @param _permissionController The PermissionController contract address
     */
    constructor(
        IAllocationManager _allocationManager,
        IKeyRegistrar _keyRegistrar,
        IPermissionController _permissionController
    ) AVSRegistrar(_allocationManager, _keyRegistrar) SocketRegistry(_permissionController) {
        _disableInitializers();
    }

    /**
     * @dev Initializer for the upgradeable contract
     * @param _avs The address of the AVS
     * @param _owner The owner of the contract
     * @param _initialConfig The initial AVS configuration
     */
    function __TaskAVSRegistrarBase_init(
        address _avs,
        address _owner,
        AvsConfig memory _initialConfig
    ) internal onlyInitializing {
        __Allowlist_init(_owner); // initializes Ownable
        __AVSRegistrar_init(_avs);

        _setAvsConfig(_initialConfig);
    }

    /// @inheritdoc ITaskAVSRegistrarBase
    function setAvsConfig(
        AvsConfig memory config
    ) external onlyOwner {
        _setAvsConfig(config);
    }

    /// @inheritdoc ITaskAVSRegistrarBase
    function getAvsConfig() external view returns (AvsConfig memory) {
        return avsConfig;
    }

    /**
     * @notice Internal function to set the AVS configuration
     * @param config The AVS configuration to set
     * @dev The executorOperatorSetIds must be monotonically increasing.
     */
    function _setAvsConfig(
        AvsConfig memory config
    ) internal {
        // Require at least one executor operator set
        require(config.executorOperatorSetIds.length > 0, ExecutorOperatorSetIdsEmpty());

        // Check monotonically increasing order and no aggregator overlap in one pass
        for (uint256 i = 0; i < config.executorOperatorSetIds.length; i++) {
            require(
                config.aggregatorOperatorSetId != config.executorOperatorSetIds[i],
                InvalidAggregatorOperatorSetId()
            );
            require(
                i == 0 || config.executorOperatorSetIds[i] > config.executorOperatorSetIds[i - 1],
                DuplicateExecutorOperatorSetId()
            );
        }

        avsConfig = config;
        emit AvsConfigSet(config.aggregatorOperatorSetId, config.executorOperatorSetIds);
    }

    /**
     * @notice Before registering operator, check if the operator is in the allowlist for the aggregator operator set
     * @dev Only the aggregator operator set requires allowlist validation. Executor operator sets do not require allowlist checks.
     * @param operator The address of the operator
     * @param operatorSetIds The IDs of the operator sets
     * @param data The data passed to the operator
     */
    function _beforeRegisterOperator(
        address operator,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) internal override {
        super._beforeRegisterOperator(operator, operatorSetIds, data);

        for (uint32 i = 0; i < operatorSetIds.length; i++) {
            if (operatorSetIds[i] == avsConfig.aggregatorOperatorSetId) {
                require(
                    isOperatorAllowed(OperatorSet({avs: avs, id: operatorSetIds[i]}), operator),
                    OperatorNotInAllowlist()
                );
            }
        }
    }

    /**
     * @notice Set the socket for the operator
     * @dev This function sets the socket even if the operator is already registered
     * @dev Operators should make sure to always provide the socket when registering
     * @param operator The address of the operator
     * @param operatorSetIds The IDs of the operator sets
     * @param data The data passed to the operator
     */
    function _afterRegisterOperator(
        address operator,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) internal override {
        super._afterRegisterOperator(operator, operatorSetIds, data);

        // Set operator socket
        string memory socket = abi.decode(data, (string));
        _setOperatorSocket(operator, socket);
    }
}

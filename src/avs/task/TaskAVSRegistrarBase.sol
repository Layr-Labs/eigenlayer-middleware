// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import {AVSRegistrarWithSocket} from
    "../../middlewareV2/registrar/presets/AVSRegistrarWithSocket.sol";
import {ITaskAVSRegistrarBase} from "../../interfaces/ITaskAVSRegistrarBase.sol";
import {TaskAVSRegistrarBaseStorage} from "./TaskAVSRegistrarBaseStorage.sol";

/**
 * @title TaskAVSRegistrarBase
 * @author Layr Labs, Inc.
 * @notice Abstract AVS Registrar for task-based AVSs
 */
abstract contract TaskAVSRegistrarBase is
    Initializable,
    OwnableUpgradeable,
    AVSRegistrarWithSocket,
    TaskAVSRegistrarBaseStorage
{
    /**
     * @dev Constructor that passes parameters to parent
     * @param _allocationManager The AllocationManager contract address
     * @param _keyRegistrar The KeyRegistrar contract address
     */
    constructor(
        IAllocationManager _allocationManager,
        IKeyRegistrar _keyRegistrar
    ) AVSRegistrarWithSocket(_allocationManager, _keyRegistrar) {
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
        __AVSRegistrar_init(_avs);
        __Ownable_init();
        _transferOwnership(_owner);
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
}

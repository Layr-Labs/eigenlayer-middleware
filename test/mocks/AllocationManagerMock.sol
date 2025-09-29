// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    IAllocationManager,
    OperatorSet
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {ISemVerMixin} from "eigenlayer-contracts/src/contracts/interfaces/ISemVerMixin.sol";

contract AllocationManagerIntermediate is IAllocationManager {
    mapping(address avs => address avsRegistrar) internal _avsRegistrar;

    function initialize(
        uint256 initialPausedStatus
    ) external virtual {}

    function slashOperator(
        address avs,
        SlashingParams calldata params
    ) external virtual returns (uint256, uint256[] memory) {}

    function modifyAllocations(
        address operator,
        AllocateParams[] calldata params
    ) external virtual {}

    function clearDeallocationQueue(
        address operator,
        IStrategy[] calldata strategies,
        uint16[] calldata numToClear
    ) external virtual {}

    function registerForOperatorSets(
        address operator,
        RegisterParams calldata params
    ) external virtual {}

    function deregisterFromOperatorSets(
        DeregisterParams calldata params
    ) external virtual {}

    function setAllocationDelay(address operator, uint32 delay) external virtual {}

    function setAVSRegistrar(address avs, IAVSRegistrar avsRegistrar) external {
        _avsRegistrar[avs] = address(avsRegistrar);
    }

    function getAVSRegistrar(
        address avs
    ) external view override returns (IAVSRegistrar) {
        return IAVSRegistrar(_avsRegistrar[avs]);
    }

    function updateAVSMetadataURI(address avs, string calldata metadataURI) external virtual {}

    function createOperatorSets(address avs, CreateSetParams[] calldata params) external virtual {}

    function createRedistributingOperatorSets(
        address avs,
        CreateSetParams[] calldata params,
        address[] calldata redistributionRecipients
    ) external virtual {}

    function addStrategiesToOperatorSet(
        address avs,
        uint32 operatorSetId,
        IStrategy[] calldata strategies
    ) external virtual {}

    function removeStrategiesFromOperatorSet(
        address avs,
        uint32 operatorSetId,
        IStrategy[] calldata strategies
    ) external virtual {}

    function getOperatorSetCount(
        address avs
    ) external view virtual returns (uint256) {}

    function getAllocatedSets(
        address operator
    ) external view virtual returns (OperatorSet[] memory) {}

    function getAllocatedStrategies(
        address operator,
        OperatorSet memory operatorSet
    ) external view virtual returns (IStrategy[] memory) {}

    function getAllocation(
        address operator,
        OperatorSet memory operatorSet,
        IStrategy strategy
    ) external view virtual returns (Allocation memory) {}

    function getAllocations(
        address[] memory operators,
        OperatorSet memory operatorSet,
        IStrategy strategy
    ) external view virtual returns (Allocation[] memory) {}

    function getStrategyAllocations(
        address operator,
        IStrategy strategy
    ) external view virtual returns (OperatorSet[] memory, Allocation[] memory) {}

    function getAllocatableMagnitude(
        address operator,
        IStrategy strategy
    ) external view virtual returns (uint64) {}

    function getMaxMagnitude(
        address operator,
        IStrategy strategy
    ) external view virtual returns (uint64) {}

    function getMaxMagnitudes(
        address operator,
        IStrategy[] calldata strategies
    ) external view virtual returns (uint64[] memory) {}

    function getMaxMagnitudes(
        address[] calldata operators,
        IStrategy strategy
    ) external view virtual returns (uint64[] memory) {}

    function getMaxMagnitudesAtBlock(
        address operator,
        IStrategy[] calldata strategies,
        uint32 blockNumber
    ) external view virtual returns (uint64[] memory) {}

    function getAllocationDelay(
        address operator
    ) external view virtual returns (bool isSet, uint32 delay) {}

    function getRegisteredSets(
        address operator
    ) external view virtual returns (OperatorSet[] memory operatorSets) {}

    function isOperatorSet(
        OperatorSet memory operatorSet
    ) external view virtual returns (bool) {}

    function getMembers(
        OperatorSet memory operatorSet
    ) external view virtual returns (address[] memory operators) {}

    function getMemberCount(
        OperatorSet memory operatorSet
    ) external view virtual returns (uint256) {}

    function getStrategiesInOperatorSet(
        OperatorSet memory operatorSet
    ) external view virtual returns (IStrategy[] memory strategies) {}

    function getMinimumSlashableStake(
        OperatorSet memory operatorSet,
        address[] memory operators,
        IStrategy[] memory strategies,
        uint32 futureBlock
    ) external view virtual returns (uint256[][] memory slashableStake) {}

    function isMemberOfOperatorSet(
        address operator,
        OperatorSet memory operatorSet
    ) external view virtual returns (bool) {}

    function getAllocatedStake(
        OperatorSet memory, /* operatorSet */
        address[] memory operators,
        IStrategy[] memory strategies
    ) external view virtual returns (uint256[][] memory slashableStake) {
        uint256[][] memory result = new uint256[][](operators.length);
        for (uint256 i = 0; i < operators.length; i++) {
            result[i] = new uint256[](strategies.length);
            for (uint256 j = 0; j < strategies.length; j++) {
                result[i][j] = 0;
            }
        }
        return result;
    }

    function getEncumberedMagnitude(
        address, /* operator */
        IStrategy /* strategy */
    ) external view virtual returns (uint64) {
        return 0;
    }

    function isOperatorSlashable(
        address, /* operator */
        OperatorSet memory /* operatorSet */
    ) external view virtual returns (bool) {
        return false;
    }

    function version() external pure virtual returns (string memory) {
        return "v0.0.1";
    }

    function DEALLOCATION_DELAY() external pure virtual returns (uint32) {}

    function getRedistributionRecipient(
        OperatorSet memory operatorSet
    ) external pure virtual returns (address) {}

    function getSlashCount(
        OperatorSet memory operatorSet
    ) external pure virtual returns (uint256) {}

    function isOperatorRedistributable(
        address operator
    ) external pure virtual returns (bool) {}

    function isRedistributingOperatorSet(
        OperatorSet memory operatorSet
    ) external pure virtual returns (bool) {}
}

contract AllocationManagerMock is AllocationManagerIntermediate {
    uint32 internal constant _DEALLOCATION_DELAY = 86400;

    mapping(bytes32 operatorSetKey => address[] members) internal _members;
    mapping(bytes32 operatorSetKey => IStrategy[] strategies) internal _strategies;
    mapping(
        bytes32 operatorSetKey
            => mapping(
                address operator => mapping(IStrategy strategy => uint256 minimumSlashableStake)
            )
    ) internal _minimumSlashableStake;

    function DEALLOCATION_DELAY() external pure override returns (uint32) {
        return _DEALLOCATION_DELAY;
    }

    function getRedistributionRecipient(
        OperatorSet memory /* operatorSet */
    ) external pure override returns (address) {
        return address(0);
    }

    function getSlashCount(
        OperatorSet memory /* operatorSet */
    ) external pure override returns (uint256) {
        return 0;
    }

    function initialize(
        uint256 initialPausedStatus
    ) external override {}

    function isOperatorRedistributable(
        address /* operator */
    ) external pure override returns (bool) {
        return false;
    }

    function isRedistributingOperatorSet(
        OperatorSet memory /* operatorSet */
    ) external pure override returns (bool) {
        return false;
    }

    function getAllocatedStake(
        address, /* operator */
        IStrategy /* strategy */
    ) external pure returns (uint256) {
        return 0;
    }

    function getMembers(
        OperatorSet memory operatorSet
    ) external view override returns (address[] memory) {
        return _members[operatorSet.key()];
    }

    function setMembersInOperatorSet(
        OperatorSet memory operatorSet,
        address[] memory members
    ) external {
        _members[operatorSet.key()] = members;
    }

    function setStrategiesInOperatorSet(
        OperatorSet memory operatorSet,
        IStrategy[] memory strategies
    ) external {
        _strategies[operatorSet.key()] = strategies;
    }

    function getStrategiesInOperatorSet(
        OperatorSet memory operatorSet
    ) external view override returns (IStrategy[] memory) {
        return _strategies[operatorSet.key()];
    }

    function setMinimumSlashableStake(
        OperatorSet memory operatorSet,
        address[] memory operators,
        IStrategy[] memory strategies,
        uint256[][] memory minimumSlashableStake
    ) external {
        for (uint256 i = 0; i < operators.length; ++i) {
            for (uint256 j = 0; j < strategies.length; ++j) {
                _minimumSlashableStake[operatorSet.key()][operators[i]][strategies[j]] =
                    minimumSlashableStake[i][j];
            }
        }
    }

    function getMinimumSlashableStake(
        OperatorSet memory operatorSet,
        address[] memory operators,
        IStrategy[] memory strategies,
        uint32 /* futureBlock */
    ) external view override returns (uint256[][] memory) {
        uint256[][] memory minimumSlashableStake = new uint256[][](operators.length);

        for (uint256 i = 0; i < operators.length; ++i) {
            minimumSlashableStake[i] = new uint256[](strategies.length);
        }

        for (uint256 i = 0; i < operators.length; ++i) {
            for (uint256 j = 0; j < strategies.length; ++j) {
                minimumSlashableStake[i][j] =
                    _minimumSlashableStake[operatorSet.key()][operators[i]][strategies[j]];
            }
        }

        return minimumSlashableStake;
    }

    /**
     * @notice Register an operator to an AVS through the AVS registrar
     * @dev This function delegates to the appropriate AVS registrar
     */
    function registerOperator(
        address avs,
        address operator,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) external {
        IAVSRegistrar avsRegistrar = IAVSRegistrar(_avsRegistrar[avs]);
        avsRegistrar.registerOperator(operator, avs, operatorSetIds, data);
    }
}

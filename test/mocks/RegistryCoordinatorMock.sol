// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../../src/interfaces/IRegistryCoordinator.sol";
import "../../src/interfaces/ISlashingRegistryCoordinator.sol";
import "../../src/libraries/BN254.sol";
import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";

abstract contract RegistryCoordinatorMock is IRegistryCoordinator {
    // Add missing function declarations from interface
    function OPERATOR_CHURN_APPROVAL_TYPEHASH() external pure virtual returns (bytes32);
    function PUBKEY_REGISTRATION_TYPEHASH() external pure virtual returns (bytes32);
    function allocationManager() external view virtual returns (IAllocationManager);
    function calculateOperatorChurnApprovalDigestHash(
        address registeringOperator,
        bytes32 registeringOperatorId,
        OperatorKickParam[] memory operatorKickParams,
        bytes32 salt,
        uint256 expiry
    ) external view virtual returns (bytes32);
    function churnApprover() external view virtual returns (address);
    function createSlashableStakeQuorum(
        OperatorSetParam memory operatorSetParams,
        uint96 minimumStake,
        IStakeRegistryTypes.StrategyParams[] memory strategyParams,
        uint32 lookAheadPeriod
    ) external virtual;
    function createTotalDelegatedStakeQuorum(
        OperatorSetParam memory operatorSetParams,
        uint96 minimumStake,
        IStakeRegistryTypes.StrategyParams[] memory strategyParams
    ) external virtual;
    function deregisterOperator(
        address operator,
        uint32[] memory operatorSetIds
    ) external virtual;
    function ejectionCooldown() external view virtual returns (uint256);
    function ejector() external view virtual returns (address);
    function enableOperatorSets() external virtual;
    function initialize(
        address _initialOwner,
        address _churnApprover,
        address _ejector,
        uint256 _initialPausedStatus,
        OperatorSetParam[] memory _operatorSetParams,
        uint96[] memory _minimumStakes,
        IStakeRegistryTypes.StrategyParams[][] memory _strategyParams,
        IStakeRegistryTypes.StakeType[] memory _stakeTypes,
        uint32[] memory _lookAheadPeriods
    ) external virtual;
    function isChurnApproverSaltUsed(
        bytes32 salt
    ) external view virtual returns (bool);
    function lastEjectionTimestamp(
        address operator
    ) external view virtual returns (uint256);
    function registerOperator(
        address operator,
        uint32[] memory operatorSetIds,
        bytes memory data
    ) external virtual;
    function registerOperator(
        bytes memory quorumNumbers,
        string memory socket,
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory params,
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature
    ) external virtual;
    function registerOperatorWithChurn(
        bytes calldata quorumNumbers,
        string memory socket,
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory params,
        ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory kickParams,
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory churnApproverSignature,
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature
    ) external virtual;
    function setChurnApprover(
        address _churnApprover
    ) external virtual;
    function setEjectionCooldown(
        uint256 _ejectionCooldown
    ) external virtual;
    function setEjector(
        address _ejector
    ) external virtual;
    function setOperatorSetParams(
        uint8 quorumNumber,
        OperatorSetParam memory operatorSetParams
    ) external virtual;
    function updateOperators(
        address[] memory operators
    ) external virtual;
    function updateOperatorsForQuorum(
        address[][] memory operatorsPerQuorum,
        bytes calldata quorumNumbers
    ) external virtual;
    function updateSocket(
        string memory socket
    ) external virtual;

    // Keep existing implementations
    function blsApkRegistry() external view virtual returns (IBLSApkRegistry) {}
    function ejectOperator(address operator, bytes calldata quorumNumbers) external virtual {}
    function getOperatorSetParams(
        uint8 quorumNumber
    ) external view virtual returns (OperatorSetParam memory) {}
    function indexRegistry() external view virtual returns (IIndexRegistry) {}
    function stakeRegistry() external view virtual returns (IStakeRegistry) {}
    function quorumCount() external view virtual returns (uint8) {}
    function getOperator(
        address operator
    ) external view virtual returns (OperatorInfo memory) {}
    function getOperatorId(
        address operator
    ) external view virtual returns (bytes32) {}
    function getOperatorFromId(
        bytes32 operatorId
    ) external view virtual returns (address) {}
    function getOperatorStatus(
        address operator
    ) external view virtual returns (OperatorStatus) {}
    function getQuorumBitmapIndicesAtBlockNumber(
        uint32 blockNumber,
        bytes32[] memory operatorIds
    ) external view virtual returns (uint32[] memory) {}
    function getQuorumBitmapAtBlockNumberByIndex(
        bytes32 operatorId,
        uint32 blockNumber,
        uint256 index
    ) external view virtual returns (uint192) {}
    function getQuorumBitmapUpdateByIndex(
        bytes32 operatorId,
        uint256 index
    ) external view virtual returns (QuorumBitmapUpdate memory) {}
    function getCurrentQuorumBitmap(
        bytes32 operatorId
    ) external view virtual returns (uint192) {}
    function getQuorumBitmapHistoryLength(
        bytes32 operatorId
    ) external view virtual returns (uint256) {}
    function numRegistries() external view virtual returns (uint256) {}
    function registries(
        uint256
    ) external view virtual returns (address) {}
    function deregisterOperator(
        bytes calldata quorumNumbers
    ) external virtual {}

    function pubkeyRegistrationMessageHash(
        address operator
    ) public view virtual returns (BN254.G1Point memory) {
        return BN254.hashToG1(keccak256(abi.encode(operator)));
    }

    function quorumUpdateBlockNumber(
        uint8 quorumNumber
    ) external view virtual returns (uint256) {}
    function owner() external view virtual returns (address) {}
    function serviceManager() external view virtual returns (IServiceManager) {}

    function isM2Quorum(
        uint8 quorumNumber
    ) external view virtual returns (bool) {
        return false;
    }
}

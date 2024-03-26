// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;


import "../../src/interfaces/IRegistryCoordinator.sol";


contract RegistryCoordinatorMock is IRegistryCoordinator {
    function blsApkRegistry() external view returns (IBLSApkRegistry) {}

    function ejectOperator(
        address operator, 
        bytes calldata quorumNumbers
    ) external {}

    function getOperatorSetParams(uint8 quorumNumber) external view returns (OperatorSetParam memory) {}

    function indexRegistry() external view returns (IIndexRegistry) {}

    function stakeRegistry() external view returns (IStakeRegistry) {}

    function quorumCount() external view returns (uint8) {}
    /// @notice Returns the bitmap of the quorums the operator is registered for.
    function operatorIdToQuorumBitmap(bytes32 pubkeyHash) external view returns (uint256){}

    function getOperator(address operator) external view returns (OperatorInfo memory){}

    /// @notice Returns the stored id for the specified `operator`.
    function getOperatorId(address operator) external view returns (bytes32){}

    /// @notice Returns the operator address for the given `operatorId`
    function getOperatorFromId(bytes32 operatorId) external view returns (address) {}

    /// @notice Returns the status for the given `operator`
    function getOperatorStatus(address operator) external view returns (IRegistryCoordinator.OperatorStatus){}

    /// @notice Returns task number from when `operator` has been registered.
    function getFromTaskNumberForOperator(address operator) external view returns (uint32){}

    function getQuorumBitmapIndicesAtBlockNumber(uint32 blockNumber, bytes32[] memory operatorIds) external view returns (uint32[] memory){}

    /// @notice Returns the quorum bitmap for the given `operatorId` at the given `blockNumber` via the `index`
    function getQuorumBitmapAtBlockNumberByIndex(bytes32 operatorId, uint32 blockNumber, uint256 index) external view returns (uint192) {}

    /// @notice Returns the `index`th entry in the operator with `operatorId`'s bitmap history
    function getQuorumBitmapUpdateByIndex(bytes32 operatorId, uint256 index) external view returns (QuorumBitmapUpdate memory) {}

    /// @notice Returns the current quorum bitmap for the given `operatorId`
    function getCurrentQuorumBitmap(bytes32 operatorId) external view returns (uint192) {}

    /// @notice Returns the length of the quorum bitmap history for the given `operatorId`
    function getQuorumBitmapHistoryLength(bytes32 operatorId) external view returns (uint256) {}

    function numRegistries() external view returns (uint256){}

    function registries(uint256) external view returns (address){}

    function registerOperator(bytes memory quorumNumbers, bytes calldata) external {}

    function deregisterOperator(bytes calldata quorumNumbers, bytes calldata) external {}

    function pubkeyRegistrationMessageHash(address operator) public view returns (BN254.G1Point memory) {
        return BN254.hashToG1(
                keccak256(abi.encode(operator))
        );
    }

    function quorumUpdateBlockNumber(uint8 quorumNumber) external view returns (uint256) {}

    function owner() external view returns (address) {}
}

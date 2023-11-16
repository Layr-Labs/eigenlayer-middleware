// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "src/BLSPubkeyRegistryStorage.sol";
import "src/libraries/BN254.sol";

contract BLSPubkeyRegistryMock is BLSPubkeyRegistryStorage {
    using BN254 for BN254.G1Point;

    /*******************************************************************************
                      EXTERNAL FUNCTIONS - REGISTRY COORDINATOR
    *******************************************************************************/
    constructor(
        IRegistryCoordinator _registryCoordinator, 
        IBLSPublicKeyCompendium _pubkeyCompendium
    ) BLSPubkeyRegistryStorage(_registryCoordinator, _pubkeyCompendium) {}
  
    function registerOperator(
        address operator,
        bytes memory quorumNumbers
    ) public virtual returns (bytes32) {
        return bytes32(abi.encode(operator));
    }

    function deregisterOperator(
        address operator,
        bytes memory quorumNumbers
    ) public virtual {
        emit OperatorRemovedFromQuorums(operator, quorumNumbers);
    }

    function initializeQuorum(uint8 quorumNumber) public virtual {}

    /*******************************************************************************
                            VIEW FUNCTIONS
    *******************************************************************************/

    /**
     * @notice Returns the indices of the quorumApks index at `blockNumber` for the provided `quorumNumbers`
     * @dev Returns the current indices if `blockNumber >= block.number`
     */
    function getApkIndicesAtBlockNumber(
        bytes calldata quorumNumbers,
        uint256 blockNumber
    ) external view returns (uint32[] memory) {
        uint32[] memory indices = new uint32[](quorumNumbers.length);
        return indices;
    }

    /// @notice Returns the current APK for the provided `quorumNumber `
    function getApk(
        uint8 quorumNumber
    ) external view returns (BN254.G1Point memory) {}

    /// @notice Returns the `ApkUpdate` struct at `index` in the list of APK updates for the `quorumNumber`
    function getApkUpdateAtIndex(
        uint8 quorumNumber,
        uint256 index
    ) external view returns (ApkUpdate memory) {}

    /**
     * @notice get hash of the apk of `quorumNumber` at `blockNumber` using the provided `index`;
     * called by checkSignatures in BLSSignatureChecker.sol.
     * @param quorumNumber is the quorum whose ApkHash is being retrieved
     * @param blockNumber is the number of the block for which the latest ApkHash will be retrieved
     * @param index is the index of the apkUpdate being retrieved from the list of quorum apkUpdates in storage
     */
    function getApkHashAtBlockNumberAndIndex(
        uint8 quorumNumber,
        uint32 blockNumber,
        uint256 index
    ) external view returns (bytes24) {}

    /// @notice Returns the length of ApkUpdates for the provided `quorumNumber`
    function getApkHistoryLength(
        uint8 quorumNumber
    ) external view returns (uint32) {}

    /// @notice Returns the operator address for the given `pubkeyHash`
    function getOperatorFromPubkeyHash(
        bytes32 pubkeyHash
    ) public view returns (address) {}

    function getOperatorId(address operator) public view returns (bytes32) {
        return bytes32(abi.encode(operator));
    }
}
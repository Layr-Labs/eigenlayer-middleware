// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "src/BLSPubkeyRegistryStorage.sol";
import "eigenlayer-contracts/src/contracts/libraries/BN254.sol";

contract BLSPubkeyRegistryMock is BLSPubkeyRegistryStorage {
    using BN254 for BN254.G1Point;

    /*******************************************************************************
                      EXTERNAL FUNCTIONS - REGISTRY COORDINATOR
    *******************************************************************************/
    constructor(
        IRegistryCoordinator _registryCoordinator, 
        IBLSPublicKeyCompendium _pubkeyCompendium
    ) BLSPubkeyRegistryStorage(_registryCoordinator, _pubkeyCompendium) {}

    /**
     * @notice Registers the `operator`'s pubkey for the specified `quorumNumbers`.
     * @param operator The address of the operator to register.
     * @param quorumNumbers The quorum numbers the operator is registering for, where each byte is an 8 bit integer quorumNumber.
     * @param pubkey The operator's BLS public key.
     * @return pubkeyHash of the operator's pubkey
     * @dev access restricted to the RegistryCoordinator
     * @dev Preconditions (these are assumed, not validated in this contract):
     *         1) `quorumNumbers` has no duplicates
     *         2) `quorumNumbers.length` != 0
     *         3) `quorumNumbers` is ordered in ascending order
     *         4) the operator is not already registered
     */
    function registerOperator(
        address operator,
        bytes memory quorumNumbers,
        BN254.G1Point memory pubkey
    ) public virtual returns (bytes32) {
        return bytes32(abi.encode(msg.sender));
    }

    /**
     * @notice Deregisters the `operator`'s pubkey for the specified `quorumNumbers`.
     * @param operator The address of the operator to deregister.
     * @param quorumNumbers The quorum numbers the operator is deregistering from, where each byte is an 8 bit integer quorumNumber.
     * @param pubkey The public key of the operator.
     * @dev access restricted to the RegistryCoordinator
     * @dev Preconditions (these are assumed, not validated in this contract):
     *         1) `quorumNumbers` has no duplicates
     *         2) `quorumNumbers.length` != 0
     *         3) `quorumNumbers` is ordered in ascending order
     *         4) the operator is not already deregistered
     *         5) `quorumNumbers` is a subset of the quorumNumbers that the operator is registered for
     *         6) `pubkey` is the same as the parameter used when registering
     */
    function deregisterOperator(
        address operator,
        bytes memory quorumNumbers,
        BN254.G1Point memory pubkey
    ) public virtual {
        emit OperatorRemovedFromQuorums(operator, quorumNumbers);
    }

    /*******************************************************************************
                            VIEW FUNCTIONS
    *******************************************************************************/

    /**
     * @notice Returns the indices of the quorumApks index at `blockNumber` for the provided `quorumNumbers`
     * @dev Returns the current indices if `blockNumber >= block.number`
     */
    function getApkIndicesForQuorumsAtBlockNumber(
        bytes calldata quorumNumbers,
        uint256 blockNumber
    ) external view returns (uint32[] memory) {
        uint32[] memory indices = new uint32[](quorumNumbers.length);
        return indices;
    }

    /// @notice Returns the current APK for the provided `quorumNumber `
    function getApkForQuorum(
        uint8 quorumNumber
    ) external view returns (BN254.G1Point memory) {}

    /// @notice Returns the `ApkUpdate` struct at `index` in the list of APK updates for the `quorumNumber`
    function getApkUpdateForQuorumByIndex(
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
    function getApkHashForQuorumAtBlockNumberFromIndex(
        uint8 quorumNumber,
        uint32 blockNumber,
        uint256 index
    ) external view returns (bytes24) {}

    /// @notice Returns the length of ApkUpdates for the provided `quorumNumber`
    function getQuorumApkHistoryLength(
        uint8 quorumNumber
    ) external view returns (uint32) {}

    /// @notice Returns the operator address for the given `pubkeyHash`
    function getOperatorFromPubkeyHash(
        bytes32 pubkeyHash
    ) public view returns (address) {}
}

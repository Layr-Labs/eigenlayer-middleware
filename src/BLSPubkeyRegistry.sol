// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "src/libraries/BN254.sol";

import "src/BLSPubkeyRegistryStorage.sol";

contract BLSPubkeyRegistry is BLSPubkeyRegistryStorage {
    using BN254 for BN254.G1Point;

    /// @notice when applied to a function, only allows the RegistryCoordinator to call it
    modifier onlyRegistryCoordinator() {
        require(
            msg.sender == address(registryCoordinator),
            "BLSPubkeyRegistry.onlyRegistryCoordinator: caller is not the registry coordinator"
        );
        _;
    }

    /// @notice Sets the (immutable) `registryCoordinator` and `pubkeyCompendium` addresses
    constructor(
        IRegistryCoordinator _registryCoordinator, 
        IBLSPublicKeyCompendium _pubkeyCompendium
    ) BLSPubkeyRegistryStorage(_registryCoordinator, _pubkeyCompendium) {}

    /*******************************************************************************
                      EXTERNAL FUNCTIONS - REGISTRY COORDINATOR
    *******************************************************************************/

    /**
     * @notice Registers the `operator`'s pubkey for the specified `quorumNumbers`.
     * @param operator The address of the operator to register.
     * @param quorumNumbers The quorum numbers the operator is registering for, where each byte is an 8 bit integer quorumNumber.
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
        bytes memory quorumNumbers
    ) public virtual onlyRegistryCoordinator returns (bytes32) {
        // Get the operator's pubkey from the compendium. Reverts if they have not registered a key
        (BN254.G1Point memory pubkey, bytes32 pubkeyHash) = pubkeyCompendium.getRegisteredPubkey(operator);

        // Update each quorum's aggregate pubkey
        _processQuorumApkUpdate(quorumNumbers, pubkey);

        // Return pubkeyHash, which will become the operator's unique id
        emit OperatorAddedToQuorums(operator, quorumNumbers);
        return pubkeyHash;
    }

    /**
     * @notice Deregisters the `operator`'s pubkey for the specified `quorumNumbers`.
     * @param operator The address of the operator to deregister.
     * @param quorumNumbers The quorum numbers the operator is deregistering from, where each byte is an 8 bit integer quorumNumber.
     * @dev access restricted to the RegistryCoordinator
     * @dev Preconditions (these are assumed, not validated in this contract):
     *         1) `quorumNumbers` has no duplicates
     *         2) `quorumNumbers.length` != 0
     *         3) `quorumNumbers` is ordered in ascending order
     *         4) the operator is not already deregistered
     *         5) `quorumNumbers` is a subset of the quorumNumbers that the operator is registered for
     */
    function deregisterOperator(
        address operator,
        bytes memory quorumNumbers
    ) public virtual onlyRegistryCoordinator {
        // Get the operator's pubkey from the compendium. Reverts if they have not registered a key
        (BN254.G1Point memory pubkey, ) = pubkeyCompendium.getRegisteredPubkey(operator);

        // Update each quorum's aggregate pubkey
        _processQuorumApkUpdate(quorumNumbers, pubkey.negate());
        emit OperatorRemovedFromQuorums(operator, quorumNumbers);
    }

    /**
     * @notice Initializes a new quorum by pushing its first apk update
     * @param quorumNumber The number of the new quorum
     */
    function initializeQuorum(uint8 quorumNumber) public virtual onlyRegistryCoordinator {
        require(apkHistory[quorumNumber].length == 0, "BLSPubkeyRegistry.initializeQuorum: quorum already exists");

        apkHistory[quorumNumber].push(ApkUpdate({
            apkHash: bytes24(0),
            updateBlockNumber: uint32(block.number),
            nextUpdateBlockNumber: 0
        }));
    }

    /*******************************************************************************
                            INTERNAL FUNCTIONS
    *******************************************************************************/

    function _processQuorumApkUpdate(bytes memory quorumNumbers, BN254.G1Point memory point) internal {
        BN254.G1Point memory newApk;

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            // Validate quorum exists and get history length
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            uint256 historyLength = apkHistory[quorumNumber].length;
            require(historyLength != 0, "BLSPubkeyRegistry._processQuorumApkUpdate: quorum does not exist");

            // Update aggregate public key for this quorum
            newApk = currentApk[quorumNumber].plus(point);
            currentApk[quorumNumber] = newApk;
            bytes24 newApkHash = bytes24(BN254.hashG1Point(newApk));

            // Update apk history. If the last update was made in this block, update the entry
            // Otherwise, push a new historical entry and update the prev->next pointer
            ApkUpdate storage lastUpdate = apkHistory[quorumNumber][historyLength - 1];
            if (lastUpdate.updateBlockNumber == uint32(block.number)) {
                lastUpdate.apkHash = newApkHash;
            } else {
                lastUpdate.nextUpdateBlockNumber = uint32(block.number);
                apkHistory[quorumNumber].push(ApkUpdate({
                    apkHash: newApkHash,
                    updateBlockNumber: uint32(block.number),
                    nextUpdateBlockNumber: 0
                }));
            }
        }
    }

    // TODO - should this fail if apkUpdate.apkHash == 0? This will be the case for the first entry in each quorum
    function _validateApkHashAtBlockNumber(ApkUpdate memory apkUpdate, uint32 blockNumber) internal pure {
        require(
            blockNumber >= apkUpdate.updateBlockNumber,
            "BLSPubkeyRegistry._validateApkHashAtBlockNumber: index too recent"
        );
        /**
         * if there is a next update, check that the blockNumber is before the next update or if
         * there is no next update, then apkUpdate.nextUpdateBlockNumber is 0.
         */
        require(
            apkUpdate.nextUpdateBlockNumber == 0 || blockNumber < apkUpdate.nextUpdateBlockNumber,
            "BLSPubkeyRegistry._validateApkHashAtBlockNumber: not latest apk update"
        );
    }

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
        for (uint i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            uint32 quorumApkUpdatesLength = uint32(apkHistory[quorumNumber].length);

            if (quorumApkUpdatesLength == 0 || blockNumber < apkHistory[quorumNumber][0].updateBlockNumber) {
                revert(
                    "BLSPubkeyRegistry.getApkIndicesAtBlockNumber: blockNumber is before the first update"
                );
            }

            for (uint32 j = 0; j < quorumApkUpdatesLength; j++) {
                if (apkHistory[quorumNumber][quorumApkUpdatesLength - j - 1].updateBlockNumber <= blockNumber) {
                    indices[i] = quorumApkUpdatesLength - j - 1;
                    break;
                }
            }
        }
        return indices;
    }

    /// @notice Returns the current APK for the provided `quorumNumber `
    function getApk(uint8 quorumNumber) external view returns (BN254.G1Point memory) {
        return currentApk[quorumNumber];
    }

    /// @notice Returns the `ApkUpdate` struct at `index` in the list of APK updates for the `quorumNumber`
    function getApkUpdateAtIndex(uint8 quorumNumber, uint256 index) external view returns (ApkUpdate memory) {
        return apkHistory[quorumNumber][index];
    }

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
    ) external view returns (bytes24) {
        ApkUpdate memory quorumApkUpdate = apkHistory[quorumNumber][index];
        _validateApkHashAtBlockNumber(quorumApkUpdate, blockNumber);
        return quorumApkUpdate.apkHash;
    }

    /// @notice Returns the length of ApkUpdates for the provided `quorumNumber`
    function getApkHistoryLength(uint8 quorumNumber) external view returns (uint32) {
        return uint32(apkHistory[quorumNumber].length);
    }

    /// @notice Returns the operator address for the given `pubkeyHash`
    function getOperatorFromPubkeyHash(bytes32 pubkeyHash) public view returns (address) {
        return pubkeyCompendium.pubkeyHashToOperator(pubkeyHash);
    }

    /// @notice Returns the pubkeyHash for the given `operator` address
    function getOperatorId(address operator) public view returns (bytes32 pubkeyHash) {
        (,pubkeyHash) = pubkeyCompendium.getRegisteredPubkey(operator);
    }

    /// @notice Returns the pubkey for the given `operator` address
    function getOperatorPubkey(address operator) public view returns (BN254.G1Point memory pubkey) {
        (pubkey,) = pubkeyCompendium.getRegisteredPubkey(operator);
    }
}

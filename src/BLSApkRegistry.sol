// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {BLSApkRegistryStorage} from "./BLSApkRegistryStorage.sol";

import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";

import {BN254} from "./libraries/BN254.sol";

contract BLSApkRegistry is BLSApkRegistryStorage {
    using BN254 for BN254.G1Point;

    /// @notice when applied to a function, only allows the RegistryCoordinator to call it
    modifier onlyRegistryCoordinator() {
        _checkRegistryCoordinator();
        _;
    }

    /// @notice Sets the (immutable) `registryCoordinator` address
    constructor(
        IRegistryCoordinator _registryCoordinator
    ) BLSApkRegistryStorage(_registryCoordinator) {}

    /*******************************************************************************
                      EXTERNAL FUNCTIONS - REGISTRY COORDINATOR
    *******************************************************************************/

    /**
     * @notice Registers the `operator`'s pubkey for the specified `quorumNumbers`.
     * @param operator The address of the operator to register.
     * @param quorumNumbers The quorum numbers the operator is registering for, where each byte is an 8 bit integer quorumNumber.
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
    ) public virtual onlyRegistryCoordinator {
        // Get the operator's pubkey. Reverts if they have not registered a key
        (BN254.G1Point memory pubkey, ) = getRegisteredPubkey(operator);

        // Update each quorum's aggregate pubkey
        _processQuorumApkUpdate(quorumNumbers, pubkey);

        // Return pubkeyHash, which will become the operator's unique id
        emit OperatorAddedToQuorums(operator, getOperatorId(operator), quorumNumbers);
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
        // Get the operator's pubkey. Reverts if they have not registered a key
        (BN254.G1Point memory pubkey, ) = getRegisteredPubkey(operator);

        // Update each quorum's aggregate pubkey
        _processQuorumApkUpdate(quorumNumbers, pubkey.negate());
        emit OperatorRemovedFromQuorums(operator, getOperatorId(operator), quorumNumbers);
    }

    /**
     * @notice Initializes a new quorum by pushing its first apk update
     * @param quorumNumber The number of the new quorum
     */
    function initializeQuorum(uint8 quorumNumber) public virtual onlyRegistryCoordinator {
        require(apkHistory[quorumNumber].length == 0, "BLSApkRegistry.initializeQuorum: quorum already exists");

        apkHistory[quorumNumber].push(ApkUpdate({
            apkHash: bytes24(0),
            updateBlockNumber: uint32(block.number),
            nextUpdateBlockNumber: 0
        }));
    }

    /**
     * @notice Called by the RegistryCoordinator register an operator as the owner of a BLS public key.
     * @param operator is the operator for whom the key is being registered
     * @param params contains the G1 & G2 public keys of the operator, and a signature proving their ownership
     * @param pubkeyRegistrationMessageHash is a hash that the operator must sign to prove key ownership
     */
    function registerBLSPublicKey(
        address operator,
        PubkeyRegistrationParams calldata params,
        BN254.G1Point calldata pubkeyRegistrationMessageHash
    ) external onlyRegistryCoordinator returns (bytes32 operatorId) {
        bytes32 pubkeyHash = BN254.hashG1Point(params.pubkeyG1);
        require(
            pubkeyHash != ZERO_PK_HASH, "BLSApkRegistry.registerBLSPublicKey: cannot register zero pubkey"
        );
        require(
            operatorToPubkeyHash[operator] == bytes32(0),
            "BLSApkRegistry.registerBLSPublicKey: operator already registered pubkey"
        );
        require(
            pubkeyHashToOperator[pubkeyHash] == address(0),
            "BLSApkRegistry.registerBLSPublicKey: public key already registered"
        );

        // gamma = h(sigma, P, P', H(m))
        uint256 gamma = uint256(keccak256(abi.encodePacked(
            params.pubkeyRegistrationSignature.X, 
            params.pubkeyRegistrationSignature.Y, 
            params.pubkeyG1.X, 
            params.pubkeyG1.Y, 
            params.pubkeyG2.X, 
            params.pubkeyG2.Y, 
            pubkeyRegistrationMessageHash.X, 
            pubkeyRegistrationMessageHash.Y
        ))) % BN254.FR_MODULUS;
        
        // e(sigma + P * gamma, [-1]_2) = e(H(m) + [1]_1 * gamma, P') 
        require(BN254.pairing(
            params.pubkeyRegistrationSignature.plus(params.pubkeyG1.scalar_mul(gamma)),
            BN254.negGeneratorG2(),
            pubkeyRegistrationMessageHash.plus(BN254.generatorG1().scalar_mul(gamma)),
            params.pubkeyG2
        ), "BLSApkRegistry.registerBLSPublicKey: either the G1 signature is wrong, or G1 and G2 private key do not match");

        operatorToPubkey[operator] = params.pubkeyG1;
        operatorToPubkeyHash[operator] = pubkeyHash;
        pubkeyHashToOperator[pubkeyHash] = operator;

        emit NewPubkeyRegistration(operator, params.pubkeyG1, params.pubkeyG2);
        return pubkeyHash;
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
            require(historyLength != 0, "BLSApkRegistry._processQuorumApkUpdate: quorum does not exist");

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

    /*******************************************************************************
                            VIEW FUNCTIONS
    *******************************************************************************/
    /**
     * @notice Returns the pubkey and pubkey hash of an operator
     * @dev Reverts if the operator has not registered a valid pubkey
     */
    function getRegisteredPubkey(address operator) public view returns (BN254.G1Point memory, bytes32) {
        BN254.G1Point memory pubkey = operatorToPubkey[operator];
        bytes32 pubkeyHash = operatorToPubkeyHash[operator];

        require(
            pubkeyHash != bytes32(0),
            "BLSApkRegistry.getRegisteredPubkey: operator is not registered"
        );
        
        return (pubkey, pubkeyHash);
    }

    /**
     * @notice Returns the indices of the quorumApks index at `blockNumber` for the provided `quorumNumbers`
     * @dev Returns the current indices if `blockNumber >= block.number`
     */
    function getApkIndicesAtBlockNumber(
        bytes calldata quorumNumbers,
        uint256 blockNumber
    ) external view returns (uint32[] memory) {
        uint32[] memory indices = new uint32[](quorumNumbers.length);
        
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            
            uint256 quorumApkUpdatesLength = apkHistory[quorumNumber].length;
            if (quorumApkUpdatesLength == 0 || blockNumber < apkHistory[quorumNumber][0].updateBlockNumber) {
                revert("BLSApkRegistry.getApkIndicesAtBlockNumber: blockNumber is before the first update");
            }

            // Loop backward through apkHistory until we find an entry that preceeds `blockNumber`
            for (uint256 j = quorumApkUpdatesLength; j > 0; j--) {
                if (apkHistory[quorumNumber][j - 1].updateBlockNumber <= blockNumber) {
                    indices[i] = uint32(j - 1);
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

        /**
         * Validate that the update is valid for the given blockNumber:
         * - blockNumber should be >= the update block number
         * - the next update block number should be either 0 or strictly greater than blockNumber
         */
        require(
            blockNumber >= quorumApkUpdate.updateBlockNumber,
            "BLSApkRegistry._validateApkHashAtBlockNumber: index too recent"
        );
        require(
            quorumApkUpdate.nextUpdateBlockNumber == 0 || blockNumber < quorumApkUpdate.nextUpdateBlockNumber,
            "BLSApkRegistry._validateApkHashAtBlockNumber: not latest apk update"
        );

        return quorumApkUpdate.apkHash;
    }

    /// @notice Returns the length of ApkUpdates for the provided `quorumNumber`
    function getApkHistoryLength(uint8 quorumNumber) external view returns (uint32) {
        return uint32(apkHistory[quorumNumber].length);
    }

    /// @notice Returns the operator address for the given `pubkeyHash`
    function getOperatorFromPubkeyHash(bytes32 pubkeyHash) public view returns (address) {
        return pubkeyHashToOperator[pubkeyHash];
    }

    /// @notice returns the ID used to identify the `operator` within this AVS
    /// @dev Returns zero in the event that the `operator` has never registered for the AVS
    function getOperatorId(address operator) public view returns (bytes32) {
        return operatorToPubkeyHash[operator];
    }

    function _checkRegistryCoordinator() internal view {
        require(
            msg.sender == address(registryCoordinator),
            "BLSApkRegistry.onlyRegistryCoordinator: caller is not the registry coordinator"
        );
    }
}

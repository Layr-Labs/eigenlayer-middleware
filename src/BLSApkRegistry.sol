// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {BLSApkRegistryStorage, IBLSApkRegistry} from "./BLSApkRegistryStorage.sol";

import {ISlashingRegistryCoordinator} from "./interfaces/ISlashingRegistryCoordinator.sol";

import {BN254} from "./libraries/BN254.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract BLSApkRegistry is BLSApkRegistryStorage {
    using BN254 for BN254.G1Point;

    /// @notice when applied to a function, only allows the RegistryCoordinator to call it
    modifier onlyRegistryCoordinator() {
        _checkRegistryCoordinator();
        _;
    }

    /// @notice when applied to a function, only allows the RegistryCoordinator owner to call it
    modifier onlyRegistryCoordinatorOwner() {
        _checkRegistryCoordinatorOwner();
        _;
    }

    /// @notice Sets the (immutable) `registryCoordinator` address
    constructor(
        ISlashingRegistryCoordinator _slashingRegistryCoordinator
    ) BLSApkRegistryStorage(_slashingRegistryCoordinator) {}

    /**
     *
     *                   EXTERNAL FUNCTIONS - REGISTRY COORDINATOR
     *
     */

    /// @inheritdoc IBLSApkRegistry
    function registerOperator(
        address operator,
        bytes memory quorumNumbers
    ) public virtual onlyRegistryCoordinator {
        // Get the operator's pubkey. Reverts if they have not registered a key
        (BN254.G1Point memory pubkey,) = getRegisteredPubkey(operator);

        // Update each quorum's aggregate pubkey
        _processQuorumApkUpdate(quorumNumbers, pubkey);

        // Return pubkeyHash, which will become the operator's unique id
        emit OperatorAddedToQuorums(operator, getOperatorId(operator), quorumNumbers);
    }

    /// @inheritdoc IBLSApkRegistry
    function deregisterOperator(
        address operator,
        bytes memory quorumNumbers
    ) public virtual onlyRegistryCoordinator {
        // Get the operator's pubkey. Reverts if they have not registered a key
        (BN254.G1Point memory pubkey,) = getRegisteredPubkey(operator);

        // Update each quorum's aggregate pubkey
        _processQuorumApkUpdate(quorumNumbers, pubkey.negate());
        emit OperatorRemovedFromQuorums(operator, getOperatorId(operator), quorumNumbers);
    }

    /// @inheritdoc IBLSApkRegistry
    function initializeQuorum(
        uint8 quorumNumber
    ) public virtual onlyRegistryCoordinator {
        require(apkHistory[quorumNumber].length == 0, QuorumAlreadyExists());

        apkHistory[quorumNumber].push(
            ApkUpdate({
                apkHash: bytes24(0),
                updateBlockNumber: uint32(block.number),
                nextUpdateBlockNumber: 0
            })
        );
    }

    /// @inheritdoc IBLSApkRegistry
    function registerBLSPublicKey(
        address operator,
        PubkeyRegistrationParams calldata params,
        BN254.G1Point calldata pubkeyRegistrationMessageHash
    ) public onlyRegistryCoordinator returns (bytes32 operatorId) {
        bytes32 pubkeyHash = BN254.hashG1Point(params.pubkeyG1);
        require(pubkeyHash != ZERO_PK_HASH, ZeroPubKey());
        require(getOperatorId(operator) == bytes32(0), OperatorAlreadyRegistered());
        require(pubkeyHashToOperator[pubkeyHash] == address(0), BLSPubkeyAlreadyRegistered());

        // gamma = h(sigma, P, P', H(m))
        uint256 gamma = uint256(
            keccak256(
                abi.encodePacked(
                    params.pubkeyRegistrationSignature.X,
                    params.pubkeyRegistrationSignature.Y,
                    params.pubkeyG1.X,
                    params.pubkeyG1.Y,
                    params.pubkeyG2.X,
                    params.pubkeyG2.Y,
                    pubkeyRegistrationMessageHash.X,
                    pubkeyRegistrationMessageHash.Y
                )
            )
        ) % BN254.FR_MODULUS;

        // e(sigma + P * gamma, [-1]_2) = e(H(m) + [1]_1 * gamma, P')
        require(
            BN254.pairing(
                params.pubkeyRegistrationSignature.plus(params.pubkeyG1.scalar_mul(gamma)),
                BN254.negGeneratorG2(),
                pubkeyRegistrationMessageHash.plus(BN254.generatorG1().scalar_mul(gamma)),
                params.pubkeyG2
            ),
            InvalidBLSSignatureOrPrivateKey()
        );

        operatorToPubkey[operator] = params.pubkeyG1;
        operatorToPubkeyG2[operator] = params.pubkeyG2;
        operatorToPubkeyHash[operator] = pubkeyHash;
        pubkeyHashToOperator[pubkeyHash] = operator;

        emit NewPubkeyRegistration(operator, params.pubkeyG1, params.pubkeyG2);
        return pubkeyHash;
    }

    /// @inheritdoc IBLSApkRegistry
    function getOrRegisterOperatorId(
        address operator,
        PubkeyRegistrationParams calldata params,
        BN254.G1Point calldata pubkeyRegistrationMessageHash
    ) external onlyRegistryCoordinator returns (bytes32 operatorId) {
        operatorId = getOperatorId(operator);
        if (operatorId == 0) {
            operatorId = registerBLSPublicKey(operator, params, pubkeyRegistrationMessageHash);
        }
        return operatorId;
    }

    /// @notice Verifies and registers a G2 public key for an operator that already has a G1 key
    /// @dev This is meant to be used as a one-time way to add G2 public keys for operators that have G1 keys but no G2 key on chain
    /// @param operator The address of the operator to register the G2 key for
    /// @param pubkeyG2 The G2 public key to register
    function verifyAndRegisterG2PubkeyForOperator(
        address operator,
        BN254.G2Point calldata pubkeyG2
    ) external onlyRegistryCoordinatorOwner {
        // Get the operator's G1 pubkey. Reverts if they have not registered a key
        (BN254.G1Point memory pubkeyG1,) = getRegisteredPubkey(operator);

        _checkG2PubkeyNotSet(operator);

        require(
            BN254.pairing(pubkeyG1, BN254.negGeneratorG2(), BN254.generatorG1(), pubkeyG2),
            InvalidBLSSignatureOrPrivateKey()
        );

        operatorToPubkeyG2[operator] = pubkeyG2;

        emit NewG2PubkeyRegistration(operator, pubkeyG2);
    }

    /**
     *
     *                         INTERNAL FUNCTIONS
     *
     */
    function _processQuorumApkUpdate(
        bytes memory quorumNumbers,
        BN254.G1Point memory point
    ) internal {
        BN254.G1Point memory newApk;

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            // Validate quorum exists and get history length
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            uint256 historyLength = apkHistory[quorumNumber].length;
            require(historyLength != 0, QuorumDoesNotExist());

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
                apkHistory[quorumNumber].push(
                    ApkUpdate({
                        apkHash: newApkHash,
                        updateBlockNumber: uint32(block.number),
                        nextUpdateBlockNumber: 0
                    })
                );
            }
        }
    }

    /**
     *
     *                         VIEW FUNCTIONS
     *
     */

    /// @inheritdoc IBLSApkRegistry
    function getRegisteredPubkey(
        address operator
    ) public view returns (BN254.G1Point memory, bytes32) {
        BN254.G1Point memory pubkey = operatorToPubkey[operator];
        bytes32 pubkeyHash = getOperatorId(operator);

        require(pubkeyHash != bytes32(0), OperatorNotRegistered());

        return (pubkey, pubkeyHash);
    }

    /// @inheritdoc IBLSApkRegistry
    function getApkIndicesAtBlockNumber(
        bytes calldata quorumNumbers,
        uint256 blockNumber
    ) external view returns (uint32[] memory) {
        uint32[] memory indices = new uint32[](quorumNumbers.length);

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);

            uint256 quorumApkUpdatesLength = apkHistory[quorumNumber].length;
            if (
                quorumApkUpdatesLength == 0
                    || blockNumber < apkHistory[quorumNumber][0].updateBlockNumber
            ) {
                revert BlockNumberBeforeFirstUpdate();
            }

            // Loop backward through apkHistory until we find an entry that precedes `blockNumber`
            for (uint256 j = quorumApkUpdatesLength; j > 0; j--) {
                if (apkHistory[quorumNumber][j - 1].updateBlockNumber <= blockNumber) {
                    indices[i] = uint32(j - 1);
                    break;
                }
            }
        }
        return indices;
    }

    /// @inheritdoc IBLSApkRegistry
    function getApk(
        uint8 quorumNumber
    ) external view returns (BN254.G1Point memory) {
        return currentApk[quorumNumber];
    }

    /// @inheritdoc IBLSApkRegistry
    function getApkUpdateAtIndex(
        uint8 quorumNumber,
        uint256 index
    ) external view returns (ApkUpdate memory) {
        return apkHistory[quorumNumber][index];
    }

    /// @inheritdoc IBLSApkRegistry
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
        require(blockNumber >= quorumApkUpdate.updateBlockNumber, BlockNumberTooRecent());
        require(
            quorumApkUpdate.nextUpdateBlockNumber == 0
                || blockNumber < quorumApkUpdate.nextUpdateBlockNumber,
            BlockNumberNotLatest()
        );

        return quorumApkUpdate.apkHash;
    }

    /// @inheritdoc IBLSApkRegistry
    function getApkHistoryLength(
        uint8 quorumNumber
    ) external view returns (uint32) {
        return uint32(apkHistory[quorumNumber].length);
    }

    /// @inheritdoc IBLSApkRegistry
    function getOperatorFromPubkeyHash(
        bytes32 pubkeyHash
    ) public view returns (address) {
        return pubkeyHashToOperator[pubkeyHash];
    }

    /// @inheritdoc IBLSApkRegistry
    function getOperatorId(
        address operator
    ) public view returns (bytes32) {
        return operatorToPubkeyHash[operator];
    }

    /// @inheritdoc IBLSApkRegistry
    function getOperatorPubkeyG2(
        address operator
    ) public view override returns (BN254.G2Point memory) {
        return operatorToPubkeyG2[operator];
    }

    function _checkRegistryCoordinator() internal view {
        require(msg.sender == address(registryCoordinator), OnlyRegistryCoordinatorOwner());
    }

    function _checkRegistryCoordinatorOwner() internal view {
        require(
            msg.sender == Ownable(address(registryCoordinator)).owner(),
            OnlyRegistryCoordinatorOwner()
        );
    }

    /// @notice Checks if a G2 pubkey is already set for an operator
    function _checkG2PubkeyNotSet(
        address operator
    ) internal view {
        BN254.G2Point memory existingG2Pubkey = getOperatorPubkeyG2(operator);
        require(
            existingG2Pubkey.X[0] == 0 && existingG2Pubkey.X[1] == 0 && existingG2Pubkey.Y[0] == 0
                && existingG2Pubkey.Y[1] == 0,
            G2PubkeyAlreadySet()
        );
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {BitmapUtils} from "./libraries/BitmapUtils.sol";
import {BN254} from "./libraries/BN254.sol";

import "./BLSSignatureCheckerStorage.sol";

/**
 * @title Used for checking BLS aggregate signatures from the operators of a `BLSRegistry`.
 * @author Layr Labs, Inc.
 * @notice Terms of Service: https://docs.eigenlayer.xyz/overview/terms-of-service
 * @notice This is the contract for checking the validity of aggregate operator signatures.
 */
contract BLSSignatureChecker is BLSSignatureCheckerStorage {
    using BN254 for BN254.G1Point;

    /// MODIFIERS

    modifier onlyCoordinatorOwner() {
        require(
            msg.sender == Ownable(address(registryCoordinator)).owner(),
            OnlyRegistryCoordinatorOwner()
        );
        _;
    }

    /// CONSTRUCTION

    constructor(
        ISlashingRegistryCoordinator _registryCoordinator
    ) BLSSignatureCheckerStorage(_registryCoordinator) {}

    /// ACTIONS

    /// @inheritdoc IBLSSignatureChecker
    function setStaleStakesForbidden(
        bool value
    ) external onlyCoordinatorOwner {
        _setStaleStakesForbidden(value);
    }

    /// VIEW

    /// @inheritdoc IBLSSignatureChecker
    function checkSignatures(
        bytes32 msgHash,
        bytes calldata quorumNumbers,
        uint32 referenceBlockNumber,
        NonSignerStakesAndSignature memory params
    ) public view returns (QuorumStakeTotals memory, bytes32) {
        require(quorumNumbers.length != 0, InputEmptyQuorumNumbers());

        require(
            (quorumNumbers.length == params.quorumApks.length)
                && (quorumNumbers.length == params.quorumApkIndices.length)
                && (quorumNumbers.length == params.totalStakeIndices.length)
                && (quorumNumbers.length == params.nonSignerStakeIndices.length),
            InputArrayLengthMismatch()
        );

        require(
            params.nonSignerPubkeys.length == params.nonSignerQuorumBitmapIndices.length,
            InputNonSignerLengthMismatch()
        );

        require(referenceBlockNumber < uint32(block.number), InvalidReferenceBlocknumber());

        // This method needs to calculate the aggregate pubkey for all signing operators across
        // all signing quorums. To do that, we can query the aggregate pubkey for each quorum
        // and subtract out the pubkey for each nonsigning operator registered to that quorum.
        //
        // In practice, we do this in reverse - calculating an aggregate pubkey for all nonsigners,
        // negating that pubkey, then adding the aggregate pubkey for each quorum.
        BN254.G1Point memory apk = BN254.G1Point(0, 0);

        // For each quorum, we're also going to query the total stake for all registered operators
        // at the referenceBlockNumber, and derive the stake held by signers by subtracting out
        // stakes held by nonsigners.
        QuorumStakeTotals memory stakeTotals;
        stakeTotals.totalStakeForQuorum = new uint96[](quorumNumbers.length);
        stakeTotals.signedStakeForQuorum = new uint96[](quorumNumbers.length);

        NonSignerInfo memory nonSigners;
        nonSigners.quorumBitmaps = new uint256[](params.nonSignerPubkeys.length);
        nonSigners.pubkeyHashes = new bytes32[](params.nonSignerPubkeys.length);

        {
            // Get a bitmap of the quorums signing the message, and validate that
            // quorumNumbers contains only unique, valid quorum numbers
            uint256 signingQuorumBitmap = BitmapUtils.orderedBytesArrayToBitmap(
                quorumNumbers, registryCoordinator.quorumCount()
            );

            for (uint256 j = 0; j < params.nonSignerPubkeys.length; j++) {
                // The nonsigner's pubkey hash doubles as their operatorId
                // The check below validates that these operatorIds are sorted (and therefore
                // free of duplicates)
                nonSigners.pubkeyHashes[j] = params.nonSignerPubkeys[j].hashG1Point();
                if (j != 0) {
                    require(
                        uint256(nonSigners.pubkeyHashes[j])
                            > uint256(nonSigners.pubkeyHashes[j - 1]),
                        NonSignerPubkeysNotSorted()
                    );
                }

                // Get the quorums the nonsigner was registered for at referenceBlockNumber
                nonSigners.quorumBitmaps[j] = registryCoordinator
                    .getQuorumBitmapAtBlockNumberByIndex({
                    operatorId: nonSigners.pubkeyHashes[j],
                    blockNumber: referenceBlockNumber,
                    index: params.nonSignerQuorumBitmapIndices[j]
                });

                // Add the nonsigner's pubkey to the total apk, multiplied by the number
                // of quorums they have in common with the signing quorums, because their
                // public key will be a part of each signing quorum's aggregate pubkey
                apk = apk.plus(
                    params.nonSignerPubkeys[j].scalar_mul_tiny(
                        BitmapUtils.countNumOnes(nonSigners.quorumBitmaps[j] & signingQuorumBitmap)
                    )
                );
            }
        }

        // Negate the sum of the nonsigner aggregate pubkeys - from here, we'll add the
        // total aggregate pubkey from each quorum. Because the nonsigners' pubkeys are
        // in these quorums, this initial negation ensures they're cancelled out
        apk = apk.negate();

        /**
         * For each quorum (at referenceBlockNumber):
         * - add the apk for all registered operators
         * - query the total stake for each quorum
         * - subtract the stake for each nonsigner to calculate the stake belonging to signers
         */
        {
            bool _staleStakesForbidden = staleStakesForbidden;
            uint256 withdrawalDelayBlocks =
                _staleStakesForbidden ? delegation.minWithdrawalDelayBlocks() : 0;

            for (uint256 i = 0; i < quorumNumbers.length; i++) {
                // If we're disallowing stale stake updates, check that each quorum's last update block
                // is within withdrawalDelayBlocks
                if (_staleStakesForbidden) {
                    require(
                        registryCoordinator.quorumUpdateBlockNumber(uint8(quorumNumbers[i]))
                            + withdrawalDelayBlocks > referenceBlockNumber,
                        StaleStakesForbidden()
                    );
                }

                // Validate params.quorumApks is correct for this quorum at the referenceBlockNumber,
                // then add it to the total apk
                require(
                    bytes24(params.quorumApks[i].hashG1Point())
                        == blsApkRegistry.getApkHashAtBlockNumberAndIndex({
                            quorumNumber: uint8(quorumNumbers[i]),
                            blockNumber: referenceBlockNumber,
                            index: params.quorumApkIndices[i]
                        }),
                    InvalidQuorumApkHash()
                );
                apk = apk.plus(params.quorumApks[i]);

                // Get the total and starting signed stake for the quorum at referenceBlockNumber
                stakeTotals.totalStakeForQuorum[i] = stakeRegistry
                    .getTotalStakeAtBlockNumberFromIndex({
                    quorumNumber: uint8(quorumNumbers[i]),
                    blockNumber: referenceBlockNumber,
                    index: params.totalStakeIndices[i]
                });
                stakeTotals.signedStakeForQuorum[i] = stakeTotals.totalStakeForQuorum[i];

                // Keep track of the nonSigners index in the quorum
                uint256 nonSignerForQuorumIndex = 0;

                // loop through all nonSigners, checking that they are a part of the quorum via their quorumBitmap
                // if so, load their stake at referenceBlockNumber and subtract it from running stake signed
                for (uint256 j = 0; j < params.nonSignerPubkeys.length; j++) {
                    // if the nonSigner is a part of the quorum, subtract their stake from the running total
                    if (BitmapUtils.isSet(nonSigners.quorumBitmaps[j], uint8(quorumNumbers[i]))) {
                        stakeTotals.signedStakeForQuorum[i] -= stakeRegistry
                            .getStakeAtBlockNumberAndIndex({
                            quorumNumber: uint8(quorumNumbers[i]),
                            blockNumber: referenceBlockNumber,
                            operatorId: nonSigners.pubkeyHashes[j],
                            index: params.nonSignerStakeIndices[i][nonSignerForQuorumIndex]
                        });
                        unchecked {
                            ++nonSignerForQuorumIndex;
                        }
                    }
                }
            }
        }
        {
            // verify the signature
            (bool pairingSuccessful, bool signatureIsValid) =
                trySignatureAndApkVerification(msgHash, apk, params.apkG2, params.sigma);
            require(pairingSuccessful, InvalidBLSPairingKey());
            require(signatureIsValid, InvalidBLSSignature());
        }
        // set signatoryRecordHash variable used for fraudproofs
        bytes32 signatoryRecordHash =
            keccak256(abi.encodePacked(referenceBlockNumber, nonSigners.pubkeyHashes));

        // return the total stakes that signed for each quorum, and a hash of the information required to prove the exact signers and stake
        return (stakeTotals, signatoryRecordHash);
    }

    /// @inheritdoc IBLSSignatureChecker
    function trySignatureAndApkVerification(
        bytes32 msgHash,
        BN254.G1Point memory apk,
        BN254.G2Point memory apkG2,
        BN254.G1Point memory sigma
    ) public view returns (bool pairingSuccessful, bool siganatureIsValid) {
        // gamma = keccak256(abi.encodePacked(msgHash, apk, apkG2, sigma))
        uint256 gamma = uint256(
            keccak256(
                abi.encodePacked(
                    msgHash,
                    apk.X,
                    apk.Y,
                    apkG2.X[0],
                    apkG2.X[1],
                    apkG2.Y[0],
                    apkG2.Y[1],
                    sigma.X,
                    sigma.Y
                )
            )
        ) % BN254.FR_MODULUS;
        // verify the signature
        (pairingSuccessful, siganatureIsValid) = BN254.safePairing(
            sigma.plus(apk.scalar_mul(gamma)),
            BN254.negGeneratorG2(),
            BN254.hashToG1(msgHash).plus(BN254.generatorG1().scalar_mul(gamma)),
            apkG2,
            PAIRING_EQUALITY_CHECK_GAS
        );
    }

    function _setStaleStakesForbidden(
        bool value
    ) internal {
        staleStakesForbidden = value;
        emit StaleStakesForbiddenUpdate(value);
    }
}

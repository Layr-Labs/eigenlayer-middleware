// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {IBLSSignatureChecker} from "src/interfaces/IBLSSignatureChecker.sol";
import {IRegistryCoordinator} from "src/interfaces/IRegistryCoordinator.sol";
import {IBLSApkRegistry} from "src/interfaces/IBLSApkRegistry.sol";
import {IStakeRegistry, IDelegationManager} from "src/interfaces/IStakeRegistry.sol";

import {BitmapUtils} from "src/libraries/BitmapUtils.sol";
import {BN254} from "src/libraries/BN254.sol";

/**
 * @title Used for checking BLS aggregate signatures from the operators of a `BLSRegistry`.
 * @author Layr Labs, Inc.
 * @notice Terms of Service: https://docs.eigenlayer.xyz/overview/terms-of-service
 * @notice This is the contract for checking the validity of aggregate operator signatures.
 */
contract BLSSignatureChecker is IBLSSignatureChecker {
    using BN254 for BN254.G1Point;
    
    // CONSTANTS & IMMUTABLES

    // gas cost of multiplying 2 pairings
    uint256 internal constant PAIRING_EQUALITY_CHECK_GAS = 120000;

    IRegistryCoordinator public immutable registryCoordinator;
    IStakeRegistry public immutable stakeRegistry;
    IBLSApkRegistry public immutable blsApkRegistry;
    IDelegationManager public immutable delegation;
    /// @notice If true, check the staleness of the operator stakes and that its within the delegation withdrawalDelayBlocks window.
    bool public staleStakesForbidden;

    modifier onlyCoordinatorOwner() {
        require(msg.sender == registryCoordinator.owner(), "BLSSignatureChecker.onlyCoordinatorOwner: caller is not the owner of the registryCoordinator");
        _;
    }

    constructor(IRegistryCoordinator _registryCoordinator) {
        registryCoordinator = _registryCoordinator;
        stakeRegistry = _registryCoordinator.stakeRegistry();
        blsApkRegistry = _registryCoordinator.blsApkRegistry();
        delegation = stakeRegistry.delegation();
        
        staleStakesForbidden = true;
    }

    /**
     * RegistryCoordinator owner can either enforce or not that operator stakes are staler
     * than the delegation.withdrawalDelayBlocks() window.
     * @param value to toggle staleStakesForbidden
     */
    function setStaleStakesForbidden(bool value) external onlyCoordinatorOwner {
        staleStakesForbidden = value;
        emit StaleStakesForbiddenUpdate(value);
    }

    /**
     * @notice This function is called by disperser when it has aggregated all the signatures of the operators
     * that are part of the quorum for a particular taskNumber and is asserting them into onchain. The function
     * checks that the claim for aggregated signatures are valid.
     *
     * The thesis of this procedure entails:
     * - getting the aggregated pubkey of all registered nodes at the time of pre-commit by the
     * disperser (represented by apk in the parameters),
     * - subtracting the pubkeys of all the signers not in the quorum (nonSignerPubkeys) and storing 
     * the output in apk to get aggregated pubkey of all operators that are part of quorum.
     * - use this aggregated pubkey to verify the aggregated signature under BLS scheme.
     * 
     * @dev Before signature verification, the function verifies operator stake information.  This includes ensuring that the provided `referenceBlockNumber`
     * is correct, i.e., ensure that the stake returned from the specified block number is recent enough and that the stake is either the most recent update
     * for the total stake (of the operator) or latest before the referenceBlockNumber.
     * @param msgHash is the hash being signed
     * @param quorumNumbers is the bytes array of quorum numbers that are being signed for
     * @param referenceBlockNumber is the block number at which the stake information is being verified
     * @param params is the struct containing information on nonsigners, stakes, quorum apks, and the aggregate signature
     * @return quorumStakeTotals is the struct containing the total and signed stake for each quorum
     * @return signatoryRecordHash is the hash of the signatory record, which is used for fraud proofs
     */
    function checkSignatures(
        bytes32 msgHash, 
        bytes calldata quorumNumbers,
        uint32 referenceBlockNumber, 
        NonSignerStakesAndSignature memory params
    ) 
        public 
        view
        returns (
            QuorumStakeTotals memory,
            bytes32
        )
    {
        require(
            (quorumNumbers.length == params.quorumApks.length) &&
            (quorumNumbers.length == params.quorumApkIndices.length) &&
            (quorumNumbers.length == params.totalStakeIndices.length) &&
            (quorumNumbers.length == params.nonSignerStakeIndices.length),
            "BLSSignatureChecker.checkSignatures: input quorum length mismatch"
        );

        require(
            params.nonSignerPubkeys.length == params.nonSignerQuorumBitmapIndices.length,
            "BLSSignatureChecker.checkSignatures: input nonsigner length mismatch"
        );

        QuorumStakeTotals memory stakeTotals;
        stakeTotals.totalStakeForQuorum = new uint96[](quorumNumbers.length);
        stakeTotals.signedStakeForQuorum = new uint96[](quorumNumbers.length);
        // This will be the aggregate pubkey for all signers across all signing quorums
        BN254.G1Point memory apk = BN254.G1Point(0, 0);

        /**
         * Calculate "total" values at the referenceBlockNumber:
         * - apk for all operators across all signing quorums
         * - total stake for each quorum
         *
         * Later, we'll calculate apks and stakes for nonsigners and
         * subtract those values out
         */
        {
            bool _staleStakesForbidden = staleStakesForbidden;
            uint256 withdrawalDelayBlocks = delegation.withdrawalDelayBlocks();
            for (uint256 i = 0; i < quorumNumbers.length; i++) {
                uint8 quorumNumber = uint8(quorumNumbers[i]);

                // If we're disallowing stale stake updates, check that each quorum's last update block
                // is within withdrawalDelayBlocks
                if (_staleStakesForbidden) {
                    require(
                        registryCoordinator.quorumUpdateBlockNumber(quorumNumber) + withdrawalDelayBlocks >= block.number,
                        "BLSSignatureChecker.checkSignatures: StakeRegistry updates must be within withdrawalDelayBlocks window"
                    );
                }

                // Validate params.quorumApks is correct for this quorum at the referenceBlockNumber,
                // then add it to the total apk
                require(
                    bytes24(params.quorumApks[i].hashG1Point()) == 
                        blsApkRegistry.getApkHashAtBlockNumberAndIndex({
                            quorumNumber: quorumNumber,
                            blockNumber: referenceBlockNumber,
                            index: params.quorumApkIndices[i]
                        }),
                    "BLSSignatureChecker.checkSignatures: quorumApk hash in storage does not match provided quorum apk"
                );
                apk = apk.plus(params.quorumApks[i]);

                // Get the total and starting signed stake for the quorum at referenceBlockNumber
                stakeTotals.totalStakeForQuorum[i] = 
                    stakeRegistry.getTotalStakeAtBlockNumberFromIndex({
                        quorumNumber: quorumNumber,
                        blockNumber: referenceBlockNumber,
                        index: params.totalStakeIndices[i]
                    });
                stakeTotals.signedStakeForQuorum[i] = stakeTotals.totalStakeForQuorum[i];
            }
        }
        
        bytes32[] memory nonSignerPubkeyHashes = new bytes32[](params.nonSignerPubkeys.length);
        {
            uint256[] memory nonSignerQuorumBitmaps = new uint256[](params.nonSignerPubkeys.length);
            {
                uint256 signingQuorumBitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers, registryCoordinator.quorumCount());

                /**
                 * Subtract each nonsigner's pubkey from the total apk being calculated.
                 *
                 * Because a nonsigner might be in more than one of the signing quorums, their pubkey
                 * could be in more than one of the quorum apks. This means we can't just subtract
                 * the nonsigner's pubkey hash once - we need to subtract it ONCE FOR EACH SIGNING QUORUM
                 * the nonsigner was registered for.
                 */
                for (uint256 i = 0; i < params.nonSignerPubkeys.length; i++) {
                    // The nonsigner's pubkey hash doubles as their operatorId
                    // The check below validates that these operatorIds are sorted (and therefore
                    // free of duplicates)
                    nonSignerPubkeyHashes[i] = params.nonSignerPubkeys[i].hashG1Point();
                    if (i != 0) {
                        require(
                            uint256(nonSignerPubkeyHashes[i]) > uint256(nonSignerPubkeyHashes[i - 1]),
                            "BLSSignatureChecker.checkSignatures: nonSignerPubkeys not sorted"
                        );
                    }

                    // Get the quorums the nonsigner was registered for at referenceBlockNumber
                    nonSignerQuorumBitmaps[i] = 
                        registryCoordinator.getQuorumBitmapAtBlockNumberByIndex({
                            operatorId: nonSignerPubkeyHashes[i],
                            blockNumber: referenceBlockNumber,
                            index: params.nonSignerQuorumBitmapIndices[i]
                        });
                    
                    // TODO - add a check here that nonSignerQuorumBitmaps[i] & signingBitmap is not empty

                    // Subtract the nonsigner pubkey from the total apk
                    apk = apk.plus(
                        params.nonSignerPubkeys[i]
                            .negate()
                            .scalar_mul_tiny(
                                BitmapUtils.countNumOnes(nonSignerQuorumBitmaps[i] & signingQuorumBitmap) 
                            )
                    );
                }
            }

            /**
             * For each quorum, calculate the total stake in the quorum at the referenceBlockNumber,
             * as well as the stake held by only signing operators.
             *
             * This means first querying the total stake for each quorum at the referenceBlockNumber, 
             * then querying each nonsigner's stake for the same quorum and block number and subtracting
             * to calculate the stake held by signing operators.
             */
            for (uint8 i = 0; i < quorumNumbers.length;  ++i) {
                uint8 quorumNumber = uint8(quorumNumbers[i]);
                
                // keep track of the nonSigners index in the quorum
                uint32 nonSignerForQuorumIndex = 0;
                
                // loop through all nonSigners, checking that they are a part of the quorum via their quorumBitmap
                // if so, load their stake at referenceBlockNumber and subtract it from running stake signed
                for (uint32 j = 0; j < params.nonSignerPubkeys.length; j++) {
                    // if the nonSigner is a part of the quorum, subtract their stake from the running total
                    if (BitmapUtils.numberIsInBitmap(nonSignerQuorumBitmaps[j], quorumNumber)) {
                        stakeTotals.signedStakeForQuorum[i] -=
                            stakeRegistry.getStakeAtBlockNumberAndIndex({
                                quorumNumber: quorumNumber,
                                blockNumber: referenceBlockNumber,
                                operatorId: nonSignerPubkeyHashes[j],
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
            (bool pairingSuccessful, bool signatureIsValid) = trySignatureAndApkVerification(
                msgHash, 
                apk, 
                params.apkG2, 
                params.sigma
            );
            require(pairingSuccessful, "BLSSignatureChecker.checkSignatures: pairing precompile call failed");
            require(signatureIsValid, "BLSSignatureChecker.checkSignatures: signature is invalid");
        }
        // set signatoryRecordHash variable used for fraudproofs
        bytes32 signatoryRecordHash = keccak256(abi.encodePacked(referenceBlockNumber, nonSignerPubkeyHashes));

        // return the total stakes that signed for each quorum, and a hash of the information required to prove the exact signers and stake
        return (stakeTotals, signatoryRecordHash);
    }

    /**
     * trySignatureAndApkVerification verifies a BLS aggregate signature and the veracity of a calculated G1 Public key
     * @param msgHash is the hash being signed
     * @param apk is the claimed G1 public key
     * @param apkG2 is provided G2 public key
     * @param sigma is the G1 point signature
     * @return pairingSuccessful is true if the pairing precompile call was successful
     * @return siganatureIsValid is true if the signature is valid
     */
    function trySignatureAndApkVerification(
        bytes32 msgHash,
        BN254.G1Point memory apk,
        BN254.G2Point memory apkG2,
        BN254.G1Point memory sigma
    ) public view returns(bool pairingSuccessful, bool siganatureIsValid) {
        // gamma = keccak256(abi.encodePacked(msgHash, apk, apkG2, sigma))
        uint256 gamma = uint256(keccak256(abi.encodePacked(msgHash, apk.X, apk.Y, apkG2.X[0], apkG2.X[1], apkG2.Y[0], apkG2.Y[1], sigma.X, sigma.Y))) % BN254.FR_MODULUS;
        // verify the signature
        (pairingSuccessful, siganatureIsValid) = BN254.safePairing(
                sigma.plus(apk.scalar_mul(gamma)),
                BN254.negGeneratorG2(),
                BN254.hashToG1(msgHash).plus(BN254.generatorG1().scalar_mul(gamma)),
                apkG2,
                PAIRING_EQUALITY_CHECK_GAS
            );
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {BLSSignatureChecker} from "../../src/BLSSignatureChecker.sol";
import {MockAVSDeployer} from "../utils/MockAVSDeployer.sol";
import {BN254} from "../../src/libraries/BN254.sol";
import {OperatorStateRetriever} from "../../src/OperatorStateRetriever.sol";
import {BitmapUtils} from "../../src/libraries/BitmapUtils.sol";

contract BLSMockAVSDeployer is MockAVSDeployer {
    using BN254 for BN254.G1Point;

    bytes32 msgHash = keccak256(abi.encodePacked("hello world"));
    uint256 aggSignerPrivKey = 69;
    BN254.G2Point aggSignerApkG2;
    BN254.G2Point oneHundredQuorumApkG2;
    BN254.G1Point sigma;

    function _setUpBLSMockAVSDeployer() public virtual {
        _deployMockEigenLayerAndAVS();
        _setAggregatePublicKeysAndSignature();
    }

    function _setUpBLSMockAVSDeployer(
        uint8 numQuorumsToAdd
    ) public virtual {
        _deployMockEigenLayerAndAVS(numQuorumsToAdd);
        _setAggregatePublicKeysAndSignature();
    }

    function _setAggregatePublicKeysAndSignature() internal {
        // aggSignerPrivKey*g2
        aggSignerApkG2.X[1] =
            19_101_821_850_089_705_274_637_533_855_249_918_363_070_101_489_527_618_151_493_230_256_975_900_223_847;
        aggSignerApkG2.X[0] =
            5_334_410_886_741_819_556_325_359_147_377_682_006_012_228_123_419_628_681_352_847_439_302_316_235_957;
        aggSignerApkG2.Y[1] =
            354_176_189_041_917_478_648_604_979_334_478_067_325_821_134_838_555_150_300_539_079_146_482_658_331;
        aggSignerApkG2.Y[0] =
            4_185_483_097_059_047_421_902_184_823_581_361_466_320_657_066_600_218_863_748_375_739_772_335_928_910;

        // 100*aggSignerPrivKey*g2
        oneHundredQuorumApkG2.X[1] =
            6_187_649_255_575_786_743_153_792_867_265_230_878_737_103_598_736_372_524_337_965_086_852_090_105_771;
        oneHundredQuorumApkG2.X[0] =
            5_334_877_400_925_935_887_383_922_877_430_837_542_135_722_474_116_902_175_395_820_705_628_447_222_839;
        oneHundredQuorumApkG2.Y[1] =
            4_668_116_328_019_846_503_695_710_811_760_363_536_142_902_258_271_850_958_815_598_072_072_236_299_223;
        oneHundredQuorumApkG2.Y[0] =
            21_446_056_442_597_180_561_077_194_011_672_151_329_458_819_211_586_246_807_143_487_001_691_968_661_015;

        sigma = BN254.hashToG1(msgHash).scalar_mul(aggSignerPrivKey);
    }

    function _generateSignerAndNonSignerPrivateKeys(
        uint256 pseudoRandomNumber,
        uint256 numSigners,
        uint256 numNonSigners
    ) internal view returns (uint256[] memory, uint256[] memory) {
        uint256[] memory signerPrivateKeys = new uint256[](numSigners);
        // generate numSigners numbers that add up to aggSignerPrivKey mod BN254.FR_MODULUS
        uint256 sum = 0;
        for (uint256 i = 0; i < numSigners - 1; i++) {
            signerPrivateKeys[i] = uint256(
                keccak256(abi.encodePacked("signerPrivateKey", pseudoRandomNumber, i))
            ) % BN254.FR_MODULUS;
            sum = addmod(sum, signerPrivateKeys[i], BN254.FR_MODULUS);
        }
        // signer private keys need to add to aggSignerPrivKey
        signerPrivateKeys[numSigners - 1] =
            addmod(aggSignerPrivKey, BN254.FR_MODULUS - sum % BN254.FR_MODULUS, BN254.FR_MODULUS);

        uint256[] memory nonSignerPrivateKeys = new uint256[](numNonSigners);
        for (uint256 i = 0; i < numNonSigners; i++) {
            nonSignerPrivateKeys[i] = uint256(
                keccak256(abi.encodePacked("nonSignerPrivateKey", pseudoRandomNumber, i))
            ) % BN254.FR_MODULUS;
        }

        // Sort nonSignerPrivateKeys in order of ascending pubkeyHash
        // Uses insertion sort to sort array in place
        for (uint256 i = 1; i < nonSignerPrivateKeys.length; i++) {
            uint256 privateKey = nonSignerPrivateKeys[i];
            bytes32 pubkeyHash = _toPubkeyHash(privateKey);
            uint256 j = i;

            // Move elements of nonSignerPrivateKeys[0..i-1] that are greater than the current key
            // to one position ahead of their current position
            while (j > 0 && _toPubkeyHash(nonSignerPrivateKeys[j - 1]) > pubkeyHash) {
                nonSignerPrivateKeys[j] = nonSignerPrivateKeys[j - 1];
                j--;
            }
            nonSignerPrivateKeys[j] = privateKey;
        }

        return (signerPrivateKeys, nonSignerPrivateKeys);
    }

    function _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
        uint256 pseudoRandomNumber,
        uint256 numNonSigners,
        uint256 quorumBitmap
    ) internal returns (uint32, BLSSignatureChecker.NonSignerStakesAndSignature memory) {
        (uint256[] memory signerPrivateKeys, uint256[] memory nonSignerPrivateKeys) =
        _generateSignerAndNonSignerPrivateKeys(
            pseudoRandomNumber, maxOperatorsToRegister - numNonSigners, numNonSigners
        );
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        // randomly combine signer and non-signer private keys
        uint256[] memory privateKeys = new uint256[](maxOperatorsToRegister);
        // generate addresses and public keys
        address[] memory operators = new address[](maxOperatorsToRegister);
        BN254.G1Point[] memory pubkeys = new BN254.G1Point[](maxOperatorsToRegister);
        BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature;
        nonSignerStakesAndSignature.quorumApks = new BN254.G1Point[](quorumNumbers.length);
        nonSignerStakesAndSignature.nonSignerPubkeys = new BN254.G1Point[](numNonSigners);
        bytes32[] memory nonSignerOperatorIds = new bytes32[](numNonSigners);
        {
            uint256 signerIndex = 0;
            uint256 nonSignerIndex = 0;
            for (uint256 i = 0; i < maxOperatorsToRegister; i++) {
                uint256 randomSeed = uint256(keccak256(abi.encodePacked("privKeyCombination", i)));
                if (randomSeed % 2 == 0 && signerIndex < signerPrivateKeys.length) {
                    privateKeys[i] = signerPrivateKeys[signerIndex];
                    signerIndex++;
                } else if (nonSignerIndex < nonSignerPrivateKeys.length) {
                    privateKeys[i] = nonSignerPrivateKeys[nonSignerIndex];
                    nonSignerStakesAndSignature.nonSignerPubkeys[nonSignerIndex] =
                        BN254.generatorG1().scalar_mul(privateKeys[i]);
                    nonSignerOperatorIds[nonSignerIndex] =
                        nonSignerStakesAndSignature.nonSignerPubkeys[nonSignerIndex].hashG1Point();
                    nonSignerIndex++;
                } else {
                    privateKeys[i] = signerPrivateKeys[signerIndex];
                    signerIndex++;
                }

                operators[i] = _incrementAddress(defaultOperator, i);
                pubkeys[i] = BN254.generatorG1().scalar_mul(privateKeys[i]);

                // add the public key to each quorum
                for (uint256 j = 0; j < nonSignerStakesAndSignature.quorumApks.length; j++) {
                    nonSignerStakesAndSignature.quorumApks[j] =
                        nonSignerStakesAndSignature.quorumApks[j].plus(pubkeys[i]);
                }
            }
        }

        // register all operators for the first quorum
        for (uint256 i = 0; i < maxOperatorsToRegister; i++) {
            cheats.roll(registrationBlockNumber + blocksBetweenRegistrations * i);
            _registerOperatorWithCoordinator(operators[i], quorumBitmap, pubkeys[i], defaultStake);
        }

        uint32 referenceBlockNumber = registrationBlockNumber
            + blocksBetweenRegistrations * uint32(maxOperatorsToRegister) + 1;
        cheats.roll(referenceBlockNumber + 100);

        OperatorStateRetriever.CheckSignaturesIndices memory checkSignaturesIndices =
        operatorStateRetriever.getCheckSignaturesIndices(
            registryCoordinator, referenceBlockNumber, quorumNumbers, nonSignerOperatorIds
        );

        nonSignerStakesAndSignature.nonSignerQuorumBitmapIndices =
            checkSignaturesIndices.nonSignerQuorumBitmapIndices;
        nonSignerStakesAndSignature.apkG2 = aggSignerApkG2;
        nonSignerStakesAndSignature.sigma = sigma;
        nonSignerStakesAndSignature.quorumApkIndices = checkSignaturesIndices.quorumApkIndices;
        nonSignerStakesAndSignature.totalStakeIndices = checkSignaturesIndices.totalStakeIndices;
        nonSignerStakesAndSignature.nonSignerStakeIndices =
            checkSignaturesIndices.nonSignerStakeIndices;

        return (referenceBlockNumber, nonSignerStakesAndSignature);
    }

    function _toPubkeyHash(
        uint256 privKey
    ) internal view returns (bytes32) {
        return BN254.generatorG1().scalar_mul(privKey).hashG1Point();
    }
}

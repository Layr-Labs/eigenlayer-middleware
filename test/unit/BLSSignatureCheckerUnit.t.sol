// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../../src/BLSSignatureChecker.sol";
import "../utils/BLSMockAVSDeployer.sol";
import {
    IBLSSignatureCheckerErrors,
    IBLSSignatureCheckerTypes
} from "../../src/interfaces/IBLSSignatureChecker.sol";
import {IBLSApkRegistryErrors} from "../../src/interfaces/IBLSApkRegistry.sol";
import {QuorumBitmapHistoryLib} from "../../src/libraries/QuorumBitmapHistoryLib.sol";
import {IStakeRegistryErrors} from "../../src/interfaces/IStakeRegistry.sol";

contract BLSSignatureCheckerUnitTests is BLSMockAVSDeployer {
    using BN254 for BN254.G1Point;

    BLSSignatureChecker blsSignatureChecker;

    event StaleStakesForbiddenUpdate(bool value);

    function setUp() public virtual {
        _setUpBLSMockAVSDeployer();

        blsSignatureChecker = new BLSSignatureChecker(registryCoordinator);
    }

    function test_setStaleStakesForbidden_revert_notRegCoordOwner() public {
        cheats.expectRevert(IBLSSignatureCheckerErrors.OnlyRegistryCoordinatorOwner.selector);
        blsSignatureChecker.setStaleStakesForbidden(true);
    }

    function test_setStaleStakesForbidden() public {
        testFuzz_setStaleStakesForbidden(false);
        testFuzz_setStaleStakesForbidden(true);
    }

    function testFuzz_setStaleStakesForbidden(
        bool newState
    ) public {
        cheats.expectEmit(true, true, true, true, address(blsSignatureChecker));
        emit StaleStakesForbiddenUpdate(newState);
        cheats.prank(registryCoordinatorOwner);
        blsSignatureChecker.setStaleStakesForbidden(newState);
        assertEq(blsSignatureChecker.staleStakesForbidden(), newState, "state not set correctly");
    }

    // this test checks that a valid signature from maxOperatorsToRegister with a random number of nonsigners is checked
    // correctly on the BLSSignatureChecker contract when all operators are only regsitered for a single quorum and
    // the signature is only checked for stakes on that quorum
    function testFuzz_checkSignatures_SingleQuorum(
        uint256 pseudoRandomNumber
    ) public {
        uint256 numNonSigners = pseudoRandomNumber % (maxOperatorsToRegister - 1);
        uint256 quorumBitmap = 1;
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        (
            uint32 referenceBlockNumber,
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
            pseudoRandomNumber, numNonSigners, quorumBitmap
        );

        bytes32[] memory pubkeyHashes =
            new bytes32[](nonSignerStakesAndSignature.nonSignerPubkeys.length);
        for (uint256 i = 0; i < nonSignerStakesAndSignature.nonSignerPubkeys.length; ++i) {
            pubkeyHashes[i] = nonSignerStakesAndSignature.nonSignerPubkeys[i].hashG1Point();
        }
        bytes32 expectedSignatoryRecordHash =
            keccak256(abi.encodePacked(referenceBlockNumber, pubkeyHashes));

        uint256 gasBefore = gasleft();
        (
            BLSSignatureChecker.QuorumStakeTotals memory quorumStakeTotals,
            bytes32 signatoryRecordHash
        ) = blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, nonSignerStakesAndSignature
        );
        uint256 gasAfter = gasleft();
        emit log_named_uint("gasUsed", gasBefore - gasAfter);

        assertTrue(
            quorumStakeTotals.signedStakeForQuorum[0] > 0, "signedStakeForQuorum should be nonzero"
        );
        assertEq(
            expectedSignatoryRecordHash,
            signatoryRecordHash,
            "signatoryRecordHash does not match expectation"
        );
        // 0 nonSigners: 159908
        // 1 nonSigner: 178683
        // 2 nonSigners: 197410
    }

    function test_checkSignatures_SingleQuorum() public {
        uint256 nonRandomNumber = 111;
        uint256 numNonSigners = 1;
        uint256 quorumBitmap = 1;
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        (
            uint32 referenceBlockNumber,
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
            nonRandomNumber, numNonSigners, quorumBitmap
        );

        bytes32[] memory pubkeyHashes =
            new bytes32[](nonSignerStakesAndSignature.nonSignerPubkeys.length);
        for (uint256 i = 0; i < nonSignerStakesAndSignature.nonSignerPubkeys.length; ++i) {
            pubkeyHashes[i] = nonSignerStakesAndSignature.nonSignerPubkeys[i].hashG1Point();
        }
        bytes32 expectedSignatoryRecordHash =
            keccak256(abi.encodePacked(referenceBlockNumber, pubkeyHashes));

        uint256 gasBefore = gasleft();
        (
            BLSSignatureChecker.QuorumStakeTotals memory quorumStakeTotals,
            bytes32 signatoryRecordHash
        ) = blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, nonSignerStakesAndSignature
        );
        uint256 gasAfter = gasleft();
        emit log_named_uint("gasUsed", gasBefore - gasAfter);

        assertEq(
            expectedSignatoryRecordHash,
            signatoryRecordHash,
            "signatoryRecordHash does not match expectation"
        );

        assertEq(
            quorumStakeTotals.signedStakeForQuorum[0],
            3000000000000000000,
            "signedStakeForQuorum incorrect"
        );
        assertEq(
            quorumStakeTotals.totalStakeForQuorum[0],
            4000000000000000000,
            "totalStakeForQuorum incorrect"
        );
    }

    // this test checks that a valid signature from maxOperatorsToRegister with a random number of nonsigners is checked
    // correctly on the BLSSignatureChecker contract when all operators are registered for the first 100 quorums
    // and the signature is only checked for stakes on those quorums
    function test_checkSignatures_100Quorums(
        uint256 pseudoRandomNumber
    ) public {
        uint256 numNonSigners = pseudoRandomNumber % (maxOperatorsToRegister - 1);
        // 100 set bits
        uint256 quorumBitmap = (1 << 100) - 1;
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        (
            uint32 referenceBlockNumber,
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
            pseudoRandomNumber, numNonSigners, quorumBitmap
        );

        nonSignerStakesAndSignature.sigma = sigma.scalar_mul(quorumNumbers.length);
        nonSignerStakesAndSignature.apkG2 = oneHundredQuorumApkG2;

        bytes32[] memory pubkeyHashes =
            new bytes32[](nonSignerStakesAndSignature.nonSignerPubkeys.length);
        for (uint256 i = 0; i < nonSignerStakesAndSignature.nonSignerPubkeys.length; ++i) {
            pubkeyHashes[i] = nonSignerStakesAndSignature.nonSignerPubkeys[i].hashG1Point();
        }
        bytes32 expectedSignatoryRecordHash =
            keccak256(abi.encodePacked(referenceBlockNumber, pubkeyHashes));

        uint256 gasBefore = gasleft();
        (
            BLSSignatureChecker.QuorumStakeTotals memory quorumStakeTotals,
            bytes32 signatoryRecordHash
        ) = blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, nonSignerStakesAndSignature
        );
        uint256 gasAfter = gasleft();
        emit log_named_uint("gasUsed", gasBefore - gasAfter);

        for (uint256 i = 0; i < quorumStakeTotals.signedStakeForQuorum.length; ++i) {
            assertTrue(
                quorumStakeTotals.signedStakeForQuorum[i] > 0,
                "signedStakeForQuorum should be nonzero"
            );
        }
        assertEq(
            expectedSignatoryRecordHash,
            signatoryRecordHash,
            "signatoryRecordHash does not match expectation"
        );
    }

    function test_checkSignatures_revert_inputLengthMismatch() public {
        uint256 numNonSigners = 0;
        uint256 quorumBitmap = 1;
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);
        (
            uint32 referenceBlockNumber,
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
            1, numNonSigners, quorumBitmap
        );

        IBLSSignatureCheckerTypes.NonSignerStakesAndSignature memory incorrectLengthInputs =
        IBLSSignatureCheckerTypes.NonSignerStakesAndSignature({
            nonSignerQuorumBitmapIndices: nonSignerStakesAndSignature.nonSignerQuorumBitmapIndices,
            nonSignerPubkeys: nonSignerStakesAndSignature.nonSignerPubkeys,
            quorumApks: nonSignerStakesAndSignature.quorumApks,
            apkG2: nonSignerStakesAndSignature.apkG2,
            sigma: nonSignerStakesAndSignature.sigma,
            quorumApkIndices: nonSignerStakesAndSignature.quorumApkIndices,
            totalStakeIndices: nonSignerStakesAndSignature.totalStakeIndices,
            nonSignerStakeIndices: nonSignerStakesAndSignature.nonSignerStakeIndices
        });
        // make one part of the input incorrect length
        incorrectLengthInputs.quorumApks = new BN254.G1Point[](5);

        cheats.expectRevert(IBLSSignatureCheckerErrors.InputArrayLengthMismatch.selector);
        blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, incorrectLengthInputs
        );

        // reset the input to correct values
        incorrectLengthInputs.quorumApks = nonSignerStakesAndSignature.quorumApks;
        // make one part of the input incorrect length
        incorrectLengthInputs.quorumApkIndices = new uint32[](5);
        cheats.expectRevert(IBLSSignatureCheckerErrors.InputArrayLengthMismatch.selector);
        blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, incorrectLengthInputs
        );

        // reset the input to correct values
        incorrectLengthInputs.quorumApkIndices = nonSignerStakesAndSignature.quorumApkIndices;
        // make one part of the input incorrect length
        incorrectLengthInputs.totalStakeIndices = new uint32[](5);
        cheats.expectRevert(IBLSSignatureCheckerErrors.InputArrayLengthMismatch.selector);
        blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, incorrectLengthInputs
        );

        // reset the input to correct values
        incorrectLengthInputs.totalStakeIndices = nonSignerStakesAndSignature.totalStakeIndices;
        // make one part of the input incorrect length
        incorrectLengthInputs.nonSignerStakeIndices = new uint32[][](5);
        cheats.expectRevert(IBLSSignatureCheckerErrors.InputArrayLengthMismatch.selector);
        blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, incorrectLengthInputs
        );

        // reset the input to correct values
        incorrectLengthInputs.nonSignerStakeIndices =
            nonSignerStakesAndSignature.nonSignerStakeIndices;
        // make one part of the input incorrect length
        incorrectLengthInputs.nonSignerQuorumBitmapIndices =
            new uint32[](nonSignerStakesAndSignature.nonSignerPubkeys.length + 1);
        cheats.expectRevert(IBLSSignatureCheckerErrors.InputNonSignerLengthMismatch.selector);
        blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, incorrectLengthInputs
        );

        // reset the input to correct values
        incorrectLengthInputs.nonSignerQuorumBitmapIndices =
            nonSignerStakesAndSignature.nonSignerQuorumBitmapIndices;
        // sanity check for call passing with the correct values
        blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, incorrectLengthInputs
        );
    }

    function test_checkSignatures_revert_referenceBlockNumberInFuture(
        uint256 pseudoRandomNumber
    ) public {
        uint256 numNonSigners = pseudoRandomNumber % (maxOperatorsToRegister - 2) + 1;
        uint256 quorumBitmap = 1;
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        ( /*uint32 referenceBlockNumber*/
            , BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
            pseudoRandomNumber, numNonSigners, quorumBitmap
        );

        // Create an invalid reference block: any block number >= the current block
        uint32 invalidReferenceBlock = uint32(block.number + (pseudoRandomNumber % 20));
        cheats.expectRevert(IBLSSignatureCheckerErrors.InvalidReferenceBlocknumber.selector);
        blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, invalidReferenceBlock, nonSignerStakesAndSignature
        );
    }

    function test_checkSignatures_revert_duplicateEntry() public {
        uint256 numNonSigners = 2;
        uint256 quorumBitmap = 1;
        uint256 nonRandomNumber = 777;
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        (
            uint32 referenceBlockNumber,
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
            nonRandomNumber, numNonSigners, quorumBitmap
        );

        // swap out a pubkey to make sure there is a duplicate
        nonSignerStakesAndSignature.nonSignerPubkeys[1] =
            nonSignerStakesAndSignature.nonSignerPubkeys[0];
        cheats.expectRevert(IBLSSignatureCheckerErrors.NonSignerPubkeysNotSorted.selector);
        blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, nonSignerStakesAndSignature
        );
    }

    function test_checkSignatures_revert_wrongOrder() public {
        uint256 numNonSigners = 2;
        uint256 quorumBitmap = 1;
        uint256 nonRandomNumber = 777;
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        (
            uint32 referenceBlockNumber,
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
            nonRandomNumber, numNonSigners, quorumBitmap
        );

        // swap two pubkeys to ensure ordering is wrong
        (
            nonSignerStakesAndSignature.nonSignerPubkeys[0],
            nonSignerStakesAndSignature.nonSignerPubkeys[1]
        ) = (
            nonSignerStakesAndSignature.nonSignerPubkeys[1],
            nonSignerStakesAndSignature.nonSignerPubkeys[0]
        );
        cheats.expectRevert(IBLSSignatureCheckerErrors.NonSignerPubkeysNotSorted.selector);
        blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, nonSignerStakesAndSignature
        );
    }

    function test_checkSignatures_revert_staleStakes() public {
        uint256 numNonSigners = 2;
        uint256 quorumBitmap = 1;
        uint256 nonRandomNumber = 777;
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        (
            uint32 referenceBlockNumber,
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
            nonRandomNumber, numNonSigners, quorumBitmap
        );

        // make sure the `staleStakesForbidden` flag is set to 'true'
        testFuzz_setStaleStakesForbidden(true);

        uint256 stalestUpdateBlock = type(uint256).max;
        for (uint256 i = 0; i < quorumNumbers.length; ++i) {
            uint256 quorumUpdateBlockNumber =
                registryCoordinator.quorumUpdateBlockNumber(uint8(quorumNumbers[i]));
            if (quorumUpdateBlockNumber < stalestUpdateBlock) {
                stalestUpdateBlock = quorumUpdateBlockNumber;
            }
        }

        // move referenceBlockNumber forward to a block number the last block number where the stakes will be considered "not stale"
        referenceBlockNumber =
            uint32(stalestUpdateBlock + delegationMock.minWithdrawalDelayBlocks()) - 1;
        // roll forward to make the reference block number valid
        // we roll to referenceBlockNumber + 1 because the current block number is not a valid reference block

        cheats.roll(referenceBlockNumber + 1);
        blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, nonSignerStakesAndSignature
        );

        // move referenceBlockNumber forward one more block, making the stakes "stale"
        referenceBlockNumber += 1;
        // roll forward to reference + 1 to ensure the referenceBlockNumber is still valid
        cheats.roll(referenceBlockNumber + 1);
        cheats.expectRevert(IBLSSignatureCheckerErrors.StaleStakesForbidden.selector);
        blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, nonSignerStakesAndSignature
        );
    }

    function test_checkSignatures_revert_incorrectQuorumBitmapIndex(
        uint256 pseudoRandomNumber
    ) public {
        uint256 numNonSigners = pseudoRandomNumber % (maxOperatorsToRegister - 2) + 1;
        uint256 quorumBitmap = 1;
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        (
            uint32 referenceBlockNumber,
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
            pseudoRandomNumber, numNonSigners, quorumBitmap
        );

        // record a quorumBitmap update via a harnessed function
        registryCoordinator._updateOperatorBitmapExternal(
            nonSignerStakesAndSignature.nonSignerPubkeys[0].hashG1Point(), uint192(quorumBitmap | 2)
        );

        // set the nonSignerQuorumBitmapIndices to a different value
        nonSignerStakesAndSignature.nonSignerQuorumBitmapIndices[0] = 1;

        cheats.expectRevert(QuorumBitmapHistoryLib.BitmapUpdateIsAfterBlockNumber.selector);
        blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, nonSignerStakesAndSignature
        );
    }

    function test_checkSignatures_revert_incorrectTotalStakeIndex(
        uint256 pseudoRandomNumber
    ) public {
        uint256 numNonSigners = pseudoRandomNumber % (maxOperatorsToRegister - 2) + 1;
        uint256 quorumBitmap = 1;
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        (
            uint32 referenceBlockNumber,
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
            pseudoRandomNumber, numNonSigners, quorumBitmap
        );

        // set the totalStakeIndices to a different value
        nonSignerStakesAndSignature.totalStakeIndices[0] = 0;

        cheats.expectRevert(IStakeRegistryErrors.InvalidBlockNumber.selector);
        blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, nonSignerStakesAndSignature
        );
    }

    function test_checkSignatures_revert_incorrectNonSignerStakeIndex(
        uint256 pseudoRandomNumber
    ) public {
        uint256 numNonSigners = pseudoRandomNumber % (maxOperatorsToRegister - 2) + 1;
        uint256 quorumBitmap = 1;
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        (
            uint32 referenceBlockNumber,
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
            pseudoRandomNumber, numNonSigners, quorumBitmap
        );

        bytes32 nonSignerOperatorId = nonSignerStakesAndSignature.nonSignerPubkeys[0].hashG1Point();

        // record a stake update
        stakeRegistry.recordOperatorStakeUpdate(nonSignerOperatorId, uint8(quorumNumbers[0]), 1234);

        // set the nonSignerStakeIndices to a different value
        nonSignerStakesAndSignature.nonSignerStakeIndices[0][0] = 1;

        cheats.expectRevert(IStakeRegistryErrors.InvalidBlockNumber.selector);
        blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, nonSignerStakesAndSignature
        );
    }

    function test_checkSignatures_revert_incorrectQuorumAPKIndex(
        uint256 pseudoRandomNumber
    ) public {
        uint256 numNonSigners = pseudoRandomNumber % (maxOperatorsToRegister - 2) + 1;
        uint256 quorumBitmap = 1;
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        (
            uint32 referenceBlockNumber,
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
            pseudoRandomNumber, numNonSigners, quorumBitmap
        );

        // set the quorumApkIndices to a different value
        nonSignerStakesAndSignature.quorumApkIndices[0] = 0;

        cheats.expectRevert(IBLSApkRegistryErrors.BlockNumberNotLatest.selector);
        blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, nonSignerStakesAndSignature
        );
    }

    function test_checkSignatures_revert_incorrectQuorumAPK(
        uint256 pseudoRandomNumber
    ) public {
        uint256 numNonSigners = pseudoRandomNumber % (maxOperatorsToRegister - 2) + 1;
        uint256 quorumBitmap = 1;
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        (
            uint32 referenceBlockNumber,
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
            pseudoRandomNumber, numNonSigners, quorumBitmap
        );

        // set the quorumApk to a different value
        nonSignerStakesAndSignature.quorumApks[0] =
            nonSignerStakesAndSignature.quorumApks[0].negate();

        cheats.expectRevert(IBLSSignatureCheckerErrors.InvalidQuorumApkHash.selector);
        blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, nonSignerStakesAndSignature
        );
    }

    function test_checkSignatures_revert_incorrectSignature(
        uint256 pseudoRandomNumber
    ) public {
        uint256 numNonSigners = pseudoRandomNumber % (maxOperatorsToRegister - 2) + 1;
        uint256 quorumBitmap = 1;
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        (
            uint32 referenceBlockNumber,
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
            pseudoRandomNumber, numNonSigners, quorumBitmap
        );

        // set the sigma to a different value
        nonSignerStakesAndSignature.sigma = nonSignerStakesAndSignature.sigma.negate();

        cheats.expectRevert(IBLSSignatureCheckerErrors.InvalidBLSSignature.selector);
        blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, nonSignerStakesAndSignature
        );
    }

    function test_checkSignatures_revert_invalidSignature(
        uint256 pseudoRandomNumber
    ) public {
        uint256 numNonSigners = pseudoRandomNumber % (maxOperatorsToRegister - 2) + 1;
        uint256 quorumBitmap = 1;
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        (
            uint32 referenceBlockNumber,
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
            pseudoRandomNumber, numNonSigners, quorumBitmap
        );

        // set the sigma to a different value
        nonSignerStakesAndSignature.sigma.X++;

        // expect a non-specific low-level revert, since this call will ultimately fail as part of the precompile call
        cheats.expectRevert();
        blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, nonSignerStakesAndSignature
        );
    }

    function testBLSSignatureChecker_reverts_emptyQuorums(
        uint256 pseudoRandomNumber
    ) public {
        uint256 numNonSigners = pseudoRandomNumber % (maxOperatorsToRegister - 2) + 1;

        uint256 quorumBitmap = 1;

        (
            uint32 referenceBlockNumber,
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
            pseudoRandomNumber, numNonSigners, quorumBitmap
        );

        // Create an empty quorumNumbers array
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(0);

        // expect a non-specific low-level revert, since this call will ultimately fail as part of the precompile call
        cheats.expectRevert(IBLSSignatureCheckerErrors.InputEmptyQuorumNumbers.selector);
        blsSignatureChecker.checkSignatures(
            msgHash, quorumNumbers, referenceBlockNumber, nonSignerStakesAndSignature
        );
    }

    function test_trySignatureAndApkVerification_success() public {
        uint256 numNonSigners = 0;
        uint256 quorumBitmap = 1;
        (
            uint32 referenceBlockNumber,
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
            1, numNonSigners, quorumBitmap
        );

        (bool pairingSuccessful, bool signatureIsValid) = blsSignatureChecker
            .trySignatureAndApkVerification(
            msgHash,
            nonSignerStakesAndSignature.quorumApks[0],
            nonSignerStakesAndSignature.apkG2,
            nonSignerStakesAndSignature.sigma
        );

        assertTrue(pairingSuccessful, "Pairing should be successful");
        assertTrue(signatureIsValid, "Signature should be valid");
    }

    function test_trySignatureAndApkVerification_invalidSignature() public {
        uint256 numNonSigners = 0;
        uint256 quorumBitmap = 1;
        (
            uint32 referenceBlockNumber,
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
            1, numNonSigners, quorumBitmap
        );

        // Modify sigma to make it invalid
        nonSignerStakesAndSignature.sigma.X++;

        cheats.expectRevert();
        blsSignatureChecker.trySignatureAndApkVerification(
            msgHash,
            nonSignerStakesAndSignature.quorumApks[0],
            nonSignerStakesAndSignature.apkG2,
            nonSignerStakesAndSignature.sigma
        );
    }

    function test_trySignatureAndApkVerification_invalidPairing() public {
        uint256 numNonSigners = 0;
        uint256 quorumBitmap = 1;
        (
            uint32 referenceBlockNumber,
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _registerSignatoriesAndGetNonSignerStakeAndSignatureRandom(
            1, numNonSigners, quorumBitmap
        );

        // Create invalid G2 point
        BN254.G2Point memory invalidG2Point = BN254.G2Point(
            [type(uint256).max, type(uint256).max], [type(uint256).max, type(uint256).max]
        );

        (bool pairingSuccessful, bool signatureIsValid) = blsSignatureChecker
            .trySignatureAndApkVerification(
            msgHash,
            nonSignerStakesAndSignature.quorumApks[0],
            invalidG2Point,
            nonSignerStakesAndSignature.sigma
        );

        assertFalse(pairingSuccessful, "Pairing should fail");
        assertFalse(signatureIsValid, "Signature should be invalid");
    }
}

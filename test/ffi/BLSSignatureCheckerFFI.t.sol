// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "./FFIBase.sol";

contract BLSSignatureCheckerFFITests is FFIBase {
    using BN254 for BN254.G1Point;

    BLSSignatureChecker blsSignatureChecker;
    uint32 constant MAX_OPERATORS = 1000;

    function setUp() virtual public {
        defaultMaxOperatorCount = MAX_OPERATORS;
        _deployMockEigenLayerAndAVS();
        blsSignatureChecker = new BLSSignatureChecker(registryCoordinator);
    }

    function xtestSingleBLSSignatureChecker() public {
        uint64 numOperators = 200;
        uint64 numNonSigners = 20;
        uint64 numberOfQuorums = 10;
        uint256 setQuorumBitmap = 0;

        bytes memory message = "eigen";
        bytes32 msgHash = _setOperators(setQuorumBitmap, numberOfQuorums, numOperators, message);
        
        (
            bytes memory quorumNumbers, 
            uint32 referenceBlockNumber, 
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _getNonSignerStakeAndSignatures(
            numOperators, 
            numNonSigners, 
            numberOfQuorums
        );

        uint256 gasBefore = gasleft();
        (
            BLSSignatureChecker.QuorumStakeTotals memory quorumStakeTotals,
            /* bytes32 signatoryRecordHash */
        ) = blsSignatureChecker.checkSignatures(
            msgHash, 
            quorumNumbers,
            referenceBlockNumber, 
            nonSignerStakesAndSignature
        );
        uint256 gasAfter = gasleft();
        uint256 gasCost = gasBefore - gasAfter;

        console.log("gasCost: %s", gasCost);

        assertTrue(quorumStakeTotals.signedStakeForQuorum[0] > 0);
    }

    function xtestFuzzyBLSSignatureChecker(
        uint256 pseduoRandomNumber,
        uint64 numOperators, 
        uint64 numNonSigners, 
        uint64 numberOfQuorums
    ) public {        
        vm.assume(numOperators > 0 && numOperators <= MAX_OPERATORS);
        vm.assume(numberOfQuorums > 0 && numberOfQuorums <= 192);
        vm.assume(numOperators > numNonSigners);
        vm.assume(numOperators > numberOfQuorums);

        _deployMockEigenLayerAndAVS(); 
        uint256 setQuorumBitmap = 0;
        bytes memory message = abi.encode(keccak256(abi.encode(pseduoRandomNumber)));
        bytes32 msgHash = _setOperators(setQuorumBitmap, numberOfQuorums, numOperators, message);

        (
            bytes memory quorumNumbers, 
            uint32 referenceBlockNumber, 
            BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
        ) = _getNonSignerStakeAndSignatures(
            numOperators, 
            numNonSigners, 
            numberOfQuorums
        );

        (
            BLSSignatureChecker.QuorumStakeTotals memory quorumStakeTotals,
            /* bytes32 signatoryRecordHash */
        ) = blsSignatureChecker.checkSignatures(
            msgHash, 
            quorumNumbers,
            referenceBlockNumber, 
            nonSignerStakesAndSignature
        );

        assertTrue(quorumStakeTotals.signedStakeForQuorum[0] > 0);
    }

}
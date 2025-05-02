// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../utils/MockAVSDeployer.sol";
import {IStakeRegistryErrors} from "../../src/interfaces/IStakeRegistry.sol";
import {ISlashingRegistryCoordinatorTypes} from "../../src/interfaces/IRegistryCoordinator.sol";
import {IBLSSignatureCheckerTypes} from "../../src/interfaces/IBLSSignatureChecker.sol";
import {BN256G2} from "../../src/unaudited/BN256G2.sol";
import {BLSSigCheckOperatorStateRetriever} from
    "../../src/unaudited/BLSSigCheckOperatorStateRetriever.sol";
import {OperatorStateRetrieverUnitTests} from "./OperatorStateRetrieverUnit.t.sol";

contract BLSSigCheckOperatorStateRetrieverUnitTests is
    MockAVSDeployer,
    OperatorStateRetrieverUnitTests
{
    using BN254 for BN254.G1Point;

    BLSSigCheckOperatorStateRetriever sigCheckOperatorStateRetriever;

    function setUp() public virtual override {
        super.setUp();
        sigCheckOperatorStateRetriever = new BLSSigCheckOperatorStateRetriever();
        setOperatorStateRetriever(address(sigCheckOperatorStateRetriever));
    }

    // helper function to generate a G2 point from a scalar
    function _makeG2Point(
        uint256 scalar
    ) internal returns (BN254.G2Point memory) {
        // BN256G2.ECTwistMul returns (X0, X1, Y0, Y1) in that order
        (uint256 reX, uint256 imX, uint256 reY, uint256 imY) =
            BN256G2.ECTwistMul(scalar, BN254.G2x0, BN254.G2x1, BN254.G2y0, BN254.G2y1);

        // BN254.G2Point uses [im, re] ordering
        return BN254.G2Point([imX, reX], [imY, reY]);
    }

    // helper function to add two G2 points
    function _addG2Points(
        BN254.G2Point memory a,
        BN254.G2Point memory b
    ) internal returns (BN254.G2Point memory) {
        BN254.G2Point memory sum;
        // sum starts as (0,0), so we add a first:
        (sum.X[1], sum.X[0], sum.Y[1], sum.Y[0]) = BN256G2.ECTwistAdd(
            // sum so far
            sum.X[1],
            sum.X[0],
            sum.Y[1],
            sum.Y[0],
            // a (flip to [im, re] for BN256G2)
            a.X[1],
            a.X[0],
            a.Y[1],
            a.Y[0]
        );
        // then add b:
        (sum.X[1], sum.X[0], sum.Y[1], sum.Y[0]) = BN256G2.ECTwistAdd(
            sum.X[1], sum.X[0], sum.Y[1], sum.Y[0], b.X[1], b.X[0], b.Y[1], b.Y[0]
        );
        return sum;
    }

    function test_getNonSignerStakesAndSignature_returnsCorrect() public {
        // setup
        uint256 quorumBitmapOne = 1;
        uint256 quorumBitmapThree = 3;
        cheats.roll(registrationBlockNumber);

        _registerOperatorWithCoordinator(defaultOperator, quorumBitmapOne, defaultPubKey);

        address otherOperator = _incrementAddress(defaultOperator, 1);
        BN254.G1Point memory otherPubKey = BN254.G1Point(1, 2);
        _registerOperatorWithCoordinator(
            otherOperator, quorumBitmapThree, otherPubKey, defaultStake - 1
        );

        // Generate actual G2 pubkeys
        BN254.G2Point memory op1G2 = _makeG2Point(2);
        BN254.G2Point memory op2G2 = _makeG2Point(3);

        // Mock the registry calls so the contract sees those G2 points
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, defaultOperator),
            abi.encode(op1G2)
        );
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, otherOperator),
            abi.encode(op2G2)
        );

        // Prepare inputs
        BN254.G1Point memory dummySigma = BN254.scalar_mul_tiny(BN254.generatorG1(), 123);
        address[] memory signingOperators = new address[](2);
        signingOperators[0] = defaultOperator;
        signingOperators[1] = otherOperator;

        bytes memory quorumNumbers = new bytes(2);
        quorumNumbers[0] = bytes1(uint8(0));
        quorumNumbers[1] = bytes1(uint8(1));

        // Call the function under test
        IBLSSignatureCheckerTypes.NonSignerStakesAndSignature memory result =
        sigCheckOperatorStateRetriever.getNonSignerStakesAndSignature(
            registryCoordinator, quorumNumbers, dummySigma, signingOperators, uint32(block.number)
        );

        // Non-signers
        assertEq(result.nonSignerQuorumBitmapIndices.length, 0, "Should have no non-signer");
        assertEq(result.nonSignerPubkeys.length, 0, "Should have no non-signer pubkeys");

        // Quorum APKs
        assertEq(result.quorumApks.length, 2, "Should have 2 quorum APKs");
        (BN254.G1Point memory expectedApk0) =
            _getApkAtBlocknumber(registryCoordinator, 0, uint32(block.number));
        (BN254.G1Point memory expectedApk1) =
            _getApkAtBlocknumber(registryCoordinator, 1, uint32(block.number));
        assertEq(result.quorumApks[0].X, expectedApk0.X, "First quorum APK X mismatch");
        assertEq(result.quorumApks[0].Y, expectedApk0.Y, "First quorum APK Y mismatch");
        assertEq(result.quorumApks[1].X, expectedApk1.X, "Second quorum APK X mismatch");
        assertEq(result.quorumApks[1].Y, expectedApk1.Y, "Second quorum APK Y mismatch");

        // Aggregated G2 = op1G2 + op2G2
        BN254.G2Point memory expectedSum = _addG2Points(op1G2, op2G2);
        assertEq(result.apkG2.X[0], expectedSum.X[0], "aggregated X[0] mismatch");
        assertEq(result.apkG2.X[1], expectedSum.X[1], "aggregated X[1] mismatch");
        assertEq(result.apkG2.Y[0], expectedSum.Y[0], "aggregated Y[0] mismatch");
        assertEq(result.apkG2.Y[1], expectedSum.Y[1], "aggregated Y[1] mismatch");

        // Sigma
        assertEq(result.sigma.X, dummySigma.X, "Sigma X mismatch");
        assertEq(result.sigma.Y, dummySigma.Y, "Sigma Y mismatch");

        // Indices
        assertEq(result.quorumApkIndices.length, 2, "Should have 2 quorum APK indices");
        assertEq(result.quorumApkIndices[0], 1, "First quorum APK index mismatch");
        assertEq(result.quorumApkIndices[1], 1, "Second quorum APK index mismatch");
        assertEq(result.totalStakeIndices.length, 2, "Should have 2 total stake indices");
        assertEq(result.totalStakeIndices[0], 1, "First total stake index mismatch");
        assertEq(result.totalStakeIndices[1], 1, "Second total stake index mismatch");

        // Non-signer stake indices
        assertEq(
            result.nonSignerStakeIndices.length,
            2,
            "Should have 2 arrays of non-signer stake indices"
        );
        assertEq(result.nonSignerStakeIndices[0].length, 0, "First quorum non-signer mismatch");
        assertEq(result.nonSignerStakeIndices[1].length, 0, "Second quorum non-signer mismatch");
    }

    function test_getNonSignerStakesAndSignature_returnsCorrect_oneSigner() public {
        // setup
        uint256 quorumBitmapOne = 1;
        uint256 quorumBitmapThree = 3;
        cheats.roll(registrationBlockNumber);

        _registerOperatorWithCoordinator(defaultOperator, quorumBitmapOne, defaultPubKey);

        address otherOperator = _incrementAddress(defaultOperator, 1);
        BN254.G1Point memory otherPubKey = BN254.G1Point(1, 2);
        _registerOperatorWithCoordinator(
            otherOperator, quorumBitmapThree, otherPubKey, defaultStake - 1
        );

        // Generate actual G2 pubkeys
        BN254.G2Point memory op1G2 = _makeG2Point(2);
        BN254.G2Point memory op2G2 = _makeG2Point(3);

        // Mock them
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, defaultOperator),
            abi.encode(op1G2)
        );
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, otherOperator),
            abi.encode(op2G2)
        );

        // Prepare input
        BN254.G1Point memory dummySigma = BN254.scalar_mul_tiny(BN254.generatorG1(), 123);

        address[] memory signingOperators = new address[](1);
        signingOperators[0] = defaultOperator; // only op1

        bytes memory quorumNumbers = new bytes(2);
        quorumNumbers[0] = bytes1(uint8(0));
        quorumNumbers[1] = bytes1(uint8(1));

        // Call under test
        IBLSSignatureCheckerTypes.NonSignerStakesAndSignature memory result =
        sigCheckOperatorStateRetriever.getNonSignerStakesAndSignature(
            registryCoordinator, quorumNumbers, dummySigma, signingOperators, uint32(block.number)
        );

        // Validate
        // One non-signer => otherOperator
        assertEq(result.nonSignerQuorumBitmapIndices.length, 1, "Should have 1 non-signer");
        assertEq(
            result.nonSignerQuorumBitmapIndices[0], 0, "Unexpected non-signer quorum bitmap index"
        );
        assertEq(result.nonSignerPubkeys.length, 1, "Should have 1 non-signer pubkey");
        assertEq(result.nonSignerPubkeys[0].X, otherPubKey.X, "Unexpected non-signer pubkey X");
        assertEq(result.nonSignerPubkeys[0].Y, otherPubKey.Y, "Unexpected non-signer pubkey Y");

        // Quorum APKs
        assertEq(result.quorumApks.length, 2, "Should have 2 quorum APKs");
        (BN254.G1Point memory expectedApk0) =
            _getApkAtBlocknumber(registryCoordinator, 0, uint32(block.number));
        (BN254.G1Point memory expectedApk1) =
            _getApkAtBlocknumber(registryCoordinator, 1, uint32(block.number));
        assertEq(result.quorumApks[0].X, expectedApk0.X, "First quorum APK X mismatch");
        assertEq(result.quorumApks[0].Y, expectedApk0.Y, "First quorum APK Y mismatch");
        assertEq(result.quorumApks[1].X, expectedApk1.X, "Second quorum APK X mismatch");
        assertEq(result.quorumApks[1].Y, expectedApk1.Y, "Second quorum APK Y mismatch");

        // Since only defaultOperator signed, aggregator's G2 should match op1G2
        assertEq(result.apkG2.X[0], op1G2.X[0], "aggregated X[0] mismatch");
        assertEq(result.apkG2.X[1], op1G2.X[1], "aggregated X[1] mismatch");
        assertEq(result.apkG2.Y[0], op1G2.Y[0], "aggregated Y[0] mismatch");
        assertEq(result.apkG2.Y[1], op1G2.Y[1], "aggregated Y[1] mismatch");

        // Sigma
        assertEq(result.sigma.X, dummySigma.X, "Sigma X mismatch");
        assertEq(result.sigma.Y, dummySigma.Y, "Sigma Y mismatch");

        // Indices
        assertEq(result.quorumApkIndices.length, 2, "Should have 2 quorum APK indices");
        assertEq(result.quorumApkIndices[0], 1, "First quorum index mismatch");
        assertEq(result.quorumApkIndices[1], 1, "Second quorum index mismatch");
        assertEq(result.totalStakeIndices.length, 2, "Should have 2 total stake indices");
        assertEq(result.totalStakeIndices[0], 1, "First total stake index mismatch");
        assertEq(result.totalStakeIndices[1], 1, "Second total stake index mismatch");

        // Non-signer stake indices
        // Each quorum has exactly 1 non-signer (the otherOperator)
        assertEq(
            result.nonSignerStakeIndices.length,
            2,
            "Should have 2 arrays of non-signer stake indices"
        );
        assertEq(
            result.nonSignerStakeIndices[0].length,
            1,
            "First quorum should have 1 non-signer stake index"
        );
        assertEq(
            result.nonSignerStakeIndices[1].length,
            1,
            "Second quorum should have 1 non-signer stake index"
        );
    }

    function test_getNonSignerStakesAndSignature_changingQuorumOperatorSet() public {
        // setup
        uint256 quorumBitmapOne = 1;
        uint256 quorumBitmapThree = 3;
        cheats.roll(registrationBlockNumber);

        _registerOperatorWithCoordinator(defaultOperator, quorumBitmapOne, defaultPubKey);

        address otherOperator = _incrementAddress(defaultOperator, 1);
        BN254.G1Point memory otherPubKey = BN254.G1Point(1, 2);
        _registerOperatorWithCoordinator(
            otherOperator, quorumBitmapThree, otherPubKey, defaultStake - 1
        );

        // Generate actual G2 pubkeys
        BN254.G2Point memory op1G2 = _makeG2Point(2);
        BN254.G2Point memory op2G2 = _makeG2Point(3);

        // Mock the registry calls so the contract sees those G2 points
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, defaultOperator),
            abi.encode(op1G2)
        );
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, otherOperator),
            abi.encode(op2G2)
        );

        // Prepare inputs
        BN254.G1Point memory dummySigma = BN254.scalar_mul_tiny(BN254.generatorG1(), 123);
        address[] memory signingOperators = new address[](2);
        signingOperators[0] = defaultOperator;
        signingOperators[1] = otherOperator;

        bytes memory quorumNumbers = new bytes(2);
        quorumNumbers[0] = bytes1(uint8(0));
        quorumNumbers[1] = bytes1(uint8(1));

        // Deregister the otherOperator
        cheats.roll(registrationBlockNumber + 10);
        cheats.prank(otherOperator);
        registryCoordinator.deregisterOperator(BitmapUtils.bitmapToBytesArray(quorumBitmapThree));

        // Call the function under test
        IBLSSignatureCheckerTypes.NonSignerStakesAndSignature memory result =
        sigCheckOperatorStateRetriever.getNonSignerStakesAndSignature(
            registryCoordinator,
            quorumNumbers,
            dummySigma,
            signingOperators,
            registrationBlockNumber
        );

        // Non-signers
        assertEq(result.nonSignerQuorumBitmapIndices.length, 0, "Should have no non-signer");
        assertEq(result.nonSignerPubkeys.length, 0, "Should have no non-signer pubkeys");

        // Quorum APKs
        assertEq(result.quorumApks.length, 2, "Should have 2 quorum APKs");
        (BN254.G1Point memory expectedApk0) =
            _getApkAtBlocknumber(registryCoordinator, 0, uint32(registrationBlockNumber));
        (BN254.G1Point memory expectedApk1) =
            _getApkAtBlocknumber(registryCoordinator, 1, uint32(registrationBlockNumber));
        assertEq(result.quorumApks[0].X, expectedApk0.X, "First quorum APK X mismatch");
        assertEq(result.quorumApks[0].Y, expectedApk0.Y, "First quorum APK Y mismatch");
        assertEq(result.quorumApks[1].X, expectedApk1.X, "Second quorum APK X mismatch");
        assertEq(result.quorumApks[1].Y, expectedApk1.Y, "Second quorum APK Y mismatch");

        // Aggregated G2 = op1G2 + op2G2
        BN254.G2Point memory expectedSum = _addG2Points(op1G2, op2G2);
        assertEq(result.apkG2.X[0], expectedSum.X[0], "aggregated X[0] mismatch");
        assertEq(result.apkG2.X[1], expectedSum.X[1], "aggregated X[1] mismatch");
        assertEq(result.apkG2.Y[0], expectedSum.Y[0], "aggregated Y[0] mismatch");
        assertEq(result.apkG2.Y[1], expectedSum.Y[1], "aggregated Y[1] mismatch");

        // Sigma
        assertEq(result.sigma.X, dummySigma.X, "Sigma X mismatch");
        assertEq(result.sigma.Y, dummySigma.Y, "Sigma Y mismatch");

        // Indices
        assertEq(result.quorumApkIndices.length, 2, "Should have 2 quorum APK indices");
        assertEq(result.quorumApkIndices[0], 1, "First quorum APK index mismatch");
        assertEq(result.quorumApkIndices[1], 1, "Second quorum APK index mismatch");
        assertEq(result.totalStakeIndices.length, 2, "Should have 2 total stake indices");
        assertEq(result.totalStakeIndices[0], 1, "First total stake index mismatch");
        assertEq(result.totalStakeIndices[1], 1, "Second total stake index mismatch");

        // Non-signer stake indices
        assertEq(
            result.nonSignerStakeIndices.length,
            2,
            "Should have 2 arrays of non-signer stake indices"
        );
        assertEq(result.nonSignerStakeIndices[0].length, 0, "First quorum non-signer mismatch");
        assertEq(result.nonSignerStakeIndices[1].length, 0, "Second quorum non-signer mismatch");
    }

    function test_getNonSignerStakesAndSignature_revert_signerNeverRegistered() public {
        // Setup - register only one operator
        uint256 quorumBitmap = 1; // Quorum 0 only

        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmap, defaultPubKey);

        // Create G2 points for the registered operator
        BN254.G2Point memory op1G2 = _makeG2Point(2);
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, defaultOperator),
            abi.encode(op1G2)
        );

        // Create a dummy signature
        BN254.G1Point memory dummySigma = BN254.scalar_mul_tiny(BN254.generatorG1(), 123);

        // Try to include an unregistered operator as a signer
        address unregisteredOperator = _incrementAddress(defaultOperator, 1);
        address[] memory signingOperators = new address[](2);
        signingOperators[0] = defaultOperator;
        signingOperators[1] = unregisteredOperator; // This operator was never registered

        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(uint8(0)); // Quorum 0

        // Should revert because one of the signers was never registered
        cheats.expectRevert(
            bytes(
                "RegistryCoordinator.getQuorumBitmapIndexAtBlockNumber: no bitmap update found for operatorId"
            )
        );
        sigCheckOperatorStateRetriever.getNonSignerStakesAndSignature(
            registryCoordinator, quorumNumbers, dummySigma, signingOperators, uint32(block.number)
        );
    }

    function test_getNonSignerStakesAndSignature_revert_signerRegisteredAfterReferenceBlock()
        public
    {
        // Setup - register one operator
        uint256 quorumBitmap = 1; // Quorum 0 only

        // Save initial block number
        uint32 initialBlock = registrationBlockNumber;

        cheats.roll(initialBlock);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmap, defaultPubKey);

        // Register second operator later
        cheats.roll(initialBlock + 10);
        address secondOperator = _incrementAddress(defaultOperator, 1);
        BN254.G1Point memory secondPubKey = BN254.G1Point(1, 2);
        _registerOperatorWithCoordinator(
            secondOperator, quorumBitmap, secondPubKey, defaultStake - 1
        );

        // Create G2 points for both operators
        BN254.G2Point memory op1G2 = _makeG2Point(2);
        BN254.G2Point memory op2G2 = _makeG2Point(3);

        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, defaultOperator),
            abi.encode(op1G2)
        );
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, secondOperator),
            abi.encode(op2G2)
        );

        // Create a dummy signature
        BN254.G1Point memory dummySigma = BN254.scalar_mul_tiny(BN254.generatorG1(), 123);

        // Include both operators as signers
        address[] memory signingOperators = new address[](2);
        signingOperators[0] = defaultOperator;
        signingOperators[1] = secondOperator;

        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(uint8(0)); // Quorum 0

        // Should revert when querying at a block before the second operator was registered
        cheats.expectRevert(
            bytes(
                "RegistryCoordinator.getQuorumBitmapIndexAtBlockNumber: no bitmap update found for operatorId"
            )
        );
        sigCheckOperatorStateRetriever.getNonSignerStakesAndSignature(
            registryCoordinator, quorumNumbers, dummySigma, signingOperators, initialBlock + 5
        );
    }

    function test_getNonSignerStakesAndSignature_revert_signerDeregisteredAtReferenceBlock()
        public
    {
        // Setup - register two operators
        uint256 quorumBitmap = 1; // Quorum 0 only

        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmap, defaultPubKey);

        address secondOperator = _incrementAddress(defaultOperator, 1);
        BN254.G1Point memory secondPubKey = BN254.G1Point(1, 2);
        _registerOperatorWithCoordinator(
            secondOperator, quorumBitmap, secondPubKey, defaultStake - 1
        );

        // Create G2 points for the operators
        BN254.G2Point memory op1G2 = _makeG2Point(2);
        BN254.G2Point memory op2G2 = _makeG2Point(3);

        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, defaultOperator),
            abi.encode(op1G2)
        );
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, secondOperator),
            abi.encode(op2G2)
        );

        // Deregister the second operator
        cheats.roll(registrationBlockNumber + 10);
        cheats.prank(secondOperator);
        registryCoordinator.deregisterOperator(BitmapUtils.bitmapToBytesArray(quorumBitmap));

        // Create a dummy signature
        BN254.G1Point memory dummySigma = BN254.scalar_mul_tiny(BN254.generatorG1(), 123);

        // Include both operators as signers
        address[] memory signingOperators = new address[](2);
        signingOperators[0] = defaultOperator;
        signingOperators[1] = secondOperator; // This operator is deregistered

        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(uint8(0)); // Quorum 0

        // Should revert because secondOperator was deregistered
        cheats.expectRevert(OperatorStateRetriever.OperatorNotRegistered.selector);
        sigCheckOperatorStateRetriever.getNonSignerStakesAndSignature(
            registryCoordinator, quorumNumbers, dummySigma, signingOperators, uint32(block.number)
        );
    }

    function test_getNonSignerStakesAndSignature_revert_quorumNotCreatedAtCallTime() public {
        // Setup - register one operator
        uint256 quorumBitmap = 1; // Quorum 0 only

        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmap, defaultPubKey);

        // Create G2 points for the operator
        BN254.G2Point memory op1G2 = _makeG2Point(2);
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, defaultOperator),
            abi.encode(op1G2)
        );

        // Create a dummy signature
        BN254.G1Point memory dummySigma = BN254.scalar_mul_tiny(BN254.generatorG1(), 123);

        // Include the operator as a signer
        address[] memory signingOperators = new address[](1);
        signingOperators[0] = defaultOperator;

        // Try to query for a non-existent quorum (quorum 9)
        bytes memory invalidQuorumNumbers = new bytes(2);
        invalidQuorumNumbers[0] = bytes1(uint8(0));
        invalidQuorumNumbers[1] = bytes1(uint8(9)); // Invalid quorum number

        // Should revert because quorum 9 doesn't exist, but with a different error message
        cheats.expectRevert(
            bytes(
                "IndexRegistry._operatorCountAtBlockNumber: quorum did not exist at given block number"
            )
        );
        sigCheckOperatorStateRetriever.getNonSignerStakesAndSignature(
            registryCoordinator,
            invalidQuorumNumbers,
            dummySigma,
            signingOperators,
            uint32(block.number)
        );
    }

    function test_getNonSignerStakesAndSignature_revert_quorumNotCreatedAtReferenceBlock() public {
        // Setup - register one operator in quorum 0
        uint256 quorumBitmap = 1;

        cheats.roll(registrationBlockNumber);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmap, defaultPubKey);

        // Save this block number
        uint32 initialBlock = uint32(block.number);

        // Create a new quorum later
        cheats.roll(initialBlock + 10);

        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: defaultMaxOperatorCount,
            kickBIPsOfOperatorStake: defaultKickBIPsOfOperatorStake,
            kickBIPsOfTotalStake: defaultKickBIPsOfTotalStake
        });
        uint96 minimumStake = 1;
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] = IStakeRegistryTypes.StrategyParams({
            strategy: IStrategy(address(1000)),
            multiplier: 1e16
        });

        // Create quorum 8
        cheats.prank(registryCoordinator.owner());
        registryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams, minimumStake, strategyParams
        );

        // Create G2 points for the operator
        BN254.G2Point memory op1G2 = _makeG2Point(2);
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, defaultOperator),
            abi.encode(op1G2)
        );

        // Create a dummy signature
        BN254.G1Point memory dummySigma = BN254.scalar_mul_tiny(BN254.generatorG1(), 123);

        // Include the operator as a signer
        address[] memory signingOperators = new address[](1);
        signingOperators[0] = defaultOperator;

        // Try to query for the newly created quorum but at a historical block
        bytes memory newQuorumNumbers = new bytes(2);
        newQuorumNumbers[0] = bytes1(uint8(0));
        newQuorumNumbers[1] = bytes1(uint8(8));

        // Should revert when querying for the newly created quorum at a block before it was created
        cheats.expectRevert(
            bytes(
                "IndexRegistry._operatorCountAtBlockNumber: quorum did not exist at given block number"
            )
        );
        sigCheckOperatorStateRetriever.getNonSignerStakesAndSignature(
            registryCoordinator, newQuorumNumbers, dummySigma, signingOperators, initialBlock
        );
    }

    function test_getNonSignerStakesAndSignature_revert_operatorRegisteredToIrrelevantQuorum()
        public
    {
        // setup
        uint256 quorumBitmapOne = 1;
        cheats.roll(registrationBlockNumber);

        _registerOperatorWithCoordinator(defaultOperator, quorumBitmapOne, defaultPubKey);

        address otherOperator = _incrementAddress(defaultOperator, 1);
        BN254.G1Point memory otherPubKey = BN254.G1Point(1, 2);
        _registerOperatorWithCoordinator(
            otherOperator, quorumBitmapOne, otherPubKey, defaultStake - 1
        );

        // Generate actual G2 pubkeys
        BN254.G2Point memory op1G2 = _makeG2Point(2);
        BN254.G2Point memory op2G2 = _makeG2Point(3);

        // Mock the registry calls so the contract sees those G2 points
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, defaultOperator),
            abi.encode(op1G2)
        );
        vm.mockCall(
            address(blsApkRegistry),
            abi.encodeWithSelector(IBLSApkRegistry.getOperatorPubkeyG2.selector, otherOperator),
            abi.encode(op2G2)
        );

        // Prepare inputs
        BN254.G1Point memory dummySigma = BN254.scalar_mul_tiny(BN254.generatorG1(), 123);
        address[] memory signingOperators = new address[](2);
        signingOperators[0] = defaultOperator;
        signingOperators[1] = otherOperator;

        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(uint8(2));

        // Call the function under test
        vm.expectRevert(OperatorStateRetriever.OperatorNotRegistered.selector);
        IBLSSignatureCheckerTypes.NonSignerStakesAndSignature memory result =
        sigCheckOperatorStateRetriever.getNonSignerStakesAndSignature(
            registryCoordinator, quorumNumbers, dummySigma, signingOperators, uint32(block.number)
        );
    }

    function _getApkAtBlocknumber(
        ISlashingRegistryCoordinator registryCoordinator,
        uint8 quorumNumber,
        uint32 blockNumber
    ) internal view returns (BN254.G1Point memory) {
        bytes32[] memory operatorIds = registryCoordinator.indexRegistry()
            .getOperatorListAtBlockNumber(quorumNumber, blockNumber);
        BN254.G1Point memory apk = BN254.G1Point(0, 0);
        IBLSApkRegistry blsApkRegistry = registryCoordinator.blsApkRegistry();
        for (uint256 i = 0; i < operatorIds.length; i++) {
            address operator = registryCoordinator.getOperatorFromId(operatorIds[i]);
            BN254.G1Point memory operatorPk;
            (operatorPk.X, operatorPk.Y) = blsApkRegistry.operatorToPubkey(operator);
            apk = BN254.plus(apk, operatorPk);
        }
        return apk;
    }
}

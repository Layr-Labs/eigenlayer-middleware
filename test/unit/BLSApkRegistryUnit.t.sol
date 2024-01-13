//SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;


import "forge-std/Test.sol";
import "../harnesses/BLSApkRegistryHarness.sol";
import "../mocks/RegistryCoordinatorMock.sol";
import "../harnesses/BitmapUtilsWrapper.sol";
import "../utils/BLSMockAVSDeployer.sol";

import {IBLSApkRegistryEvents} from "../events/IBLSApkRegistryEvents.sol";

contract BLSApkRegistryUnitTests is BLSMockAVSDeployer, IBLSApkRegistryEvents {
    using BitmapUtils for uint192;
    using BN254 for BN254.G1Point;

    BitmapUtilsWrapper bitmapUtilsWrapper;

    bytes32 internal constant ZERO_PK_HASH = hex"ad3228b676f7d3cd4284a5443f17f1962b36e491b30a40b2405849e597ba5fb5";

    // BN254.G1Point internal defaultPubKey =  BN254.G1Point(18260007818883133054078754218619977578772505796600400998181738095793040006897,3432351341799135763167709827653955074218841517684851694584291831827675065899);
    BN254.G1Point defaultPubkey;
    bytes32 defaultPubkeyHash;

    address alice = address(1);
    address bob = address(2);

    uint256 privKey = 69;

    uint8 nextQuorum = 0;
    address nextOperator = address(1000);
    bytes32 nextOperatorId = bytes32(uint256(1000));

    /**
     * Fuzz input filters:
     */
    uint192 initializedQuorumBitmap = 0;
    bytes initializedQuorumBytes;

    // Track initialized quorums so we can filter these out when fuzzing
    mapping(uint8 => bool) initializedQuorums;
    // Track addresses that are excluded from fuzzed inputs such as defaultOperator, proxyAdminOwner, etc.
    mapping(address => bool) public addressIsExcludedFromFuzzedInputs;

    /*******************************************************************************
                            HELPERS AND MODIFIERS
    *******************************************************************************/

    modifier filterFuzzedAddressInputs(address fuzzedAddress) {
        cheats.assume(!addressIsExcludedFromFuzzedInputs[fuzzedAddress]);
        _;
    }

    function setUp() external {
        _setUpBLSMockAVSDeployer(0);
        
        bitmapUtilsWrapper = new BitmapUtilsWrapper();
        
        // exclude defaultOperator
        addressIsExcludedFromFuzzedInputs[defaultOperator] = true;
        addressIsExcludedFromFuzzedInputs[address(proxyAdmin)] = true;

        pubkeyRegistrationParams.pubkeyG1 = BN254.generatorG1().scalar_mul(privKey);

        defaultPubkey = pubkeyRegistrationParams.pubkeyG1;
        defaultPubkeyHash = BN254.hashG1Point(defaultPubkey);
        
        //privKey*G2
        pubkeyRegistrationParams.pubkeyG2.X[1] = 19101821850089705274637533855249918363070101489527618151493230256975900223847;
        pubkeyRegistrationParams.pubkeyG2.X[0] = 5334410886741819556325359147377682006012228123419628681352847439302316235957;
        pubkeyRegistrationParams.pubkeyG2.Y[1] = 354176189041917478648604979334478067325821134838555150300539079146482658331;
        pubkeyRegistrationParams.pubkeyG2.Y[0] = 4185483097059047421902184823581361466320657066600218863748375739772335928910;


        // Initialize 3 quorums
        _initializeQuorum();
        _initializeQuorum();
        _initializeQuorum();
    }

    function _initializeQuorum() internal {
        uint8 quorumNumber = nextQuorum;
        nextQuorum++;

        cheats.prank(address(registryCoordinator));

        // Initialize quorum and mark registered
        blsApkRegistry.initializeQuorum(quorumNumber);
        initializedQuorums[quorumNumber] = true;

        // Mark quorum initialized for other tests
        initializedQuorumBitmap = uint192(initializedQuorumBitmap.setBit(quorumNumber));
        initializedQuorumBytes = initializedQuorumBitmap.bitmapToBytesArray();
    }

    /// @dev Doesn't increment nextQuorum as assumes quorumNumber is any valid arbitrary quorumNumber
    function _initializeQuorum(uint8 quorumNumber) internal {
        cheats.prank(address(registryCoordinator));

        // Initialize quorum and mark registered
        blsApkRegistry.initializeQuorum(quorumNumber);
        initializedQuorums[quorumNumber] = true;
    }

    /// @dev initializeQuorum based on passed in bitmap of quorum numbers
    /// assumes that bitmap does not contain already initailized quorums and doesn't increment nextQuorum
    function _initializeFuzzedQuorums(uint192 bitmap) internal {
        bytes memory quorumNumbers = bitmapUtilsWrapper.bitmapToBytesArray(bitmap);

        for (uint i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            _initializeQuorum(quorumNumber);
        }
    }

    function _initializeFuzzedQuorum(
        uint8 quorumNumber
    ) internal {
        cheats.assume(!initializedQuorums[quorumNumber]);
        _initializeQuorum(quorumNumber);
    }

    function _getRandomPk(uint256 seed) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(block.timestamp, seed));
    }

    function _generateRandomNumber(uint256 seed) internal view returns (uint256) {
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(block.timestamp, seed)));
        return (randomNumber % 100) + 1; 
    }

    /*******************************************************************************
                        Helpers using the default preset BLS key
    *******************************************************************************/

    function _signMessage(address signer) internal view returns(BN254.G1Point memory) {
        BN254.G1Point memory messageHash = registryCoordinator.pubkeyRegistrationMessageHash(signer);
        return BN254.scalar_mul(messageHash, privKey);
    }

    /**
     * @dev registering operator with a random BLS pubkey, note this is a random pubkey without a known
     *  private key and is only used for fuzzing purposes. We use the harness function `setBLSPublicKey` 
     * here to set the operator BLS public key.
     */
    function _registerRandomBLSPubkey(
        address operator,
        uint256 seed
    ) internal returns (BN254.G1Point memory, bytes32) {
        BN254.G1Point memory pubkey = BN254.hashToG1(_getRandomPk(seed));
        bytes32 pubkeyHash = BN254.hashG1Point(pubkey);

        blsApkRegistry.setBLSPublicKey(operator, pubkey);
        return (pubkey, pubkeyHash);
    }

    /**
     * @dev registering operator with the default preset BLS key
     */
    function _registerDefaultBLSPubkey(address operator) internal returns (bytes32) {
        pubkeyRegistrationParams.pubkeyRegistrationSignature = _signMessage(operator);
        BN254.G1Point memory messageHash = registryCoordinator.pubkeyRegistrationMessageHash(operator);

        cheats.prank(address(registryCoordinator));
        return blsApkRegistry.registerBLSPublicKey(operator, pubkeyRegistrationParams, messageHash);
    }

    /**
     * @dev register operator, assumes operator has a registered BLS public key and that quorumNumbers are valid
     */
    function _registerOperator(address operator, bytes memory quorumNumbers) internal {
        cheats.prank(address(registryCoordinator));
        blsApkRegistry.registerOperator(operator, quorumNumbers);
    }

    function _deregisterOperator() internal {
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        cheats.prank(address(registryCoordinator));
        blsApkRegistry.deregisterOperator(defaultOperator, quorumNumbers);
    }

    /*******************************************************************************
                        Helpers for 
    *******************************************************************************/
}

contract BLSApkRegistryUnitTests_configAndGetters is BLSApkRegistryUnitTests {
    function testConstructorArgs() public {
        assertEq(
            blsApkRegistry.registryCoordinator(),
            address(registryCoordinator),
            "registryCoordinator not set correctly"
        );
    }

    function test_initializeQuorum_Revert_WhenNotRegistryCoordinator(
        address nonCoordinatorAddress
    ) public filterFuzzedAddressInputs(nonCoordinatorAddress) {
        cheats.assume(nonCoordinatorAddress != address(registryCoordinator));

        cheats.prank(address(nonCoordinatorAddress));
        cheats.expectRevert("BLSApkRegistry.onlyRegistryCoordinator: caller is not the registry coordinator");
        blsApkRegistry.initializeQuorum(defaultQuorumNumber);
    }
}

contract BLSApkRegistryUnitTests_registerBLSPublicKey is BLSApkRegistryUnitTests {
    using BN254 for BN254.G1Point;

    function test_registerOperator_Revert_WhenNotRegistryCoordinator(
        address nonCoordinatorAddress
    ) public filterFuzzedAddressInputs(nonCoordinatorAddress) {
        cheats.assume(nonCoordinatorAddress != address(registryCoordinator));

        pubkeyRegistrationParams.pubkeyRegistrationSignature = _signMessage(alice);
        BN254.G1Point memory messageHash = registryCoordinator.pubkeyRegistrationMessageHash(alice);

        cheats.prank(address(nonCoordinatorAddress));
        cheats.expectRevert("BLSApkRegistry.onlyRegistryCoordinator: caller is not the registry coordinator");
        blsApkRegistry.registerBLSPublicKey(alice, pubkeyRegistrationParams, messageHash);
    }

    function test_registerOperator_Revert_WhenZeroPubkeyHash(address operator) public {
        pubkeyRegistrationParams.pubkeyG1.X = 0;
        pubkeyRegistrationParams.pubkeyG1.Y = 0;
        BN254.G1Point memory messageHash = registryCoordinator.pubkeyRegistrationMessageHash(operator);

        cheats.prank(address(registryCoordinator));
        cheats.expectRevert("BLSApkRegistry.registerBLSPublicKey: cannot register zero pubkey");
        blsApkRegistry.registerBLSPublicKey(operator, pubkeyRegistrationParams, messageHash);
    }

    function test_registerOperator_Revert_WhenOperatorAlreadyRegistered(address operator) public {
        pubkeyRegistrationParams.pubkeyRegistrationSignature = _signMessage(operator);
        BN254.G1Point memory messageHash = registryCoordinator.pubkeyRegistrationMessageHash(operator);

        cheats.startPrank(address(registryCoordinator));
        blsApkRegistry.registerBLSPublicKey(operator, pubkeyRegistrationParams, messageHash);

        cheats.expectRevert("BLSApkRegistry.registerBLSPublicKey: operator already registered pubkey");
        blsApkRegistry.registerBLSPublicKey(operator, pubkeyRegistrationParams, messageHash);
    }

    function test_registerOperator_Revert_WhenPubkeyAlreadyRegistered(address operator, address operator2) public {
        cheats.assume(operator != operator2);
        BN254.G1Point memory messageHash = registryCoordinator.pubkeyRegistrationMessageHash(operator);
        pubkeyRegistrationParams.pubkeyRegistrationSignature = _signMessage(operator);

        cheats.startPrank(address(registryCoordinator));
        blsApkRegistry.registerBLSPublicKey(operator, pubkeyRegistrationParams, messageHash);

        cheats.expectRevert("BLSApkRegistry.registerBLSPublicKey: public key already registered");
        blsApkRegistry.registerBLSPublicKey(operator2, pubkeyRegistrationParams, messageHash);
    }

    /**
     * @dev operator is registering their public key but signing on the wrong message hash
     * results in the wrong signature. This should revert.
     */
    function test_registerOperator_Revert_WhenInvalidSignature(
        address operator,
        address invalidOperator
    ) public {
        cheats.assume(invalidOperator != operator);
        BN254.G1Point memory messageHash = registryCoordinator.pubkeyRegistrationMessageHash(operator);

        BN254.G1Point memory invalidSignature = _signMessage(invalidOperator);
        pubkeyRegistrationParams.pubkeyRegistrationSignature = invalidSignature;

        cheats.startPrank(address(registryCoordinator));
        cheats.expectRevert("BLSApkRegistry.registerBLSPublicKey: either the G1 signature is wrong, or G1 and G2 private key do not match");
        blsApkRegistry.registerBLSPublicKey(operator, pubkeyRegistrationParams, messageHash);
    }

    /**
     * @dev operator is registering their public key but G1 and G2 private keys do not match
     */
    function test_registerOperator_Revert_WhenInvalidSignatureMismatchKey(
        address operator
    ) public filterFuzzedAddressInputs(operator) {
        pubkeyRegistrationParams.pubkeyRegistrationSignature = _signMessage(operator);
        BN254.G1Point memory badPubkeyG1 = BN254.generatorG1().scalar_mul(420); // mismatch public keys

        pubkeyRegistrationParams.pubkeyG1 = badPubkeyG1;

        BN254.G1Point memory messageHash = registryCoordinator.pubkeyRegistrationMessageHash(operator);
        cheats.prank(address(registryCoordinator));
        cheats.expectRevert("BLSApkRegistry.registerBLSPublicKey: either the G1 signature is wrong, or G1 and G2 private key do not match");
        blsApkRegistry.registerBLSPublicKey(operator, pubkeyRegistrationParams, messageHash);
    }

    /**
     * @dev fuzz tests for different operator addresses but uses the same BLS key for each.
     * Checks for storage mappings being set correctly.
     */
    function test_registerBLSPublicKey(
        address operator
    ) public filterFuzzedAddressInputs(operator) {
        // sign messagehash for operator with private key
        pubkeyRegistrationParams.pubkeyRegistrationSignature = _signMessage(operator);
        BN254.G1Point memory messageHash = registryCoordinator.pubkeyRegistrationMessageHash(operator);
        cheats.prank(address(registryCoordinator));
        cheats.expectEmit(true, true, true, true, address(blsApkRegistry));
        emit NewPubkeyRegistration(operator, pubkeyRegistrationParams.pubkeyG1, pubkeyRegistrationParams.pubkeyG2);
        blsApkRegistry.registerBLSPublicKey(operator, pubkeyRegistrationParams, messageHash);

        (BN254.G1Point memory registeredPubkey, bytes32 registeredpkHash) = blsApkRegistry.getRegisteredPubkey(operator);
        assertEq(
            registeredPubkey.X,
            defaultPubkey.X,
            "registeredPubkey not set correctly"
        );
        assertEq(
            registeredPubkey.Y,
            defaultPubkey.Y,
            "registeredPubkey not set correctly"
        );
        assertEq(
            registeredpkHash,
            defaultPubkeyHash,
            "registeredpkHash not set correctly");
        assertEq(
            blsApkRegistry.pubkeyHashToOperator(BN254.hashG1Point(defaultPubkey)),
            operator,
            "operator address not stored correctly"
        );
    }
}

contract BLSApkRegistryUnitTests_registerOperator is BLSApkRegistryUnitTests {
    using BN254 for BN254.G1Point;
    using BitmapUtils for *;

    function testFuzz_registerOperator_Revert_WhenNotRegistryCoordinator(
        address nonCoordinatorAddress
    ) public filterFuzzedAddressInputs(nonCoordinatorAddress) {
        cheats.assume(nonCoordinatorAddress != address(registryCoordinator));

        cheats.prank(nonCoordinatorAddress);
        cheats.expectRevert("BLSApkRegistry.onlyRegistryCoordinator: caller is not the registry coordinator");
        blsApkRegistry.registerOperator(nonCoordinatorAddress, new bytes(0));
    }

    function testFuzz_registerOperator_Revert_WhenOperatorDoesNotOwnPubkey(
        address operator
    ) public filterFuzzedAddressInputs(operator) {
        cheats.prank(address(registryCoordinator));
        cheats.expectRevert("BLSApkRegistry.getRegisteredPubkey: operator is not registered");
        blsApkRegistry.registerOperator(operator, new bytes(1));
    }

    function testFuzz_registerOperator_Revert_WhenInvalidQuorums(
        address operator,
        uint192 quorumBitmap
    ) public filterFuzzedAddressInputs(operator) {
        cheats.prank(address(registryCoordinator));
        cheats.assume(quorumBitmap > initializedQuorumBitmap);
        // mask out quorums that are already initialized
        quorumBitmap = uint192(quorumBitmap.minus(uint256(initializedQuorumBitmap)));
        bytes memory quorumNumbers = bitmapUtilsWrapper.bitmapToBytesArray(quorumBitmap);

        _registerDefaultBLSPubkey(operator);
        
        cheats.prank(address(registryCoordinator));
        cheats.expectRevert("BLSApkRegistry._processQuorumApkUpdate: quorum does not exist");
        blsApkRegistry.registerOperator(operator, quorumNumbers);
    }

    /**
     * @dev fuzz operator address, quorumNumbers, and the BLS pubkey values
     * calls registerOperator and checks the quorum apk values are updated correctly
     * as well as latest ApkUpdate values
     */
    function testFuzz_registerOperator(
        address operator,
        uint192 quorumBitmap,
        uint256 randomSeed
    ) public filterFuzzedAddressInputs(operator) {
        // Test setup, initialize fuzzed quorums and register operator BLS pubkey
        cheats.assume(quorumBitmap > initializedQuorumBitmap);
        uint192 initializingBitmap = uint192(quorumBitmap.minus(uint256(initializedQuorumBitmap)));
        _initializeFuzzedQuorums(initializingBitmap);
        bytes memory quorumNumbers = bitmapUtilsWrapper.bitmapToBytesArray(quorumBitmap);
        (
            BN254.G1Point memory pubkey,
        ) = _registerRandomBLSPubkey(operator, randomSeed);

        // get before values
        BN254.G1Point[] memory quorumApksBefore = new BN254.G1Point[](quorumNumbers.length);
        for(uint8 i = 0; i < quorumNumbers.length; i++){
            quorumApksBefore[i] = blsApkRegistry.getApk(uint8(quorumNumbers[i]));
        }

        // registerOperator with expected OperatorAddedToQuorums event
        cheats.prank(address(registryCoordinator));
        cheats.expectEmit(true, true, true, true, address(blsApkRegistry));
        emit OperatorAddedToQuorums(operator, quorumNumbers);
        blsApkRegistry.registerOperator(operator, quorumNumbers);

        // check updated storage values for each quorum
        for(uint8 i = 0; i < quorumNumbers.length; i++){
            // Check currentApk[quorumNumber] values
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            BN254.G1Point memory quorumApkAfter = blsApkRegistry.getApk(uint8(quorumNumbers[i]));
            assertEq(
                BN254.hashG1Point(quorumApkAfter),
                BN254.hashG1Point(quorumApksBefore[i].plus(pubkey)),
                "quorum apk not updated correctly adding the operator pubkey"
            );
            // Check the latest ApkUpdate values
            uint32 quorumHistoryLength = blsApkRegistry.getApkHistoryLength(quorumNumber);
            IBLSApkRegistry.ApkUpdate memory latestApkUpdate = blsApkRegistry.getApkUpdateAtIndex(quorumNumber, quorumHistoryLength - 1);
            assertEq(
                latestApkUpdate.apkHash,
                bytes24(BN254.hashG1Point(quorumApkAfter)),
                "apkHash does not match"
            );
            assertEq(
                latestApkUpdate.updateBlockNumber,
                uint32(block.number),
                "updateBlockNumber not set correctly"
            );
            assertEq(
                latestApkUpdate.nextUpdateBlockNumber,
                uint32(0),
                "nextUpdateBlockNumber should be 0 as this is the latest ApkUpdate"
            );
        }
    }
}

/// @notice test for BLSApkRegistry.deregisterOperator()
contract BLSApkRegistryUnitTests_deregisterOperator is BLSApkRegistryUnitTests {
    using BN254 for BN254.G1Point;
    using BitmapUtils for *;

    function testFuzz_deregisterOperator_Revert_WhenNotRegistryCoordinator(
        address nonCoordinatorAddress
    ) public filterFuzzedAddressInputs(nonCoordinatorAddress) {
        cheats.assume(nonCoordinatorAddress != address(registryCoordinator));

        cheats.prank(nonCoordinatorAddress);
        cheats.expectRevert("BLSApkRegistry.onlyRegistryCoordinator: caller is not the registry coordinator");
        blsApkRegistry.deregisterOperator(nonCoordinatorAddress, new bytes(0));
    }

    function testFuzz_deregisterOperator_Revert_WhenOperatorDoesNotOwnPubkey(
        address operator
    ) public filterFuzzedAddressInputs(operator) {
        cheats.prank(address(registryCoordinator));
        cheats.expectRevert("BLSApkRegistry.getRegisteredPubkey: operator is not registered");
        blsApkRegistry.registerOperator(operator, new bytes(1));
    }

    function testFuzz_deregisterOperator_Revert_WhenInvalidQuorums(
        address operator,
        uint192 quorumBitmap
    ) public filterFuzzedAddressInputs(operator) {
        cheats.prank(address(registryCoordinator));
        cheats.assume(quorumBitmap > initializedQuorumBitmap);
        // mask out quorums that are already initialized
        quorumBitmap = uint192(quorumBitmap.minus(uint256(initializedQuorumBitmap)));
        bytes memory validQuorumNumbers = bitmapUtilsWrapper.bitmapToBytesArray(initializedQuorumBitmap);
        bytes memory invalidQuorumNumbers = bitmapUtilsWrapper.bitmapToBytesArray(quorumBitmap);

        _registerDefaultBLSPubkey(operator);
        _registerOperator(operator, validQuorumNumbers);
        
        cheats.prank(address(registryCoordinator));
        cheats.expectRevert("BLSApkRegistry._processQuorumApkUpdate: quorum does not exist");
        blsApkRegistry.deregisterOperator(operator, invalidQuorumNumbers);
    }

    /**
     * @dev fuzz operator address, quorumNumbers, and the BLS pubkey values
     * calls deregisterOperator and checks the quorum apk values are updated correctly
     * as well as latest ApkUpdate values
     */
    function testFuzz_deregisterOperator(
        address operator,
        uint192 quorumBitmap,
        uint256 randomSeed
    ) public filterFuzzedAddressInputs(operator) {
        // Test setup, initialize fuzzed quorums and register operator BLS pubkey
        cheats.assume(quorumBitmap > initializedQuorumBitmap);
        uint192 initializingBitmap = uint192(quorumBitmap.minus(uint256(initializedQuorumBitmap)));
        _initializeFuzzedQuorums(initializingBitmap);
        bytes memory quorumNumbers = bitmapUtilsWrapper.bitmapToBytesArray(quorumBitmap);
        (
            BN254.G1Point memory pubkey,
        ) = _registerRandomBLSPubkey(operator, randomSeed);
        _registerOperator(operator, quorumNumbers);

        // get before values
        BN254.G1Point[] memory quorumApksBefore = new BN254.G1Point[](quorumNumbers.length);
        for(uint8 i = 0; i < quorumNumbers.length; i++){
            quorumApksBefore[i] = blsApkRegistry.getApk(uint8(quorumNumbers[i]));
        }

        // registerOperator with expected OperatorAddedToQuorums event
        cheats.prank(address(registryCoordinator));
        cheats.expectEmit(true, true, true, true, address(blsApkRegistry));
        emit OperatorRemovedFromQuorums(operator, quorumNumbers);
        blsApkRegistry.deregisterOperator(operator, quorumNumbers);

        // check updated storage values for each quorum
        for(uint8 i = 0; i < quorumNumbers.length; i++){
            // Check currentApk[quorumNumber] values
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            BN254.G1Point memory quorumApkAfter = blsApkRegistry.getApk(uint8(quorumNumbers[i]));
            assertEq(
                BN254.hashG1Point(quorumApkAfter),
                BN254.hashG1Point(quorumApksBefore[i].plus(pubkey.negate())),
                "quorum apk not updated correctly removing the operator pubkey"
            );
            // Check the latest ApkUpdate values
            uint32 quorumHistoryLength = blsApkRegistry.getApkHistoryLength(quorumNumber);
            IBLSApkRegistry.ApkUpdate memory latestApkUpdate = blsApkRegistry.getApkUpdateAtIndex(quorumNumber, quorumHistoryLength - 1);
            assertEq(
                latestApkUpdate.apkHash,
                bytes24(BN254.hashG1Point(quorumApkAfter)),
                "apkHash does not match"
            );
            assertEq(
                latestApkUpdate.updateBlockNumber,
                uint32(block.number),
                "updateBlockNumber not set correctly"
            );
            assertEq(
                latestApkUpdate.nextUpdateBlockNumber,
                uint32(0),
                "nextUpdateBlockNumber should be 0 as this is the latest ApkUpdate"
            );
        }
    }
}

contract BLSApkRegistryUnitTests_quorumApkUpdates is BLSApkRegistryUnitTests {
    using BN254 for BN254.G1Point;
    using BitmapUtils for *;
//     function testQuorumApkUpdates(uint8 quorumNumber1, uint8 quorumNumber2) public {
//         cheats.assume(quorumNumber1 != quorumNumber2);

//         bytes memory quorumNumbers = new bytes(2);
//         quorumNumbers[0] = bytes1(quorumNumber1);
//         quorumNumbers[1] = bytes1(quorumNumber2);
//         if (!initializedQuorums[quorumNumber1]) {
//             _initializeFuzzedQuorum(quorumNumber1);
//         }
//         if (!initializedQuorums[quorumNumber2]) {
//             _initializeFuzzedQuorum(quorumNumber2);
//         }

//         BN254.G1Point[] memory quorumApksBefore = new BN254.G1Point[](quorumNumbers.length);
//         for(uint8 i = 0; i < quorumNumbers.length; i++){
//             quorumApksBefore[i] = blsApkRegistry.getApk(uint8(quorumNumbers[i]));
//         }

//         // use harnessed function to directly set the pubkey, bypassing the ordinary checks
//         blsApkRegistry.setBLSPublicKey(defaultOperator, defaultPubKey);
        
//         cheats.prank(address(registryCoordinator));
//         blsApkRegistry.registerOperator(defaultOperator, quorumNumbers);

//         //check quorum apk updates
//         for(uint8 i = 0; i < quorumNumbers.length; i++){
//             BN254.G1Point memory quorumApkAfter = blsApkRegistry.getApk(uint8(quorumNumbers[i]));
//             bytes32 temp = BN254.hashG1Point(BN254.plus(quorumApkAfter, BN254.negate(quorumApksBefore[i])));
//             require(temp == BN254.hashG1Point(defaultPubKey), "quorum apk not updated correctly");
//         }
//     }

//     function testRegisterWithNegativeQuorumApk(address operator, bytes32 x) external {
//         testRegisterOperatorBLSPubkey(defaultOperator, x);

//         BN254.G1Point memory quorumApk = blsApkRegistry.getApk(defaultQuorumNumber);

//         BN254.G1Point memory negatedQuorumApk = BN254.negate(quorumApk);

//         //register for one quorum
//         bytes memory quorumNumbers = new bytes(1);
//         quorumNumbers[0] = bytes1(defaultQuorumNumber);

//         // use harnessed function to directly set the pubkey, bypassing the ordinary checks
//         blsApkRegistry.setBLSPublicKey(operator, negatedQuorumApk);
//         cheats.stopPrank();

//         cheats.startPrank(address(registryCoordinator));
//         blsApkRegistry.registerOperator(operator, quorumNumbers);
//         cheats.stopPrank();

//         require(BN254.hashG1Point(blsApkRegistry.getApk(defaultQuorumNumber)) == ZERO_PK_HASH, "quorumApk not set correctly");
//     }

//     function testQuorumApkUpdatesAtBlockNumber(uint256 numRegistrants, uint256 blockGap) external{
//         cheats.assume(numRegistrants > 0 && numRegistrants <  100);
//         cheats.assume(blockGap < 100);

//         BN254.G1Point memory quorumApk = BN254.G1Point(0,0);
//         bytes24 quorumApkHash;
//         for (uint256 i = 0; i < numRegistrants; i++) {
//             bytes32 pk = _getRandomPk(i);
//             testRegisterOperatorBLSPubkey(defaultOperator, pk);
//             quorumApk = quorumApk.plus(BN254.hashToG1(pk));
//             quorumApkHash = bytes24(BN254.hashG1Point(quorumApk));
//             uint historyLength = blsApkRegistry.getApkHistoryLength(defaultQuorumNumber);
//             assertEq(quorumApkHash, blsApkRegistry.getApkHashAtBlockNumberAndIndex(defaultQuorumNumber, uint32(block.number + blockGap), historyLength-1), "incorrect quorum apk update");
//             cheats.roll(block.number + 100);
//             if(_generateRandomNumber(i) % 2 == 0){
//                 _deregisterOperator();
//                 quorumApk = quorumApk.plus(BN254.hashToG1(pk).negate());
//                 quorumApkHash = bytes24(BN254.hashG1Point(quorumApk));
//                 historyLength = blsApkRegistry.getApkHistoryLength(defaultQuorumNumber);
//                 assertEq(quorumApkHash, blsApkRegistry.getApkHashAtBlockNumberAndIndex(defaultQuorumNumber, uint32(block.number + blockGap), historyLength-1), "incorrect quorum apk update");
//                 cheats.roll(block.number + 100);
//                 i++;
//             }
//         }
//     }

//         /// TODO - fix test
//     function testIncorrectBlockNumberForQuorumApkUpdates(uint256 numRegistrants, uint32 indexToCheck, uint32 wrongBlockNumber) external {
//         cheats.assume(numRegistrants > 0 && numRegistrants <  100);
//         cheats.assume(indexToCheck < numRegistrants - 1);

//         uint256 startingBlockNumber = block.number;

//         for (uint256 i = 0; i < numRegistrants; i++) {
//             bytes32 pk = _getRandomPk(i);
//             testRegisterOperatorBLSPubkey(defaultOperator, pk);
//             cheats.roll(block.number + 100);
//         }
//         if(wrongBlockNumber < startingBlockNumber + indexToCheck*100){
//             emit log_named_uint("index too recent: ", indexToCheck);
//             cheats.expectRevert("BLSApkRegistry._validateApkHashAtBlockNumber: index too recent");
//             blsApkRegistry.getApkHashAtBlockNumberAndIndex(defaultQuorumNumber, wrongBlockNumber, indexToCheck);
//         } 
//         if (wrongBlockNumber >= startingBlockNumber + (indexToCheck+1)*100){
//             emit log_named_uint("index not latest: ", indexToCheck);
//             cheats.expectRevert("BLSApkRegistry._validateApkHashAtBlockNumber: not latest apk update");
//             blsApkRegistry.getApkHashAtBlockNumberAndIndex(defaultQuorumNumber, wrongBlockNumber, indexToCheck);
//         }
//     }

    // function testQuorumApkUpdatesDeregistration(uint8 quorumNumber1, uint8 quorumNumber2) external {
    //     cheats.assume(quorumNumber1 != quorumNumber2);
    //     bytes memory quorumNumbers = new bytes(2);
    //     quorumNumbers[0] = bytes1(quorumNumber1);
    //     quorumNumbers[1] = bytes1(quorumNumber2);
    //     _initializeFuzzedQuorum(quorumNumber1);
    //     _initializeFuzzedQuorum(quorumNumber2);

    //     testQuorumApkUpdates(quorumNumber1, quorumNumber2);

    //     BN254.G1Point[] memory quorumApksBefore = new BN254.G1Point[](2);
    //     for(uint8 i = 0; i < quorumNumbers.length; i++){
    //         quorumApksBefore[i] = blsApkRegistry.getApk(uint8(quorumNumbers[i]));
    //     }

    //     cheats.startPrank(address(registryCoordinator));
    //     blsApkRegistry.deregisterOperator(defaultOperator, quorumNumbers);
    //     cheats.stopPrank();

        
    //     BN254.G1Point memory quorumApkAfter;
    //     for(uint8 i = 0; i < quorumNumbers.length; i++){
    //         quorumApkAfter = blsApkRegistry.getApk(uint8(quorumNumbers[i]));
    //         require(BN254.hashG1Point(quorumApksBefore[i].plus(defaultPubKey.negate())) == BN254.hashG1Point(quorumApkAfter), "quorum apk not updated correctly");
    //     }
    // }
 

    // function testDeregisterOperatorWithQuorumApk(bytes32 x1, bytes32 x2) external {
    //     testRegisterOperatorBLSPubkey(defaultOperator, x1);
    //     testRegisterOperatorBLSPubkey(defaultOperator2, x2);

    //     BN254.G1Point memory quorumApksBefore= blsApkRegistry.getApk(defaultQuorumNumber);

    //     bytes memory quorumNumbers = new bytes(1);
    //     quorumNumbers[0] = bytes1(defaultQuorumNumber);

    //     // use harnessed function to directly set the pubkey, bypassing the ordinary checks
    //     blsApkRegistry.setBLSPublicKey(defaultOperator, quorumApksBefore);
    //     cheats.stopPrank();

    //     cheats.prank(address(registryCoordinator));
    //     blsApkRegistry.deregisterOperator(defaultOperator, quorumNumbers);

    //     BN254.G1Point memory pk = blsApkRegistry.getApk(defaultQuorumNumber);
    //     require(pk.X == 0, "quorum apk not set to zero");
    //     require(pk.Y == 0, "quorum apk not set to zero");
    // }
}

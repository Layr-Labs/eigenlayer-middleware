// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../utils/MockAVSDeployer.sol";
import {
    ISlashingRegistryCoordinator,
    ISlashingRegistryCoordinatorTypes,
    ISlashingRegistryCoordinatorErrors
} from "../../src/interfaces/ISlashingRegistryCoordinator.sol";

import {
    IRegistryCoordinator,
    IRegistryCoordinatorTypes,
    IRegistryCoordinatorErrors
} from "../../src/interfaces/IRegistryCoordinator.sol";

import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";

import {IBLSApkRegistryTypes} from "../../src/interfaces/IBLSApkRegistry.sol";
import {QuorumBitmapHistoryLib} from "../../src/libraries/QuorumBitmapHistoryLib.sol";
import {BitmapUtils} from "../../src/libraries/BitmapUtils.sol";
import {console} from "forge-std/console.sol";
import {
    OperatorWalletLib,
    SigningKeyOperationsLib,
    OperatorKeyOperationsLib,
    Operator
} from "../utils/OperatorWalletLib.sol";

contract RegistryCoordinatorUnitTests is MockAVSDeployer {
    using BN254 for BN254.G1Point;
    using stdStorage for StdStorage;

    uint8 internal constant PAUSED_REGISTER_OPERATOR = 0;
    uint8 internal constant PAUSED_DEREGISTER_OPERATOR = 1;
    uint8 internal constant PAUSED_UPDATE_OPERATOR = 2;
    uint8 internal constant MAX_QUORUM_COUNT = 192;

    /// Emits when an operator is registered
    event OperatorRegistered(address indexed operator, bytes32 indexed operatorId);
    /// Emits when an operator is deregistered
    event OperatorDeregistered(address indexed operator, bytes32 indexed operatorId);

    event OperatorSocketUpdate(bytes32 indexed operatorId, string socket);

    /// @notice emitted whenever the stake of `operator` is updated
    event OperatorStakeUpdate(bytes32 indexed operatorId, uint8 quorumNumber, uint96 stake);

    // Emitted when a new operator pubkey is registered for a set of quorums
    event OperatorAddedToQuorums(address operator, bytes32 operatorId, bytes quorumNumbers);

    // Emitted when an operator pubkey is removed from a set of quorums
    event OperatorRemovedFromQuorums(address operator, bytes32 operatorId, bytes quorumNumbers);

    // emitted when an operator's index in the orderd operator list for the quorum with number `quorumNumber` is updated
    event QuorumIndexUpdate(bytes32 indexed operatorId, uint8 quorumNumber, uint32 newIndex);

    event OperatorSetParamsUpdated(
        uint8 indexed quorumNumber,
        ISlashingRegistryCoordinatorTypes.OperatorSetParam operatorSetParams
    );

    event ChurnApproverUpdated(address prevChurnApprover, address newChurnApprover);

    event EjectorUpdated(address prevEjector, address newEjector);

    event QuorumBlockNumberUpdated(uint8 indexed quorumNumber, uint256 blocknumber);

    function setUp() public virtual {
        _deployMockEigenLayerAndAVS(numQuorums);
    }

    function _test_registerOperatorWithChurn_SetUp(
        uint256 pseudoRandomNumber,
        bytes memory quorumNumbers,
        uint96 operatorToKickStake
    )
        internal
        returns (
            address operatorToRegister,
            BN254.G1Point memory operatorToRegisterPubKey,
            ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory operatorKickParams
        )
    {
        uint32 kickRegistrationBlockNumber = 100;

        uint256 quorumBitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers);

        cheats.roll(kickRegistrationBlockNumber);

        for (uint256 i = 0; i < defaultMaxOperatorCount - 1; i++) {
            BN254.G1Point memory pubKey =
                BN254.hashToG1(keccak256(abi.encodePacked(pseudoRandomNumber, i)));
            address operator = _incrementAddress(defaultOperator, i);

            _registerOperatorWithCoordinator(operator, quorumBitmap, pubKey);
        }

        operatorToRegister = _incrementAddress(defaultOperator, defaultMaxOperatorCount);
        operatorToRegisterPubKey =
            BN254.hashToG1(keccak256(abi.encodePacked(pseudoRandomNumber, defaultMaxOperatorCount)));
        bytes32 operatorToRegisterId = BN254.hashG1Point(operatorToRegisterPubKey);
        bytes32 operatorToKickId;
        address operatorToKick;

        // register last operator before kick
        operatorKickParams = new ISlashingRegistryCoordinatorTypes.OperatorKickParam[](1);
        {
            BN254.G1Point memory pubKey = BN254.hashToG1(
                keccak256(abi.encodePacked(pseudoRandomNumber, defaultMaxOperatorCount - 1))
            );
            operatorToKickId = BN254.hashG1Point(pubKey);
            operatorToKick = _incrementAddress(defaultOperator, defaultMaxOperatorCount - 1);

            // register last operator with much more than the kickBIPsOfTotalStake stake
            _registerOperatorWithCoordinator(
                operatorToKick, quorumBitmap, pubKey, operatorToKickStake
            );

            bytes32[] memory operatorIdsToSwap = new bytes32[](1);
            // operatorIdsToSwap[0] = operatorToRegisterId
            operatorIdsToSwap[0] = operatorToRegisterId;

            operatorKickParams[0] = ISlashingRegistryCoordinatorTypes.OperatorKickParam({
                quorumNumber: uint8(quorumNumbers[0]),
                operator: operatorToKick
            });
        }

        blsApkRegistry.setBLSPublicKey(operatorToRegister, operatorToRegisterPubKey);
    }
}

contract RegistryCoordinatorUnitTests_Initialization_Setters is RegistryCoordinatorUnitTests {
    function test_initialization() public {
        assertEq(address(registryCoordinator.stakeRegistry()), address(stakeRegistry));
        assertEq(address(registryCoordinator.blsApkRegistry()), address(blsApkRegistry));
        assertEq(address(registryCoordinator.indexRegistry()), address(indexRegistry));
        assertEq(address(registryCoordinator.serviceManager()), address(serviceManager));

        for (uint256 i = 0; i < numQuorums; i++) {
            assertEq(
                keccak256(abi.encode(registryCoordinator.getOperatorSetParams(uint8(i)))),
                keccak256(abi.encode(operatorSetParams[i]))
            );
        }

        // make sure the contract initializers are disabled
        cheats.expectRevert(bytes("Initializable: contract is already initialized"));
        registryCoordinator.initialize(
            registryCoordinatorOwner,
            churnApprover,
            ejector,
            0, // _initialPausedStatus
            address(serviceManager) // _accountIdentifier
        );
    }

    function test_setOperatorSetParams() public {
        cheats.prank(registryCoordinatorOwner);
        cheats.expectEmit(true, true, true, true, address(registryCoordinator));
        emit OperatorSetParamsUpdated(0, operatorSetParams[1]);
        registryCoordinator.setOperatorSetParams(0, operatorSetParams[1]);
        assertEq(
            keccak256(abi.encode(registryCoordinator.getOperatorSetParams(0))),
            keccak256(abi.encode(operatorSetParams[1])),
            "operator set params not updated correctly"
        );
    }

    function test_setOperatorSetParams_revert_notOwner() public {
        cheats.expectRevert("Ownable: caller is not the owner");
        cheats.prank(defaultOperator);
        registryCoordinator.setOperatorSetParams(0, operatorSetParams[0]);
    }

    function test_setChurnApprover() public {
        address newChurnApprover = address(uint160(uint256(keccak256("newChurnApprover"))));
        cheats.prank(registryCoordinatorOwner);
        cheats.expectEmit(true, true, true, true, address(registryCoordinator));
        emit ChurnApproverUpdated(churnApprover, newChurnApprover);
        registryCoordinator.setChurnApprover(newChurnApprover);
        assertEq(registryCoordinator.churnApprover(), newChurnApprover);
    }

    function test_setChurnApprover_revert_notOwner() public {
        address newChurnApprover = address(uint160(uint256(keccak256("newChurnApprover"))));
        cheats.expectRevert("Ownable: caller is not the owner");
        cheats.prank(defaultOperator);
        registryCoordinator.setChurnApprover(newChurnApprover);
    }

    function test_setEjector() public {
        address newEjector = address(uint160(uint256(keccak256("newEjector"))));
        cheats.prank(registryCoordinatorOwner);
        cheats.expectEmit(true, true, true, true, address(registryCoordinator));
        emit EjectorUpdated(ejector, newEjector);
        registryCoordinator.setEjector(newEjector);
        assertEq(registryCoordinator.ejector(), newEjector);
    }

    function test_setEjector_revert_notOwner() public {
        address newEjector = address(uint160(uint256(keccak256("newEjector"))));
        cheats.expectRevert("Ownable: caller is not the owner");
        cheats.prank(defaultOperator);
        registryCoordinator.setEjector(newEjector);
    }

    function test_updateSocket() public {
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        uint256 quorumBitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers);
        _registerOperatorWithCoordinator(defaultOperator, quorumBitmap, defaultPubKey);

        cheats.prank(defaultOperator);
        cheats.expectEmit(true, true, true, true, address(registryCoordinator));
        emit OperatorSocketUpdate(defaultOperatorId, "localhost:32004");
        registryCoordinator.updateSocket("localhost:32004");
    }

    function test_updateSocket_revert_notRegistered() public {
        cheats.prank(defaultOperator);
        cheats.expectRevert(bytes4(keccak256("NotRegistered()")));
        registryCoordinator.updateSocket("localhost:32004");
    }

    function test_createQuorum_revert_notOwner() public {
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams;
        uint96 minimumStake;
        IStakeRegistryTypes.StrategyParams[] memory strategyParams;

        cheats.expectRevert("Ownable: caller is not the owner");
        cheats.prank(defaultOperator);
        registryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams, minimumStake, strategyParams
        );
    }

    function test_createQuorum() public {
        // re-run setup, but setting up zero quorums
        // this is necessary since the default setup already configures the max number of quorums, preventing adding more
        _deployMockEigenLayerAndAVS(0);

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

        uint8 quorumCountBefore = registryCoordinator.quorumCount();

        cheats.expectEmit(true, true, true, true, address(registryCoordinator));
        emit OperatorSetParamsUpdated(quorumCountBefore, operatorSetParams);
        cheats.prank(registryCoordinatorOwner);
        registryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams, minimumStake, strategyParams
        );

        uint8 quorumCountAfter = registryCoordinator.quorumCount();
        assertEq(quorumCountAfter, quorumCountBefore + 1, "quorum count did not increase properly");
        assertLe(quorumCountAfter, MAX_QUORUM_COUNT, "quorum count exceeded max");

        assertEq(
            keccak256(abi.encode(operatorSetParams)),
            keccak256(abi.encode(registryCoordinator.getOperatorSetParams(quorumCountBefore))),
            "OperatorSetParams not stored properly"
        );
    }
}

contract RegistryCoordinatorUnitTests_RegisterOperator is RegistryCoordinatorUnitTests {
    function test_registerOperator_revert_paused() public {
        bytes memory emptyQuorumNumbers = new bytes(0);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;

        // pause registerOperator
        cheats.prank(pauser);
        registryCoordinator.pause(2 ** PAUSED_REGISTER_OPERATOR);

        cheats.startPrank(defaultOperator);
        cheats.expectRevert(bytes4(keccak256("CurrentlyPaused()")));
        registryCoordinator.registerOperator(
            emptyQuorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );
    }

    function test_registerOperator_revert_emptyQuorumNumbers() public {
        bytes memory emptyQuorumNumbers = new bytes(0);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;

        cheats.expectRevert(bytes4(keccak256("BitmapEmpty()")));
        cheats.prank(defaultOperator);
        registryCoordinator.registerOperator(
            emptyQuorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );
    }

    function test_registerOperator_revert_invalidQuorum() public {
        bytes memory quorumNumbersTooLarge = new bytes(1);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;

        quorumNumbersTooLarge[0] = 0xC0;

        cheats.expectRevert(IRegistryCoordinatorErrors.OnlyM2QuorumsAllowed.selector);
        cheats.prank(defaultOperator);
        registryCoordinator.registerOperator(
            quorumNumbersTooLarge, defaultSocket, pubkeyRegistrationParams, emptySig
        );
    }

    function test_registerOperator_revert_nonexistentQuorum() public {
        _deployMockEigenLayerAndAVS(10);
        bytes memory quorumNumbersNotCreated = new bytes(1);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;

        quorumNumbersNotCreated[0] = 0x0B;

        cheats.prank(defaultOperator);
        cheats.expectRevert(IRegistryCoordinatorErrors.OnlyM2QuorumsAllowed.selector);
        registryCoordinator.registerOperator(
            quorumNumbersNotCreated, defaultSocket, pubkeyRegistrationParams, emptySig
        );
    }

    function test_registerOperator_singleQuorum() public {
        bytes memory quorumNumbers = new bytes(1);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        uint96 actualStake = _setOperatorWeight(defaultOperator, defaultQuorumNumber, defaultStake);

        cheats.expectEmit(true, true, true, true, address(registryCoordinator));
        emit OperatorSocketUpdate(defaultOperatorId, defaultSocket);
        cheats.expectEmit(true, true, true, true, address(blsApkRegistry));
        emit OperatorAddedToQuorums(defaultOperator, defaultOperatorId, quorumNumbers);
        cheats.expectEmit(true, true, true, true, address(stakeRegistry));
        emit OperatorStakeUpdate(defaultOperatorId, defaultQuorumNumber, actualStake);
        cheats.expectEmit(true, true, true, true, address(indexRegistry));
        emit QuorumIndexUpdate(defaultOperatorId, defaultQuorumNumber, 0);

        uint256 gasBefore = gasleft();
        cheats.prank(defaultOperator);
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );
        uint256 gasAfter = gasleft();
        emit log_named_uint("gasUsed, register for single quorum", gasBefore - gasAfter);

        uint256 quorumBitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers);

        assertEq(registryCoordinator.getOperatorId(defaultOperator), defaultOperatorId);
        assertEq(
            keccak256(abi.encode(registryCoordinator.getOperator(defaultOperator))),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.OperatorInfo({
                        operatorId: defaultOperatorId,
                        status: ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
                    })
                )
            )
        );
        assertEq(registryCoordinator.getCurrentQuorumBitmap(defaultOperatorId), quorumBitmap);
        assertEq(
            keccak256(
                abi.encode(registryCoordinator.getQuorumBitmapUpdateByIndex(defaultOperatorId, 0))
            ),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                        quorumBitmap: uint192(quorumBitmap),
                        updateBlockNumber: uint32(block.number),
                        nextUpdateBlockNumber: 0
                    })
                )
            )
        );
    }

    // @notice tests registering an operator for a fuzzed assortment of quorums
    function testFuzz_registerOperator(
        uint256 quorumBitmap
    ) public {
        // filter the fuzzed input down to only valid quorums
        quorumBitmap = quorumBitmap & MAX_QUORUM_BITMAP;
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;
        cheats.assume(quorumBitmap != 0);
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        uint96 actualStake;
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            actualStake = _setOperatorWeight(defaultOperator, uint8(quorumNumbers[i]), defaultStake);
        }

        cheats.expectEmit(true, true, true, true, address(registryCoordinator));
        emit OperatorSocketUpdate(defaultOperatorId, defaultSocket);
        cheats.expectEmit(true, true, true, true, address(registryCoordinator));
        emit OperatorRegistered(defaultOperator, defaultOperatorId);
        cheats.expectEmit(true, true, true, true, address(blsApkRegistry));
        emit OperatorAddedToQuorums(defaultOperator, defaultOperatorId, quorumNumbers);
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            cheats.expectEmit(true, true, true, true, address(stakeRegistry));
            emit OperatorStakeUpdate(defaultOperatorId, uint8(quorumNumbers[i]), actualStake);
        }
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            cheats.expectEmit(true, true, true, true, address(indexRegistry));
            emit QuorumIndexUpdate(defaultOperatorId, uint8(quorumNumbers[i]), 0);
        }

        uint256 gasBefore = gasleft();
        cheats.prank(defaultOperator);
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );
        uint256 gasAfter = gasleft();
        emit log_named_uint("gasUsed", gasBefore - gasAfter);
        emit log_named_uint("numQuorums", quorumNumbers.length);

        assertEq(registryCoordinator.getOperatorId(defaultOperator), defaultOperatorId);
        assertEq(
            keccak256(abi.encode(registryCoordinator.getOperator(defaultOperator))),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.OperatorInfo({
                        operatorId: defaultOperatorId,
                        status: ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
                    })
                )
            )
        );
        assertEq(registryCoordinator.getCurrentQuorumBitmap(defaultOperatorId), quorumBitmap);
        assertEq(
            keccak256(
                abi.encode(registryCoordinator.getQuorumBitmapUpdateByIndex(defaultOperatorId, 0))
            ),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                        quorumBitmap: uint192(quorumBitmap),
                        updateBlockNumber: uint32(block.number),
                        nextUpdateBlockNumber: 0
                    })
                )
            )
        );
    }

    // @notice tests registering an operator for a single quorum and later registering them for an additional quorum
    function test_registerOperator_addingQuorumsAfterInitialRegistration() public {
        uint256 registrationBlockNumber = block.number + 100;
        uint256 nextRegistrationBlockNumber = registrationBlockNumber + 100;
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;

        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        _setOperatorWeight(defaultOperator, uint8(quorumNumbers[0]), defaultStake);
        cheats.prank(defaultOperator);
        cheats.roll(registrationBlockNumber);
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );

        bytes memory newQuorumNumbers = new bytes(1);
        newQuorumNumbers[0] = bytes1(defaultQuorumNumber + 1);

        uint96 actualStake =
            _setOperatorWeight(defaultOperator, uint8(newQuorumNumbers[0]), defaultStake);
        cheats.expectEmit(true, true, true, true, address(registryCoordinator));
        emit OperatorSocketUpdate(defaultOperatorId, defaultSocket);
        cheats.expectEmit(true, true, true, true, address(blsApkRegistry));
        emit OperatorAddedToQuorums(defaultOperator, defaultOperatorId, newQuorumNumbers);
        cheats.expectEmit(true, true, true, true, address(stakeRegistry));
        emit OperatorStakeUpdate(defaultOperatorId, uint8(newQuorumNumbers[0]), actualStake);
        cheats.expectEmit(true, true, true, true, address(indexRegistry));
        emit QuorumIndexUpdate(defaultOperatorId, uint8(newQuorumNumbers[0]), 0);
        cheats.roll(nextRegistrationBlockNumber);
        cheats.prank(defaultOperator);
        registryCoordinator.registerOperator(
            newQuorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );

        uint256 quorumBitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers)
            | BitmapUtils.orderedBytesArrayToBitmap(newQuorumNumbers);

        assertEq(registryCoordinator.getOperatorId(defaultOperator), defaultOperatorId);
        assertEq(
            keccak256(abi.encode(registryCoordinator.getOperator(defaultOperator))),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.OperatorInfo({
                        operatorId: defaultOperatorId,
                        status: ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
                    })
                )
            )
        );
        assertEq(registryCoordinator.getCurrentQuorumBitmap(defaultOperatorId), quorumBitmap);
        assertEq(
            keccak256(
                abi.encode(registryCoordinator.getQuorumBitmapUpdateByIndex(defaultOperatorId, 0))
            ),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                        quorumBitmap: uint192(BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers)),
                        updateBlockNumber: uint32(registrationBlockNumber),
                        nextUpdateBlockNumber: uint32(nextRegistrationBlockNumber)
                    })
                )
            )
        );
        assertEq(
            keccak256(
                abi.encode(registryCoordinator.getQuorumBitmapUpdateByIndex(defaultOperatorId, 1))
            ),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                        quorumBitmap: uint192(quorumBitmap),
                        updateBlockNumber: uint32(nextRegistrationBlockNumber),
                        nextUpdateBlockNumber: 0
                    })
                )
            )
        );
    }

    function test_registerOperator_revert_overFilledQuorum(
        uint256 pseudoRandomNumber
    ) public {
        uint32 numOperators = defaultMaxOperatorCount;
        uint32 registrationBlockNumber = 200;
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;

        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        uint256 quorumBitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers);

        cheats.roll(registrationBlockNumber);

        for (uint256 i = 0; i < numOperators; i++) {
            BN254.G1Point memory pubKey =
                BN254.hashToG1(keccak256(abi.encodePacked(pseudoRandomNumber, i)));
            address operator = _incrementAddress(defaultOperator, i);

            _registerOperatorWithCoordinator(operator, quorumBitmap, pubKey);
        }

        address operatorToRegister = _incrementAddress(defaultOperator, numOperators);
        BN254.G1Point memory operatorToRegisterPubKey =
            BN254.hashToG1(keccak256(abi.encodePacked(pseudoRandomNumber, numOperators)));

        blsApkRegistry.setBLSPublicKey(operatorToRegister, operatorToRegisterPubKey);

        _setOperatorWeight(operatorToRegister, defaultQuorumNumber, defaultStake);

        cheats.prank(operatorToRegister);
        cheats.expectRevert(bytes4(keccak256("MaxOperatorCountReached()")));
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );
    }

    function test_registerOperator_revert_operatorAlreadyRegisteredForQuorum() public {
        uint256 registrationBlockNumber = block.number + 100;
        uint256 nextRegistrationBlockNumber = registrationBlockNumber + 100;
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;

        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        _setOperatorWeight(defaultOperator, uint8(quorumNumbers[0]), defaultStake);
        cheats.prank(defaultOperator);
        cheats.roll(registrationBlockNumber);

        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );

        cheats.prank(defaultOperator);
        cheats.roll(nextRegistrationBlockNumber);
        cheats.expectRevert(bytes4(keccak256("AlreadyRegisteredForQuorums()")));
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );
    }

    // tests for the internal `_registerOperator` function:
    function test_registerOperatorInternal_revert_noQuorums() public {
        bytes memory emptyQuorumNumbers = new bytes(0);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;

        cheats.expectRevert(bytes4(keccak256("BitmapEmpty()")));
        registryCoordinator._registerOperatorExternal(
            defaultOperator, defaultOperatorId, emptyQuorumNumbers, defaultSocket, emptySig
        );
    }

    function test_registerOperatorInternal_revert_nonexistentQuorum() public {
        bytes memory quorumNumbersTooLarge = new bytes(1);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;

        quorumNumbersTooLarge[0] = 0xC0;

        cheats.expectRevert(BitmapUtils.BitmapValueTooLarge.selector);
        registryCoordinator._registerOperatorExternal(
            defaultOperator, defaultOperatorId, quorumNumbersTooLarge, defaultSocket, emptySig
        );
    }

    function test_registerOperatorInternal_revert_operatorAlreadyRegisteredForQuorum() public {
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        _setOperatorWeight(defaultOperator, uint8(quorumNumbers[0]), defaultStake);
        registryCoordinator._registerOperatorExternal(
            defaultOperator, defaultOperatorId, quorumNumbers, defaultSocket, emptySig
        );

        cheats.expectRevert(bytes4(keccak256("AlreadyRegisteredForQuorums()")));
        registryCoordinator._registerOperatorExternal(
            defaultOperator, defaultOperatorId, quorumNumbers, defaultSocket, emptySig
        );
    }

    function test_registerOperatorInternal() public {
        bytes memory quorumNumbers = new bytes(1);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        defaultStake = _setOperatorWeight(defaultOperator, uint8(quorumNumbers[0]), defaultStake);

        cheats.expectEmit(true, true, true, true, address(registryCoordinator));
        emit OperatorSocketUpdate(defaultOperatorId, defaultSocket);
        cheats.expectEmit(true, true, true, true, address(registryCoordinator));
        emit OperatorRegistered(defaultOperator, defaultOperatorId);
        cheats.expectEmit(true, true, true, true, address(blsApkRegistry));
        emit OperatorAddedToQuorums(defaultOperator, defaultOperatorId, quorumNumbers);
        cheats.expectEmit(true, true, true, true, address(stakeRegistry));
        emit OperatorStakeUpdate(defaultOperatorId, defaultQuorumNumber, defaultStake);
        cheats.expectEmit(true, true, true, true, address(indexRegistry));
        emit QuorumIndexUpdate(defaultOperatorId, defaultQuorumNumber, 0);

        registryCoordinator._registerOperatorExternal(
            defaultOperator, defaultOperatorId, quorumNumbers, defaultSocket, emptySig
        );

        uint256 quorumBitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers);

        assertEq(registryCoordinator.getCurrentQuorumBitmap(defaultOperatorId), quorumBitmap);
        assertEq(
            keccak256(
                abi.encode(registryCoordinator.getQuorumBitmapUpdateByIndex(defaultOperatorId, 0))
            ),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                        quorumBitmap: uint192(quorumBitmap),
                        updateBlockNumber: uint32(block.number),
                        nextUpdateBlockNumber: 0
                    })
                )
            )
        );
    }
}

// @dev note that this contract also contains tests for the `getQuorumBitmapIndicesAtBlockNumber` and `getQuorumBitmapAtBlockNumberByIndex` view fncs
contract RegistryCoordinatorUnitTests_DeregisterOperator_EjectOperator is
    RegistryCoordinatorUnitTests
{
    function test_deregisterOperator_revert_paused() public {
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        uint256 quorumBitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers);

        _registerOperatorWithCoordinator(defaultOperator, quorumBitmap, defaultPubKey);

        // pause deregisterOperator
        cheats.prank(pauser);
        registryCoordinator.pause(2 ** PAUSED_DEREGISTER_OPERATOR);

        cheats.expectRevert(bytes4(keccak256("CurrentlyPaused()")));
        cheats.prank(defaultOperator);
        registryCoordinator.deregisterOperator(quorumNumbers);
    }

    function test_deregisterOperator_revert_notRegistered() public {
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        cheats.expectRevert(bytes4(keccak256("NotRegistered()")));
        cheats.prank(defaultOperator);
        registryCoordinator.deregisterOperator(quorumNumbers);
    }

    function test_deregisterOperator_revert_incorrectQuorums() public {
        console.log("quorumCount", registryCoordinator.quorumCount());

        assertTrue(
            registryCoordinator.isM2Quorum(uint8(defaultQuorumNumber)),
            "defaultQuorumNumber should be a M2 quorum"
        );

        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        uint256 quorumBitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers);

        quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        cheats.expectRevert(bytes4(keccak256("NotRegistered()")));
        cheats.prank(defaultOperator);
        registryCoordinator.deregisterOperator(quorumNumbers);
    }

    // @notice verifies that an operator who was registered for a single quorum can be deregistered
    function test_deregisterOperator_singleQuorumAndSingleOperator() public {
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;
        uint32 registrationBlockNumber = 100;
        uint32 deregistrationBlockNumber = 200;

        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        _setOperatorWeight(defaultOperator, uint8(quorumNumbers[0]), defaultStake);

        cheats.startPrank(defaultOperator);

        cheats.roll(registrationBlockNumber);

        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );

        uint256 quorumBitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers);

        cheats.expectEmit(true, true, true, true, address(blsApkRegistry));
        emit OperatorRemovedFromQuorums(defaultOperator, defaultOperatorId, quorumNumbers);
        cheats.expectEmit(true, true, true, true, address(stakeRegistry));
        emit OperatorStakeUpdate(defaultOperatorId, defaultQuorumNumber, 0);

        cheats.roll(deregistrationBlockNumber);

        uint256 gasBefore = gasleft();
        registryCoordinator.deregisterOperator(quorumNumbers);
        uint256 gasAfter = gasleft();
        emit log_named_uint("gasUsed", gasBefore - gasAfter);

        assertEq(
            keccak256(abi.encode(registryCoordinator.getOperator(defaultOperator))),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.OperatorInfo({
                        operatorId: defaultOperatorId,
                        status: ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED
                    })
                )
            )
        );
        assertEq(registryCoordinator.getCurrentQuorumBitmap(defaultOperatorId), 0);
        assertEq(
            keccak256(
                abi.encode(registryCoordinator.getQuorumBitmapUpdateByIndex(defaultOperatorId, 0))
            ),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                        quorumBitmap: uint192(quorumBitmap),
                        updateBlockNumber: registrationBlockNumber,
                        nextUpdateBlockNumber: deregistrationBlockNumber
                    })
                )
            )
        );
    }

    // @notice verifies that an operator who was registered for a fuzzed set of quorums can be deregistered
    // @dev deregisters the operator from *all* quorums for which they we registered.
    function testFuzz_deregisterOperator_fuzzedQuorumAndSingleOperator(
        uint256 quorumBitmap
    ) public {
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;
        uint32 registrationBlockNumber = 100;
        uint32 deregistrationBlockNumber = 200;

        // filter down fuzzed input to only valid quorums
        quorumBitmap = quorumBitmap & MAX_QUORUM_BITMAP;
        cheats.assume(quorumBitmap != 0);
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            _setOperatorWeight(defaultOperator, uint8(quorumNumbers[i]), defaultStake);
        }

        cheats.startPrank(defaultOperator);

        cheats.roll(registrationBlockNumber);

        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );

        cheats.expectEmit(true, true, true, true, address(blsApkRegistry));
        emit OperatorRemovedFromQuorums(defaultOperator, defaultOperatorId, quorumNumbers);
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            cheats.expectEmit(true, true, true, true, address(stakeRegistry));
            emit OperatorStakeUpdate(defaultOperatorId, uint8(quorumNumbers[i]), 0);
        }

        cheats.roll(deregistrationBlockNumber);

        uint256 gasBefore = gasleft();
        registryCoordinator.deregisterOperator(quorumNumbers);
        uint256 gasAfter = gasleft();
        emit log_named_uint("gasUsed", gasBefore - gasAfter);
        emit log_named_uint("numQuorums", quorumNumbers.length);

        assertEq(
            keccak256(abi.encode(registryCoordinator.getOperator(defaultOperator))),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.OperatorInfo({
                        operatorId: defaultOperatorId,
                        status: ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED
                    })
                )
            )
        );
        assertEq(registryCoordinator.getCurrentQuorumBitmap(defaultOperatorId), 0);
        assertEq(
            keccak256(
                abi.encode(registryCoordinator.getQuorumBitmapUpdateByIndex(defaultOperatorId, 0))
            ),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                        quorumBitmap: uint192(quorumBitmap),
                        updateBlockNumber: registrationBlockNumber,
                        nextUpdateBlockNumber: deregistrationBlockNumber
                    })
                )
            )
        );
    }
    // @notice verifies that an operator who was registered for a fuzzed set of quorums can be deregistered from a subset of those quorums
    // @dev deregisters the operator from a fuzzed subset of the quorums for which they we registered.

    function testFuzz_deregisterOperator_singleOperator_partialDeregistration(
        uint256 registrationQuorumBitmap,
        uint256 deregistrationQuorumBitmap
    ) public {
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;
        uint32 registrationBlockNumber = 100;
        uint32 deregistrationBlockNumber = 200;

        // filter down fuzzed input to only valid quorums
        registrationQuorumBitmap = registrationQuorumBitmap & MAX_QUORUM_BITMAP;
        cheats.assume(registrationQuorumBitmap != 0);
        // filter the other fuzzed input to a subset of the first fuzzed input
        deregistrationQuorumBitmap = deregistrationQuorumBitmap & registrationQuorumBitmap;
        cheats.assume(deregistrationQuorumBitmap != 0);
        bytes memory registrationquorumNumbers =
            BitmapUtils.bitmapToBytesArray(registrationQuorumBitmap);

        for (uint256 i = 0; i < registrationquorumNumbers.length; i++) {
            _setOperatorWeight(defaultOperator, uint8(registrationquorumNumbers[i]), defaultStake);
        }

        cheats.startPrank(defaultOperator);

        cheats.roll(registrationBlockNumber);

        registryCoordinator.registerOperator(
            registrationquorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );

        bytes memory deregistrationquorumNumbers =
            BitmapUtils.bitmapToBytesArray(deregistrationQuorumBitmap);

        cheats.expectEmit(true, true, true, true, address(blsApkRegistry));
        emit OperatorRemovedFromQuorums(
            defaultOperator, defaultOperatorId, deregistrationquorumNumbers
        );
        for (uint256 i = 0; i < deregistrationquorumNumbers.length; i++) {
            cheats.expectEmit(true, true, true, true, address(stakeRegistry));
            emit OperatorStakeUpdate(defaultOperatorId, uint8(deregistrationquorumNumbers[i]), 0);
        }

        cheats.roll(deregistrationBlockNumber);

        uint256 gasBefore = gasleft();
        registryCoordinator.deregisterOperator(deregistrationquorumNumbers);
        uint256 gasAfter = gasleft();
        emit log_named_uint("gasUsed", gasBefore - gasAfter);
        emit log_named_uint("numQuorums", deregistrationquorumNumbers.length);

        // check that the operator is marked as 'degregistered' only if deregistered from *all* quorums
        if (deregistrationQuorumBitmap == registrationQuorumBitmap) {
            assertEq(
                keccak256(abi.encode(registryCoordinator.getOperator(defaultOperator))),
                keccak256(
                    abi.encode(
                        ISlashingRegistryCoordinatorTypes.OperatorInfo({
                            operatorId: defaultOperatorId,
                            status: ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED
                        })
                    )
                )
            );
        } else {
            assertEq(
                keccak256(abi.encode(registryCoordinator.getOperator(defaultOperator))),
                keccak256(
                    abi.encode(
                        ISlashingRegistryCoordinatorTypes.OperatorInfo({
                            operatorId: defaultOperatorId,
                            status: ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
                        })
                    )
                )
            );
        }
        // ensure that the operator's current quorum bitmap matches the expectation
        uint256 expectedQuorumBitmap =
            BitmapUtils.minus(registrationQuorumBitmap, deregistrationQuorumBitmap);
        assertEq(
            registryCoordinator.getCurrentQuorumBitmap(defaultOperatorId), expectedQuorumBitmap
        );
        // check that the quorum bitmap history is as expected
        assertEq(
            keccak256(
                abi.encode(registryCoordinator.getQuorumBitmapUpdateByIndex(defaultOperatorId, 0))
            ),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                        quorumBitmap: uint192(registrationQuorumBitmap),
                        updateBlockNumber: registrationBlockNumber,
                        nextUpdateBlockNumber: deregistrationBlockNumber
                    })
                )
            )
        );
        // note: there will be no second entry in the operator's bitmap history in the event that the operator has totally deregistered
        if (deregistrationQuorumBitmap != registrationQuorumBitmap) {
            assertEq(
                keccak256(
                    abi.encode(
                        registryCoordinator.getQuorumBitmapUpdateByIndex(defaultOperatorId, 1)
                    )
                ),
                keccak256(
                    abi.encode(
                        ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                            quorumBitmap: uint192(expectedQuorumBitmap),
                            updateBlockNumber: deregistrationBlockNumber,
                            nextUpdateBlockNumber: 0
                        })
                    )
                )
            );
        }
    }

    // @notice registers the max number of operators with fuzzed bitmaps and then deregisters a pseudorandom operator (from all of their quorums)
    function testFuzz_deregisterOperator_manyOperators(
        uint256 pseudoRandomNumber
    ) public {
        uint32 numOperators = defaultMaxOperatorCount;

        uint32 registrationBlockNumber = 100;
        uint32 deregistrationBlockNumber = 200;

        // pad quorumBitmap with 1 until it has numOperators elements
        uint256[] memory quorumBitmaps = new uint256[](numOperators);
        for (uint256 i = 0; i < numOperators; i++) {
            // limit to maxQuorumsToRegisterFor quorums via mask so we don't run out of gas, make them all register for quorum 0 as well
            quorumBitmaps[i] = uint256(
                keccak256(abi.encodePacked("quorumBitmap", pseudoRandomNumber, i))
            ) & (1 << maxQuorumsToRegisterFor - 1) | 1;
        }

        cheats.roll(registrationBlockNumber);

        bytes32[] memory lastOperatorInQuorum = new bytes32[](numQuorums);
        for (uint256 i = 0; i < numOperators; i++) {
            emit log_named_uint("i", i);
            BN254.G1Point memory pubKey =
                BN254.hashToG1(keccak256(abi.encodePacked(pseudoRandomNumber, i)));
            bytes32 operatorId = BN254.hashG1Point(pubKey);
            address operator = _incrementAddress(defaultOperator, i);

            _registerOperatorWithCoordinator(operator, quorumBitmaps[i], pubKey);

            // for each quorum the operator is in, save the operatorId
            bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmaps[i]);
            for (uint256 j = 0; j < quorumNumbers.length; j++) {
                lastOperatorInQuorum[uint8(quorumNumbers[j])] = operatorId;
            }
        }

        uint256 indexOfOperatorToDeregister = pseudoRandomNumber % numOperators;
        address operatorToDeregister =
            _incrementAddress(defaultOperator, indexOfOperatorToDeregister);
        BN254.G1Point memory operatorToDeregisterPubKey = BN254.hashToG1(
            keccak256(abi.encodePacked(pseudoRandomNumber, indexOfOperatorToDeregister))
        );
        bytes32 operatorToDeregisterId = BN254.hashG1Point(operatorToDeregisterPubKey);
        uint256 operatorToDeregisterQuorumBitmap = quorumBitmaps[indexOfOperatorToDeregister];
        bytes memory operatorToDeregisterQuorumNumbers =
            BitmapUtils.bitmapToBytesArray(operatorToDeregisterQuorumBitmap);

        bytes32[] memory operatorIdsToSwap = new bytes32[](operatorToDeregisterQuorumNumbers.length);
        for (uint256 i = 0; i < operatorToDeregisterQuorumNumbers.length; i++) {
            operatorIdsToSwap[i] = lastOperatorInQuorum[uint8(operatorToDeregisterQuorumNumbers[i])];
        }

        cheats.expectEmit(true, true, true, true, address(blsApkRegistry));
        emit OperatorRemovedFromQuorums(
            operatorToDeregister, operatorToDeregisterId, operatorToDeregisterQuorumNumbers
        );

        for (uint256 i = 0; i < operatorToDeregisterQuorumNumbers.length; i++) {
            cheats.expectEmit(true, true, true, true, address(stakeRegistry));
            emit OperatorStakeUpdate(
                operatorToDeregisterId, uint8(operatorToDeregisterQuorumNumbers[i]), 0
            );
        }

        cheats.roll(deregistrationBlockNumber);

        cheats.prank(operatorToDeregister);
        registryCoordinator.deregisterOperator(operatorToDeregisterQuorumNumbers);

        assertEq(
            keccak256(abi.encode(registryCoordinator.getOperator(operatorToDeregister))),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.OperatorInfo({
                        operatorId: operatorToDeregisterId,
                        status: ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED
                    })
                )
            )
        );
        assertEq(registryCoordinator.getCurrentQuorumBitmap(defaultOperatorId), 0);
        assertEq(
            keccak256(
                abi.encode(
                    registryCoordinator.getQuorumBitmapUpdateByIndex(operatorToDeregisterId, 0)
                )
            ),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                        quorumBitmap: uint192(operatorToDeregisterQuorumBitmap),
                        updateBlockNumber: registrationBlockNumber,
                        nextUpdateBlockNumber: deregistrationBlockNumber
                    })
                )
            )
        );
    }

    // @notice verify that it is possible for an operator to register, deregister, and then register again!
    function test_reregisterOperator() public {
        test_deregisterOperator_singleQuorumAndSingleOperator();

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;
        uint32 reregistrationBlockNumber = 201;

        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        cheats.startPrank(defaultOperator);

        cheats.roll(reregistrationBlockNumber);

        // store data before registering, to check against later
        ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate memory previousQuorumBitmapUpdate =
            registryCoordinator.getQuorumBitmapUpdateByIndex(defaultOperatorId, 0);

        // re-register the operator
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );
        // check success of registration
        uint256 quorumBitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers);
        assertEq(registryCoordinator.getOperatorId(defaultOperator), defaultOperatorId, "1");
        assertEq(
            keccak256(abi.encode(registryCoordinator.getOperator(defaultOperator))),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.OperatorInfo({
                        operatorId: defaultOperatorId,
                        status: ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
                    })
                )
            ),
            "2"
        );
        assertEq(registryCoordinator.getCurrentQuorumBitmap(defaultOperatorId), quorumBitmap, "3");
        // check that previous entry in bitmap history was not changed
        assertEq(
            keccak256(
                abi.encode(registryCoordinator.getQuorumBitmapUpdateByIndex(defaultOperatorId, 0))
            ),
            keccak256(abi.encode(previousQuorumBitmapUpdate)),
            "4"
        );
        // check that new entry in bitmap history is as expected
        uint256 historyLength = registryCoordinator.getQuorumBitmapHistoryLength(defaultOperatorId);
        assertEq(
            keccak256(
                abi.encode(
                    registryCoordinator.getQuorumBitmapUpdateByIndex(
                        defaultOperatorId, historyLength - 1
                    )
                )
            ),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                        quorumBitmap: uint192(quorumBitmap),
                        updateBlockNumber: uint32(reregistrationBlockNumber),
                        nextUpdateBlockNumber: 0
                    })
                )
            ),
            "5"
        );
    }

    // tests for the internal `_deregisterOperator` function:
    function test_deregisterOperatorExternal_revert_noQuorums() public {
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;
        uint32 registrationBlockNumber = 100;
        uint32 deregistrationBlockNumber = 200;

        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        _setOperatorWeight(defaultOperator, uint8(quorumNumbers[0]), defaultStake);

        cheats.roll(registrationBlockNumber);
        cheats.startPrank(defaultOperator);
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );

        bytes memory emptyQuorumNumbers = new bytes(0);

        cheats.roll(deregistrationBlockNumber);
        cheats.expectRevert(bytes4(keccak256("BitmapCannotBeZero()")));
        registryCoordinator._deregisterOperatorExternal(defaultOperator, emptyQuorumNumbers);
    }

    function test_deregisterOperatorExternal_revert_notRegistered() public {
        bytes memory emptyQuorumNumbers = new bytes(0);
        cheats.expectRevert(bytes4(keccak256("NotRegistered()")));
        registryCoordinator._deregisterOperatorExternal(defaultOperator, emptyQuorumNumbers);
    }

    function test_deregisterOperatorExternal_revert_incorrectQuorums() public {
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;
        uint32 registrationBlockNumber = 100;
        uint32 deregistrationBlockNumber = 200;

        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        _setOperatorWeight(defaultOperator, uint8(quorumNumbers[0]), defaultStake);

        cheats.roll(registrationBlockNumber);
        cheats.startPrank(defaultOperator);
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );

        bytes memory incorrectQuorum = new bytes(1);
        incorrectQuorum[0] = bytes1(defaultQuorumNumber + 1);

        cheats.roll(deregistrationBlockNumber);
        cheats.expectRevert(bytes4(keccak256("NotRegisteredForQuorum()")));
        registryCoordinator._deregisterOperatorExternal(defaultOperator, incorrectQuorum);
    }

    function test_reregisterOperator_revert_reregistrationDelay() public {
        uint256 reregistrationDelay = 1 days;
        cheats.warp(block.timestamp + reregistrationDelay);
        cheats.prank(registryCoordinatorOwner);
        registryCoordinator.setEjectionCooldown(reregistrationDelay);

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;
        uint32 registrationBlockNumber = 100;
        uint32 reregistrationBlockNumber = 200;

        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        _setOperatorWeight(defaultOperator, uint8(quorumNumbers[0]), defaultStake);

        cheats.prank(defaultOperator);
        cheats.roll(registrationBlockNumber);
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );

        cheats.prank(ejector);
        registryCoordinator.ejectOperator(defaultOperator, quorumNumbers);

        cheats.prank(defaultOperator);
        cheats.roll(reregistrationBlockNumber);
        cheats.expectRevert(bytes4(keccak256("CannotReregisterYet()")));
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );
    }

    function test_reregisterOperator_reregistrationDelay() public {
        uint256 reregistrationDelay = 1 days;
        cheats.warp(block.timestamp + reregistrationDelay);
        cheats.prank(registryCoordinatorOwner);
        registryCoordinator.setEjectionCooldown(reregistrationDelay);

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;
        uint32 registrationBlockNumber = 100;
        uint32 reregistrationBlockNumber = 200;

        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        _setOperatorWeight(defaultOperator, uint8(quorumNumbers[0]), defaultStake);

        cheats.prank(defaultOperator);
        cheats.roll(registrationBlockNumber);
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );

        cheats.prank(ejector);
        registryCoordinator.ejectOperator(defaultOperator, quorumNumbers);

        cheats.prank(defaultOperator);
        cheats.roll(reregistrationBlockNumber);
        cheats.warp(block.timestamp + reregistrationDelay + 1);
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );
    }

    // note: this is not possible to test, because there is no route to getting the operator registered for nonexistent quorums
    // function test_deregisterOperatorExternal_revert_nonexistentQuorums() public {

    function testFuzz_deregisterOperatorInternal_partialDeregistration(
        uint256 registrationQuorumBitmap,
        uint256 deregistrationQuorumBitmap
    ) public {
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;
        uint32 registrationBlockNumber = 100;
        uint32 deregistrationBlockNumber = 200;

        // filter down fuzzed input to only valid quorums
        registrationQuorumBitmap = registrationQuorumBitmap & MAX_QUORUM_BITMAP;
        cheats.assume(registrationQuorumBitmap != 0);
        // filter the other fuzzed input to a subset of the first fuzzed input
        deregistrationQuorumBitmap = deregistrationQuorumBitmap & registrationQuorumBitmap;
        cheats.assume(deregistrationQuorumBitmap != 0);
        bytes memory registrationquorumNumbers =
            BitmapUtils.bitmapToBytesArray(registrationQuorumBitmap);

        for (uint256 i = 0; i < registrationquorumNumbers.length; i++) {
            _setOperatorWeight(defaultOperator, uint8(registrationquorumNumbers[i]), defaultStake);
        }

        cheats.roll(registrationBlockNumber);
        cheats.startPrank(defaultOperator);
        registryCoordinator.registerOperator(
            registrationquorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );

        bytes memory deregistrationquorumNumbers =
            BitmapUtils.bitmapToBytesArray(deregistrationQuorumBitmap);

        cheats.expectEmit(true, true, true, true, address(blsApkRegistry));
        emit OperatorRemovedFromQuorums(
            defaultOperator, defaultOperatorId, deregistrationquorumNumbers
        );
        for (uint256 i = 0; i < deregistrationquorumNumbers.length; i++) {
            cheats.expectEmit(true, true, true, true, address(stakeRegistry));
            emit OperatorStakeUpdate(defaultOperatorId, uint8(deregistrationquorumNumbers[i]), 0);
        }

        cheats.roll(deregistrationBlockNumber);

        registryCoordinator._deregisterOperatorExternal(
            defaultOperator, deregistrationquorumNumbers
        );

        // check that the operator is marked as 'degregistered' only if deregistered from *all* quorums
        if (deregistrationQuorumBitmap == registrationQuorumBitmap) {
            assertEq(
                keccak256(abi.encode(registryCoordinator.getOperator(defaultOperator))),
                keccak256(
                    abi.encode(
                        ISlashingRegistryCoordinatorTypes.OperatorInfo({
                            operatorId: defaultOperatorId,
                            status: ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED
                        })
                    )
                )
            );
        } else {
            assertEq(
                keccak256(abi.encode(registryCoordinator.getOperator(defaultOperator))),
                keccak256(
                    abi.encode(
                        ISlashingRegistryCoordinatorTypes.OperatorInfo({
                            operatorId: defaultOperatorId,
                            status: ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
                        })
                    )
                )
            );
        }
        // ensure that the operator's current quorum bitmap matches the expectation
        uint256 expectedQuorumBitmap =
            BitmapUtils.minus(registrationQuorumBitmap, deregistrationQuorumBitmap);
        assertEq(
            registryCoordinator.getCurrentQuorumBitmap(defaultOperatorId), expectedQuorumBitmap
        );
        // check that the quorum bitmap history is as expected
        assertEq(
            keccak256(
                abi.encode(registryCoordinator.getQuorumBitmapUpdateByIndex(defaultOperatorId, 0))
            ),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                        quorumBitmap: uint192(registrationQuorumBitmap),
                        updateBlockNumber: registrationBlockNumber,
                        nextUpdateBlockNumber: deregistrationBlockNumber
                    })
                )
            )
        );
        // note: there will be no second entry in the operator's bitmap history in the event that the operator has totally deregistered
        if (deregistrationQuorumBitmap != registrationQuorumBitmap) {
            assertEq(
                keccak256(
                    abi.encode(
                        registryCoordinator.getQuorumBitmapUpdateByIndex(defaultOperatorId, 1)
                    )
                ),
                keccak256(
                    abi.encode(
                        ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                            quorumBitmap: uint192(expectedQuorumBitmap),
                            updateBlockNumber: deregistrationBlockNumber,
                            nextUpdateBlockNumber: 0
                        })
                    )
                )
            );
        }
    }

    function test_ejectOperator_allQuorums() public {
        // register operator with default stake with default quorum number
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;

        _setOperatorWeight(defaultOperator, uint8(quorumNumbers[0]), defaultStake);

        cheats.prank(defaultOperator);
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );

        cheats.expectEmit(true, true, true, true, address(blsApkRegistry));
        emit OperatorRemovedFromQuorums(defaultOperator, defaultOperatorId, quorumNumbers);

        cheats.expectEmit(true, true, true, true, address(stakeRegistry));
        emit OperatorStakeUpdate(defaultOperatorId, uint8(quorumNumbers[0]), 0);

        // eject
        cheats.prank(ejector);
        registryCoordinator.ejectOperator(defaultOperator, quorumNumbers);

        // make sure the operator is deregistered
        assertEq(
            keccak256(abi.encode(registryCoordinator.getOperator(defaultOperator))),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.OperatorInfo({
                        operatorId: defaultOperatorId,
                        status: ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED
                    })
                )
            )
        );
        // make sure the operator is not in any quorums
        assertEq(registryCoordinator.getCurrentQuorumBitmap(defaultOperatorId), 0);
    }

    function test_ejectOperator_subsetOfQuorums() public {
        // register operator with default stake with 2 quorums
        bytes memory quorumNumbers = new bytes(2);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        quorumNumbers[1] = bytes1(defaultQuorumNumber + 1);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            _setOperatorWeight(defaultOperator, uint8(quorumNumbers[i]), defaultStake);
        }

        cheats.prank(defaultOperator);
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );

        // eject from only first quorum
        bytes memory quorumNumbersToEject = new bytes(1);
        quorumNumbersToEject[0] = quorumNumbers[0];

        cheats.expectEmit(true, true, true, true, address(blsApkRegistry));
        emit OperatorRemovedFromQuorums(defaultOperator, defaultOperatorId, quorumNumbersToEject);

        cheats.expectEmit(true, true, true, true, address(stakeRegistry));
        emit OperatorStakeUpdate(defaultOperatorId, uint8(quorumNumbersToEject[0]), 0);

        cheats.prank(ejector);
        registryCoordinator.ejectOperator(defaultOperator, quorumNumbersToEject);

        // make sure the operator is registered
        assertEq(
            keccak256(abi.encode(registryCoordinator.getOperator(defaultOperator))),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.OperatorInfo({
                        operatorId: defaultOperatorId,
                        status: ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
                    })
                )
            )
        );
        // make sure the operator is properly removed from the quorums
        assertEq(
            registryCoordinator.getCurrentQuorumBitmap(defaultOperatorId),
            // quorumsRegisteredFor & ~quorumsEjectedFrom
            BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers)
                & ~BitmapUtils.orderedBytesArrayToBitmap(quorumNumbersToEject)
        );
    }

    function test_ejectOperator_revert_notEjector() public {
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;

        _setOperatorWeight(defaultOperator, uint8(quorumNumbers[0]), defaultStake);

        cheats.prank(defaultOperator);
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );

        cheats.expectRevert(bytes4(keccak256("OnlyEjector()")));
        cheats.prank(defaultOperator);
        registryCoordinator.ejectOperator(defaultOperator, quorumNumbers);
    }

    function test_getQuorumBitmapIndicesAtBlockNumber_revert_notRegistered() public {
        uint32 blockNumber;
        bytes32[] memory operatorIds = new bytes32[](1);
        cheats.expectRevert(
            "RegistryCoordinator.getQuorumBitmapIndexAtBlockNumber: no bitmap update found for operatorId"
        );
        registryCoordinator.getQuorumBitmapIndicesAtBlockNumber(blockNumber, operatorIds);
    }

    // @notice tests for correct reversion and return values in the event that an operator registers
    function test_getQuorumBitmapIndicesAtBlockNumber_operatorRegistered() public {
        // register the operator
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;
        uint32 registrationBlockNumber = 100;
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        _setOperatorWeight(defaultOperator, uint8(quorumNumbers[0]), defaultStake);
        cheats.roll(registrationBlockNumber);
        cheats.startPrank(defaultOperator);
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );

        uint32 blockNumber = 0;
        bytes32[] memory operatorIds = new bytes32[](1);
        operatorIds[0] = defaultOperatorId;

        uint32[] memory returnArray;
        cheats.expectRevert(
            "RegistryCoordinator.getQuorumBitmapIndexAtBlockNumber: no bitmap update found for operatorId"
        );
        registryCoordinator.getQuorumBitmapIndicesAtBlockNumber(blockNumber, operatorIds);

        blockNumber = registrationBlockNumber;
        returnArray =
            registryCoordinator.getQuorumBitmapIndicesAtBlockNumber(blockNumber, operatorIds);
        assertEq(
            returnArray[0],
            0,
            "defaultOperator bitmap index at blockNumber registrationBlockNumber was not 0"
        );

        blockNumber = registrationBlockNumber + 1;
        returnArray =
            registryCoordinator.getQuorumBitmapIndicesAtBlockNumber(blockNumber, operatorIds);
        assertEq(
            returnArray[0],
            0,
            "defaultOperator bitmap index at blockNumber registrationBlockNumber + 1 was not 0"
        );
    }

    // @notice tests for correct reversion and return values in the event that an operator registers and later deregisters
    function test_getQuorumBitmapIndicesAtBlockNumber_operatorDeregistered() public {
        test_deregisterOperator_singleQuorumAndSingleOperator();
        uint32 registrationBlockNumber = 100;
        uint32 deregistrationBlockNumber = 200;
        uint32 blockNumber = 0;
        bytes32[] memory operatorIds = new bytes32[](1);
        operatorIds[0] = defaultOperatorId;

        uint32[] memory returnArray;
        cheats.expectRevert(
            "RegistryCoordinator.getQuorumBitmapIndexAtBlockNumber: no bitmap update found for operatorId"
        );
        registryCoordinator.getQuorumBitmapIndicesAtBlockNumber(blockNumber, operatorIds);

        blockNumber = registrationBlockNumber;
        returnArray =
            registryCoordinator.getQuorumBitmapIndicesAtBlockNumber(blockNumber, operatorIds);
        assertEq(
            returnArray[0],
            0,
            "defaultOperator bitmap index at blockNumber registrationBlockNumber was not 0"
        );

        blockNumber = registrationBlockNumber + 1;
        returnArray =
            registryCoordinator.getQuorumBitmapIndicesAtBlockNumber(blockNumber, operatorIds);
        assertEq(
            returnArray[0],
            0,
            "defaultOperator bitmap index at blockNumber registrationBlockNumber + 1 was not 0"
        );

        blockNumber = deregistrationBlockNumber;
        returnArray =
            registryCoordinator.getQuorumBitmapIndicesAtBlockNumber(blockNumber, operatorIds);
        assertEq(
            returnArray[0],
            1,
            "defaultOperator bitmap index at blockNumber deregistrationBlockNumber was not 1"
        );

        blockNumber = deregistrationBlockNumber + 1;
        returnArray =
            registryCoordinator.getQuorumBitmapIndicesAtBlockNumber(blockNumber, operatorIds);
        assertEq(
            returnArray[0],
            1,
            "defaultOperator bitmap index at blockNumber deregistrationBlockNumber + 1 was not 1"
        );
    }

    // @notice tests for correct reversion and return values in the event that an operator registers and later deregisters
    function test_getQuorumBitmapAtBlockNumberByIndex_operatorDeregistered() public {
        test_deregisterOperator_singleQuorumAndSingleOperator();
        uint32 registrationBlockNumber = 100;
        uint32 deregistrationBlockNumber = 200;
        uint32 blockNumber = 0;
        bytes32 operatorId = defaultOperatorId;
        uint256 index = 0;

        uint192 defaultQuorumBitmap = 1;
        uint192 emptyBitmap = 0;

        // try an incorrect blockNumber input and confirm reversion
        cheats.expectRevert(QuorumBitmapHistoryLib.BitmapUpdateIsAfterBlockNumber.selector);
        uint192 returnVal =
            registryCoordinator.getQuorumBitmapAtBlockNumberByIndex(operatorId, blockNumber, index);

        blockNumber = registrationBlockNumber;
        returnVal =
            registryCoordinator.getQuorumBitmapAtBlockNumberByIndex(operatorId, blockNumber, index);
        assertEq(
            returnVal,
            defaultQuorumBitmap,
            "defaultOperator bitmap index at blockNumber registrationBlockNumber was not defaultQuorumBitmap"
        );

        blockNumber = registrationBlockNumber + 1;
        returnVal =
            registryCoordinator.getQuorumBitmapAtBlockNumberByIndex(operatorId, blockNumber, index);
        assertEq(
            returnVal,
            defaultQuorumBitmap,
            "defaultOperator bitmap index at blockNumber registrationBlockNumber + 1 was not defaultQuorumBitmap"
        );

        // try an incorrect index input and confirm reversion
        index = 1;
        cheats.expectRevert(QuorumBitmapHistoryLib.BitmapUpdateIsAfterBlockNumber.selector);
        returnVal =
            registryCoordinator.getQuorumBitmapAtBlockNumberByIndex(operatorId, blockNumber, index);

        blockNumber = deregistrationBlockNumber;
        returnVal =
            registryCoordinator.getQuorumBitmapAtBlockNumberByIndex(operatorId, blockNumber, index);
        assertEq(
            returnVal,
            emptyBitmap,
            "defaultOperator bitmap index at blockNumber deregistrationBlockNumber was not emptyBitmap"
        );

        blockNumber = deregistrationBlockNumber + 1;
        returnVal =
            registryCoordinator.getQuorumBitmapAtBlockNumberByIndex(operatorId, blockNumber, index);
        assertEq(
            returnVal,
            emptyBitmap,
            "defaultOperator bitmap index at blockNumber deregistrationBlockNumber + 1 was not emptyBitmap"
        );

        // try an incorrect index input and confirm reversion
        index = 0;
        cheats.expectRevert(QuorumBitmapHistoryLib.NextBitmapUpdateIsBeforeBlockNumber.selector);
        returnVal =
            registryCoordinator.getQuorumBitmapAtBlockNumberByIndex(operatorId, blockNumber, index);
    }
}

contract RegistryCoordinatorUnitTests_RegisterOperatorWithChurn is RegistryCoordinatorUnitTests {
    // @notice registers an operator for a single quorum, with a fuzzed pubkey, churning out another operator from the quorum
    function testFuzz_registerOperatorWithChurn(
        uint256 pseudoRandomNumber
    ) public {
        uint32 numOperators = defaultMaxOperatorCount;
        uint32 kickRegistrationBlockNumber = 100;
        uint32 registrationBlockNumber = 200;

        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        uint256 quorumBitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers);

        cheats.roll(kickRegistrationBlockNumber);

        for (uint256 i = 0; i < numOperators - 1; i++) {
            BN254.G1Point memory pubKey =
                BN254.hashToG1(keccak256(abi.encodePacked(pseudoRandomNumber, i)));
            address operator = _incrementAddress(defaultOperator, i);

            _registerOperatorWithCoordinator(operator, quorumBitmap, pubKey);
        }

        address operatorToRegister = _incrementAddress(defaultOperator, numOperators);
        BN254.G1Point memory operatorToRegisterPubKey =
            BN254.hashToG1(keccak256(abi.encodePacked(pseudoRandomNumber, numOperators)));
        bytes32 operatorToRegisterId = BN254.hashG1Point(operatorToRegisterPubKey);
        bytes32 operatorToKickId;
        address operatorToKick;

        // register last operator before kick
        ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory operatorKickParams =
            new ISlashingRegistryCoordinatorTypes.OperatorKickParam[](1);
        {
            BN254.G1Point memory pubKey =
                BN254.hashToG1(keccak256(abi.encodePacked(pseudoRandomNumber, numOperators - 1)));
            operatorToKickId = BN254.hashG1Point(pubKey);
            operatorToKick = _incrementAddress(defaultOperator, numOperators - 1);

            _registerOperatorWithCoordinator(operatorToKick, quorumBitmap, pubKey);

            bytes32[] memory operatorIdsToSwap = new bytes32[](1);
            // operatorIdsToSwap[0] = operatorToRegisterId
            operatorIdsToSwap[0] = operatorToRegisterId;

            operatorKickParams[0] = ISlashingRegistryCoordinatorTypes.OperatorKickParam({
                quorumNumber: defaultQuorumNumber,
                operator: operatorToKick
            });
        }

        blsApkRegistry.setBLSPublicKey(operatorToRegister, operatorToRegisterPubKey);

        uint96 registeringStake = defaultKickBIPsOfOperatorStake * defaultStake;
        _setOperatorWeight(operatorToRegister, defaultQuorumNumber, registeringStake);

        cheats.roll(registrationBlockNumber);
        cheats.expectEmit(true, true, true, true, address(registryCoordinator));
        emit OperatorSocketUpdate(operatorToRegisterId, defaultSocket);

        cheats.expectEmit(true, true, true, true, address(registryCoordinator));
        emit OperatorRegistered(operatorToRegister, operatorToRegisterId);

        cheats.expectEmit(true, true, true, true, address(blsApkRegistry));
        emit OperatorAddedToQuorums(operatorToRegister, operatorToRegisterId, quorumNumbers);
        cheats.expectEmit(true, true, true, false, address(stakeRegistry));
        emit OperatorStakeUpdate(operatorToRegisterId, defaultQuorumNumber, registeringStake);
        cheats.expectEmit(true, true, true, true, address(indexRegistry));
        emit QuorumIndexUpdate(operatorToRegisterId, defaultQuorumNumber, numOperators);

        // Then expect the deregistration events
        cheats.expectEmit(true, true, true, true, address(registryCoordinator));
        emit OperatorDeregistered(operatorKickParams[0].operator, operatorToKickId);
        cheats.expectEmit(true, true, true, true, address(blsApkRegistry));
        emit OperatorRemovedFromQuorums(
            operatorKickParams[0].operator, operatorToKickId, quorumNumbers
        );
        cheats.expectEmit(true, true, true, true, address(stakeRegistry));
        emit OperatorStakeUpdate(operatorToKickId, defaultQuorumNumber, 0);
        cheats.expectEmit(true, true, true, true, address(indexRegistry));
        emit QuorumIndexUpdate(operatorToRegisterId, defaultQuorumNumber, numOperators - 1);

        {
            ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptyAVSRegSig;
            ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory signatureWithExpiry =
            _signOperatorChurnApproval(
                operatorToRegister,
                operatorToRegisterId,
                operatorKickParams,
                defaultSalt,
                block.timestamp + 10
            );
            cheats.prank(operatorToRegister);
            uint256 gasBefore = gasleft();
            registryCoordinator.registerOperatorWithChurn(
                quorumNumbers,
                defaultSocket,
                pubkeyRegistrationParams,
                operatorKickParams,
                signatureWithExpiry,
                emptyAVSRegSig
            );
            uint256 gasAfter = gasleft();
            emit log_named_uint("gasUsed", gasBefore - gasAfter);
        }

        assertEq(
            keccak256(abi.encode(registryCoordinator.getOperator(operatorToRegister))),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.OperatorInfo({
                        operatorId: operatorToRegisterId,
                        status: ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED
                    })
                )
            )
        );
        assertEq(
            keccak256(abi.encode(registryCoordinator.getOperator(operatorToKick))),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.OperatorInfo({
                        operatorId: operatorToKickId,
                        status: ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED
                    })
                )
            )
        );
        assertEq(
            keccak256(
                abi.encode(registryCoordinator.getQuorumBitmapUpdateByIndex(operatorToKickId, 0))
            ),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                        quorumBitmap: uint192(quorumBitmap),
                        updateBlockNumber: kickRegistrationBlockNumber,
                        nextUpdateBlockNumber: registrationBlockNumber
                    })
                )
            )
        );
    }

    function test_registerOperatorWithChurn_revert_lessThanKickBIPsOfOperatorStake(
        uint256 pseudoRandomNumber
    ) public {
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptyAVSRegSig;

        (
            address operatorToRegister,
            BN254.G1Point memory operatorToRegisterPubKey,
            ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory operatorKickParams
        ) = _test_registerOperatorWithChurn_SetUp(pseudoRandomNumber, quorumNumbers, defaultStake);
        bytes32 operatorToRegisterId = BN254.hashG1Point(operatorToRegisterPubKey);

        _setOperatorWeight(operatorToRegister, defaultQuorumNumber, defaultStake);

        cheats.roll(registrationBlockNumber);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory signatureWithExpiry =
        _signOperatorChurnApproval(
            operatorToRegister,
            operatorToRegisterId,
            operatorKickParams,
            defaultSalt,
            block.timestamp + 10
        );
        cheats.prank(operatorToRegister);
        cheats.expectRevert(bytes4(keccak256("InsufficientStakeForChurn()")));
        registryCoordinator.registerOperatorWithChurn(
            quorumNumbers,
            defaultSocket,
            pubkeyRegistrationParams,
            operatorKickParams,
            signatureWithExpiry,
            emptyAVSRegSig
        );
    }

    function test_registerOperatorWithChurn_revert_lessThanKickBIPsOfTotalStake(
        uint256 pseudoRandomNumber
    ) public {
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptyAVSRegSig;

        uint96 operatorToKickStake = defaultMaxOperatorCount * defaultStake;
        (
            address operatorToRegister,
            BN254.G1Point memory operatorToRegisterPubKey,
            ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory operatorKickParams
        ) = _test_registerOperatorWithChurn_SetUp(
            pseudoRandomNumber, quorumNumbers, operatorToKickStake
        );
        bytes32 operatorToRegisterId = BN254.hashG1Point(operatorToRegisterPubKey);

        // set the stake of the operator to register to the defaultKickBIPsOfOperatorStake multiple of the operatorToKickStake
        _setOperatorWeight(
            operatorToRegister,
            defaultQuorumNumber,
            operatorToKickStake * defaultKickBIPsOfOperatorStake / 10000 + 1
        );

        cheats.roll(registrationBlockNumber);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory signatureWithExpiry =
        _signOperatorChurnApproval(
            operatorToRegister,
            operatorToRegisterId,
            operatorKickParams,
            defaultSalt,
            block.timestamp + 10
        );
        cheats.prank(operatorToRegister);
        cheats.expectRevert(bytes4(keccak256("CannotKickOperatorAboveThreshold()")));
        registryCoordinator.registerOperatorWithChurn(
            quorumNumbers,
            defaultSocket,
            pubkeyRegistrationParams,
            operatorKickParams,
            signatureWithExpiry,
            emptyAVSRegSig
        );
    }

    function test_registerOperatorWithChurn_revert_invalidChurnApproverSignature(
        uint256 pseudoRandomNumber
    ) public {
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptyAVSRegSig;

        (
            address operatorToRegister,
            ,
            ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory operatorKickParams
        ) = _test_registerOperatorWithChurn_SetUp(pseudoRandomNumber, quorumNumbers, defaultStake);

        uint96 registeringStake = defaultKickBIPsOfOperatorStake * defaultStake;
        _setOperatorWeight(operatorToRegister, defaultQuorumNumber, registeringStake);

        cheats.roll(registrationBlockNumber);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory signatureWithSaltAndExpiry;
        signatureWithSaltAndExpiry.expiry = block.timestamp + 10;
        signatureWithSaltAndExpiry.signature =
            hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001B";
        signatureWithSaltAndExpiry.salt = defaultSalt;
        cheats.prank(operatorToRegister);
        cheats.expectRevert(bytes4(keccak256("InvalidSignature()")));
        registryCoordinator.registerOperatorWithChurn(
            quorumNumbers,
            defaultSocket,
            pubkeyRegistrationParams,
            operatorKickParams,
            signatureWithSaltAndExpiry,
            emptyAVSRegSig
        );
    }

    function test_registerOperatorWithChurn_revert_expiredChurnApproverSignature(
        uint256 pseudoRandomNumber
    ) public {
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptyAVSRegSig;

        (
            address operatorToRegister,
            BN254.G1Point memory operatorToRegisterPubKey,
            ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory operatorKickParams
        ) = _test_registerOperatorWithChurn_SetUp(pseudoRandomNumber, quorumNumbers, defaultStake);
        bytes32 operatorToRegisterId = BN254.hashG1Point(operatorToRegisterPubKey);

        uint96 registeringStake = defaultKickBIPsOfOperatorStake * defaultStake;
        _setOperatorWeight(operatorToRegister, defaultQuorumNumber, registeringStake);

        cheats.roll(registrationBlockNumber);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory signatureWithSaltAndExpiry =
        _signOperatorChurnApproval(
            operatorToRegister,
            operatorToRegisterId,
            operatorKickParams,
            defaultSalt,
            block.timestamp - 1
        );
        cheats.prank(operatorToRegister);
        cheats.expectRevert(bytes4(keccak256("SignatureExpired()")));
        registryCoordinator.registerOperatorWithChurn(
            quorumNumbers,
            defaultSocket,
            pubkeyRegistrationParams,
            operatorKickParams,
            signatureWithSaltAndExpiry,
            emptyAVSRegSig
        );
    }
}

contract RegistryCoordinatorUnitTests_UpdateOperators is RegistryCoordinatorUnitTests {
    function test_updateOperators_revert_paused() public {
        cheats.prank(pauser);
        registryCoordinator.pause(2 ** PAUSED_UPDATE_OPERATOR);

        address[] memory operatorsToUpdate = new address[](1);
        operatorsToUpdate[0] = defaultOperator;

        cheats.expectRevert(bytes4(keccak256("CurrentlyPaused()")));
        registryCoordinator.updateOperators(operatorsToUpdate);
    }

    // @notice tests the `updateOperators` function with a single registered operator as input
    function test_updateOperators_singleOperator() public {
        // register the default operator
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;
        uint32 registrationBlockNumber = 100;
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        _setOperatorWeight(defaultOperator, uint8(quorumNumbers[0]), defaultStake);
        cheats.startPrank(defaultOperator);
        cheats.roll(registrationBlockNumber);
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );

        address[] memory operatorsToUpdate = new address[](1);
        operatorsToUpdate[0] = defaultOperator;

        registryCoordinator.updateOperators(operatorsToUpdate);
    }

    // @notice tests the `updateOperators` function with a single registered operator as input
    // @dev also sets up return data from the StakeRegistry
    function testFuzz_updateOperators_singleOperator(
        uint192 registrationBitmap,
        uint192 mockReturnData
    ) public {
        // filter fuzzed inputs to only valid inputs
        cheats.assume(registrationBitmap != 0);
        mockReturnData = (mockReturnData & registrationBitmap);
        emit log_named_uint("mockReturnData", mockReturnData);

        // register the default operator
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;
        uint32 registrationBlockNumber = 100;
        bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(registrationBitmap);
        for (uint256 i = 0; i < quorumNumbers.length; ++i) {
            _setOperatorWeight(defaultOperator, uint8(quorumNumbers[i]), defaultStake);
        }
        cheats.startPrank(defaultOperator);
        cheats.roll(registrationBlockNumber);
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );

        address[] memory operatorsToUpdate = new address[](1);
        operatorsToUpdate[0] = defaultOperator;

        uint192 quorumBitmapBefore = registryCoordinator.getCurrentQuorumBitmap(defaultOperatorId);
        assertEq(quorumBitmapBefore, registrationBitmap, "operator bitmap somehow incorrect");

        // make the stake registry return info that the operator should be removed from quorums
        uint192 quorumBitmapToRemove = mockReturnData;
        bytes memory quorumNumbersToRemove = BitmapUtils.bitmapToBytesArray(quorumBitmapToRemove);
        for (uint256 i = 0; i < quorumNumbersToRemove.length; ++i) {
            _setOperatorWeight(defaultOperator, uint8(quorumNumbersToRemove[i]), 0);
        }
        uint256 expectedQuorumBitmap = BitmapUtils.minus(quorumBitmapBefore, quorumBitmapToRemove);

        registryCoordinator.updateOperators(operatorsToUpdate);
        uint192 quorumBitmapAfter = registryCoordinator.getCurrentQuorumBitmap(defaultOperatorId);
        assertEq(expectedQuorumBitmap, quorumBitmapAfter, "quorum bitmap did not update correctly");
    }

    // @notice tests the `updateOperators` function with a single *un*registered operator as input
    function test_updateOperators_unregisteredOperator() public view {
        address[] memory operatorsToUpdate = new address[](1);
        operatorsToUpdate[0] = defaultOperator;

        // force a staticcall to the `updateOperators` function -- this should *pass* because the call should be a strict no-op!
        (bool success,) = address(registryCoordinator).staticcall(
            abi.encodeWithSignature("updateOperators(address[])", operatorsToUpdate)
        );
        require(success, "staticcall failed!");
    }

    function test_updateOperatorsForQuorum_revert_paused() public {
        cheats.prank(pauser);
        registryCoordinator.pause(2 ** PAUSED_UPDATE_OPERATOR);

        address[][] memory operatorsToUpdate = new address[][](1);
        address[] memory operatorArray = new address[](1);
        operatorArray[0] = defaultOperator;
        operatorsToUpdate[0] = operatorArray;
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        cheats.expectRevert(bytes4(keccak256("CurrentlyPaused()")));
        registryCoordinator.updateOperatorsForQuorum(operatorsToUpdate, quorumNumbers);
    }

    function test_updateOperatorsForQuorum_revert_nonexistentQuorum() public {
        _deployMockEigenLayerAndAVS(10);
        bytes memory quorumNumbersNotCreated = new bytes(1);
        quorumNumbersNotCreated[0] = 0x0B;
        address[][] memory operatorsToUpdate = new address[][](1);

        cheats.prank(defaultOperator);
        cheats.expectRevert(BitmapUtils.BitmapValueTooLarge.selector);
        registryCoordinator.updateOperatorsForQuorum(operatorsToUpdate, quorumNumbersNotCreated);
    }

    function test_updateOperatorsForQuorum_revert_inputLengthMismatch() public {
        address[][] memory operatorsToUpdate = new address[][](2);
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        cheats.expectRevert(bytes4(keccak256("InputLengthMismatch()")));
        registryCoordinator.updateOperatorsForQuorum(operatorsToUpdate, quorumNumbers);
    }

    function test_updateOperatorsForQuorum_revert_incorrectNumberOfOperators() public {
        address[][] memory operatorsToUpdate = new address[][](1);
        address[] memory operatorArray = new address[](1);
        operatorArray[0] = defaultOperator;
        operatorsToUpdate[0] = operatorArray;
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);

        cheats.expectRevert(bytes4(keccak256("QuorumOperatorCountMismatch()")));
        registryCoordinator.updateOperatorsForQuorum(operatorsToUpdate, quorumNumbers);
    }

    function test_updateOperatorsForQuorum_revert_unregisteredOperator() public {
        // register the default operator
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;
        uint32 registrationBlockNumber = 100;
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        _setOperatorWeight(defaultOperator, uint8(quorumNumbers[0]), defaultStake);
        cheats.startPrank(defaultOperator);
        cheats.roll(registrationBlockNumber);
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );

        address[][] memory operatorsToUpdate = new address[][](1);
        address[] memory operatorArray = new address[](1);
        // use an unregistered operator address as input
        operatorArray[0] = _incrementAddress(defaultOperator, 1);
        operatorsToUpdate[0] = operatorArray;

        cheats.expectRevert(bytes4(keccak256("NotRegisteredForQuorum()")));
        registryCoordinator.updateOperatorsForQuorum(operatorsToUpdate, quorumNumbers);
    }

    // note: there is not an explicit check for duplicates, as checking for explicit ordering covers this
    function test_updateOperatorsForQuorum_revert_duplicateOperator(
        uint256 pseudoRandomNumber
    ) public {
        // register 2 operators
        uint32 numOperators = 2;
        uint32 registrationBlockNumber = 200;
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        uint256 quorumBitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers);
        cheats.roll(registrationBlockNumber);
        for (uint256 i = 0; i < numOperators; i++) {
            BN254.G1Point memory pubKey =
                BN254.hashToG1(keccak256(abi.encodePacked(pseudoRandomNumber, i)));
            address operator = _incrementAddress(defaultOperator, i);

            _registerOperatorWithCoordinator(operator, quorumBitmap, pubKey);
        }

        address[][] memory operatorsToUpdate = new address[][](1);
        address[] memory operatorArray = new address[](2);
        // use the same operator address twice as input
        operatorArray[0] = defaultOperator;
        operatorArray[1] = defaultOperator;
        operatorsToUpdate[0] = operatorArray;

        // note: there is not an explicit check for duplicates, as checking for explicit ordering covers this
        cheats.expectRevert(bytes4(keccak256("NotSorted()")));
        registryCoordinator.updateOperatorsForQuorum(operatorsToUpdate, quorumNumbers);
    }

    function test_updateOperatorsForQuorum_revert_incorrectListOrder(
        uint256 pseudoRandomNumber
    ) public {
        // register 2 operators
        uint32 numOperators = 2;
        uint32 registrationBlockNumber = 200;
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        uint256 quorumBitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers);
        cheats.roll(registrationBlockNumber);
        for (uint256 i = 0; i < numOperators; i++) {
            BN254.G1Point memory pubKey =
                BN254.hashToG1(keccak256(abi.encodePacked(pseudoRandomNumber, i)));
            address operator = _incrementAddress(defaultOperator, i);

            _registerOperatorWithCoordinator(operator, quorumBitmap, pubKey);
        }

        address[][] memory operatorsToUpdate = new address[][](1);
        address[] memory operatorArray = new address[](2);
        // order the operator addresses in descending order, instead of ascending order
        operatorArray[0] = _incrementAddress(defaultOperator, 1);
        operatorArray[1] = defaultOperator;
        operatorsToUpdate[0] = operatorArray;

        cheats.expectRevert(bytes4(keccak256("NotSorted()")));
        registryCoordinator.updateOperatorsForQuorum(operatorsToUpdate, quorumNumbers);
    }

    function test_updateOperatorsForQuorum_singleOperator() public {
        // register the default operator
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory emptySig;
        uint32 registrationBlockNumber = 100;
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        _setOperatorWeight(defaultOperator, uint8(quorumNumbers[0]), defaultStake);
        cheats.startPrank(defaultOperator);
        cheats.roll(registrationBlockNumber);
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig
        );

        address[][] memory operatorsToUpdate = new address[][](1);
        address[] memory operatorArray = new address[](1);
        operatorArray[0] = defaultOperator;
        operatorsToUpdate[0] = operatorArray;

        uint256 quorumUpdateBlockNumberBefore =
            registryCoordinator.quorumUpdateBlockNumber(defaultQuorumNumber);
        require(quorumUpdateBlockNumberBefore != block.number, "bad test setup!");

        cheats.expectEmit(true, true, true, true, address(registryCoordinator));
        emit QuorumBlockNumberUpdated(defaultQuorumNumber, block.number);
        registryCoordinator.updateOperatorsForQuorum(operatorsToUpdate, quorumNumbers);

        uint256 quorumUpdateBlockNumberAfter =
            registryCoordinator.quorumUpdateBlockNumber(defaultQuorumNumber);
        assertEq(
            quorumUpdateBlockNumberAfter, block.number, "quorumUpdateBlockNumber not set correctly"
        );
    }

    function test_updateOperatorsForQuorum_twoOperators(
        uint256 pseudoRandomNumber
    ) public {
        // register 2 operators
        uint32 numOperators = 2;
        uint32 registrationBlockNumber = 200;
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        uint256 quorumBitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers);
        cheats.roll(registrationBlockNumber);
        for (uint256 i = 0; i < numOperators; i++) {
            BN254.G1Point memory pubKey =
                BN254.hashToG1(keccak256(abi.encodePacked(pseudoRandomNumber, i)));
            address operator = _incrementAddress(defaultOperator, i);

            _registerOperatorWithCoordinator(operator, quorumBitmap, pubKey);
        }

        address[][] memory operatorsToUpdate = new address[][](1);
        address[] memory operatorArray = new address[](2);
        // order the operator addresses in descending order, instead of ascending order
        operatorArray[0] = defaultOperator;
        operatorArray[1] = _incrementAddress(defaultOperator, 1);
        operatorsToUpdate[0] = operatorArray;

        uint256 quorumUpdateBlockNumberBefore =
            registryCoordinator.quorumUpdateBlockNumber(defaultQuorumNumber);
        require(quorumUpdateBlockNumberBefore != block.number, "bad test setup!");

        cheats.expectEmit(true, true, true, true, address(registryCoordinator));
        emit QuorumBlockNumberUpdated(defaultQuorumNumber, block.number);
        registryCoordinator.updateOperatorsForQuorum(operatorsToUpdate, quorumNumbers);

        uint256 quorumUpdateBlockNumberAfter =
            registryCoordinator.quorumUpdateBlockNumber(defaultQuorumNumber);
        assertEq(
            quorumUpdateBlockNumberAfter, block.number, "quorumUpdateBlockNumber not set correctly"
        );
    }

    // @notice tests that the internal `_updateOperatorBitmap` function works as expected, for fuzzed inputs
    function testFuzz_updateOperatorBitmapInternal_noPreviousEntries(
        uint192 newBitmap
    ) public {
        registryCoordinator._updateOperatorBitmapExternal(defaultOperatorId, newBitmap);
        assertEq(
            keccak256(
                abi.encode(registryCoordinator.getQuorumBitmapUpdateByIndex(defaultOperatorId, 0))
            ),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                        quorumBitmap: uint192(newBitmap),
                        updateBlockNumber: uint32(block.number),
                        nextUpdateBlockNumber: 0
                    })
                )
            )
        );
    }

    // @notice tests that the internal `_updateOperatorBitmap` function works as expected, for fuzzed inputs
    function testFuzz_updateOperatorBitmapInternal_previousEntryInCurrentBlock(
        uint192 newBitmap
    ) public {
        uint192 pastBitmap = 1;
        testFuzz_updateOperatorBitmapInternal_noPreviousEntries(pastBitmap);

        registryCoordinator._updateOperatorBitmapExternal(defaultOperatorId, newBitmap);
        assertEq(
            keccak256(
                abi.encode(registryCoordinator.getQuorumBitmapUpdateByIndex(defaultOperatorId, 0))
            ),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                        quorumBitmap: uint192(newBitmap),
                        updateBlockNumber: uint32(block.number),
                        nextUpdateBlockNumber: 0
                    })
                )
            )
        );
    }

    // @notice tests that the internal `_updateOperatorBitmap` function works as expected, for fuzzed inputs
    function testFuzz_updateOperatorBitmapInternal_previousEntryInPastBlock(
        uint192 newBitmap
    ) public {
        uint192 pastBitmap = 1;
        testFuzz_updateOperatorBitmapInternal_noPreviousEntries(pastBitmap);

        // advance the block number
        uint256 previousBlockNumber = block.number;
        cheats.roll(previousBlockNumber + 1);

        registryCoordinator._updateOperatorBitmapExternal(defaultOperatorId, newBitmap);
        assertEq(
            keccak256(
                abi.encode(registryCoordinator.getQuorumBitmapUpdateByIndex(defaultOperatorId, 0))
            ),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                        quorumBitmap: uint192(pastBitmap),
                        updateBlockNumber: uint32(previousBlockNumber),
                        nextUpdateBlockNumber: uint32(block.number)
                    })
                )
            )
        );
        assertEq(
            keccak256(
                abi.encode(registryCoordinator.getQuorumBitmapUpdateByIndex(defaultOperatorId, 1))
            ),
            keccak256(
                abi.encode(
                    ISlashingRegistryCoordinatorTypes.QuorumBitmapUpdate({
                        quorumBitmap: uint192(newBitmap),
                        updateBlockNumber: uint32(block.number),
                        nextUpdateBlockNumber: 0
                    })
                )
            )
        );
    }
}

contract RegistryCoordinatorUnitTests_BeforeMigration is RegistryCoordinatorUnitTests {
    function test_registerALMHook_Reverts() public {
        cheats.prank(address(registryCoordinator.allocationManager()));
        cheats.expectRevert();
        /// TODO:
        registryCoordinator.registerOperator(
            defaultOperator,
            address(0),
            new uint32[](0),
            abi.encode(defaultSocket, pubkeyRegistrationParams)
        );
    }

    function test_deregisterALMHook_Reverts() public {
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 0;
        cheats.prank(address(registryCoordinator.allocationManager()));
        cheats.expectRevert();
        /// TODO:
        registryCoordinator.deregisterOperator(defaultOperator, address(0), operatorSetIds);
    }

    function test_CreateTotalDelegatedStakeQuorum() public {
        _deployMockEigenLayerAndAVS(0);
        // Set up test params
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 0,
            kickBIPsOfTotalStake: 0
        });
        uint96 minimumStake = 100;
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] = IStakeRegistryTypes.StrategyParams({
            strategy: IStrategy(address(0x1)),
            multiplier: 1000
        });

        // Get initial quorum count
        uint8 initialQuorumCount = registryCoordinator.quorumCount();

        // Create quorum with total delegated stake type
        cheats.prank(registryCoordinatorOwner);
        registryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams, minimumStake, strategyParams
        );

        // Verify quorum was created
        assertEq(registryCoordinator.quorumCount(), initialQuorumCount + 1);

        // Verify quorum params were set correctly
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory storedParams =
            registryCoordinator.getOperatorSetParams(initialQuorumCount);
        assertEq(storedParams.maxOperatorCount, operatorSetParams.maxOperatorCount);
        assertEq(storedParams.kickBIPsOfOperatorStake, operatorSetParams.kickBIPsOfOperatorStake);
        assertEq(storedParams.kickBIPsOfTotalStake, operatorSetParams.kickBIPsOfTotalStake);
    }

    function test_CreateSlashableStakeQuorum_Reverts() public {
        _deployMockEigenLayerAndAVS(0);
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 0,
            kickBIPsOfTotalStake: 0
        });
        uint96 minimumStake = 100;
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] = IStakeRegistryTypes.StrategyParams({
            strategy: IStrategy(address(0x1)),
            multiplier: 1000
        });
        uint32 lookAheadPeriod = 100;

        assertEq(registryCoordinator.quorumCount(), 0, "No quorums should exist before");

        // Attempt to create quorum with slashable stake type before enabling operator sets
        cheats.prank(registryCoordinatorOwner);
        registryCoordinator.createSlashableStakeQuorum(
            operatorSetParams, minimumStake, strategyParams, lookAheadPeriod
        );
        assertEq(registryCoordinator.quorumCount(), 1, "New quorum 0 should be created");
        assertFalse(registryCoordinator.isM2Quorum(0), "Quorum created should not be an M2 quorum");
    }
}

contract RegistryCoordinatorUnitTests_AfterMigration is RegistryCoordinatorUnitTests {
    function test_M2_Deregister() public {
        _deployMockEigenLayerAndAVS(2);

        Operator memory operatorToRegister = OperatorWalletLib.createOperator("4");

        /// NOTE: resolves stack too deep
        {
            // Set operator shares for quorum 0
            (IStrategy strategy,) = stakeRegistry.strategyParams(0, 0);
            delegationMock.setOperatorShares(operatorToRegister.key.addr, strategy, 1 ether);
        }
        bytes32 salt = bytes32(uint256(1));
        uint256 expiry = block.timestamp + 1 days;
        bytes32 digestHash = avsDirectory.calculateOperatorAVSRegistrationDigestHash(
            operatorToRegister.key.addr, address(registryCoordinator), salt, expiry
        );
        bytes memory signature = OperatorKeyOperationsLib.sign(operatorToRegister.key, digestHash);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature =
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry({
            signature: signature,
            salt: salt,
            expiry: expiry
        });

        bytes32 messageHash =
            registryCoordinator.calculatePubkeyRegistrationMessageHash(operatorToRegister.key.addr);
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory operatorRegisterApkParams =
        IBLSApkRegistryTypes.PubkeyRegistrationParams({
            pubkeyRegistrationSignature: SigningKeyOperationsLib.sign(
                operatorToRegister.signingKey, messageHash
            ),
            pubkeyG1: operatorToRegister.signingKey.publicKeyG1,
            pubkeyG2: operatorToRegister.signingKey.publicKeyG2
        });

        string memory socket = "socket";

        // register for quorum 0
        vm.prank(operatorToRegister.key.addr);
        registryCoordinator.registerOperator(
            new bytes(1), // Convert 0 to bytes1 first
            socket,
            operatorRegisterApkParams,
            operatorSignature
        );

        /// Deregistration for m2 should for the first two operator sets
        vm.prank(operatorToRegister.key.addr);
        registryCoordinator.deregisterOperator(new bytes(1));

        // Verify operator was deregistered by checking their bitmap is empty
        bytes32 operatorId = registryCoordinator.getOperatorId(operatorToRegister.key.addr);
        uint192 bitmap = registryCoordinator.getCurrentQuorumBitmap(operatorId);
        assertEq(bitmap, 0, "Operator bitmap should be empty after deregistration");

        // Verify operator status is NEVER_REGISTERED
        ISlashingRegistryCoordinatorTypes.OperatorStatus status =
            registryCoordinator.getOperatorStatus(operatorToRegister.key.addr);
        assertEq(
            uint8(status),
            uint8(ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED),
            "Operator status should be NEVER_REGISTERED"
        );
    }

    function test_M2_Register_Reverts() public {
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(uint8(0));
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory params;
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature;

        cheats.expectRevert();
        registryCoordinator.registerOperator(
            quorumNumbers, defaultSocket, params, operatorSignature
        );
    }

    function test_createSlashableStakeQuorum() public {
        // Deploy with 0 quorums
        _deployMockEigenLayerAndAVS(0);

        // Create quorum params
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 1000,
            kickBIPsOfTotalStake: 100
        });
        uint96 minimumStake = 100;
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] =
            IStakeRegistryTypes.StrategyParams({strategy: IStrategy(address(1)), multiplier: 1});
        uint32 lookAheadPeriod = 100;

        // Create slashable stake quorum
        cheats.prank(registryCoordinatorOwner);
        registryCoordinator.createSlashableStakeQuorum(
            operatorSetParams, minimumStake, strategyParams, lookAheadPeriod
        );
    }

    function test_createTotalDelegatedStakeQuorum() public {
        // Deploy with 0 quorums
        _deployMockEigenLayerAndAVS(0);

        // Create quorum params
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 1000,
            kickBIPsOfTotalStake: 100
        });
        uint96 minimumStake = 100;
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] =
            IStakeRegistryTypes.StrategyParams({strategy: IStrategy(address(1)), multiplier: 10000});

        // Create total delegated stake quorum
        cheats.prank(registryCoordinatorOwner);
        registryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams, minimumStake, strategyParams
        );
    }

    function test_registerHook() public {
        vm.skip(true);

        _deployMockEigenLayerAndAVS(0);

        // Create quorum params
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 1000,
            kickBIPsOfTotalStake: 100
        });

        uint96 minimumStake = 100;
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] =
            IStakeRegistryTypes.StrategyParams({strategy: IStrategy(address(1)), multiplier: 10000});

        // Create total delegated stake quorum
        cheats.prank(registryCoordinatorOwner);
        registryCoordinator.createTotalDelegatedStakeQuorum(operatorSetParams, 0, strategyParams);

        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 0;

        string memory socket = "socket";
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory params;
        // TODO:
        // params = IBLSApkRegistryTypes.PubkeyRegistrationParams({
        //     pubkeyG1: defaultPubKey,
        //     pubkeyG2: defaultPubKeyG2,
        //     pubkeySignature: defaultPubKeySignature
        // });

        // Encode with RegistrationType.NORMAL
        bytes memory data =
            abi.encode(ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL, socket, params);

        cheats.prank(address(registryCoordinator.allocationManager()));
        /// TODO:
        registryCoordinator.registerOperator(
            defaultOperator, address(serviceManager), operatorSetIds, data
        );
    }

    function test_registerHook_WithChurn() public {
        vm.skip(true);
        _deployMockEigenLayerAndAVS(0);

        // Create quorum params
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 1000,
            kickBIPsOfTotalStake: 100
        });

        uint96 minimumStake = 100;
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] =
            IStakeRegistryTypes.StrategyParams({strategy: IStrategy(address(1)), multiplier: 10000});

        // Create total delegated stake quorum
        cheats.prank(registryCoordinatorOwner);
        registryCoordinator.createTotalDelegatedStakeQuorum(operatorSetParams, 0, strategyParams);

        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 0;

        string memory socket = "socket";
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory params;
        // TODO:
        // params = IBLSApkRegistryTypes.PubkeyRegistrationParams({
        //     pubkeyG1: defaultPubKey,
        //     pubkeyG2: defaultPubKeyG2,
        //     pubkeySignature: defaultPubKeySignature
        // });

        ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory operatorKickParams =
            new ISlashingRegistryCoordinatorTypes.OperatorKickParam[](1);
        operatorKickParams[0] = ISlashingRegistryCoordinatorTypes.OperatorKickParam({
            operator: address(0x1),
            quorumNumber: 0
        });

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory churnApproverSignature;

        // Encode with RegistrationType.CHURN
        bytes memory data = abi.encode(
            ISlashingRegistryCoordinatorTypes.RegistrationType.CHURN,
            socket,
            params,
            operatorKickParams,
            churnApproverSignature
        );

        // Prank as allocation manager and call register hook
        cheats.prank(address(registryCoordinator.allocationManager()));
        registryCoordinator.registerOperator(
            defaultOperator, address(serviceManager), operatorSetIds, data
        );
    }

    function test_updateStakesForQuorum() public {
        vm.skip(true);
        _deployMockEigenLayerAndAVS(0);

        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: defaultMaxOperatorCount,
            kickBIPsOfOperatorStake: defaultKickBIPsOfOperatorStake,
            kickBIPsOfTotalStake: defaultKickBIPsOfTotalStake
        });

        uint96 minimumStake = 100;
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] =
            IStakeRegistryTypes.StrategyParams({strategy: IStrategy(address(1)), multiplier: 10000});

        cheats.prank(registryCoordinatorOwner);
        registryCoordinator.createTotalDelegatedStakeQuorum(
            operatorSetParams, minimumStake, strategyParams
        );

        uint256 quorumBitmap = 0;

        // TODO: register actually and update stakes
    }

    function test_deregisterHook() public {
        _deployMockEigenLayerAndAVS(0);

        // Create quorum params
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 1000,
            kickBIPsOfTotalStake: 100
        });

        uint96 minimumStake = 100;
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] =
            IStakeRegistryTypes.StrategyParams({strategy: IStrategy(address(1)), multiplier: 10000});

        // Create total delegated stake quorum
        cheats.prank(registryCoordinatorOwner);
        registryCoordinator.createTotalDelegatedStakeQuorum(operatorSetParams, 0, strategyParams);

        // Prank as allocation manager and call register hook
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 0;

        string memory socket = "socket";
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory params;
        // TODO:
        // params = IBLSApkRegistryTypes.PubkeyRegistrationParams({
        //     pubkeyG1: defaultPubKey,
        //     pubkeyG2: defaultPubKeyG2,
        //     pubkeySignature: defaultPubKeySignature
        // });

        // Encode with RegistrationType.NORMAL
        bytes memory data =
            abi.encode(ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL, socket, params);

        cheats.startPrank(address(registryCoordinator.allocationManager()));
        registryCoordinator.registerOperator(
            defaultOperator, address(serviceManager), operatorSetIds, data
        );

        cheats.stopPrank();
    }

    function test_registerHook_Reverts_WhenNotALM() public {
        _deployMockEigenLayerAndAVS(0);

        // Create quorum params
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 1000,
            kickBIPsOfTotalStake: 100
        });

        uint96 minimumStake = 100;
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] =
            IStakeRegistryTypes.StrategyParams({strategy: IStrategy(address(1)), multiplier: 10000});

        // Create total delegated stake quorum
        cheats.prank(registryCoordinatorOwner);
        registryCoordinator.createTotalDelegatedStakeQuorum(operatorSetParams, 0, strategyParams);

        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 0;

        string memory socket = "socket";
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory params;
        // TODO:
        // params = IBLSApkRegistryTypes.PubkeyRegistrationParams({
        //     pubkeyG1: defaultPubKey,
        //     pubkeyG2: defaultPubKeyG2,
        //     pubkeySignature: defaultPubKeySignature
        // });

        // Encode with RegistrationType.NORMAL
        bytes memory data =
            abi.encode(ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL, socket, params);

        vm.expectRevert();
        registryCoordinator.registerOperator(
            defaultOperator, address(serviceManager), operatorSetIds, data
        );
    }

    function test_deregisterHook_Reverts_WhenNotALM() public {
        _deployMockEigenLayerAndAVS(0);

        // Create quorum params
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 1000,
            kickBIPsOfTotalStake: 100
        });

        uint96 minimumStake = 100;
        IStakeRegistryTypes.StrategyParams[] memory strategyParams =
            new IStakeRegistryTypes.StrategyParams[](1);
        strategyParams[0] =
            IStakeRegistryTypes.StrategyParams({strategy: IStrategy(address(1)), multiplier: 10000});

        // Create total delegated stake quorum
        cheats.prank(registryCoordinatorOwner);
        registryCoordinator.createTotalDelegatedStakeQuorum(operatorSetParams, 0, strategyParams);

        // operator sets should be enabled after creating a new quorum
        assertTrue(registryCoordinator.operatorSetsEnabled(), "operatorSetsEnabled should be true");

        // Prank as allocation manager and call register hook
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 0;

        string memory socket = "socket";
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory params;
        // TODO:
        // params = IBLSApkRegistryTypes.PubkeyRegistrationParams({
        //     pubkeyG1: defaultPubKey,
        //     pubkeyG2: defaultPubKeyG2,
        //     pubkeySignature: defaultPubKeySignature
        // });

        bytes memory data =
            abi.encode(ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL, socket, params);

        cheats.prank(address(registryCoordinator.allocationManager()));
        registryCoordinator.registerOperator(
            defaultOperator, address(serviceManager), operatorSetIds, data
        );

        cheats.expectRevert();
        registryCoordinator.deregisterOperator(
            defaultOperator, address(serviceManager), operatorSetIds
        );
    }

    function test_DeregisterHook_Reverts_WhenM2Quorum() public {
        vm.skip(true);
    }

    function test_registerHook_Reverts_WhenM2Quorum() public {
        vm.skip(true);
    }
}

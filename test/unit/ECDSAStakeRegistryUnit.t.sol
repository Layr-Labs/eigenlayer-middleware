// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Test} from "forge-std/Test.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ECDSAStakeRegistry} from "../../src/unaudited/ECDSAStakeRegistry.sol";
import {ECDSAStakeRegistryEventsAndErrors, Quorum, StrategyParams} from "../../src/interfaces/IECDSAStakeRegistryEventsAndErrors.sol";

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

contract MockServiceManager {
    // solhint-disable-next-line
    function deregisterOperatorFromAVS(address) external {}

    function registerOperatorToAVS(
        address,
        ISignatureUtils.SignatureWithSaltAndExpiry memory // solhint-disable-next-line
    ) external {}
}

contract MockDelegationManager {
    function operatorShares(address, address) external pure returns (uint256) {
        return 1000; // Return a dummy value for simplicity
    }
}

contract ECDSAStakeRegistryTest is Test, ECDSAStakeRegistryEventsAndErrors {
    ECDSAStakeRegistry public registry;
    MockDelegationManager public mockDelegationManager;
    MockServiceManager public mockServiceManager;
    address internal operator1;
    address internal operator2;
    uint256 internal operator1Pk;
    uint256 internal operator2Pk;
    bytes internal signature1;
    bytes internal signature2;
    address[] internal signers;
    bytes[] internal signatures;
    bytes32 internal msgHash;

    function setUp() public virtual {
        (operator1, operator1Pk) = makeAddrAndKey("Signer 1");
        (operator2, operator2Pk) = makeAddrAndKey("Signer 2");
        mockDelegationManager = new MockDelegationManager();
        mockServiceManager = new MockServiceManager();
        registry = new ECDSAStakeRegistry(IDelegationManager(address(mockDelegationManager)));

        IStrategy mockStrategy = IStrategy(address(0x1234));
        Quorum memory quorum = Quorum({strategies: new StrategyParams[](1)});
        quorum.strategies[0] = StrategyParams({strategy: mockStrategy, multiplier: 10000});
        registry.initialize(address(mockServiceManager), 100, quorum);

        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature;
        registry.registerOperatorWithSignature(operator1, operatorSignature);
        registry.registerOperatorWithSignature(operator2, operatorSignature);
    }
}

contract UpdateQuorumConfig is ECDSAStakeRegistryTest {
    function test_Update() public {
        IStrategy mockStrategy = IStrategy(address(420));

        Quorum memory oldQuorum = registry.stakeQuorum();
        Quorum memory newQuorum = Quorum({strategies: new StrategyParams[](1)});
        newQuorum.strategies[0] = StrategyParams({strategy: mockStrategy, multiplier: 10000});

        vm.expectEmit(true, true, false, true);
        emit QuorumUpdated(oldQuorum, newQuorum);

        registry.updateQuorumConfig(newQuorum);
    }

    function test_RevertsWhen_InvalidQuorum() public {
        Quorum memory invalidQuorum = Quorum({strategies: new StrategyParams[](1)});
        invalidQuorum.strategies[0] = StrategyParams({
            /// TODO: Make mock strategy
            strategy: IStrategy(address(420)),
            multiplier: 5000 // This should cause the update to revert as it's not the total required
        });

        vm.expectRevert(ECDSAStakeRegistryEventsAndErrors.InvalidQuorum.selector);
        registry.updateQuorumConfig(invalidQuorum);
    }

    function test_RevertsWhen_NotOwner() public {
        Quorum memory validQuorum = Quorum({strategies: new StrategyParams[](1)});
        validQuorum.strategies[0] = StrategyParams({
            strategy: IStrategy(address(420)),
            multiplier: 10000
        });

        address nonOwner = address(0x123);
        vm.prank(nonOwner);

        vm.expectRevert("Ownable: caller is not the owner");
        registry.updateQuorumConfig(validQuorum);
    }

    function test_RevertsWhen_SameQuorum() public {
        Quorum memory quorum = registry.stakeQuorum();

        /// Showing this doesnt revert
        registry.updateQuorumConfig(quorum);
    }

    function test_RevertSWhen_Duplicate() public {
        Quorum memory validQuorum = Quorum({strategies: new StrategyParams[](2)});
        validQuorum.strategies[0] = StrategyParams({
            strategy: IStrategy(address(420)),
            multiplier: 5_000
        });

        validQuorum.strategies[1] = StrategyParams({
            strategy: IStrategy(address(420)),
            multiplier: 5_000
        });
        vm.expectRevert(ECDSAStakeRegistryEventsAndErrors.NotSorted.selector);
        registry.updateQuorumConfig(validQuorum);
    }

    function test_RevertSWhen_NotSorted() public {
        Quorum memory validQuorum = Quorum({strategies: new StrategyParams[](2)});
        validQuorum.strategies[0] = StrategyParams({
            strategy: IStrategy(address(420)),
            multiplier: 5_000
        });

        validQuorum.strategies[1] = StrategyParams({
            strategy: IStrategy(address(419)),
            multiplier: 5_000
        });
        vm.expectRevert(ECDSAStakeRegistryEventsAndErrors.NotSorted.selector);
        registry.updateQuorumConfig(validQuorum);
    }

    function test_RevertSWhen_OverMultiplierTotal() public {
        Quorum memory validQuorum = Quorum({strategies: new StrategyParams[](1)});
        validQuorum.strategies[0] = StrategyParams({
            strategy: IStrategy(address(420)),
            multiplier: 10001
        });

        vm.expectRevert(ECDSAStakeRegistryEventsAndErrors.InvalidQuorum.selector);
        registry.updateQuorumConfig(validQuorum);
    }
}

contract RegisterOperatorWithSignature is ECDSAStakeRegistryTest {
    function testRegisterOperatorWithSignature() public {
        address operator3 = address(0x125);
        ISignatureUtils.SignatureWithSaltAndExpiry memory signature;
        registry.registerOperatorWithSignature(operator3, signature);
        assertTrue(registry.operatorRegistered(operator3));
        assertEq(registry.getLastCheckpointOperatorWeight(operator3), 1000);
    }

    function test_RevertsWhen_AlreadyRegistered() public {
        assertEq(registry.getLastCheckpointOperatorWeight(operator1), 1000);
        assertEq(registry.getLastCheckpointTotalWeight(), 2000);

        ISignatureUtils.SignatureWithSaltAndExpiry memory signature;
        vm.expectRevert(ECDSAStakeRegistryEventsAndErrors.OperatorAlreadyRegistered.selector);
        registry.registerOperatorWithSignature(operator1, signature);
    }

    function test_RevertsWhen_SignatureIsInvalid() public {
        bytes memory signatureData;
        vm.mockCall(
            address(mockServiceManager),
            abi.encodeWithSelector(
                MockServiceManager.registerOperatorToAVS.selector,
                operator1,
                ISignatureUtils.SignatureWithSaltAndExpiry({
                    signature: signatureData,
                    salt: bytes32(uint256(0x120)),
                    expiry: 10
                })
            ),
            abi.encode(50)
        );
    }

    function test_RevertsWhen_InsufficientStake() public {
        /// TODO: Missing implementation for this check
        vm.skip(true);
    }
}

contract DeregisterOperator is ECDSAStakeRegistryTest {
    function testDeregisterOperatorAsOwner() public {
        assertEq(registry.getLastCheckpointOperatorWeight(operator1), 1000);
        assertEq(registry.getLastCheckpointTotalWeight(), 2000);

        vm.prank(operator1);
        registry.deregisterOperator();

        assertEq(registry.getLastCheckpointOperatorWeight(operator1), 0);
        assertEq(registry.getLastCheckpointTotalWeight(), 1000);
    }

    function testDeregisterOperatorAsNonOwner() public {
        address notOperator = address(0x2);
        vm.prank(notOperator);
        vm.expectRevert(ECDSAStakeRegistryEventsAndErrors.OperatorNotRegistered.selector);
        registry.deregisterOperator();
    }
}

contract UpdateOperators is ECDSAStakeRegistryTest {
    function test_When_Empty() public {
        address[] memory operators = new address[](0);
        registry.updateOperators(operators);
    }

    function test_When_SingleOperator() public {
        address[] memory operators = new address[](1);
        operators[0] = operator1;

        registry.updateOperators(operators);
        uint256 updatedWeight = registry.getLastCheckpointOperatorWeight(operator1);
        assertEq(updatedWeight, 1000);
    }

    function test_When_SameBlock() public {
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        assertEq(registry.getLastCheckpointOperatorWeight(operator1), 1000);
        assertEq(registry.getLastCheckpointTotalWeight(), 2000);

        registry.updateOperators(operators);

        assertEq(registry.getLastCheckpointOperatorWeight(operator1), 1000);
        assertEq(registry.getLastCheckpointTotalWeight(), 2000);

        registry.updateOperators(operators);

        assertEq(registry.getLastCheckpointOperatorWeight(operator1), 1000);
        assertEq(registry.getLastCheckpointTotalWeight(), 2000);
        /// TODO: Need to confirm we always pull the last if the block numbers are the same for checkpoints
        /// in the getAtBlock function or if we need to prevent this behavior
    }

    function test_When_MultipleOperators() public {
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        registry.updateOperators(operators);

        uint256 updatedWeight1 = registry.getLastCheckpointOperatorWeight(operator1);
        uint256 updatedWeight2 = registry.getLastCheckpointOperatorWeight(operator2);
        assertEq(updatedWeight1, 1000);
        assertEq(updatedWeight2, 1000);
    }

    function test_When_Duplicates() public {
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator1;

        registry.updateOperators(operators);

        uint256 updatedWeight = registry.getLastCheckpointOperatorWeight(operator1);
        assertEq(updatedWeight, 1000);
    }

    function test_When_MultipleStrategies() public {
        IStrategy mockStrategy = IStrategy(address(420));
        IStrategy mockStrategy2 = IStrategy(address(421));

        Quorum memory quorum = Quorum({strategies: new StrategyParams[](2)});
        quorum.strategies[0] = StrategyParams({strategy: mockStrategy, multiplier: 5_000});
        quorum.strategies[1] = StrategyParams({strategy: mockStrategy2, multiplier: 5_000});

        registry.updateQuorumConfig(quorum);
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        vm.mockCall(
            address(mockDelegationManager),
            abi.encodeWithSelector(
                MockDelegationManager.operatorShares.selector,
                operator1,
                address(mockStrategy2)
            ),
            abi.encode(50)
        );

        registry.updateOperators(operators);

        uint256 updatedWeight1 = registry.getLastCheckpointOperatorWeight(operator1);
        uint256 updatedWeight2 = registry.getLastCheckpointOperatorWeight(operator2);
        assertEq(updatedWeight1, 525);
        assertEq(updatedWeight2, 1000);
        vm.roll(block.number + 1);
    }
}

contract UpdateMinimumWeight is ECDSAStakeRegistryTest {
    function test_UpdatesMinimumWeight() public {
        uint256 initialMinimumWeight = registry.minimumWeight();
        uint256 newMinimumWeight = 5000;

        assertEq(initialMinimumWeight, 0); // Assuming initial state is 0

        registry.updateMinimumWeight(newMinimumWeight);

        uint256 updatedMinimumWeight = registry.minimumWeight();
        assertEq(updatedMinimumWeight, newMinimumWeight);
    }

    function test_RevertsWhen_NotOwner() public {
        uint256 newMinimumWeight = 5000;
        vm.prank(address(0xBEEF)); // An arbitrary non-owner address
        vm.expectRevert("Ownable: caller is not the owner");
        registry.updateMinimumWeight(newMinimumWeight);
    }

    function test_When_SameWeight() public {
        uint256 initialMinimumWeight = 5000;
        registry.updateMinimumWeight(initialMinimumWeight);

        uint256 updatedMinimumWeight = registry.minimumWeight();
        assertEq(updatedMinimumWeight, initialMinimumWeight);
    }

    function test_When_Weight0() public {
        uint256 initialMinimumWeight = 5000;
        registry.updateMinimumWeight(initialMinimumWeight);

        uint256 newMinimumWeight = 0;

        registry.updateMinimumWeight(newMinimumWeight);

        uint256 updatedMinimumWeight = registry.minimumWeight();
        assertEq(updatedMinimumWeight, newMinimumWeight);
    }
}

contract UpdateThresholdStake is ECDSAStakeRegistryTest {
    function testUpdateThresholdStake() public {
        uint256 thresholdWeight = 10000000000;
        vm.prank(registry.owner());
        registry.updateStakeThreshold(thresholdWeight);
    }

    function test_RevertsWhen_NotOwner() public {
        uint256 thresholdWeight = 10000000000;
        address notOwner = address(0x123);
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        registry.updateStakeThreshold(thresholdWeight);
    }
}

contract CheckSignatures is ECDSAStakeRegistryTest {
    function testCheckSignatures() public {
        msgHash = keccak256("data");
        signers = new address[](2);
        (signers[0], signers[1]) = (operator1, operator2);
        signatures = new bytes[](2);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator1Pk, msgHash);
        signatures[0] = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(operator2Pk, msgHash);
        signatures[1] = abi.encodePacked(r, s, v);

        registry.isValidSignature(msgHash, abi.encode(signers, signatures, type(uint32).max));
    }

    function testCheckSignaturesLengthMismatch() public {
        msgHash = keccak256("data");
        signers = new address[](2);
        (signers[0], signers[1]) = (operator1, operator2);
        signatures = new bytes[](1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator1Pk, msgHash);
        signatures[0] = abi.encode(v, r, s);

        vm.expectRevert(ECDSAStakeRegistryEventsAndErrors.LengthMismatch.selector);
        registry.isValidSignature(msgHash, abi.encode(signers, signatures, type(uint32).max));
    }

    function testCheckSignaturesInvalidLength() public {
        bytes32 dataHash = keccak256("data");
        address[] memory signers = new address[](0);
        bytes[] memory signatures = new bytes[](0);

        vm.expectRevert(ECDSAStakeRegistryEventsAndErrors.InvalidLength.selector);
        registry.isValidSignature(dataHash, abi.encode(signers, signatures, type(uint32).max));
    }

    function testCheckSignaturesNotSorted() public {
        msgHash = keccak256("data");
        signers = new address[](2);
        (signers[1], signers[0]) = (operator1, operator2);
        registry.updateOperators(signers);
        signatures = new bytes[](2);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator1Pk, msgHash);
        signatures[1] = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(operator2Pk, msgHash);
        signatures[0] = abi.encodePacked(r, s, v);

        vm.expectRevert(ECDSAStakeRegistryEventsAndErrors.NotSorted.selector);
        registry.isValidSignature(msgHash, abi.encode(signers, signatures, type(uint32).max));
    }

    function testCheckSignaturesInvalidSignature() public {
        bytes32 dataHash = keccak256("data");
        address[] memory signers = new address[](1);
        signers[0] = operator1;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = "invalid-signature";

        vm.expectRevert(ECDSAStakeRegistryEventsAndErrors.InvalidSignature.selector);
        registry.isValidSignature(dataHash, abi.encode(signers, signatures, type(uint32).max));
    }

    function testCheckSignaturesInsufficientSignedStake() public {
        msgHash = keccak256("data");
        signers = new address[](2);
        (signers[0], signers[1]) = (operator1, operator2);
        registry.updateOperators(signers);
        signatures = new bytes[](2);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator1Pk, msgHash);
        signatures[0] = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(operator2Pk, msgHash);
        signatures[1] = abi.encodePacked(r, s, v);

        uint256 thresholdWeight = 10000000000;
        vm.prank(registry.owner());
        registry.updateStakeThreshold(thresholdWeight);
        vm.roll(block.number + 1);

        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(
                ECDSAStakeRegistry.getLastCheckpointOperatorWeight.selector,
                operator1
            ),
            abi.encode(50)
        );

        vm.expectRevert(ECDSAStakeRegistryEventsAndErrors.InsufficientSignedStake.selector);
        registry.isValidSignature(msgHash, abi.encode(signers, signatures, type(uint32).max));
    }

    function testCheckSignaturesAtBlockLengthMismatch() public {
        bytes32 dataHash = keccak256("data");
        uint32 referenceBlock = 123;
        address[] memory signers = new address[](2);
        signers[0] = operator1;
        signers[1] = operator2;
        bytes[] memory signatures = new bytes[](1);

        vm.expectRevert(ECDSAStakeRegistryEventsAndErrors.LengthMismatch.selector);
        registry.isValidSignature(dataHash, abi.encode(signers, signatures, referenceBlock));
    }

    function testCheckSignaturesAtBlockInvalidLength() public {
        bytes32 dataHash = keccak256("data");
        uint32 referenceBlock = 123;
        address[] memory signers = new address[](0);
        bytes[] memory signatures = new bytes[](0);

        vm.expectRevert(ECDSAStakeRegistryEventsAndErrors.InvalidLength.selector);
        registry.isValidSignature(dataHash, abi.encode(signers, signatures, referenceBlock));
    }

    function testCheckSignaturesAtBlockNotSorted() public {
        uint32 referenceBlock = 123;
        vm.roll(123 + 1);
        msgHash = keccak256("data");
        signers = new address[](2);
        (signers[1], signers[0]) = (operator1, operator2);
        registry.updateOperators(signers);
        signatures = new bytes[](2);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator1Pk, msgHash);
        signatures[1] = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(operator2Pk, msgHash);
        signatures[0] = abi.encodePacked(r, s, v);

        vm.expectRevert(ECDSAStakeRegistryEventsAndErrors.NotSorted.selector);
        registry.isValidSignature(msgHash, abi.encode(signers, signatures, referenceBlock));
    }

    function testCheckSignaturesAtBlockInsufficientSignedStake() public {
        uint32 referenceBlock = 123;
        msgHash = keccak256("data");
        signers = new address[](2);
        (signers[0], signers[1]) = (operator1, operator2);
        registry.updateOperators(signers);
        signatures = new bytes[](2);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator1Pk, msgHash);
        signatures[0] = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(operator2Pk, msgHash);
        signatures[1] = abi.encodePacked(r, s, v);

        uint256 thresholdWeight = 10000000000;
        vm.prank(registry.owner());
        registry.updateStakeThreshold(thresholdWeight);
        vm.roll(referenceBlock + 1);

        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(
                ECDSAStakeRegistry.getOperatorWeightAtBlock.selector,
                operator1,
                referenceBlock
            ),
            abi.encode(50)
        );

        vm.expectRevert(ECDSAStakeRegistryEventsAndErrors.InsufficientSignedStake.selector);
        registry.isValidSignature(msgHash, abi.encode(signers, signatures, referenceBlock));
    }
}

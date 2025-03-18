// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";

import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {ECDSAStakeRegistry} from "../../src/unaudited/ECDSAStakeRegistry.sol";
import {
    IECDSAStakeRegistry,
    IECDSAStakeRegistryErrors,
    IECDSAStakeRegistryTypes,
    IECDSAStakeRegistryEvents
} from "../../src/interfaces/IECDSAStakeRegistry.sol";

contract MockServiceManager {
    // solhint-disable-next-line
    function deregisterOperatorFromAVS(
        address
    ) external {}

    function registerOperatorToAVS(
        address,
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory // solhint-disable-next-line
    ) external {}
}

contract MockDelegationManager {
    function operatorShares(address, address) external pure returns (uint256) {
        return 1000; // Return a dummy value for simplicity
    }

    function getOperatorShares(
        address,
        address[] memory strategies
    ) external pure returns (uint256[] memory) {
        uint256[] memory response = new uint256[](strategies.length);
        for (uint256 i; i < strategies.length; i++) {
            response[i] = 1000;
        }
        return response; // Return a dummy value for simplicity
    }
}

contract ECDSAStakeRegistrySetup is Test, IECDSAStakeRegistryEvents {
    MockDelegationManager public mockDelegationManager;
    MockServiceManager public mockServiceManager;
    ECDSAStakeRegistry public registry;
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
        IStrategy mockStrategy = IStrategy(address(0x1234));
        IECDSAStakeRegistryTypes.Quorum memory quorum = IECDSAStakeRegistryTypes.Quorum({
            strategies: new IECDSAStakeRegistryTypes.StrategyParams[](1)
        });
        quorum.strategies[0] =
            IECDSAStakeRegistryTypes.StrategyParams({strategy: mockStrategy, multiplier: 10000});
        registry = new ECDSAStakeRegistry(IDelegationManager(address(mockDelegationManager)));
        registry.initialize(address(mockServiceManager), 100, quorum);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature;
        vm.prank(operator1);
        registry.registerOperatorWithSignature(operatorSignature, operator1);
        vm.prank(operator2);
        registry.registerOperatorWithSignature(operatorSignature, operator2);
        vm.roll(block.number + 1);
    }
}

contract ECDSAStakeRegistryTest is ECDSAStakeRegistrySetup {
    function test_UpdateQuorumConfig() public {
        IStrategy mockStrategy = IStrategy(address(420));

        IECDSAStakeRegistryTypes.Quorum memory oldQuorum = registry.quorum();
        IECDSAStakeRegistryTypes.Quorum memory newQuorum = IECDSAStakeRegistryTypes.Quorum({
            strategies: new IECDSAStakeRegistryTypes.StrategyParams[](1)
        });
        newQuorum.strategies[0] =
            IECDSAStakeRegistryTypes.StrategyParams({strategy: mockStrategy, multiplier: 10000});
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        vm.expectEmit(true, true, false, true);
        emit QuorumUpdated(oldQuorum, newQuorum);

        registry.updateQuorumConfig(newQuorum, operators);
    }

    function test_RevertsWhen_InvalidQuorum_UpdateQuourmConfig() public {
        IECDSAStakeRegistryTypes.Quorum memory invalidQuorum = IECDSAStakeRegistryTypes.Quorum({
            strategies: new IECDSAStakeRegistryTypes.StrategyParams[](1)
        });
        invalidQuorum.strategies[0] = IECDSAStakeRegistryTypes.StrategyParams({
            /// TODO: Make mock strategy
            strategy: IStrategy(address(420)),
            multiplier: 5000 // This should cause the update to revert as it's not the total required
        });
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        vm.expectRevert(IECDSAStakeRegistryErrors.InvalidQuorum.selector);
        registry.updateQuorumConfig(invalidQuorum, operators);
    }

    function test_RevertsWhen_NotOwner_UpdateQuorumConfig() public {
        IECDSAStakeRegistryTypes.Quorum memory validQuorum = IECDSAStakeRegistryTypes.Quorum({
            strategies: new IECDSAStakeRegistryTypes.StrategyParams[](1)
        });
        validQuorum.strategies[0] = IECDSAStakeRegistryTypes.StrategyParams({
            strategy: IStrategy(address(420)),
            multiplier: 10000
        });

        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        address nonOwner = address(0x123);
        vm.prank(nonOwner);

        vm.expectRevert("Ownable: caller is not the owner");
        registry.updateQuorumConfig(validQuorum, operators);
    }

    function test_RevertsWhen_SameQuorum_UpdateQuorumConfig() public {
        IECDSAStakeRegistryTypes.Quorum memory quorum = registry.quorum();
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        /// Showing this doesnt revert
        registry.updateQuorumConfig(quorum, operators);
    }

    function test_RevertSWhen_Duplicate_UpdateQuorumConfig() public {
        IECDSAStakeRegistryTypes.Quorum memory invalidQuorum =
            IECDSAStakeRegistryTypes.Quorum({strategies: new StrategyParams[](2)});
        invalidQuorum.strategies[0] =
            StrategyParams({strategy: IStrategy(address(420)), multiplier: 5000});
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        invalidQuorum.strategies[1] =
            StrategyParams({strategy: IStrategy(address(420)), multiplier: 5000});
        vm.expectRevert(IECDSAStakeRegistryErrors.NotSorted.selector);
        registry.updateQuorumConfig(invalidQuorum, operators);
    }

    function test_RevertSWhen_NotSorted_UpdateQuorumConfig() public {
        IECDSAStakeRegistryTypes.Quorum memory invalidQuorum =
            IECDSAStakeRegistryTypes.Quorum({strategies: new StrategyParams[](2)});
        invalidQuorum.strategies[0] =
            StrategyParams({strategy: IStrategy(address(420)), multiplier: 5000});
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        invalidQuorum.strategies[1] =
            StrategyParams({strategy: IStrategy(address(419)), multiplier: 5000});
        vm.expectRevert(IECDSAStakeRegistryErrors.NotSorted.selector);
        registry.updateQuorumConfig(invalidQuorum, operators);
    }

    function test_RevertSWhen_OverMultiplierTotal_UpdateQuorumConfig() public {
        IECDSAStakeRegistryTypes.Quorum memory invalidQuorum =
            IECDSAStakeRegistryTypes.Quorum({strategies: new StrategyParams[](1)});
        invalidQuorum.strategies[0] =
            StrategyParams({strategy: IStrategy(address(420)), multiplier: 10001});
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        vm.expectRevert(IECDSAStakeRegistryErrors.InvalidQuorum.selector);
        registry.updateQuorumConfig(invalidQuorum, operators);
    }

    function test_RegisterOperatorWithSignature() public {
        address operator3 = address(0x125);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory signature;
        vm.prank(operator3);
        registry.registerOperatorWithSignature(signature, operator3);
        assertTrue(registry.operatorRegistered(operator3));
        assertEq(registry.getLastCheckpointOperatorWeight(operator3), 1000);
    }

    function test_RevertsWhen_AlreadyRegistered_RegisterOperatorWithSignature() public {
        assertEq(registry.getLastCheckpointOperatorWeight(operator1), 1000);
        assertEq(registry.getLastCheckpointTotalWeight(), 2000);

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory signature;
        vm.expectRevert(IECDSAStakeRegistryErrors.OperatorAlreadyRegistered.selector);
        vm.prank(operator1);
        registry.registerOperatorWithSignature(signature, operator1);
    }

    function test_RevertsWhen_SignatureIsInvalid_RegisterOperatorWithSignature() public {
        bytes memory signatureData;
        vm.mockCall(
            address(mockServiceManager),
            abi.encodeWithSelector(
                MockServiceManager.registerOperatorToAVS.selector,
                operator1,
                ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry({
                    signature: signatureData,
                    salt: bytes32(uint256(0x120)),
                    expiry: 10
                })
            ),
            abi.encode(50)
        );
    }

    function test_DeregisterOperator() public {
        assertEq(registry.getLastCheckpointOperatorWeight(operator1), 1000);
        assertEq(registry.getLastCheckpointTotalWeight(), 2000);

        vm.prank(operator1);
        registry.deregisterOperator();

        assertEq(registry.getLastCheckpointOperatorWeight(operator1), 0);
        assertEq(registry.getLastCheckpointTotalWeight(), 1000);
    }

    function test_RevertsWhen_NotOperator_DeregisterOperator() public {
        address notOperator = address(0x2);
        vm.prank(notOperator);
        vm.expectRevert(IECDSAStakeRegistryErrors.OperatorNotRegistered.selector);
        registry.deregisterOperator();
    }

    function test_When_Empty_UpdateOperators() public {
        address[] memory operators = new address[](0);
        registry.updateOperators(operators);
    }

    function test_When_OperatorNotRegistered_UpdateOperators() public {
        address[] memory operators = new address[](3);
        address operator3 = address(0xBEEF);
        operators[0] = operator1;
        operators[1] = operator2;
        operators[2] = operator3;
        registry.updateOperators(operators);
        assertEq(registry.getLastCheckpointOperatorWeight(operator3), 0);
    }

    function test_When_SingleOperator_UpdateOperators() public {
        address[] memory operators = new address[](1);
        operators[0] = operator1;

        registry.updateOperators(operators);
        uint256 updatedWeight = registry.getLastCheckpointOperatorWeight(operator1);
        assertEq(updatedWeight, 1000);
    }

    function test_When_SameBlock_UpdateOperators() public {
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

    function test_When_MultipleOperators_UpdateOperators() public {
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        registry.updateOperators(operators);

        uint256 updatedWeight1 = registry.getLastCheckpointOperatorWeight(operator1);
        uint256 updatedWeight2 = registry.getLastCheckpointOperatorWeight(operator2);
        assertEq(updatedWeight1, 1000);
        assertEq(updatedWeight2, 1000);
    }

    function test_When_Duplicates_UpdateOperators() public {
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator1;

        registry.updateOperators(operators);

        uint256 updatedWeight = registry.getLastCheckpointOperatorWeight(operator1);
        assertEq(updatedWeight, 1000);
    }

    function test_When_MultipleStrategies_UpdateOperators() public {
        IStrategy mockStrategy = IStrategy(address(420));
        IStrategy mockStrategy2 = IStrategy(address(421));

        IECDSAStakeRegistryTypes.Quorum memory quorum =
            IECDSAStakeRegistryTypes.Quorum({strategies: new StrategyParams[](2)});
        quorum.strategies[0] = StrategyParams({strategy: mockStrategy, multiplier: 5000});
        quorum.strategies[1] = StrategyParams({strategy: mockStrategy2, multiplier: 5000});

        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        registry.updateQuorumConfig(quorum, operators);

        address[] memory strategies = new address[](2);
        uint256[] memory shares = new uint256[](2);
        strategies[0] = address(mockStrategy);
        strategies[1] = address(mockStrategy2);
        shares[0] = 50;
        shares[1] = 1000;
        vm.mockCall(
            address(mockDelegationManager),
            abi.encodeWithSelector(
                MockDelegationManager.getOperatorShares.selector, operator1, strategies
            ),
            abi.encode(shares)
        );

        registry.updateOperators(operators);

        uint256 updatedWeight1 = registry.getLastCheckpointOperatorWeight(operator1);
        uint256 updatedWeight2 = registry.getLastCheckpointOperatorWeight(operator2);
        assertEq(updatedWeight1, 525);
        assertEq(updatedWeight2, 1000);
        vm.roll(block.number + 1);
    }

    function test_UpdateMinimumWeight() public {
        uint256 initialMinimumWeight = registry.minimumWeight();
        uint256 newMinimumWeight = 5000;

        assertEq(initialMinimumWeight, 0); // Assuming initial state is 0

        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;
        registry.updateMinimumWeight(newMinimumWeight, operators);

        uint256 updatedMinimumWeight = registry.minimumWeight();
        assertEq(updatedMinimumWeight, newMinimumWeight);
    }

    function test_RevertsWhen_NotOwner_UpdateMinimumWeight() public {
        uint256 newMinimumWeight = 5000;
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;
        vm.prank(address(0xBEEF)); // An arbitrary non-owner address
        vm.expectRevert("Ownable: caller is not the owner");
        registry.updateMinimumWeight(newMinimumWeight, operators);
    }

    function test_When_SameWeight_UpdateMinimumWeight() public {
        uint256 initialMinimumWeight = 5000;
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;
        registry.updateMinimumWeight(initialMinimumWeight, operators);

        uint256 updatedMinimumWeight = registry.minimumWeight();
        assertEq(updatedMinimumWeight, initialMinimumWeight);
    }

    function test_When_Weight0_UpdateMinimumWeight() public {
        uint256 initialMinimumWeight = 5000;
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;
        registry.updateMinimumWeight(initialMinimumWeight, operators);

        uint256 newMinimumWeight = 0;

        registry.updateMinimumWeight(newMinimumWeight, operators);

        uint256 updatedMinimumWeight = registry.minimumWeight();
        assertEq(updatedMinimumWeight, newMinimumWeight);
    }

    function testUpdateThresholdStake_UpdateThresholdStake() public {
        uint256 thresholdWeight = 10000000000;
        vm.prank(registry.owner());
        registry.updateStakeThreshold(thresholdWeight);
    }

    function test_RevertsWhen_NotOwner_UpdateThresholdStake() public {
        uint256 thresholdWeight = 10000000000;
        address notOwner = address(0x123);
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        registry.updateStakeThreshold(thresholdWeight);
    }

    function test_CheckSignatures() public {
        msgHash = keccak256("data");
        signers = new address[](2);
        (signers[0], signers[1]) = (operator1, operator2);
        signatures = new bytes[](2);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator1Pk, msgHash);
        signatures[0] = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(operator2Pk, msgHash);
        signatures[1] = abi.encodePacked(r, s, v);

        registry.isValidSignature(msgHash, abi.encode(signers, signatures, block.number - 1));
    }

    function test_RevertsWhen_LengthMismatch_CheckSignatures() public {
        msgHash = keccak256("data");
        signers = new address[](2);
        (signers[0], signers[1]) = (operator1, operator2);
        signatures = new bytes[](1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator1Pk, msgHash);
        signatures[0] = abi.encode(v, r, s);

        vm.expectRevert(IECDSAStakeRegistryErrors.LengthMismatch.selector);
        registry.isValidSignature(msgHash, abi.encode(signers, signatures, block.number - 1));
    }

    function test_RevertsWhen_InvalidLength_CheckSignatures() public {
        bytes32 dataHash = keccak256("data");
        address[] memory signers = new address[](0);
        bytes[] memory signatures = new bytes[](0);

        vm.expectRevert(IECDSAStakeRegistryErrors.InvalidLength.selector);
        registry.isValidSignature(dataHash, abi.encode(signers, signatures, block.number - 1));
    }

    function test_RevertsWhen_NotSorted_CheckSignatures() public {
        msgHash = keccak256("data");
        signers = new address[](2);
        (signers[1], signers[0]) = (operator1, operator2);
        registry.updateOperators(signers);
        signatures = new bytes[](2);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator1Pk, msgHash);
        signatures[1] = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(operator2Pk, msgHash);
        signatures[0] = abi.encodePacked(r, s, v);

        vm.expectRevert(IECDSAStakeRegistryErrors.NotSorted.selector);
        registry.isValidSignature(msgHash, abi.encode(signers, signatures, block.number - 1));
    }

    function test_RevertsWhen_Duplicates_CheckSignatures() public {
        msgHash = keccak256("data");
        signers = new address[](2);
        signers[1] = operator1;
        signers[0] = operator1;

        /// Duplicate
        assertEq(signers[0], signers[1]);
        registry.updateOperators(signers);
        signatures = new bytes[](2);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator1Pk, msgHash);
        signatures[0] = abi.encodePacked(r, s, v);
        signatures[1] = abi.encodePacked(r, s, v);

        vm.expectRevert(IECDSAStakeRegistryErrors.NotSorted.selector);
        registry.isValidSignature(msgHash, abi.encode(signers, signatures, block.number - 1));
    }

    function test_RevetsWhen_InvalidSignature_CheckSignatures() public {
        bytes32 dataHash = keccak256("data");
        address[] memory signers = new address[](1);
        signers[0] = operator1;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = "invalid-signature";

        vm.expectRevert(IECDSAStakeRegistryErrors.InvalidSignature.selector);
        registry.isValidSignature(dataHash, abi.encode(signers, signatures, block.number - 1));
    }

    function test_RevertsWhen_InsufficientSignedStake_CheckSignatures() public {
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
                ECDSAStakeRegistry.getLastCheckpointOperatorWeight.selector, operator1
            ),
            abi.encode(50)
        );

        vm.expectRevert(IECDSAStakeRegistryErrors.InsufficientSignedStake.selector);
        registry.isValidSignature(msgHash, abi.encode(signers, signatures, block.number - 1));
    }

    function test_RevertsWhen_LengthMismatch_CheckSignaturesAtBlock() public {
        bytes32 dataHash = keccak256("data");
        uint32 referenceBlock = 123;
        address[] memory signers = new address[](2);
        signers[0] = operator1;
        signers[1] = operator2;
        bytes[] memory signatures = new bytes[](1);

        vm.expectRevert(IECDSAStakeRegistryErrors.LengthMismatch.selector);
        registry.isValidSignature(dataHash, abi.encode(signers, signatures, referenceBlock));
    }

    function test_RevertsWhen_InvalidLength_CheckSignaturesAtBlock() public {
        bytes32 dataHash = keccak256("data");
        uint32 referenceBlock = 123;
        address[] memory signers = new address[](0);
        bytes[] memory signatures = new bytes[](0);

        vm.expectRevert(IECDSAStakeRegistryErrors.InvalidLength.selector);
        registry.isValidSignature(dataHash, abi.encode(signers, signatures, referenceBlock));
    }

    function test_RevertsWhen_NotSorted_CheckSignaturesAtBlock() public {
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

        vm.expectRevert(IECDSAStakeRegistryErrors.NotSorted.selector);
        registry.isValidSignature(msgHash, abi.encode(signers, signatures, referenceBlock));
    }

    function test_RevetsWhen_InsufficientSignedStake_CheckSignaturesAtBlock() public {
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
                ECDSAStakeRegistry.getOperatorWeightAtBlock.selector, operator1, referenceBlock
            ),
            abi.encode(50)
        );

        vm.expectRevert(IECDSAStakeRegistryErrors.InsufficientSignedStake.selector);
        registry.isValidSignature(msgHash, abi.encode(signers, signatures, referenceBlock));
    }

    function test_Gas_UpdateOperators() public {
        uint256 before = gasleft();
        vm.pauseGasMetering();
        vm.prank(operator1);
        registry.deregisterOperator();
        vm.prank(operator2);
        registry.deregisterOperator();

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature;
        address[] memory operators = new address[](30);
        for (uint256 i; i < operators.length; i++) {
            operators[i] = address(uint160(i));
            vm.prank(operators[i]);
            registry.registerOperatorWithSignature(operatorSignature, operators[i]);
        }
        vm.resumeGasMetering();
        registry.updateOperators(operators);

        emit log_named_uint("Gas consumed", before - gasleft());
    }

    function test_Gas_CheckSignatures() public {
        uint256 before = gasleft();
        vm.pauseGasMetering();
        vm.prank(operator1);
        registry.deregisterOperator();
        vm.prank(operator2);
        registry.deregisterOperator();
        msgHash = keccak256("data");

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature;
        address[] memory operators = new address[](30);
        bytes[] memory signatures = new bytes[](30);
        uint8 v;
        bytes32 r;
        bytes32 s;
        for (uint256 i = 1; i < operators.length + 1; i++) {
            operators[i - 1] = address(vm.addr(i));
            vm.prank(operators[i - 1]);
            registry.registerOperatorWithSignature(operatorSignature, operators[i - 1]);
            (v, r, s) = vm.sign(i, msgHash);
            signatures[i - 1] = abi.encodePacked(r, s, v);
        }
        (operators, signatures) = _sort(operators, signatures);
        registry.updateOperators(operators);
        vm.roll(block.number + 1);
        vm.resumeGasMetering();

        registry.isValidSignature(msgHash, abi.encode(operators, signatures, block.number - 1));

        emit log_named_uint("Gas consumed", before - gasleft());
    }

    // Define private and public keys for operator3 and signer
    uint256 private operator3Pk = 3;
    address private operator3 = address(vm.addr(operator3Pk));
    uint256 private signerPk = 4;
    address private signer = address(vm.addr(signerPk));

    function test_WhenUsingSigningKey_RegierOperatorWithSignature() public {
        address operator = operator3;

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature;

        // Register operator with a different signing key
        vm.prank(operator);
        registry.registerOperatorWithSignature(operatorSignature, signer);

        // Verify that the signing key has been successfully registered for the operator
        address registeredSigningKey = registry.getLatestOperatorSigningKey(operator);
        assertEq(
            registeredSigningKey,
            signer,
            "The registered signing key does not match the provided signing key"
        );
    }

    function test_Twice_RegierOperatorWithSignature() public {
        address operator = operator3;

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature;

        // Register operator with a different signing key
        vm.prank(operator);
        registry.registerOperatorWithSignature(operatorSignature, signer);

        /// Register a second time
        vm.prank(operator);
        registry.updateOperatorSigningKey(address(420));

        // Verify that the signing key has been successfully registered for the operator
        address registeredSigningKey = registry.getLatestOperatorSigningKey(operator);

        vm.roll(block.number + 1);
        registeredSigningKey =
            registry.getOperatorSigningKeyAtBlock(operator, uint32(block.number - 1));
        assertEq(
            registeredSigningKey,
            address(420),
            "The registered signing key does not match the provided signing key"
        );
    }

    function test_WhenUsingSigningKey_CheckSignatures() public {
        address operator = operator3;

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature;

        // Register operator with a different signing key
        vm.prank(operator);
        registry.registerOperatorWithSignature(operatorSignature, signer);
        vm.roll(block.number + 1);

        // Prepare data for signature
        bytes32 dataHash = keccak256("data");
        address[] memory operators = new address[](1);
        operators[0] = operator;
        bytes[] memory signatures = new bytes[](1);

        // Generate signature using the signing key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, dataHash);
        signatures[0] = abi.encodePacked(r, s, v);

        // Check signatures using the registered signing key
        registry.isValidSignature(dataHash, abi.encode(operators, signatures, block.number - 1));
    }

    function test_WhenUsingSigningKey_CheckSignaturesAtBlock() public {
        address operator = operator3;
        address initialSigningKey = address(vm.addr(signerPk));
        address updatedSigningKey = address(vm.addr(signerPk + 1));

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature;

        // Register operator with the initial signing key
        vm.prank(operator);
        registry.registerOperatorWithSignature(operatorSignature, initialSigningKey);
        vm.roll(block.number + 1);

        // Prepare data for signature with initial signing key
        bytes32 dataHash = keccak256("data");
        address[] memory operators = new address[](1);
        operators[0] = operator;
        bytes[] memory signatures = new bytes[](1);

        // Generate signature using the initial signing key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, dataHash);
        signatures[0] = abi.encodePacked(r, s, v);

        // Check signatures using the initial registered signing key
        registry.isValidSignature(dataHash, abi.encode(operators, signatures, block.number - 1));

        // Increase block number
        vm.roll(block.number + 10);

        // Update operator's signing key
        vm.prank(operator);
        registry.updateOperatorSigningKey(updatedSigningKey);
        vm.roll(block.number + 1);

        // Generate signature using the updated signing key
        (v, r, s) = vm.sign(signerPk + 1, dataHash);
        signatures[0] = abi.encodePacked(r, s, v);

        // Check signatures using the updated registered signing key
        registry.isValidSignature(dataHash, abi.encode(operators, signatures, block.number - 1));
    }

    function test_WhenUsingPriorSigningKey_CheckSignaturesAtBlock() public {
        address operator = operator3;
        address initialSigningKey = address(vm.addr(signerPk));
        address updatedSigningKey = address(vm.addr(signerPk + 1));

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature;

        // Register operator with the initial signing key
        vm.prank(operator);
        registry.registerOperatorWithSignature(operatorSignature, initialSigningKey);
        vm.roll(block.number + 1);

        // Prepare data for signature with initial signing key
        bytes32 dataHash = keccak256("data");
        address[] memory operators = new address[](1);
        operators[0] = operator;
        bytes[] memory signatures = new bytes[](1);

        // Generate signature using the initial signing key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, dataHash);
        signatures[0] = abi.encodePacked(r, s, v);

        // Increase block number
        vm.roll(block.number + 10);

        // Update operator's signing key
        vm.prank(operator);
        registry.updateOperatorSigningKey(updatedSigningKey);

        // Check signatures using the initial registered signing key at the previous block
        registry.isValidSignature(dataHash, abi.encode(operators, signatures, block.number - 10));
    }

    function test_RevertsWhen_SigningCurrentBlock_IsValidSignature() public {
        address operator = operator1;
        address signingKey = address(vm.addr(signerPk));
        bytes32 dataHash = keccak256(abi.encodePacked("test data"));
        uint256 currentBlock = block.number;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, dataHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        address[] memory operators = new address[](1);
        operators[0] = operator;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        vm.expectRevert(abi.encodeWithSignature("InvalidReferenceBlock()"));
        registry.isValidSignature(dataHash, abi.encode(operators, signatures, currentBlock));
    }

    function test_RevertsWhen_SigningKeyNotValidAtBlock_IsValidSignature() public {
        address operator = operator1;
        uint256 invalidSignerPk = signerPk + 1;
        address updatedSigningKey = address(vm.addr(invalidSignerPk));
        /// Different key to simulate invalid signing key
        bytes32 dataHash = keccak256(abi.encodePacked("test data"));
        uint256 referenceBlock = block.number;
        /// Past reference block where the signer update won't be valid
        vm.roll(block.number + 1);

        vm.prank(operator);
        registry.updateOperatorSigningKey(address(updatedSigningKey));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(invalidSignerPk, dataHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        address[] memory operators = new address[](1);
        operators[0] = operator;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        vm.expectRevert(abi.encodeWithSignature("InvalidSignature()"));
        registry.isValidSignature(dataHash, abi.encode(operators, signatures, referenceBlock));
    }

    function _sort(
        address[] memory operators,
        bytes[] memory signatures
    ) internal pure returns (address[] memory, bytes[] memory) {
        require(operators.length == signatures.length, "Operators and signatures length mismatch");

        uint256 length = operators.length;
        for (uint256 i = 0; i < length - 1; i++) {
            uint256 minIndex = i;
            for (uint256 j = i + 1; j < length; j++) {
                if (operators[j] < operators[minIndex]) {
                    minIndex = j;
                }
            }
            if (minIndex != i) {
                // Swap operators
                address tempOperator = operators[i];
                operators[i] = operators[minIndex];
                operators[minIndex] = tempOperator;
                // Swap corresponding signatures
                bytes memory tempSignature = signatures[i];
                signatures[i] = signatures[minIndex];
                signatures[minIndex] = tempSignature;
            }
        }
        return (operators, signatures);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "../utils/MockAVSDeployer.sol";
import {MockRiscZeroVerifier} from "../mocks/MockRisc0Verifier.sol";
import {RegistryCoordinatorUnitTests} from "./RegistryCoordinatorUnit.t.sol";

contract zkRegistryUpdate is RegistryCoordinatorUnitTests {
    MockRiscZeroVerifier internal zkVerifier;
    function setUp() public override {
        super.setUp();
        zkVerifier = new MockRiscZeroVerifier();
        vm.prank(registryCoordinator.owner());
        registryCoordinator.updateZkVerifier(address(zkVerifier));
    }

    function test_updateOperatorsForQuorum_singleOperator() public {
        // register the default operator
        ISignatureUtils.SignatureWithSaltAndExpiry memory emptySig;
        uint32 registrationBlockNumber = 100;
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        _setOperatorWeight(defaultOperator, uint8(quorumNumbers[0]), defaultStake);
        cheats.startPrank(defaultOperator);
        cheats.roll(registrationBlockNumber);
        registryCoordinator.registerOperator(quorumNumbers, defaultSocket, pubkeyRegistrationParams, emptySig);

        address[][] memory operatorsToUpdate = new address[][](1);
        address[] memory operatorArray = new address[](1);
        operatorArray[0] =  defaultOperator;
        operatorsToUpdate[0] = operatorArray;

        address[] memory operatorsInput = new address[](1);
        operatorsInput[0] = defaultOperator;
        (address[] memory operatorsOutput, bytes32[] memory operatorIdsOutput, uint8 quorumNumberOutput, uint96[] memory stakes) = registryCoordinator.viewUpdateOperatorsForQuorum(operatorsInput, defaultQuorumNumber);

        uint256 quorumUpdateBlockNumberBefore = registryCoordinator.quorumUpdateBlockNumber(defaultQuorumNumber);
        require(quorumUpdateBlockNumberBefore != block.number, "bad test setup!");

        cheats.expectEmit(true, true, true, true, address(registryCoordinator));
        emit QuorumBlockNumberUpdated(defaultQuorumNumber, block.number);

        uint256 updateBlock = block.number;
        bytes memory seal;
        bytes32 postStateDigest;
        uint96 totalStake;
        registryCoordinator.zkUpdateOperatorsForQuorum(updateBlock, operatorsOutput, operatorIdsOutput, defaultQuorumNumber, stakes, totalStake, postStateDigest, seal);

        uint256 quorumUpdateBlockNumberAfter = registryCoordinator.quorumUpdateBlockNumber(defaultQuorumNumber);
        assertEq(quorumUpdateBlockNumberAfter, block.number, "quorumUpdateBlockNumber not set correctly");
    }

    function test_updateOperatorsForQuorum_twoOperators(uint256 pseudoRandomNumber) public {
        // register 2 operators
        uint32 numOperators = 2;
        uint32 registrationBlockNumber = 200;
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(defaultQuorumNumber);
        uint256 quorumBitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers);
        cheats.roll(registrationBlockNumber);
        for (uint i = 0; i < numOperators; i++) {
            BN254.G1Point memory pubKey = BN254.hashToG1(keccak256(abi.encodePacked(pseudoRandomNumber, i)));
            address operator = _incrementAddress(defaultOperator, i);
            
            _registerOperatorWithCoordinator(operator, quorumBitmap, pubKey);
        }

        address[][] memory operatorsToUpdate = new address[][](1);
        address[] memory operatorArray = new address[](2);
        // order the operator addresses in descending order, instead of ascending order
        operatorArray[0] =  defaultOperator;
        operatorArray[1] =  _incrementAddress(defaultOperator, 1);
        operatorsToUpdate[0] = operatorArray;

        uint256 quorumUpdateBlockNumberBefore = registryCoordinator.quorumUpdateBlockNumber(defaultQuorumNumber);
        require(quorumUpdateBlockNumberBefore != block.number, "bad test setup!");

        cheats.expectEmit(true, true, true, true, address(registryCoordinator));
        emit QuorumBlockNumberUpdated(defaultQuorumNumber, block.number);
        registryCoordinator.updateOperatorsForQuorum(operatorsToUpdate, quorumNumbers);

        uint256 quorumUpdateBlockNumberAfter = registryCoordinator.quorumUpdateBlockNumber(defaultQuorumNumber);
        assertEq(quorumUpdateBlockNumberAfter, block.number, "quorumUpdateBlockNumber not set correctly");
    }

}

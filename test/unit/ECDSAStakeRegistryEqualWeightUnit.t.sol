// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {ECDSAStakeRegistryEventsAndErrors, Quorum, StrategyParams} from "../../src/interfaces/IECDSAStakeRegistryEventsAndErrors.sol";
import {ECDSAStakeRegistrySetup} from "./ECDSAStakeRegistryUnit.t.sol";
import {ECDSAStakeRegistryEqualWeight} from "../../src/unaudited/examples/ECDSAStakeRegistryEqualWeight.sol";

contract EqualWeightECDSARegistry is ECDSAStakeRegistrySetup {
    ECDSAStakeRegistryEqualWeight internal fixedWeightRegistry;

    function setUp() public virtual override {
        super.setUp();
        fixedWeightRegistry = new ECDSAStakeRegistryEqualWeight(
            IDelegationManager(address(mockDelegationManager))
        );
        IStrategy mockStrategy = IStrategy(address(0x1234));
        Quorum memory quorum = Quorum({strategies: new StrategyParams[](1)});
        quorum.strategies[0] = StrategyParams({
            strategy: mockStrategy,
            multiplier: 10000
        });
        fixedWeightRegistry.initialize(
            address(mockServiceManager),
            100,
            quorum
        );

        fixedWeightRegistry.permitOperator(operator1);
        fixedWeightRegistry.permitOperator(operator2);
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature;
        vm.prank(operator1);
        fixedWeightRegistry.registerOperatorWithSignature(
            operatorSignature,
            operator1
        );
        vm.prank(operator2);
        fixedWeightRegistry.registerOperatorWithSignature(
            operatorSignature,
            operator2
        );
    }

    function test_FixedStakeUpdates() public {
        assertEq(
            fixedWeightRegistry.getLastCheckpointOperatorWeight(operator1),
            1
        );
        assertEq(
            fixedWeightRegistry.getLastCheckpointOperatorWeight(operator2),
            1
        );
        assertEq(fixedWeightRegistry.getLastCheckpointTotalWeight(), 2);

        vm.roll(block.number + 1);
        vm.prank(operator1);
        fixedWeightRegistry.deregisterOperator();

        assertEq(
            fixedWeightRegistry.getLastCheckpointOperatorWeight(operator1),
            0
        );
        assertEq(
            fixedWeightRegistry.getLastCheckpointOperatorWeight(operator2),
            1
        );
        assertEq(fixedWeightRegistry.getLastCheckpointTotalWeight(), 1);

        vm.roll(block.number + 1);
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature;
        vm.prank(operator1);
        fixedWeightRegistry.registerOperatorWithSignature(
            operatorSignature,
            operator1
        );

        assertEq(
            fixedWeightRegistry.getLastCheckpointOperatorWeight(operator1),
            1
        );
        assertEq(
            fixedWeightRegistry.getLastCheckpointOperatorWeight(operator2),
            1
        );
        assertEq(fixedWeightRegistry.getLastCheckpointTotalWeight(), 2);

        vm.roll(block.number + 1);
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;
        fixedWeightRegistry.updateOperators(operators);

        assertEq(
            fixedWeightRegistry.getLastCheckpointOperatorWeight(operator1),
            1
        );
        assertEq(
            fixedWeightRegistry.getLastCheckpointOperatorWeight(operator2),
            1
        );
        assertEq(fixedWeightRegistry.getLastCheckpointTotalWeight(), 2);
    }
}

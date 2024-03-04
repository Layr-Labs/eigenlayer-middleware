// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {ECDSAStakeRegistryEventsAndErrors, Quorum, StrategyParams} from "../../src/interfaces/IECDSAStakeRegistryEventsAndErrors.sol";
import {ECDSAStakeRegistrySetup} from "./ECDSAStakeRegistryUnit.t.sol";
import {ECDSAStakeRegistryPermissioned} from "../../src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol";

contract PermissionedECDSAStakeRegistryTest is ECDSAStakeRegistrySetup {
    ECDSAStakeRegistryPermissioned internal permissionedRegistry;
    function setUp() public virtual override {
        super.setUp();
        permissionedRegistry = new ECDSAStakeRegistryPermissioned(IDelegationManager(address(mockDelegationManager)));
        IStrategy mockStrategy = IStrategy(address(0x1234));
        Quorum memory quorum = Quorum({strategies: new StrategyParams[](1)});
        quorum.strategies[0] = StrategyParams({strategy: mockStrategy, multiplier: 10000});
        permissionedRegistry.initialize(address(mockServiceManager), 100, quorum);

        permissionedRegistry.permitOperator(operator1);
        permissionedRegistry.permitOperator(operator2);
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature;
        permissionedRegistry.registerOperatorWithSignature(operator1, operatorSignature);
        permissionedRegistry.registerOperatorWithSignature(operator2, operatorSignature);
    }

    function test_RevertsWhen_NotOwner_PermitOperator() public {
        vm.skip(true);
    }

    function test_When_Owner_PermitOperator() public {
        vm.skip(true);
    }

    function test_RevertsWhen_NotOwner_RevokeOperator() public {
        vm.skip(true);
    }

    function test_RevertsWhen_NotOperator_RevokeOperator() public {
        vm.skip(true);
    }

    function test_When_Owner_RevokeOperator() public {
        vm.skip(true);
    }

    function test_RevertsWhen_NotOwner_EjectOperator() public {
        vm.skip(true);
    }

    function test_RevertsWhen_NotOperator_EjectOperator() public {
        vm.skip(true);
    }

    function test_When_Owner_EjectOperator() public {
        vm.skip(true);
    }

    function test_RevertsWhen_NotAllowlisted_RegisterOperatorWithSig() public {
        vm.skip(true);
    }

    function test_WhenAllowlisted_RegisterOperatorWithSig() public {
        vm.skip(true);
    }

    function test_DeregisterOperator() public {
        vm.skip(true);
    }

}

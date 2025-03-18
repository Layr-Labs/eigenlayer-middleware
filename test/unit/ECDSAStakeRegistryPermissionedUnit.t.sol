// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {
    IECDSAStakeRegistry,
    IECDSAStakeRegistryTypes,
    IECDSAStakeRegistryErrors
} from "../../src/interfaces/IECDSAStakeRegistry.sol";
import {ECDSAStakeRegistrySetup} from "./ECDSAStakeRegistryUnit.t.sol";
import {ECDSAStakeRegistryPermissioned} from
    "../../src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol";

contract PermissionedECDSAStakeRegistryTest is ECDSAStakeRegistrySetup {
    ECDSAStakeRegistryPermissioned internal permissionedRegistry;

    function setUp() public virtual override {
        super.setUp();
        permissionedRegistry =
            new ECDSAStakeRegistryPermissioned(IDelegationManager(address(mockDelegationManager)));
        IStrategy mockStrategy = IStrategy(address(0x1234));
        IECDSAStakeRegistryTypes.Quorum memory quorum =
            IECDSAStakeRegistryTypes.Quorum({strategies: new StrategyParams[](1)});
        quorum.strategies[0] = StrategyParams({strategy: mockStrategy, multiplier: 10000});
        permissionedRegistry.initialize(address(mockServiceManager), 100, quorum);

        permissionedRegistry.permitOperator(operator1);
        permissionedRegistry.permitOperator(operator2);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature;
        vm.prank(operator1);
        permissionedRegistry.registerOperatorWithSignature(operatorSignature, operator1);
        vm.prank(operator2);
        permissionedRegistry.registerOperatorWithSignature(operatorSignature, operator1);
    }

    function test_RevertsWhen_NotOwner_PermitOperator() public {
        address notOwner = address(0xBEEF);
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        permissionedRegistry.permitOperator(operator1);
    }

    function test_When_Owner_PermitOperator() public {
        address operator3 = address(0xBEEF);
        permissionedRegistry.permitOperator(operator3);
    }

    function test_RevertsWhen_NotOwner_RevokeOperator() public {
        address notOwner = address(0xBEEF);
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        permissionedRegistry.revokeOperator(operator1);
    }

    function test_When_NotOperator_RevokeOperator() public {
        address notOperator = address(0xBEEF);
        permissionedRegistry.permitOperator(notOperator);

        permissionedRegistry.revokeOperator(notOperator);
    }

    function test_When_Owner_RevokeOperator() public {
        permissionedRegistry.revokeOperator(operator1);
    }

    function test_RevertsWhen_NotOwner_EjectOperator() public {
        address notOwner = address(0xBEEF);
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        permissionedRegistry.ejectOperator(operator1);
    }

    function test_RevertsWhen_NotOperator_EjectOperator() public {
        address notOperator = address(0xBEEF);
        vm.expectRevert(
            abi.encodeWithSelector(IECDSAStakeRegistryErrors.OperatorNotRegistered.selector)
        );
        permissionedRegistry.ejectOperator(notOperator);
    }

    function test_When_Owner_EjectOperator() public {
        permissionedRegistry.ejectOperator(operator1);
    }

    function test_RevertsWhen_NotAllowlisted_RegisterOperatorWithSig() public {
        address operator3 = address(0xBEEF);

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature;
        vm.expectRevert(
            abi.encodeWithSelector(ECDSAStakeRegistryPermissioned.OperatorNotAllowlisted.selector)
        );
        vm.prank(operator3);
        permissionedRegistry.registerOperatorWithSignature(operatorSignature, operator3);
    }

    function test_WhenAllowlisted_RegisterOperatorWithSig() public {
        address operator3 = address(0xBEEF);
        permissionedRegistry.permitOperator(operator3);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature;
        vm.prank(operator3);
        permissionedRegistry.registerOperatorWithSignature(operatorSignature, operator3);
    }

    function test_DeregisterOperator() public {
        address operator3 = address(0xBEEF);
        permissionedRegistry.permitOperator(operator3);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature;
        vm.prank(operator3);
        permissionedRegistry.registerOperatorWithSignature(operatorSignature, operator3);

        vm.prank(operator3);
        permissionedRegistry.deregisterOperator();
    }
}
